import SwiftData
import SwiftUI

/// 「グループ」モードの本文 (S3-1 / Plan: docs/plans/unclassified-segment-empty-bug.md)。
///
/// PoC Step 0.1 の結論により Predicate を使わず、リレーション直読み + in-memory フィルタ + ソートで統一する。
///
/// 表示分岐 (scope 別):
/// - `.root` → `HomeQueries.filterGroups` (`parent == nil` の Group のみ。Item は表示しない。
///   ルート直下 Item は未分類モードに分離されている)。直下 Item の最新 createdAt 降順 (Item ゼロの中間 Group は末尾)。
/// - `.group(X)` → `HomeQueries.directContents(group: X)` (X.children + X.items を `HomeRowEntry` の
///   1 リストに混在、createdAt 降順)。子 Group は `rowView(for:)` + `NavigationLink(value: ItemGroup)`、
///   子 Item は `ItemRowView` + `NavigationLink(value: Item)` で行を発行する。
///
/// destination 解決は `RootView` のグループモード NavigationStack に集約された
/// `.navigationDestination(for: ItemGroup.self)` / `.navigationDestination(for: Item.self)` が担当する
/// (Step 0.3 で確定。子 View では destination を再宣言しない)。
struct GroupListView: View {
    let scope: SegmentScope

    @Query private var allGroups: [ItemGroup]

    var body: some View {
        switch scope {
        case .root:
            rootBody
        case .group(let g):
            groupBody(group: g)
        }
    }

    @ViewBuilder
    private var rootBody: some View {
        let groups = HomeQueries.filterGroups(allGroups: allGroups, scope: .root)
        if groups.isEmpty {
            rootEmptyView
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
    private func groupBody(group: ItemGroup) -> some View {
        let entries = HomeQueries.directContents(group: group)
        if entries.isEmpty {
            groupEmptyView
        } else {
            List(entries) { entry in
                switch entry {
                case .group(let childGroup):
                    NavigationLink(value: childGroup) {
                        rowView(for: childGroup)
                    }
                case .item(let item):
                    NavigationLink(value: item) {
                        ItemRowView(item: item)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var rootEmptyView: some View {
        ContentUnavailableView {
            Label("グループはまだありません", systemImage: "folder")
        } description: {
            Text("翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。")
        }
    }

    @ViewBuilder
    private var groupEmptyView: some View {
        ContentUnavailableView {
            Label("翻訳もグループもまだありません", systemImage: "tray")
        } description: {
            Text("右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいグループを作成できます。")
        }
    }

    /// グループ行の leading アイコンサイズ。Item 行のサムネと揃える
    /// (`docs/plans/list-thumbnails.md` Step 5)。
    private static let leadingSize = CGSize(width: 56, height: 56)

    @ViewBuilder
    private func rowView(for group: ItemGroup) -> some View {
        HStack(alignment: .top, spacing: 12) {
            leadingIcon(for: group)

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

    @ViewBuilder
    private func leadingIcon(for group: ItemGroup) -> some View {
        if let representative = HomeQueries.representativeItem(of: group) {
            ItemThumbnailView(imagePath: representative.imagePath, size: Self.leadingSize)
        } else {
            folderPlaceholder
        }
    }

    private var folderPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: Self.leadingSize.width, height: Self.leadingSize.height)
            .overlay(
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            )
            .accessibilityHidden(true)
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
