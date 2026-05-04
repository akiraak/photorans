import AVFoundation
import SwiftData
import SwiftUI

/// カメラプレビュー + 撮影 UI 全体。
///
/// 仕様 (Plan Step 3.3 / 3.5):
/// - 親 (`HomeFAB`) から `targetGroup` を受け取り、撮影 Item の保存先 group とする (S4 / S13-4)。
/// - シャッター成功直後に `onCaptured` を呼んで親に dismiss させる楽観的 UI (S6)。
///   翻訳の進行・完了は `Item.status` を Home / 詳細画面が観測する責務。
struct CameraView: View {
    let targetGroup: ItemGroup?
    var onCaptured: @MainActor () -> Void = {}
    var onClose: @MainActor () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.translationCoordinator) private var translationCoordinator
    @State private var viewModel = CameraViewModel()
    @State private var errorAlertMessage: String?
    @State private var focusReticle: FocusReticleState?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                // UI は portrait 固定 (Info.plist で landscape を除外)。preview は常に縦長
                // frame に portrait sensor 向き (90°) で映し、撮影画像だけ capture connection の
                // rotation で世界向きに保存する (iOS 純正カメラを portrait lock で使った時と同じ動作)。
                let previewWidth = geometry.size.width
                let previewHeight = previewWidth * 4.0 / 3.0

                VStack(spacing: 0) {
                    previewSection
                        .frame(width: previewWidth, height: previewHeight)
                        .clipped()
                    controlsSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            switch viewModel.permissionStatus {
            case .denied, .restricted:
                permissionDeniedOverlay
            default:
                EmptyView()
            }

            closeButton
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: viewModel.lastError) { _, newValue in
            if let newValue {
                errorAlertMessage = newValue
                viewModel.lastError = nil
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
                onTap: { layerPoint, devicePoint in
                    viewModel.focus(at: devicePoint)
                    showFocusReticle(at: layerPoint)
                },
                onPinch: { scale, state in
                    viewModel.updateZoom(scale: scale, state: state)
                }
            )

            if let reticle = focusReticle {
                FocusReticleView()
                    .position(reticle.point)
                    .id(reticle.id)
                    .transition(.opacity)
            }

            zoomHUD
        }
    }

    /// preview 上部に常設する倍率 HUD。ピンチ中は強調 (1.0)、それ以外は控えめ (0.6)。
    /// 仮想デバイスは `displayZoomLabel` 側で `factor / 2` 換算済み (純正カメラ風表記)。
    /// UI は portrait 固定だが、文字だけ端末向きに合わせて回す (純正カメラ準拠)。
    private var zoomHUD: some View {
        Capsule()
            .fill(.black.opacity(0.5))
            .overlay(
                Text(viewModel.displayZoomLabel)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .rotationEffect(zoomHUDRotation)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.lastValidRotationAngle)
            )
            .frame(width: 56, height: 28)
            .opacity(viewModel.isPinching ? 1.0 : 0.6)
            .animation(.easeOut(duration: 0.2), value: viewModel.isPinching)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// `lastValidRotationAngle` (capture connection 用、sensor → world) を SwiftUI ビューの
    /// `.rotationEffect` (画面ローカル → 世界向き) に写像する。`portraitUpsideDown` /
    /// `faceUp` / `faceDown` / `unknown` は ViewModel 側で直前値維持されるのでここでは扱わない。
    private var zoomHUDRotation: Angle {
        switch viewModel.lastValidRotationAngle {
        case 0: return .degrees(90)     // landscapeLeft
        case 180: return .degrees(-90)  // landscapeRight
        default: return .degrees(0)     // portrait + 直前値維持
        }
    }

    private var controlsSection: some View {
        ZStack {
            if viewModel.permissionStatus == .authorized {
                shutterButton
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )
    }

    private var shutterButton: some View {
        Button {
            Task {
                await viewModel.capturePhoto(
                    modelContext: modelContext,
                    coordinator: translationCoordinator,
                    targetGroup: targetGroup,
                    onCaptured: onCaptured
                )
            }
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
        .disabled(viewModel.isCapturing)
        .accessibilityLabel("撮影")
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(0.5)))
        }
        .accessibilityLabel("閉じる")
        .padding(.top, 12)
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    CameraView(targetGroup: nil)
        .modelContainer(for: [Item.self, ItemGroup.self], inMemory: true)
}
