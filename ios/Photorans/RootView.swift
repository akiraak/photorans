import SwiftData
import SwiftUI

/// アプリのルート画面。
///
/// Picker `[未分類 | グループ]` を **NavigationStack の外側 (= VStack 直下) に固定** し、
/// `ZStack + opacity` で 未分類モード / グループモード それぞれの NavigationStack を切替する
/// (Plan: docs/plans/unclassified-segment-empty-bug.md)。階層 push しても Picker は動かない。
///
/// 状態:
/// - `selectedSegment`: グローバルなモードフィルタ。`.unclassified` を初期値とする (S2 既定値維持)
/// - `path`: グループモードの階層 push 用 (`ItemGroup` / `Item`)
/// - `unclassifiedPath`: 未分類モードの Item 詳細 push 用 (独立 NavigationStack を持つことで
///   `NavigationLink(value: Item)` を機能させる)
///
/// destination 宣言は両 NavigationStack root に集約する (Step 0.3 / Step 2.3 の方針継続)。
/// モード切替時は `ZStack + opacity` で identity を維持し、両モードの `NavigationPath` を保持する。
struct RootView: View {
    @State private var selectedSegment: HomeSegment = .unclassified
    @State private var path = NavigationPath()
    @State private var unclassifiedPath = NavigationPath()

    var body: some View {
        VStack(spacing: 0) {
            Picker("セグメント", selection: $selectedSegment) {
                ForEach(HomeSegment.allCases) { segment in
                    Text(segment.label).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            ZStack {
                // 未分類モード: UnclassifiedListView + Item destination のみ集約 (ItemGroup destination は持たない)。
                // 階層 push は無いが NavigationLink(value: Item) を機能させるため独立 NavigationStack を常駐させる。
                NavigationStack(path: $unclassifiedPath) {
                    UnclassifiedListView()
                        .navigationDestination(for: Item.self) { item in
                            ItemDetailView(item: item)
                        }
                }
                .opacity(selectedSegment == .unclassified ? 1 : 0)
                .allowsHitTesting(selectedSegment == .unclassified)

                // グループモード: HomeView(scope: .root) + ItemGroup / Item destinations をこの NavigationStack root に集約
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
                .opacity(selectedSegment == .groups ? 1 : 0)
                .allowsHitTesting(selectedSegment == .groups)
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Item.self, ItemGroup.self], inMemory: true)
}
