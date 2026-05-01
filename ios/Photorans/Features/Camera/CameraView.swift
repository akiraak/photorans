import AVFoundation
import SwiftData
import SwiftUI

struct CameraView: View {
    var onTranslated: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CameraViewModel()
    @State private var errorAlertMessage: String?
    @State private var focusReticle: FocusReticleState?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { geometry in
                let previewWidth = geometry.size.width
                // sessionPreset = .photo は 4:3 アスペクト。portrait 画面では画面幅にフィットさせ、
                // 高さ = 幅 × 4/3 でプレビューを上部に貼る。残った下部余白に bottomControls を置く。
                let previewHeight = previewWidth * 4.0 / 3.0

                VStack(spacing: 0) {
                    ZStack {
                        CameraPreviewView(
                            session: viewModel.camera.session,
                            rotationAngle: viewModel.lastValidRotationAngle
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
                    .frame(width: previewWidth, height: previewHeight)
                    .clipped()

                    ZStack {
                        if viewModel.permissionStatus == .authorized {
                            shutterButton
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
