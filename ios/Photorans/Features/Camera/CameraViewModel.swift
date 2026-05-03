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
    var lastError: String?
    /// 直近に観測した有効な端末向きを `AVCaptureConnection.videoRotationAngle` 用の角度で保持。
    /// portrait=90 / landscapeLeft=0 / landscapeRight=180 のいずれか。
    /// portraitUpsideDown / faceUp / faceDown / unknown が来たときは更新しない (直前値維持)。
    var lastValidRotationAngle: CGFloat = 90

    /// AVFoundation の `videoZoomFactor` をそのまま保持する真実値。HUD 表示・clamp の基準。
    var zoomFactor: CGFloat = 1.0
    /// `onConfigured` snapshot で受け取った device の最大 zoom factor のミラー。
    var maxZoomFactor: CGFloat = 1.0
    /// Triple / DualWide なら true。HUD 表記変換用 (ViewModel 側ミラー、device は直接読まない)。
    var isVirtualDevice: Bool = false
    /// ピンチ中の HUD 強調表示用フラグ (Phase3 の HUD 不透明度切替に使う)。
    var isPinching: Bool = false

    /// HUD に表示する純正カメラ風の倍率文字列。仮想デバイスは `zoomFactor / 2` で換算
    /// (videoZoomFactor=2.0 = 純正 1.0x = Wide FOV、=1.0 = 純正 0.5x = UltraWide)。
    var displayZoomLabel: String {
        let displayed = isVirtualDevice ? zoomFactor / 2 : zoomFactor
        return String(format: "%.1fx", displayed)
    }

    /// ピンチ開始時の zoomFactor。`UIPinchGestureRecognizer.scale` は連続値なので
    /// 開始時の倍率 × scale で目標値を組む (`.began` で更新)。
    private var pinchStartFactor: CGFloat = 1.0

    private var orientationObserver: NSObjectProtocol?

    init() {
        // CameraSession からの configure 完了通知を受け取り、ミラーを初期化する。
        // closure は sessionQueue 上で呼ばれるので Task で MainActor へ hop する。
        camera.onConfigured = { [weak self] snapshot in
            Task { @MainActor in
                self?.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: ZoomSnapshot) {
        isVirtualDevice = snapshot.isVirtualDevice
        maxZoomFactor = snapshot.maxFactor
        zoomFactor = snapshot.initialFactor
    }

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

        // sessionQueue 上で initialZoomFactor を再適用する。permission denied 経路では
        // CameraSession 側 guard で no-op になる (configureIfNeeded 未到達)。
        // MainActor 側ミラーは初回 onAppear では onConfigured snapshot で正解値が来るまで
        // 既知の isVirtualDevice ベースで暫定リセット (再 onAppear 時に意味を持つ)。
        camera.resetZoomToInitial()
        zoomFactor = isVirtualDevice ? 2.0 : 1.0
        isPinching = false
    }

    func onDisappear() {
        camera.stop()
        stopTrackingOrientation()
    }

    /// 楽観的撮影フロー (Plan Step 3.4):
    /// 1. シャッター成功 + 写真ファイル保存
    /// 2. **MainActor の modelContext で `Item(.processing, group: targetGroup)` を insert + save**
    ///    (background coordinator が `PersistentIdentifier` で再 fetch する前にディスクへ確実に乗せる)
    /// 3. `onCaptured` を呼んでカメラを即 dismiss
    /// 4. `coordinator.enqueue(itemID:jpegData:)` で background 翻訳を起動
    ///
    /// 翻訳の進行状況は `Item.status` 経由で Home / 詳細画面が観測する。
    /// このメソッド自身は `lastResult` / `isTranslating` を持たない (Phase 3 で廃止)。
    func capturePhoto(
        modelContext: ModelContext,
        coordinator: TranslationCoordinator?,
        targetGroup: ItemGroup?,
        onCaptured: @MainActor () -> Void
    ) async {
        guard permissionStatus == .authorized, !isCapturing else { return }
        isCapturing = true

        let angle = lastValidRotationAngle
        let compressed: Data
        let saved: SavedPhoto
        do {
            let captured = try await camera.capturePhoto(rotationAngle: angle)
            compressed = ImageCompressor.compressForUpload(jpegData: captured)
            saved = try PhotoStorage.save(jpegData: compressed)
        } catch {
            lastError = error.localizedDescription
            isCapturing = false
            return
        }

        let item: Item
        do {
            item = try insertProcessingItem(
                modelContext: modelContext,
                imagePath: saved.relativePath,
                targetGroup: targetGroup
            )
        } catch {
            lastError = error.localizedDescription
            isCapturing = false
            return
        }

        let itemID = item.persistentModelID
        isCapturing = false
        onCaptured()

        if let coordinator {
            await coordinator.enqueue(itemID: itemID, jpegData: compressed)
        }
    }

    /// `.processing` Item を modelContext に挿入して save するまでを MainActor で完結させる。
    /// background coordinator が `PersistentIdentifier` で再 fetch する時点で必ずディスクに
    /// 乗っていることを保証するため (Plan Step 3.4)。
    /// `CaptureContextTests` がこの関数を直接呼んで `Item.group` の対応関係を検証する (Step 3.9)。
    func insertProcessingItem(
        modelContext: ModelContext,
        imagePath: String,
        targetGroup: ItemGroup?
    ) throws -> Item {
        let item = Item(imagePath: imagePath, status: .processing, group: targetGroup)
        modelContext.insert(item)
        try modelContext.save()
        return item
    }

    /// プレビュー上タップで AF 点を切り替える。`devicePoint` は
    /// `AVCaptureVideoPreviewLayer.captureDevicePointConverted` で得た 0...1 座標。
    func focus(at devicePoint: CGPoint) {
        guard permissionStatus == .authorized else { return }
        camera.focus(at: devicePoint)
    }

    /// `UIPinchGestureRecognizer` から呼ばれる zoom 更新。AVFoundation の videoZoomFactor を
    /// `pinchStartFactor * scale` で組み、1.0 〜 maxZoomFactor の範囲に clamp する。
    /// 仮想デバイス (Triple / DualWide) の場合 1.0 は UltraWide FOV (純正 0.5x) に該当する。
    /// `state` の型は UIKit の `UIGestureRecognizer.State` (SwiftUI の GestureState ではない)。
    func updateZoom(scale: CGFloat, state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            pinchStartFactor = zoomFactor
            isPinching = true
        case .changed:
            let target = pinchStartFactor * scale
            let clamped = min(max(target, 1.0), maxZoomFactor)
            zoomFactor = clamped
            camera.setZoomFactor(clamped)
        case .ended, .cancelled, .failed:
            isPinching = false
        default:
            break
        }
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
            // queue: .main で配送されるが `MainActor.assumeIsolated` は executor を check するため、
            // Task で MainActor 隔離 context を明示的に作って self を安全に更新する。
            Task { @MainActor in
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
