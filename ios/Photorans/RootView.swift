import SwiftData
import SwiftUI

/// アプリのルート画面。
///
/// NavigationStack 直下に `HomeView(scope: .root)` を配置し、ここに
/// `.navigationDestination(for: ItemGroup.self)` / `.navigationDestination(for: Item.self)` を **集約** する
/// (Step 0.3 / Step 2.3)。子 View 側 (HomeView / GroupDetailView 等) では destination を再宣言しない。
///
/// Item の destination は Phase 4 Step 4.1 で `ItemDetailView` に差し替える。本 Phase は確認用の仮スタブ。
struct RootView: View {
    var body: some View {
        NavigationStack {
            HomeView(scope: .root)
                .navigationTitle("Photorans")
                .navigationDestination(for: ItemGroup.self) { group in
                    GroupDetailView(group: group)
                }
                .navigationDestination(for: Item.self) { item in
                    ItemDetailPlaceholderView(item: item)
                }
        }
    }
}

/// Phase 4 Step 4.1 で `ItemDetailView` に差し替える仮の詳細画面。
private struct ItemDetailPlaceholderView: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Item: \(item.id.uuidString)")
                .font(.headline)
            Text("status: \(item.status.rawValue)")
            if let translated = item.translatedText {
                Text(translated)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("詳細 (仮)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Item.self, ItemGroup.self], inMemory: true)
}
