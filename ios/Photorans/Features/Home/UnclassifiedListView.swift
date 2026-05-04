import SwiftData
import SwiftUI

/// 「未分類」モードの本文 (Plan: docs/plans/unclassified-segment-empty-bug.md)。
///
/// アプリ全体で **`group == nil` の Item を `createdAt` 降順で平坦表示する** 単一画面。
/// scope 非依存 (Step 1.7)。`RootView` 直下の独立 NavigationStack に配置されるため、
/// 行は `NavigationLink(value: Item)` で Item 詳細に push される。
///
/// PoC Step 0.1 の結論により SwiftData `#Predicate` は optional to-one の `nil` 比較を
/// iOS 17 で安定にサポートしないため、**Predicate を使わず `@Query` 全件取得 + in-memory フィルタ** で統一する。
///
/// 行 View は `ItemRowView` (Plan Step 3.7 / 3.8) に委譲し、status による分岐表示はそちらが担当する。
///
/// 撮影 FAB (`HomeFAB(scope: .root)`) を overlay として持つ。`scope: .root` で渡すことにより
/// `scope.targetGroup == nil` となり、撮影された Item は `group == nil` で保存され、本リストに即時反映される。
struct UnclassifiedListView: View {
    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]

    var body: some View {
        let items = allItems.filter { $0.group == nil }
        Group {
            if items.isEmpty {
                emptyView
            } else {
                List(items, id: \.id) { item in
                    NavigationLink(value: item) {
                        ItemRowView(item: item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomTrailing) {
            HomeFAB(scope: .root)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
        }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("まだ翻訳がありません", systemImage: "camera")
        } description: {
            Text("画面右下のカメラボタンからテキストを撮影すると、自動で翻訳されてここに保存されます。")
        }
    }
}
