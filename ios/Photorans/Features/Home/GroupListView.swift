import SwiftData
import SwiftUI

/// 「グループ」セグメントの本文 (S3-1)。
///
/// PoC Step 0.1 の結論により Predicate を使わず、リレーション直読み + in-memory フィルタ + ソートで統一する。
///
/// フィルタ + ソートは `HomeQueries.filterGroups` (Plan Step 5.2) に純関数化されており、本 View は
/// `@Query` で取得した全 Group をそれに渡すだけ:
/// scope 直下の Group のみ (Root → parent == nil / Group X → X.children) を、
/// 直下 Item の最新 createdAt 降順 (Item ゼロの中間 Group は末尾) で表示。
///
/// 行タップで `NavigationLink(value: ItemGroup)` を発行し、destination 解決は `RootView` に集約された
/// `.navigationDestination(for: ItemGroup.self)` が担当する (Step 0.3 で確定。子 View では destination を再宣言しない)。
struct GroupListView: View {
    let scope: SegmentScope

    @Query private var allGroups: [ItemGroup]

    var body: some View {
        let groups = HomeQueries.filterGroups(allGroups: allGroups, scope: scope)
        if groups.isEmpty {
            emptyView
        } else {
            List(groups, id: \.id) { group in
                NavigationLink(value: group) {
                    rowView(for: group)
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        ContentUnavailableView {
            Label("グループはまだありません", systemImage: "folder")
        } description: {
            Text("翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。")
        }
    }

    @ViewBuilder
    private func rowView(for group: ItemGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.headline)
                Text(subtitle(for: group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(for group: ItemGroup) -> String {
        let itemCount = group.items.count
        let childCount = group.children.count
        if childCount > 0 {
            return "\(itemCount) 件 ・ サブグループ \(childCount)"
        } else {
            return "\(itemCount) 件"
        }
    }
}
