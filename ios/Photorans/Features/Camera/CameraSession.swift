import AVFoundation
import os

/// AVCaptureSession を専用 DispatchQueue で管理する薄いラッパ。
///
/// - SwiftUI の MainActor 側からは `start()` / `stop()` を呼ぶだけ。
/// - 内部の AVFoundation 操作はすべて `sessionQueue` 上で行うため、
///   MainActor からの直接アクセスはしない (UIViewRepresentable から
///   `session` 参照を渡すケースのみ例外。AVCaptureVideoPreviewLayer は
///   session 参照を内部でスレッドセーフに扱う前提)。
final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.akiraak.photorans.camera.session")
    private let logger = Logger(subsystem: "com.akiraak.photorans", category: "CameraSession")
    private var isConfigured = false

    /// 権限が `.authorized` の前提で session を開始する。
    /// 権限の取得は呼び出し側 (CameraViewModel) の責務。
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
            isConfigured = true
        } catch {
            logger.error("AVCaptureDeviceInput 作成失敗: \(error.localizedDescription, privacy: .public)")
        }
    }
}
