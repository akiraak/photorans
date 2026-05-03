import Foundation

/// HomeView が「Root を表示しているのか / 特定の ItemGroup の詳細を表示しているのか」を表す文脈。
///
/// Root と Group 詳細で同じ `[グループ | 未分類]` セグメント UI を再利用するため、
/// HomeView と配下のリスト View はこの SegmentScope を受け取り、
/// `targetGroup` で「現在階層 = カメラ FAB / Group 作成 FAB の保存先」を解決する (S13-2 / S13-4 / S13-5)。
enum SegmentScope {
    case root
    case group(ItemGroup)

    /// 現在階層を ItemGroup として返す。Root → nil、Group X → X。
    /// カメラ FAB の保存先 (S13-4) と Group 作成 FAB の親 (S13-5) を統一的に解決するために用いる。
    var targetGroup: ItemGroup? {
        switch self {
        case .root:
            return nil
        case .group(let g):
            return g
        }
    }

    /// HomeView インスタンスを開いたときの初期セグメント (Plan: docs/plans/group-default-segment.md)。
    ///
    /// - Root: `.unclassified` (S2 既定値)。アプリ起動 / Root 復帰時の挙動は変えない。
    /// - Group 詳細: `.groups`。親グループからは必ず「グループタブ → サブグループタップ」の経路で
    ///   push されるため、遷移先で `未分類` から始めると操作の連続性が断ち切られる。
    var defaultSegment: HomeSegment {
        switch self {
        case .root:
            return .unclassified
        case .group:
            return .groups
        }
    }
}
