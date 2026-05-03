import Foundation
import SwiftData

/// `HomeView` のセグメント表示と `.searchable` のフィルタを担う純関数群 (Plan Step 5.2 / 5.5)。
///
/// 設計の要点:
/// - SwiftData の `#Predicate` を使わず、`@Query` で取得した全件 + リレーション直読みの結果を
///   in-memory フィルタ + ソートする (Plan PoC Step 0.1 の方針を継承)。
/// - 表示分岐:
///   - **検索文字列が空** → 現セグメント / scope に応じた **直下のみ** を表示 (S14 「空文字列のときはフィルタ無し」)。
///   - **検索文字列あり**:
///     - Item: scope に依らず **全 `.completed` Item を横断** (S14 「Item は全件横断」)。
///     - Group: scope **配下の子孫 Group** を対象に名前 contains フィルタ (S14 「Group 名は現在階層配下のみ」)。
/// - 純関数化 (`enum HomeQueries` + static func) で View から切り離し、`SegmentQueryTests`
///   (Plan Step 5.5) のフィクスチャ駆動テストの対象にする。
enum HomeQueries {
    /// 「未分類」セグメント本文の表示リスト。
    ///
    /// - 空文字列: scope 直下の Item を createdAt 降順で返す (Root → group == nil の Item / Group X → X.items)。
    /// - 非空: 全 `.completed` Item の中から originalText / translatedText が contains マッチするものを
    ///   createdAt 降順で返す。scope は無視 (S14)。
    static func filterItems(
        allItems: [Item],
        scope: SegmentScope,
        searchText: String
    ) -> [Item] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return directItems(allItems: allItems, scope: scope)
                .sorted { $0.createdAt > $1.createdAt }
        }
        return allItems
            .filter { $0.status == .completed }
            .filter { item in
                let original = item.originalText ?? ""
                let translated = item.translatedText ?? ""
                return original.localizedCaseInsensitiveContains(trimmed)
                    || translated.localizedCaseInsensitiveContains(trimmed)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 「グループ」セグメント本文の表示リスト。
    ///
    /// - 空文字列: scope 直下の Group のみを「直下 Item の最新 createdAt 降順 (空 Group は末尾)」で返す。
    /// - 非空: scope 配下の子孫 Group (Root → 全 Group / Group X → X の子孫) のうち、
    ///   名前が contains マッチするものを Group 自身の createdAt 降順で返す。
    static func filterGroups(
        allGroups: [ItemGroup],
        scope: SegmentScope,
        searchText: String
    ) -> [ItemGroup] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return sortDirectGroups(directGroups(allGroups: allGroups, scope: scope))
        }
        return descendantGroups(allGroups: allGroups, scope: scope)
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// scope 直下の Item (= 検索が空のときの「未分類」表示対象)。
    static func directItems(allItems: [Item], scope: SegmentScope) -> [Item] {
        switch scope {
        case .root:
            return allItems.filter { $0.group == nil }
        case .group(let g):
            return g.items
        }
    }

    /// scope 直下の Group (= 検索が空のときの「グループ」表示対象)。
    static func directGroups(allGroups: [ItemGroup], scope: SegmentScope) -> [ItemGroup] {
        switch scope {
        case .root:
            return allGroups.filter { $0.parent == nil }
        case .group(let g):
            return g.children
        }
    }

    /// 「直下 Item の最新 createdAt 降順、Item ゼロの中間 Group は末尾固定、同点は Group の createdAt 降順」
    /// の安定ソート (S3-1 / Plan Step 2.5)。
    static func sortDirectGroups(_ groups: [ItemGroup]) -> [ItemGroup] {
        groups.sorted { lhs, rhs in
            let lhsLatest = lhs.items.map { $0.createdAt }.max()
            let rhsLatest = rhs.items.map { $0.createdAt }.max()
            switch (lhsLatest, rhsLatest) {
            case let (l?, r?):
                return l > r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    /// scope 配下 (自身を除く) の子孫 Group 集合 (= 検索が非空のときの「グループ」検索対象)。
    ///
    /// Root → `allGroups` の全件 (Root 以下に居ない Group は存在しない)。
    /// Group X → `g.children` を再帰展開した子孫一覧。
    static func descendantGroups(allGroups: [ItemGroup], scope: SegmentScope) -> [ItemGroup] {
        switch scope {
        case .root:
            return allGroups
        case .group(let g):
            var result: [ItemGroup] = []
            collectDescendants(of: g, into: &result)
            return result
        }
    }

    private static func collectDescendants(of group: ItemGroup, into result: inout [ItemGroup]) {
        for child in group.children {
            result.append(child)
            collectDescendants(of: child, into: &result)
        }
    }
}
