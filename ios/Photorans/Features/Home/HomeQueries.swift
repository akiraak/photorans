import Foundation
import SwiftData

/// グループモード (`HomeView` → `GroupListView`) 配下のリスト表示を担う純関数群 (Plan Step 5.2 / 5.5)。
///
/// 設計の要点:
/// - SwiftData の `#Predicate` を使わず、`@Query` で取得した全件 + リレーション直読みの結果を
///   in-memory フィルタ + ソートする (Plan PoC Step 0.1 の方針を継承)。
/// - グループモードの表示分岐 (Plan: docs/plans/unclassified-segment-empty-bug.md):
///   - Root → `parent == nil` の Group のみ (Item は表示しない。ルート直下 Item は未分類モードに分離)。
///   - Group X → X 直下の **子 Group + 子 Item を 1 リストに混在** させ createdAt 降順
///     (`directContents(group:)` + `HomeRowEntry`)。
/// - 「未分類」モードは `RootView` 直下の独立 NavigationStack で `UnclassifiedListView` が
///   `@Query(sort:)` + in-memory `.filter { $0.group == nil }` を直接実行するので本ファイルの関数は経由しない
///   (Step 1.6 で `filterItems` / `directItems` を撤去済 — PoC Step 0.1 の理由により optional to-one の
///   `nil` 比較は `#Predicate` ではなく in-memory フィルタで行う)。
/// - 純関数化 (`enum HomeQueries` + static func) で View から切り離し、`SegmentQueryTests`
///   (Plan Step 5.5) のフィクスチャ駆動テストの対象にする。
///
/// 検索 UI はパンくず実装で一旦削除済み。再導入時の仕様リファレンスは `SegmentQueryTests` 末尾の
/// コメントブロックに残してある (TODO「検索 UI を再導入する」)。
enum HomeQueries {
    /// 「グループ」セグメント本文の表示リスト。scope 直下の Group のみを「直下 Item の最新
    /// createdAt 降順 (空 Group は末尾)」で返す。
    static func filterGroups(allGroups: [ItemGroup], scope: SegmentScope) -> [ItemGroup] {
        sortDirectGroups(directGroups(allGroups: allGroups, scope: scope))
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

    /// Group X 直下の **子 Group + 子 Item を 1 リストに混在** させた表示用配列を `createdAt` 降順で返す
    /// (Plan: docs/plans/unclassified-segment-empty-bug.md「確定した設計」)。
    ///
    /// 並び順は `createdAt` 降順のみで、Group / Item のセクション分けは行わない (シンプル優先)。
    /// Root scope (`parent == nil` の Group のみ表示) には用いず、`GroupListView` の `.group(X)` branch
    /// 専用。
    static func directContents(group: ItemGroup) -> [HomeRowEntry] {
        let entries: [HomeRowEntry] =
            group.children.map(HomeRowEntry.group) + group.items.map(HomeRowEntry.item)
        return entries.sorted { $0.createdAt > $1.createdAt }
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

/// Group 詳細でのリスト行 1 件を表す sum type (Plan: docs/plans/unclassified-segment-empty-bug.md)。
///
/// `GroupListView` の `.group(X)` branch で「子 Group + 子 Item」を 1 リストに混在させるために用いる。
/// `Identifiable` の `id` は元モデルの UUID を流用 (`Item.id` / `ItemGroup.id` の両方が
/// `@Attribute(.unique) UUID` で実質的に衝突しない)。
enum HomeRowEntry: Identifiable {
    case group(ItemGroup)
    case item(Item)

    var id: UUID {
        switch self {
        case .group(let g): return g.id
        case .item(let i): return i.id
        }
    }

    /// 混在ソート用。Group も Item も `createdAt: Date` を持つので 1 軸で降順ソートできる。
    var createdAt: Date {
        switch self {
        case .group(let g): return g.createdAt
        case .item(let i): return i.createdAt
        }
    }
}
