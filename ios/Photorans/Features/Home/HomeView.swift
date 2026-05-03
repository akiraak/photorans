import SwiftData
import SwiftUI

/// Root と Group 詳細で共通利用するセグメントスクリーン (S1 / S13-2)。
///
/// 上部に `[グループ | 未分類]` の Segmented Picker、本文に対応するリスト、
/// 右下に 2 段スタックの `HomeFAB` (Group 作成 / カメラ) を重ねる。
///
/// `navigationTitle` / `navigationDestination` は宣言しない:
/// - タイトル付与は呼び出し側 (`RootView` / `GroupDetailView`) の責務 (Step 2.3 / 2.8)。
/// - destination は `RootView` の NavigationStack root に集約 (Step 0.3 / 2.3)。子 View での再宣言は禁止。
///
/// ナビバー削除 + パンくずリンク導入 (Plan: docs/plans/breadcrumb-navigation.md):
/// - `path: Binding<NavigationPath>?` を任意で受け取る。Root インスタンスでは nil で渡され、
///   `GroupDetailView` インスタンスでは `RootView.@State path` の Binding が伝播される。
/// - `scope` が `.group` かつ `selectedSegment == .groups` かつ `path != nil` のときだけ
///   Picker 直下にパンくず (`BreadcrumbView`) を描画する。Root / 未分類タブ / path 非伝搬は描画しない。
struct HomeView: View {
    let scope: SegmentScope
    var path: Binding<NavigationPath>? = nil

    /// アプリ起動 / Root 復帰時のデフォルトは `未分類` (S2)。Group 詳細でも初期値は `未分類` 統一で揃える。
    @State private var selectedSegment: HomeSegment = .unclassified

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

            breadcrumb

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            HomeFAB(scope: scope)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
        }
    }

    /// Picker 直下のパンくず行。条件を満たさないときは行ごと詰めるため `EmptyView` を返す。
    @ViewBuilder
    private var breadcrumb: some View {
        if case .group(let g) = scope,
           selectedSegment == .groups,
           let pathBinding = path {
            let chain = BreadcrumbView.ancestorChain(of: g)
            BreadcrumbView(chain: chain) { tappedIndex in
                let k = BreadcrumbView.popCount(chainLength: chain.count, tappedIndex: tappedIndex)
                if k > 0 {
                    pathBinding.wrappedValue.removeLast(k)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSegment {
        case .groups:
            GroupListView(scope: scope)
        case .unclassified:
            UnclassifiedListView(scope: scope)
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
