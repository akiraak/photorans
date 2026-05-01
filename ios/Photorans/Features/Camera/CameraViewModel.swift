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
    var lastThumbnail: UIImage?
    var lastResult: TranslateResponse?

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

        let angle = currentRotationAngle()
        let captured: Data
        let saved: SavedPhoto
        do {
            captured = try await camera.capturePhoto(rotationAngle: angle)
            saved = try PhotoStorage.save(jpegData: captured)
            lastSavedURL = saved.absoluteURL
            lastThumbnail = UIImage(data: captured)
        } catch {
            lastError = error.localizedDescription
            isCapturing = false
            return
        }
        isCapturing = false

        await translate(jpegData: captured, savedPhoto: saved, modelContext: modelContext)
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
        orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            // 値は capturePhoto 時に直接読むので、observer 自体は通知購読を維持するためだけに登録。
        }
    }

    private func stopTrackingOrientation() {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
            orientationObserver = nil
        }
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    /// `UIDevice.current.orientation` を `AVCaptureConnection.videoRotationAngle` 用の角度に変換。
    /// 背面カメラ前提のマッピング。`unknown` / `faceUp` / `faceDown` は portrait (90°) にフォールバック。
    private func currentRotationAngle() -> CGFloat {
        switch UIDevice.current.orientation {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeLeft: return 0
        case .landscapeRight: return 180
        default: return 90
        }
    }
}
