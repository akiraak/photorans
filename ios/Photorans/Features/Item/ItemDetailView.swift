import SwiftData
import SwiftUI
import UIKit

/// Item 詳細画面 (Plan Step 4.1 / 4.2 / S6 / S8)。
///
/// 表示要素:
/// - 写真 (`item.imagePath` を `PhotoStorage.absoluteURL` で解決して `UIImage` 化)
/// - 本文: `.processing` は `TranslationProgressIndicator(style: .detail)` / `.completed` は訳文 + 原文 / `.failed` は失敗メッセージ + リトライ
/// - メタデータ: 撮影日時 / モデル名 / 所属 Group
///
/// ツールバー (右上 Menu):
/// - 「グループへ移動」→ `MoveToGroupSheet` を提示
/// - 「削除」→ 確認ダイアログ → jpeg を `FileManager.removeItem` で消した後 `modelContext.delete(item)`
///   して `dismiss()`。SwiftData の cascade は Item には作用しない (Group の cascade のみ) ので、
///   Item 単独削除はここで明示的に行う。
struct ItemDetailView: View {
    let item: Item

    @Environment(\.modelContext) private var modelContext
    @Environment(\.translationCoordinator) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingMoveSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoSection
                bodySection
                metadataSection
            }
            .padding(16)
        }
        .navigationTitle("詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isShowingMoveSheet = true
                    } label: {
                        Label("フォルダへ移動", systemImage: "folder")
                    }
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("詳細メニュー")
            }
        }
        .confirmationDialog(
            "この翻訳を削除しますか？",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { performDelete() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("写真と翻訳結果が完全に削除されます。元には戻せません。")
        }
        .sheet(isPresented: $isShowingMoveSheet) {
            MoveToGroupSheet(item: item)
        }
        .task(id: item.imagePath) {
            let url = PhotoStorage.absoluteURL(for: item.imagePath)
            image = UIImage(contentsOfFile: url.path)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var photoSection: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.15))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        switch item.status {
        case .processing:
            processingBody
        case .completed:
            completedBody
        case .failed:
            failedBody
        }
    }

    private var processingBody: some View {
        TranslationProgressIndicator(style: .detail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("処理中")
    }

    private var completedBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let translated = item.translatedText, !translated.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(translatedLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(translated)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            if let original = item.originalText, !original.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(originalLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(original)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var translatedLabel: String {
        let name = languageDisplayName(item.targetLanguage)
        return name.isEmpty ? "翻訳" : "翻訳 (\(name))"
    }

    private var originalLabel: String {
        let name = languageDisplayName(item.sourceLanguage)
        return name.isEmpty ? "原文" : "原文 (\(name))"
    }

    private var failedBody: some View {
        let canRetry = item.retryCount < Item.maxRetryCount
        return VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(item.failureReason ?? "翻訳に失敗しました")
                    .font(.body)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
            if !canRetry {
                Text("これ以上自動リトライしません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                guard let coordinator else { return }
                let itemID = item.persistentModelID
                Task { await coordinator.retry(itemID: itemID) }
            } label: {
                Label("リトライ", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRetry)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(label: "撮影日時", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let model = item.model {
                metadataRow(label: "モデル", value: model)
            }
            if let direction = translationDirection {
                metadataRow(label: "翻訳方向", value: direction)
            }
            metadataRow(label: "フォルダ", value: item.group?.name ?? "未分類")
        }
        .padding(.top, 8)
    }

    private var translationDirection: String? {
        guard let source = item.sourceLanguage, !source.isEmpty,
              let target = item.targetLanguage, !target.isEmpty else { return nil }
        return "\(source.uppercased()) → \(target.uppercased())"
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func performDelete() {
        let url = PhotoStorage.absoluteURL(for: item.imagePath)
        try? FileManager.default.removeItem(at: url)
        modelContext.delete(item)
        try? modelContext.save()
        dismiss()
    }
}
