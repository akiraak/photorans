import SwiftUI

/// 右下に縦積みする 2 つの FAB。
///
/// - 上段: Group 作成 FAB (`folder.badge.plus` / 二次色)。タップで `GroupCreateSheet` を提示 (S7 / S13-5)。
/// - 下段: カメラ FAB (`camera.fill` / アクセント色)。タップで `CameraView` を fullScreenCover で提示
///   (Plan Step 3.5)。撮影成功時は `onCaptured` で即 dismiss し、翻訳は背景で進行する楽観的 UI (S6)。
///
/// 押し間違い対策として 2 つのボタンを 56pt × 56pt + 16pt spacing で配置し、中心間距離 72pt を確保。
/// 色とアクセシビリティラベルで明確に区別する。
struct HomeFAB: View {
    let scope: SegmentScope

    @State private var isShowingGroupCreate = false
    @State private var isShowingCamera = false

    private static let buttonSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 16) {
            groupCreateButton
            cameraButton
        }
        .sheet(isPresented: $isShowingGroupCreate) {
            GroupCreateSheet(scope: scope)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraView(
                targetGroup: scope.targetGroup,
                onCaptured: { isShowingCamera = false },
                onClose: { isShowingCamera = false }
            )
        }
    }

    private var groupCreateButton: some View {
        Button {
            isShowingGroupCreate = true
        } label: {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Color.secondary, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .accessibilityLabel("グループを作成")
    }

    private var cameraButton: some View {
        Button {
            isShowingCamera = true
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.buttonSize, height: Self.buttonSize)
                .background(Color.accentColor, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .accessibilityLabel("撮影")
    }
}
