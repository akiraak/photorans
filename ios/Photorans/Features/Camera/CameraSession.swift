import AVFoundation
import os

/// CameraSession の configureIfNeeded 完了時に MainActor (ViewModel) へ渡す zoom 関連スナップショット。
/// ViewModel はこの値で内部ミラー (`zoomFactor` / `maxZoomFactor` / `isVirtualDevice`) を初期化し、
/// 以降は `device` を直接読まずに HUD 表示・clamp を行う。
struct ZoomSnapshot: Sendable {
    let isVirtualDevice: Bool
    let initialFactor: CGFloat
    let minFactor: CGFloat
    let maxFactor: CGFloat
}

enum CameraError: Error, LocalizedError {
    case notConfigured
    case noVideoConnection
    case noPhotoData
    case noDevice

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "カメラがまだ準備できていません"
        case .noVideoConnection:
            return "カメラ出力の接続が見つかりません"
        case .noPhotoData:
            return "撮影データを取得できませんでした"
        case .noDevice:
            return "カメラデバイスが見つかりません"
        }
    }
}

/// AVCaptureSession を専用 DispatchQueue で管理する薄いラッパ。
///
/// - SwiftUI の MainActor 側からは `start()` / `stop()` / `capturePhoto(rotationAngle:)` を呼ぶだけ。
/// - 内部の AVFoundation 操作はすべて `sessionQueue` 上で行う。
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.akiraak.photorans.camera.session")
    private let logger = Logger(subsystem: "com.akiraak.photorans", category: "CameraSession")
    private var isConfigured = false
    private var device: AVCaptureDevice?
    /// 仮想デバイス (Triple / DualWide) なら true。zoom HUD 表記変換と initialZoomFactor 決定に使う。
    /// sessionQueue 専有 — MainActor から直接読まない (Phase2 で snapshot ハンドオフ予定)。
    private var isVirtualDevice = false
    /// configureIfNeeded 完了時 / resetZoomToInitial 時に適用する videoZoomFactor 初期値。
    /// 仮想デバイスは 2.0 (= 純正 1.0x = Wide FOV)、Wide 単独は 1.0。sessionQueue 専有。
    private var initialZoomFactor: CGFloat = 1.0
    private var pendingDelegates: [UUID: PhotoCaptureDelegate] = [:]

    /// configureIfNeeded 完了時に sessionQueue 上で 1 度だけ呼ぶ。MainActor 側 ViewModel が
    /// `device` を直接読まずに済ませるためのハンドオフ経路。closure 自体は MainActor に
    /// hop しない (受け取り側が `Task { @MainActor in ... }` で hop する責務)。
    var onConfigured: (@Sendable (ZoomSnapshot) -> Void)?

    func start() {
        sessionQueue.async { [self] in
            configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// 静止画を撮影して JPEG データを返す。
    /// `rotationAngle` は `AVCaptureConnection.videoRotationAngle` に直接渡す角度 (度数)。
    func capturePhoto(rotationAngle: CGFloat) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard isConfigured else {
                    continuation.resume(throwing: CameraError.notConfigured)
                    return
                }
                guard let connection = photoOutput.connection(with: .video) else {
                    continuation.resume(throwing: CameraError.noVideoConnection)
                    return
                }

                if connection.isVideoRotationAngleSupported(rotationAngle) {
                    connection.videoRotationAngle = rotationAngle
                }

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced

                let delegateID = UUID()
                // self は strong capture。撮影完了 → pendingDelegates から削除 → delegate 解放
                // → クロージャ解放、で retain cycle は自然に解ける。
                // [weak self] にすると Swift 6 strict concurrency が weak var の再キャプチャを拒否する。
                let delegate = PhotoCaptureDelegate { [self] result in
                    sessionQueue.async {
                        self.pendingDelegates.removeValue(forKey: delegateID)
                    }
                    continuation.resume(with: result)
                }
                pendingDelegates[delegateID] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    /// プレビュー上のタップ位置 (`AVCaptureVideoPreviewLayer.captureDevicePointConverted` で
    /// 既に device 座標 (0...1) に変換済み) にフォーカスを合わせる。
    func focus(at devicePoint: CGPoint) {
        sessionQueue.async { [self] in
            guard isConfigured, let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                }
                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                }
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }
            } catch {
                logger.error("focus lockForConfiguration 失敗: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        // 仮想デバイス (Triple / DualWide) を優先入力に入れて switchover をシステムに任せる方針。
        // DiscoverySession は deviceTypes の指定順を維持して devices を返すので、
        // Triple → DualWide → Wide 単独 の優先順位がそのまま first 取得の順序になる。
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        guard let device = discovery.devices.first else {
            logger.error("背面カメラデバイスが見つかりません")
            return
        }
        isVirtualDevice = (device.deviceType == .builtInTripleCamera || device.deviceType == .builtInDualWideCamera)
        initialZoomFactor = isVirtualDevice ? 2.0 : 1.0

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                logger.error("session に入力を追加できません")
                return
            }
            session.addInput(input)
        } catch {
            logger.error("AVCaptureDeviceInput 作成失敗: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard session.canAddOutput(photoOutput) else {
            logger.error("session に photoOutput を追加できません")
            return
        }
        session.addOutput(photoOutput)

        configureFocus(on: device)

        self.device = device
        isConfigured = true

        let snapshot = ZoomSnapshot(
            isVirtualDevice: isVirtualDevice,
            initialFactor: initialZoomFactor,
            minFactor: device.minAvailableVideoZoomFactor,
            maxFactor: device.maxAvailableVideoZoomFactor
        )
        onConfigured?(snapshot)
    }

    /// ピンチジェスチャ等から呼ばれる zoom 適用。AVFoundation の `videoZoomFactor` を直接動かす。
    /// permission denied / 未設定時は no-op (ViewModel 側の clamp 結果と device 側の clamp が
    /// 一致しないケースに備えて sessionQueue 上で再 clamp する)。
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [self] in
            guard isConfigured, let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = clamped
            } catch {
                logger.error("setZoomFactor lockForConfiguration 失敗: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// CameraView の onAppear から呼ばれる zoom リセット。`initialZoomFactor` (Phase1 で決定済み) を
    /// 再適用する。configureIfNeeded 直後は configureFocus 内ですでに同じ値が入っているので冪等。
    func resetZoomToInitial() {
        sessionQueue.async { [self] in
            guard isConfigured, let device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                let clamped = min(max(initialZoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                device.videoZoomFactor = clamped
            } catch {
                logger.error("resetZoomToInitial lockForConfiguration 失敗: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 近接被写体 (テキスト撮影想定) に強い AF と初期 videoZoomFactor を設定する。
    /// `.near` は OCR 用途で重要なので、サポートされない端末でも他の設定だけは適用する。
    /// 初期 zoom は configureIfNeeded で決めた `initialZoomFactor` を同じ lock 内で適用して
    /// AF/AE 反映と同時にシステムへ commit する。
    private func configureFocus(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            let clamped = min(max(initialZoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clamped
        } catch {
            logger.error("初期 focus 設定失敗: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<Data, Error>) -> Void

    init(completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.completion = completion
        super.init()
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.noPhotoData))
            return
        }
        completion(.success(data))
    }
}
