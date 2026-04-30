import AVFoundation
import os

enum CameraError: Error, LocalizedError {
    case notConfigured
    case noVideoConnection
    case noPhotoData

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "カメラがまだ準備できていません"
        case .noVideoConnection:
            return "カメラ出力の接続が見つかりません"
        case .noPhotoData:
            return "撮影データを取得できませんでした"
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
                let delegate = PhotoCaptureDelegate { [weak self] result in
                    self?.sessionQueue.async {
                        self?.pendingDelegates.removeValue(forKey: delegateID)
                    }
                    continuation.resume(with: result)
                }
                pendingDelegates[delegateID] = delegate
                photoOutput.capturePhoto(with: settings, delegate: delegate)
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

        isConfigured = true
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
