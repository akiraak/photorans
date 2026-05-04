import Foundation
import SwiftData

/// `HomeView` のセグメント表示を担う純関数群 (Plan Step 5.2 / 5.5)。
///
/// 設計の要点:
/// - SwiftData の `#Predicate` を使わず、`@Query` で取得した全件 + リレーション直読みの結果を
///   in-memory フィルタ + ソートする (Plan PoC Step 0.1 の方針を継承)。
/// - 表示分岐: 現セグメント / scope に応じた **直下のみ** を表示する。
///   - Item: Root → `group == nil`、Group X → `X.items` を createdAt 降順。
///   - Group: Root → `parent == nil`、Group X → `X.children` を直下 Item の最新 createdAt 降順
///     (Item ゼロの中間 Group は末尾)。
/// - 純関数化 (`enum HomeQueries` + static func) で View から切り離し、`SegmentQueryTests`
///   (Plan Step 5.5) のフィクスチャ駆動テストの対象にする。
///
/// 検索 UI はパンくず実装で一旦削除済み。再導入時は `searchText` 引数と検索 branch
/// (Item: scope 無視で全 `.completed` 横断 / Group: scope 配下子孫の名前 contains) を再追加する
/// (TODO「検索 UI を再導入する」+ `SegmentQueryTests` 末尾の仕様コメント参照)。
enum HomeQueries {
    /// 「未分類」セグメント本文の表示リスト。scope 直下の Item を createdAt 降順で返す
    /// (Root → group == nil の Item / Group X → X.items)。
    static func filterItems(allItems: [Item], scope: SegmentScope) -> [Item] {
        directItems(allItems: allItems, scope: scope)
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// 「グループ」セグメント本文の表示リスト。scope 直下の Group のみを「直下 Item の最新
    /// createdAt 降順 (空 Group は末尾)」で返す。
    static func filterGroups(allGroups: [ItemGroup], scope: SegmentScope) -> [ItemGroup] {
        sortDirectGroups(directGroups(allGroups: allGroups, scope: scope))
    }

    /// scope 直下の Item。
    static func directItems(allItems: [Item], scope: SegmentScope) -> [Item] {
        switch scope {
        case .root:
            return allItems.filter { $0.group == nil }
        case .group(let g):
            return g.items
        }
    }

    /// scope 直下の Group。
    static func directGroups(allGroups: [ItemGroup], scope: SegmentScope) -> [ItemGroup] {
        switch scope {
        case .root:
            return allGroups.filter { $0.parent == nil }
        case .group(let g):
            return g.children
        }
    }

    /// グループ行のサムネに使う代表 Item (`docs/plans/list-thumbnails.md` Step 4)。
    ///
    /// 直下 Item の `createdAt` 最大の Item を返す。Item ゼロの Group (= サブグループしか持たない中間 Group) は
    /// nil を返し、呼び出し側 (`GroupListView`) で folder アイコンにフォールバックする。子孫まで再帰しないのは、
    /// `sortDirectGroups` の並び順 (直下 Item の最新 createdAt 降順) と一貫させるため。
    static func representativeItem(of group: ItemGroup) -> Item? {
        group.items.max(by: { $0.createdAt < $1.createdAt })
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
}
