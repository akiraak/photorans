import AVFoundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class CameraViewModel {
    let camera = CameraSession()
    var permissionStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var isCapturing: Bool = false
    var lastError: String?
    var lastSavedURL: URL?

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

    func capturePhoto() async {
        guard permissionStatus == .authorized, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        let angle = currentRotationAngle()
        do {
            let data = try await camera.capturePhoto(rotationAngle: angle)
            let url = try PhotoStorage.save(jpegData: data)
            lastSavedURL = url
        } catch {
            lastError = error.localizedDescription
        }
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
