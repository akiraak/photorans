import AVFoundation
import SwiftData
import SwiftUI

struct CameraView: View {
    var onTranslated: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CameraViewModel()
    @State private var errorAlertMessage: String?
    @State private var focusReticle: FocusReticleState?
    /// Phase2 Step2-3 切り分け用: NotificationCenter から直接観測した端末向き。
    /// Phase3 着手時に削除する。
    @State private var debugDeviceOrientation: UIDeviceOrientation = .unknown

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                // sessionPreset = .photo は 4:3 アスペクト。preview frame は短辺基準で
                // 「短辺 × 4/3」を長辺方向に確保し、残った余白に shutter を置く。
                // portrait: 画面幅 = 短辺 → preview を上、shutter を下。
                // landscape: 画面高 = 短辺 → preview を左、shutter を右。
                let isLandscape = geometry.size.width > geometry.size.height
                let shortEdge = min(geometry.size.width, geometry.size.height)
                let longEdgeForPreview = shortEdge * 4.0 / 3.0

                if isLandscape {
                    HStack(spacing: 0) {
                        previewSection
                            .frame(width: longEdgeForPreview, height: shortEdge)
                            .clipped()
                        controlsSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(spacing: 0) {
                        previewSection
                            .frame(width: shortEdge, height: longEdgeForPreview)
                            .clipped()
                        controlsSection
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            switch viewModel.permissionStatus {
            case .denied, .restricted:
                permissionDeniedOverlay
            default:
                EmptyView()
            }

            if viewModel.isTranslating {
                translatingOverlay
            }

            debugOverlay
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            debugDeviceOrientation = UIDevice.current.orientation
        }
        .onChange(of: viewModel.lastError) { _, newValue in
            if let newValue {
                errorAlertMessage = newValue
                viewModel.lastError = nil
            }
        }
        .onChange(of: viewModel.lastResult) { _, newValue in
            if newValue != nil {
                viewModel.lastResult = nil
                onTranslated()
            }
        }
        .alert("エラー", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage ?? "")
        }
    }

    private var previewSection: some View {
        ZStack {
            CameraPreviewView(
                session: viewModel.camera.session,
                rotationAngle: viewModel.lastValidRotationAngle,
                onApplyState: { state in
                    viewModel.debugConnectionState = state
                }
            ) { layerPoint, devicePoint in
                viewModel.focus(at: devicePoint)
                showFocusReticle(at: layerPoint)
            }

            if let reticle = focusReticle {
                FocusReticleView()
                    .position(reticle.point)
                    .id(reticle.id)
                    .transition(.opacity)
            }
        }
    }

    private var controlsSection: some View {
        ZStack {
            if viewModel.permissionStatus == .authorized {
                shutterButton
            }
        }
    }

    /// Phase2 Step2-3 切り分け用 overlay。
    /// rot: ViewModel が capture/preview に渡す角度。
    /// dev: NotificationCenter から直接観測した端末向き (ViewModel 経由ではない)。
    /// upd: ViewModel の orientation observer が呼ばれた回数。
    /// Phase3 着手時に削除する。
    private var debugOverlay: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("rot: \(Int(viewModel.lastValidRotationAngle))°")
            Text("dev: \(orientationName(debugDeviceOrientation))")
            Text("upd: \(viewModel.debugUpdateCount)")
            Text(viewModel.debugConnectionState)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(8)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        .foregroundStyle(.green)
        .padding(.top, 60)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func orientationName(_ orientation: UIDeviceOrientation) -> String {
        switch orientation {
        case .unknown: return "unknown"
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "upsideDown"
        case .landscapeLeft: return "landLeft"
        case .landscapeRight: return "landRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        @unknown default: return "?"
        }
    }

    private var translatingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("翻訳中…")
                .font(.subheadline)
                .foregroundStyle(.white)
        }
        .padding(24)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )
    }

    private var shutterButton: some View {
        Button {
            Task { await viewModel.capturePhoto(modelContext: modelContext) }
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(viewModel.isCapturing ? Color.gray : Color.white)
                    .frame(width: 64, height: 64)
                if viewModel.isCapturing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.black)
                }
            }
        }
        .disabled(viewModel.isCapturing || viewModel.isTranslating)
        .accessibilityLabel("撮影")
    }

    private var permissionDeniedOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text("カメラへのアクセスが許可されていません")
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("設定アプリから「Photorans」のカメラ使用を許可してください")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func showFocusReticle(at point: CGPoint) {
        let state = FocusReticleState(point: point)
        focusReticle = state
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            if focusReticle?.id == state.id {
                withAnimation(.easeOut(duration: 0.2)) {
                    focusReticle = nil
                }
            }
        }
    }
}

private struct FocusReticleState: Equatable {
    let id = UUID()
    let point: CGPoint
}

private struct FocusReticleView: View {
    @State private var scale: CGFloat = 1.4

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .onAppear {
                withAnimation(.easeOut(duration: 0.25)) {
                    scale = 1.0
                }
            }
    }
}

#Preview {
    CameraView()
        .modelContainer(for: HistoryEntry.self, inMemory: true)
}
