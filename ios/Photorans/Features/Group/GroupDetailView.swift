import SwiftData
import SwiftUI

/// 特定の `ItemGroup` 詳細画面 (S13-2 / Plan Step 4.5 / 4.6)。
///
/// 中身は `HomeView(scope: .group(group))` を呼ぶラッパだが、
/// Group 自身の操作 (名前編集 / 削除) のツールバーをここに付ける。
///
/// - destination は **宣言しない** (Step 0.3。`RootView` の NavigationStack root に集約)。
/// - 削除は `ItemGroup.deleteRecursively(modelContext:)` (Step 4.6) を呼び、SwiftData の `.cascade` で
///   子 Group / Item を連鎖削除しつつ jpeg ファイルは traverse して `FileManager` から消す。
/// - 削除後は `dismiss()` で 1 階層戻る (Root or 親 Group 詳細)。
struct GroupDetailView: View {
    let group: ItemGroup

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRenameSheet = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        HomeView(scope: .group(group))
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isShowingRenameSheet = true
                        } label: {
                            Label("名前を編集", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("グループを削除", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("グループ メニュー")
                }
            }
            .sheet(isPresented: $isShowingRenameSheet) {
                GroupRenameSheet(group: group)
            }
            .confirmationDialog(
                "「\(group.name)」を削除しますか？",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) { performDelete() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
    }

    /// 確認ダイアログの本文。子 Group の有無で分岐する (S13-3)。
    private var deleteMessage: String {
        if !group.children.isEmpty {
            return "サブグループ \(group.children.count) 件と、配下の翻訳もすべて削除されます。元には戻せません。"
        }
        if !group.items.isEmpty {
            return "このグループに含まれる翻訳 \(group.items.count) 件もすべて削除されます。元には戻せません。"
        }
        return "このグループを削除します。元には戻せません。"
    }

    private func performDelete() {
        group.deleteRecursively(modelContext: modelContext)
        try? modelContext.save()
        dismiss()
    }
}
