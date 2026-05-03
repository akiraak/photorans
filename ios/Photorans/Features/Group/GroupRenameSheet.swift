import SwiftData
import SwiftUI

/// 既存 ItemGroup の名前を編集するシート (Plan Step 4.5 / S7)。
///
/// 空白のみの名前は無効。送信時に `group.name` を更新し dismiss。
struct GroupRenameSheet: View {
    let group: ItemGroup

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("グループ名", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { attemptRename() }
                }
            }
            .navigationTitle("グループ名を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { attemptRename() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear {
                name = group.name
                isNameFocused = true
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attemptRename() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        group.name = trimmed
        try? modelContext.save()
        dismiss()
    }
}
