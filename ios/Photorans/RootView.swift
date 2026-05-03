import SwiftData
import SwiftUI

/// アプリのルート画面。
///
/// NavigationStack 直下に `HomeView(scope: .root)` を配置し、ここに
/// `.navigationDestination(for: ItemGroup.self)` / `.navigationDestination(for: Item.self)` を **集約** する
/// (Step 0.3 / Step 2.3)。子 View 側 (HomeView / GroupDetailView 等) では destination を再宣言しない。
///
/// ナビバー削除 + パンくずリンク導入 (Plan: docs/plans/breadcrumb-navigation.md):
/// - `path` を保持して `NavigationStack(path:)` に渡す。Group 詳細でパンくずから祖先タップで
///   `path.removeLast(k)` を行うため、Binding で `GroupDetailView` まで配線する (Phase 3)。
/// - Root では `.toolbar(.hidden, for: .navigationBar)` でナビバー領域を 0pt にする。
struct RootView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(scope: .root)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: ItemGroup.self) { group in
                    GroupDetailView(group: group, path: $path)
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
