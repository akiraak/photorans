import SwiftData
import SwiftUI

/// 「未分類」セグメントの本文 (S3-2 / S14)。
///
/// PoC Step 0.1 の結論により SwiftData `#Predicate` は optional to-one の `nil` 比較を
/// iOS 17 で安定にサポートしないため、**Predicate を使わずリレーション直読み + in-memory フィルタ** で統一する。
///
/// フィルタ + ソートは `HomeQueries.filterItems` (Plan Step 5.2) に純関数化されており、本 View は
/// `@Query` で取得した全 Item と `searchText` をそれに渡すだけ:
/// - `searchText` が空 (= 検索 UI 非操作時): scope 直下のみ (Root → group == nil / Group X → X.items) を表示。
/// - `searchText` が非空: scope に依らず **全 `.completed` Item を横断** で originalText / translatedText
///   contains マッチ (S14 「Item は全件横断」)。
///
/// 行 View は `ItemRowView` (Plan Step 3.7 / 3.8) に委譲し、status による分岐表示はそちらが担当する。
struct UnclassifiedListView: View {
    let scope: SegmentScope
    let searchText: String

    @Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]

    var body: some View {
        let items = HomeQueries.filterItems(
            allItems: allItems,
            scope: scope,
            searchText: searchText
        )
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

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
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
}
