import AVFoundation
import SwiftUI

struct CameraView: View {
    @State private var viewModel = CameraViewModel()
    @State private var errorAlertMessage: String?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()

            switch viewModel.permissionStatus {
            case .denied, .restricted:
                permissionDeniedOverlay
            case .authorized:
                shutterControl
            default:
                EmptyView()
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
        .alert("撮影エラー", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorAlertMessage ?? "")
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorAlertMessage != nil },
            set: { if !$0 { errorAlertMessage = nil } }
        )
    }

    private var shutterControl: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                shutterButton
                Spacer()
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
        .disabled(viewModel.isCapturing)
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
}

#Preview {
    CameraView()
}
