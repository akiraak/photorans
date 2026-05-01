import SwiftData
import SwiftUI

struct RootView: View {
    enum Tab: Hashable {
        case camera
        case history
    }

    @State private var selectedTab: Tab = .camera

    var body: some View {
        TabView(selection: $selectedTab) {
            CameraView(onTranslated: { selectedTab = .history })
                .tabItem {
                    Label("カメラ", systemImage: "camera")
                }
                .tag(Tab.camera)

            NavigationStack {
                HistoryListView()
            }
            .tabItem {
                Label("履歴", systemImage: "list.bullet")
            }
            .tag(Tab.history)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: HistoryEntry.self, inMemory: true)
}
