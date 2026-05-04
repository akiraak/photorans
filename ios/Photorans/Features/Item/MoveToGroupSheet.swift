import SwiftData
import SwiftUI

/// Item を別 Group へ移動するシート (Plan Step 4.3 / S8)。
///
/// - 全 Group のフラットリスト + 「未分類に移動」を提示。タップで `item.group` を更新して dismiss。
/// - Group は同名でも階層が違えば別物なので、各行に祖先パス (例: "親 / 子") を補助表示する。
/// - 現在の所属には ✓ を付け、操作前後の差分が分かるようにする。
struct MoveToGroupSheet: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ItemGroup.name) private var allGroups: [ItemGroup]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        move(to: nil)
                    } label: {
                        HStack {
                            Label("未分類に移動", systemImage: "tray")
                                .foregroundStyle(.primary)
                            Spacer()
                            if item.group == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }

                if !allGroups.isEmpty {
                    Section("フォルダ") {
                        ForEach(allGroups, id: \.id) { group in
                            Button {
                                move(to: group)
                            } label: {
                                groupRow(for: group)
                            }
                        }
                    }
                }
            }
            .navigationTitle("フォルダへ移動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }

    private func groupRow(for group: ItemGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .foregroundStyle(.primary)
                if let path = ancestorPath(for: group) {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.group?.id == group.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func move(to group: ItemGroup?) {
        item.group = group
        try? modelContext.save()
        dismiss()
    }

    /// 当該 Group の祖先名を ` / ` で連結して返す (Group 自身は含めない)。
    /// 祖先が無ければ nil。
    private func ancestorPath(for group: ItemGroup) -> String? {
        var ancestors: [String] = []
        var node = group.parent
        while let current = node {
            ancestors.insert(current.name, at: 0)
            node = current.parent
        }
        return ancestors.isEmpty ? nil : ancestors.joined(separator: " / ")
    }
}
