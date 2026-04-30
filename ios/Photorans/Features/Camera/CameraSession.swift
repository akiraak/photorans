import AVFoundation
import os

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
    private var pendingDelegates: [UUID: PhotoCaptureDelegate] = [:]

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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            logger.error("背面ワイドカメラデバイスが見つかりません")
            return
        }

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
    }

    /// 近接被写体 (テキスト撮影想定) に強い AF を初期設定する。
    /// `.near` は OCR 用途で重要なので、サポートされない端末でも他の設定だけは適用する。
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
