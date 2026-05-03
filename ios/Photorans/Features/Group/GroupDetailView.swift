import SwiftData
import SwiftUI

/// 特定の `ItemGroup` 詳細画面 (S13-2 / Plan Step 4.5 / 4.6)。
///
/// 中身は `HomeView(scope: .group(group))` を呼ぶラッパだが、
/// Group 自身の操作 (名前編集 / 削除) のメニューと戻るボタンをカスタム上部行として持つ。
///
/// - destination は **宣言しない** (Step 0.3。`RootView` の NavigationStack root に集約)。
/// - 削除は `ItemGroup.deleteRecursively(modelContext:)` (Step 4.6) を呼び、SwiftData の `.cascade` で
///   子 Group / Item を連鎖削除しつつ jpeg ファイルは traverse して `FileManager` から消す。
/// - 削除後は `dismiss()` で 1 階層戻る (Root or 親 Group 詳細)。
///
/// ナビバー削除 + パンくずリンク導入 (Plan: docs/plans/breadcrumb-navigation.md):
/// - `.navigationTitle` / `.navigationBarTitleDisplayMode` / `.toolbar { ToolbarItem(...) }` は使わず、
///   カスタム上部行 (戻る + 既存メニュー) を `HomeView(scope: .group(group))` の上に置く。
/// - 本体に `.toolbar(.hidden, for: .navigationBar)` を当ててナビバー領域を 0pt にする。
/// - パンくず本体は `HomeView` 側で Picker 直下に統合する (Phase 3)。本 View では `path` の Binding を
///   受け取って `HomeView` に中継するだけ。
struct GroupDetailView: View {
    let group: ItemGroup
    let path: Binding<NavigationPath>

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingRenameSheet = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            customTopBar
            HomeView(scope: .group(group), path: path)
        }
        // 子グループへ push したときに navbar が表示される事象 (TestFlight v0.1.17 で確認) への
        // 保険として、HomeView 側の `.toolbar(.hidden,...)` に加えて outer VStack 側でも宣言する。
        // `.toolbarBackground(.hidden,...)` も併用し、bar 自体が隠れない場合でも背景を透過させる。
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
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

    /// ナビバー削除後の上部行: 左に戻るボタン、右に既存メニュー。
    private var customTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("戻る")

            Spacer()

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
                    .font(.title3)
                    .frame(width: 44, height: 44, alignment: .trailing)
            }
            .accessibilityLabel("グループ メニュー")
        }
        .padding(.horizontal, 8)
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
