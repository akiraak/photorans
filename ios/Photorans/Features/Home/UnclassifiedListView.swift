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
/// 行 View は Phase 3 Step 3.7 で `ItemRowView` に差し替える。本 Phase は最低限のテキスト行で表示する。
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
                    rowView(for: item)
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

    @ViewBuilder
    private func rowView(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(primaryText(for: item))
                .font(.body)
                .lineLimit(2)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func primaryText(for item: Item) -> String {
        switch item.status {
        case .processing:
            return "処理中…"
        case .completed:
            return item.translatedText ?? "(翻訳なし)"
        case .failed:
            return "失敗: \(item.failureReason ?? "不明なエラー")"
        }
    }
}
