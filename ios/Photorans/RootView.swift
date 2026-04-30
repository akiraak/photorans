import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            CameraView()
                .tabItem {
                    Label("カメラ", systemImage: "camera")
                }

            HistoryTabView()
                .tabItem {
                    Label("履歴", systemImage: "list.bullet")
                }
        }
    }
}

private struct HistoryTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("履歴 (Phase5 で実装)")
                    .font(.title2)
            }
            .navigationTitle("履歴")
        }
    }
}

#Preview {
    RootView()
}
