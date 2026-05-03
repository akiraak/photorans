import SwiftData
import SwiftUI

/// Root と Group 詳細で共通利用するセグメントスクリーン (S1 / S13-2)。
///
/// 上部に `[グループ | 未分類]` の Segmented Picker、本文に対応するリスト、
/// 右下に 2 段スタックの `HomeFAB` (Group 作成 / カメラ) を重ねる。
///
/// 検索 (Plan Step 5.1):
/// - `.searchable` は **HomeView 1 箇所だけ** で宣言する。子 View (GroupListView / UnclassifiedListView)
///   は `searchText` を引数で受け取りフィルタにのみ使う (子 View で `.searchable` を再宣言すると
///   検索 UI が点滅するため禁止)。
/// - `searchText` は HomeView の `@State`。各 HomeView インスタンス (Root / 各 Group 詳細) ごとに独立。
///
/// `navigationTitle` / `navigationDestination` は宣言しない:
/// - タイトル付与は呼び出し側 (`RootView` / `GroupDetailView`) の責務 (Step 2.3 / 2.8)。
/// - destination は `RootView` の NavigationStack root に集約 (Step 0.3 / 2.3)。子 View での再宣言は禁止。
struct HomeView: View {
    let scope: SegmentScope

    /// アプリ起動 / Root 復帰時のデフォルトは `未分類` (S2)。Group 詳細でも初期値は `未分類` 統一で揃える。
    @State private var selectedSegment: HomeSegment = .unclassified

    /// 現セグメント / scope の `HomeQueries` フィルタに渡す検索文字列。空文字列でフィルタ無し (S14)。
    @State private var searchText: String = ""

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

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            HomeFAB(scope: scope)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
        }
        .searchable(text: $searchText, prompt: "翻訳・グループ名を検索")
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSegment {
        case .groups:
            GroupListView(scope: scope, searchText: searchText)
        case .unclassified:
            UnclassifiedListView(scope: scope, searchText: searchText)
        }
    }
}

/// HomeView 上部の Segmented Picker 用のセグメント識別子。
enum HomeSegment: String, CaseIterable, Identifiable {
    case groups
    case unclassified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groups: return "グループ"
        case .unclassified: return "未分類"
        }
    }
}
