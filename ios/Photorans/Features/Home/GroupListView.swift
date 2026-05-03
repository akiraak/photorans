import SwiftData
import SwiftUI

/// 「グループ」セグメントの本文 (S3-1)。
///
/// PoC Step 0.1 の結論により Predicate を使わず、リレーション直読み + in-memory フィルタ + ソートで統一する。
///
/// - Root (`scope == .root`): `@Query` で全 Group を取得し、`parent == nil` をフィルタ (= ルート Group のみ)。
/// - Group X (`scope == .group(let g)`): `g.children` を直読み (= X の直下の子 Group)。
///
/// 並び順は **直下 Item の最新 createdAt 降順**。直下 Item ゼロの中間 Group は最新日時を持たないため末尾固定とし、
/// 同点同士は Group 自身の `createdAt` 降順で安定化する (S3-1 / impl plan Step 2.5)。
///
/// 行タップで `NavigationLink(value: ItemGroup)` を発行し、destination 解決は `RootView` に集約された
/// `.navigationDestination(for: ItemGroup.self)` が担当する (Step 0.3 で確定。子 View では destination を再宣言しない)。
struct GroupListView: View {
    let scope: SegmentScope

    @Query private var allGroups: [ItemGroup]

    var body: some View {
        let groups = sortedDirectGroups()
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

    private func directGroups() -> [ItemGroup] {
        switch scope {
        case .root:
            return allGroups.filter { $0.parent == nil }
        case .group(let g):
            return g.children
        }
    }

    private func sortedDirectGroups() -> [ItemGroup] {
        directGroups().sorted { lhs, rhs in
            let lhsLatest = lhs.items.map { $0.createdAt }.max()
            let rhsLatest = rhs.items.map { $0.createdAt }.max()
            switch (lhsLatest, rhsLatest) {
            case let (l?, r?):
                return l > r
            case (.some, nil):
                // 直下 Item のある Group を先に並べ、Item ゼロの中間 Group を末尾固定にする (S3-1)。
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                // 直下 Item ゼロ同士は安定化のため Group 自身の createdAt 降順。
                return lhs.createdAt > rhs.createdAt
            }
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
