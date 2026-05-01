import AVFoundation
import Observation
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraViewModel {
    let camera = CameraSession()
    var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var isCapturing: Bool = false
    var isTranslating: Bool = false
    var lastError: String?
    var lastSavedURL: URL?
    var lastResult: TranslateResponse?
    /// 直近に観測した有効な端末向きを `AVCaptureConnection.videoRotationAngle` 用の角度で保持。
    /// プレビュー回転 / 撮影回転 / UI アイコン回転で共通参照する。
    /// portrait=90 / landscapeLeft=0 / landscapeRight=180 のいずれか。
    /// portraitUpsideDown / faceUp / faceDown / unknown が来たときは更新しない (直前値維持)。
    var lastValidRotationAngle: CGFloat = 90

    private var orientationObserver: NSObjectProtocol?

    func onAppear() async {
        startTrackingOrientation()
        switch permissionStatus {
        case .authorized:
            camera.start()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permissionStatus = granted ? .authorized : .denied
            if granted {
                camera.start()
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func onDisappear() {
        camera.stop()
        stopTrackingOrientation()
    }

    func capturePhoto(modelContext: ModelContext) async {
        guard permissionStatus == .authorized, !isCapturing, !isTranslating else { return }
        isCapturing = true

        let angle = lastValidRotationAngle
        let compressed: Data
        let saved: SavedPhoto
        do {
            let captured = try await camera.capturePhoto(rotationAngle: angle)
            compressed = ImageCompressor.compressForUpload(jpegData: captured)
            saved = try PhotoStorage.save(jpegData: compressed)
            lastSavedURL = saved.absoluteURL
        } catch {
            lastError = error.localizedDescription
            isCapturing = false
            return
        }
        isCapturing = false

        await translate(jpegData: compressed, savedPhoto: saved, modelContext: modelContext)
    }

    private func translate(jpegData: Data, savedPhoto: SavedPhoto, modelContext: ModelContext) async {
        isTranslating = true
        defer { isTranslating = false }
        do {
            let response = try await TranslateAPI.shared.translate(jpegData: jpegData)
            lastResult = response
            persistHistoryEntry(response: response, savedPhoto: savedPhoto, modelContext: modelContext)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistHistoryEntry(
        response: TranslateResponse,
        savedPhoto: SavedPhoto,
        modelContext: ModelContext
    ) {
        let entry = HistoryEntry(
            imagePath: savedPhoto.relativePath,
            originalText: response.originalText,
            translatedText: response.translatedText,
            model: response.model
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
        } catch {
            lastError = "履歴の保存に失敗しました: \(error.localizedDescription)"
        }
    }

    /// プレビュー上タップで AF 点を切り替える。`devicePoint` は
    /// `AVCaptureVideoPreviewLayer.captureDevicePointConverted` で得た 0...1 座標。
    func focus(at devicePoint: CGPoint) {
        guard permissionStatus == .authorized else { return }
        camera.focus(at: devicePoint)
    }

    // MARK: - Orientation

    private func startTrackingOrientation() {
        guard orientationObserver == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        // 起動時の初期値: 既存値 (default 90) を念のため現在向きで上書き。
        updateRotationAngleFromDeviceOrientation()
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main で配送されるため main thread 上。`@MainActor` 隔離の self を直接更新する。
            MainActor.assumeIsolated {
                self?.updateRotationAngleFromDeviceOrientation()
            }
        }
    }

    private func stopTrackingOrientation() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// `UIDevice.current.orientation` を `AVCaptureConnection.videoRotationAngle` 用の角度に変換し、
    /// `lastValidRotationAngle` を更新する。背面カメラ前提のマッピング。
    /// `portraitUpsideDown` / `faceUp` / `faceDown` / `unknown` は無視 (直前値維持)。
    private func updateRotationAngleFromDeviceOrientation() {
        switch UIDevice.current.orientation {
        case .portrait:
            lastValidRotationAngle = 90
        case .landscapeLeft:
            lastValidRotationAngle = 0
        case .landscapeRight:
            lastValidRotationAngle = 180
        default:
            break
        }
    }
}
