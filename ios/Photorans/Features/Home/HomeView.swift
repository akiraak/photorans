import SwiftData
import SwiftUI

/// Root と Group 詳細で共通利用するセグメントスクリーン (S1 / S13-2)。
///
/// 上部に `[未分類 | グループ]` の Segmented Picker、本文に対応するリスト、
/// 右下に 2 段スタックの `HomeFAB` (Group 作成 / カメラ) を重ねる。
///
/// `navigationTitle` / `navigationDestination` は宣言しない:
/// - destination は `RootView` の NavigationStack root に集約 (Step 0.3 / 2.3)。子 View での再宣言は禁止。
///
/// ナビバー削除 + パンくずリンク導入 (Plan: docs/plans/breadcrumb-navigation.md / TestFlight v0.1.18 反映):
/// - `path: Binding<NavigationPath>?` を任意で受け取る。Root インスタンスでは nil で渡され、
///   `GroupDetailView` インスタンスでは `RootView.@State path` の Binding が伝播される。
/// - `scope` が `.group` かつ `selectedSegment == .groups` かつ `path != nil` のときだけ
///   Picker 直下にパンくず行を描画する。Root / 未分類タブ / path 非伝搬は描画しない。
/// - パンくず行は **`[←] 親 › 子 › [現在地] [⋯]`** の 1 行に統合する (TestFlight v0.1.18 フィードバック)。
///   従前のカスタム上部行は廃止し、戻るボタンとメニュー (名前を編集 / グループ削除) はこの行に収める。
/// - 未分類タブでは行ごと出さない。戻りたい場合は edge swipe / グループタブへ切替後の戻るボタンを使う。
struct HomeView: View {
    let scope: SegmentScope
    var path: Binding<NavigationPath>? = nil
    /// Group 詳細から渡される「名前を編集」ハンドラ。Root では nil。
    var onRenameGroup: (() -> Void)? = nil
    /// Group 詳細から渡される「グループ削除」ハンドラ。Root では nil。
    var onDeleteGroup: (() -> Void)? = nil

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

            breadcrumbRow

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottomTrailing) {
            HomeFAB(scope: scope)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
        }
        // ナビバー領域を 0pt にする (Plan Phase 2)。Root と Group 詳細の両方で HomeView が
        // 描画されるため、HomeView 側で常に hidden を宣言しておくと nested destination
        // (Group → SubGroup) でも確実に navbar が消える。
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// `[←] 親 › 子 › [現在地] [⋯]` の 1 行。グループタブ + .group scope + path 伝搬時のみ表示。
    @ViewBuilder
    private var breadcrumbRow: some View {
        if case .group(let g) = scope,
           selectedSegment == .groups,
           let pathBinding = path {
            let chain = BreadcrumbView.ancestorChain(of: g)
            HStack(spacing: 8) {
                Button {
                    if !pathBinding.wrappedValue.isEmpty {
                        pathBinding.wrappedValue.removeLast()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("戻る")

                BreadcrumbView(chain: chain) { tappedIndex in
                    let k = BreadcrumbView.popCount(chainLength: chain.count, tappedIndex: tappedIndex)
                    if k > 0 {
                        pathBinding.wrappedValue.removeLast(k)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let onRename = onRenameGroup, let onDelete = onDeleteGroup {
                    Menu {
                        Button {
                            onRename()
                        } label: {
                            Label("名前を編集", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("グループを削除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32, alignment: .trailing)
                    }
                    .accessibilityLabel("グループ メニュー")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
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
///
/// 並び順は `[未分類 | グループ]` (S2 既定値「未分類」を左側に置く)。`allCases` の順序が
/// Picker の表示順序になるため、enum の宣言順序を変更しないこと。
enum HomeSegment: String, CaseIterable, Identifiable {
    case unclassified
    case groups

    var id: String { rawValue }

    var label: String {
        switch self {
        case .groups: return "グループ"
        case .unclassified: return "未分類"
        }
    }
}
