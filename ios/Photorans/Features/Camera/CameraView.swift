import AVFoundation
import SwiftUI

struct CameraView: View {
    @State private var viewModel = CameraViewModel()
    @State private var errorAlertMessage: String?
    @State private var focusReticle: FocusReticleState?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            CameraPreviewView(session: viewModel.camera.session) { layerPoint, devicePoint in
                viewModel.focus(at: devicePoint)
                showFocusReticle(at: layerPoint)
            }
            .ignoresSafeArea()

            if let reticle = focusReticle {
                FocusReticleView()
                    .position(reticle.point)
                    .id(reticle.id)
                    .transition(.opacity)
            }

            switch viewModel.permissionStatus {
            case .denied, .restricted:
                permissionDeniedOverlay
            case .authorized:
                bottomControls
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
        .alert("エラー", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage ?? "")
        }
        .sheet(item: resultBinding) { result in
            TranslateResultView(result: result)
        }
    }

    private var resultBinding: Binding<TranslateResultItem?> {
        Binding(
            get: { viewModel.lastResult.map(TranslateResultItem.init) },
            set: { if $0 == nil { viewModel.lastResult = nil } }
        )
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

    private var bottomControls: some View {
        VStack {
            Spacer()
            ZStack {
                shutterButton
                HStack {
                    thumbnailView
                    Spacer()
                }
                .padding(.horizontal, 28)
            }
            .padding(.bottom, 40)
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await viewModel.capturePhoto() }
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

    @ViewBuilder
    private var thumbnailView: some View {
        if let image = viewModel.lastThumbnail {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white, lineWidth: 1.5)
                )
                .accessibilityLabel("直前の撮影")
        } else {
            Color.clear.frame(width: 56, height: 56)
        }
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
}
