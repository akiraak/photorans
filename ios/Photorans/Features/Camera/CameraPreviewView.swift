import AVFoundation
import SwiftUI
import UIKit

/// AVCaptureVideoPreviewLayer を SwiftUI に橋渡しする UIViewRepresentable。
/// プレビュー内のタップは `onTap` で layer 座標 (UIView 内の点) と
/// device 座標 (`AVCaptureDevice.focusPointOfInterest` 用、0...1) の両方で通知される。
struct CameraPreviewView: UIViewRepresentable {
    /// preview connection の `videoRotationAngle` に常に渡す角度。
    /// portrait sensor 向き = 90°。UI portrait 固定 (B3' 純正カメラ準拠) で preview frame は常に
    /// 縦長矩形なので、sensor も portrait に合わせれば「縦長 frame に縦長映像」が成立する。
    /// 撮影画像の世界向き保存は別経路 (capture connection 側) で扱う。
    private static let previewRotationAngle: CGFloat = 90

    let session: AVCaptureSession
    var onTap: (@MainActor (_ layerPoint: CGPoint, _ devicePoint: CGPoint) -> Void)?
    /// `UIPinchGestureRecognizer` のイベントを ViewModel へ流す closure。
    /// `state` は UIKit の `UIGestureRecognizer.State` (enum)。`.began` で開始、
    /// `.changed` で連続更新、`.ended` / `.cancelled` / `.failed` で終了。
    var onPinch: (@MainActor (_ scale: CGFloat, _ state: UIGestureRecognizer.State) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPinch: onPinch)
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        // WYSIWYG: プレビュー枠 = 撮影画像の見える範囲を一致させる。`.resizeAspectFill`
        // は画像が枠よりはみ出して保存範囲とズレるため使わない。
        view.previewLayer.videoGravity = .resizeAspect
        applyRotationAngle(to: view.previewLayer)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(tap)

        // tap (1 finger) と pinch (2 finger) は finger count で UIKit が排他判定するので
        // requireToFail 等の追加設定は不要。
        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:))
        )
        view.addGestureRecognizer(pinch)

        context.coordinator.previewView = view
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        applyRotationAngle(to: uiView.previewLayer)
        context.coordinator.onTap = onTap
        context.coordinator.onPinch = onPinch
    }

    /// `previewLayer.connection` を常に portrait sensor 向き (90°) に固定する。
    private func applyRotationAngle(to layer: AVCaptureVideoPreviewLayer) {
        let angle = Self.previewRotationAngle
        guard let connection = layer.connection else { return }
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    /// UITapGestureRecognizer のアクションは常に main thread で呼ばれるため、
    /// Coordinator 自体を MainActor 化して `onTap` (MainActor closure) を直接呼び出せるようにする。
    @MainActor
    final class Coordinator: NSObject {
        weak var previewView: PreviewUIView?
        var onTap: (@MainActor (CGPoint, CGPoint) -> Void)?
        var onPinch: (@MainActor (CGFloat, UIGestureRecognizer.State) -> Void)?

        init(
            onTap: (@MainActor (CGPoint, CGPoint) -> Void)?,
            onPinch: (@MainActor (CGFloat, UIGestureRecognizer.State) -> Void)?
        ) {
            self.onTap = onTap
            self.onPinch = onPinch
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = previewView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onTap?(layerPoint, devicePoint)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            onPinch?(recognizer.scale, recognizer.state)
            // 終了系ステートで `scale` を 1 に戻すことで、次回 `.began` 〜 `.changed` の
            // 倍率乗算 (pinchStartFactor * scale) が常に基準 1.0 から始まる。
            switch recognizer.state {
            case .ended, .cancelled, .failed:
                recognizer.scale = 1
            default:
                break
            }
        }
    }

    /// UIView の root layer を AVCaptureVideoPreviewLayer に直接差し替える。
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
