import SwiftData
import SwiftUI

/// アプリのルート画面。
///
/// NavigationStack 直下に `HomeView(scope: .root)` を配置し、ここに
/// `.navigationDestination(for: ItemGroup.self)` / `.navigationDestination(for: Item.self)` を **集約** する
/// (Step 0.3 / Step 2.3)。子 View 側 (HomeView / GroupDetailView 等) では destination を再宣言しない。
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView(scope: .root)
                .navigationTitle("Photorans")
                .navigationDestination(for: ItemGroup.self) { group in
                    GroupDetailView(group: group)
                }
                .navigationDestination(for: Item.self) { item in
                    ItemDetailView(item: item)
                }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Item.self, ItemGroup.self], inMemory: true)
}
