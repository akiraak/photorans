import SwiftData
import SwiftUI

/// 「未分類」セグメントの本文 (S3-2)。
///
/// PoC Step 0.1 の結論により SwiftData `#Predicate` は optional to-one の `nil` 比較を
/// iOS 17 で安定にサポートしないため、**Predicate を使わずリレーション直読み + in-memory フィルタ** で統一する。
///
/// - Root (`scope == .root`): `@Query` で全 Item を取得し、`group == nil` をフィルタ。
/// - Group X (`scope == .group(let g)`): `g.items` を直読みし、createdAt 降順で in-memory ソート。
///
/// 行 View は `ItemRowView` (Plan Step 3.7 / 3.8) に委譲し、status による分岐表示はそちらが担当する。
struct UnclassifiedListView: View {
    let scope: SegmentScope

    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]

    var body: some View {
        let items = filteredItems()
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

    private func filteredItems() -> [Item] {
        switch scope {
        case .root:
            return allItems.filter { $0.group == nil }
        case .group(let g):
            return g.items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        switch scope {
        case .root:
            ContentUnavailableView {
                Label("まだ翻訳がありません", systemImage: "camera")
            } description: {
                Text("画面右下のカメラボタンからテキストを撮影すると、自動で翻訳されてここに保存されます。")
            }
        case .group:
            ContentUnavailableView {
                Label("このグループはまだ空です", systemImage: "camera")
            } description: {
                Text("画面右下のカメラボタンから撮影すると、このグループに翻訳が追加されます。")
            }
        }
    }
}
