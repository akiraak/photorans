import AVFoundation
import SwiftUI
import UIKit

/// AVCaptureVideoPreviewLayer を SwiftUI に橋渡しする UIViewRepresentable。
/// プレビュー内のタップは `onTap` で layer 座標 (UIView 内の点) と
/// device 座標 (`AVCaptureDevice.focusPointOfInterest` 用、0...1) の両方で通知される。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (@MainActor (_ layerPoint: CGPoint, _ devicePoint: CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        let recognizer = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(recognizer)
        context.coordinator.previewView = view
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        context.coordinator.onTap = onTap
    }

    /// UITapGestureRecognizer のアクションは常に main thread で呼ばれるため、
    /// Coordinator 自体を MainActor 化して `onTap` (MainActor closure) を直接呼び出せるようにする。
    @MainActor
    final class Coordinator: NSObject {
        weak var previewView: PreviewUIView?
        var onTap: (@MainActor (CGPoint, CGPoint) -> Void)?

        init(onTap: (@MainActor (CGPoint, CGPoint) -> Void)?) {
            self.onTap = onTap
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = previewView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            onTap?(layerPoint, devicePoint)
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
