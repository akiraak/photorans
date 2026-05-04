import SwiftData
import SwiftUI

/// 新規 ItemGroup を作成するシート (S7 / S13-5)。
///
/// - 親階層は `scope.targetGroup`: Root → nil (= ルート Group)、Group X → X の子。
/// - 「キャンセル」「作成」の 2 アクション。空白のみの名前は無効。
struct GroupCreateSheet: View {
    let scope: SegmentScope

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("フォルダ名", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit { attemptCreate() }
                } footer: {
                    if let parent = scope.targetGroup {
                        Text("「\(parent.name)」の中に作成されます。")
                    } else {
                        Text("ルート階層に作成されます。")
                    }
                }
            }
            .navigationTitle("新しいフォルダ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { attemptCreate() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attemptCreate() {
        let trimmed = trimmedName
        guard !trimmed.isEmpty else { return }
        let group = ItemGroup(name: trimmed, parent: scope.targetGroup)
        modelContext.insert(group)
        dismiss()
    }
}
