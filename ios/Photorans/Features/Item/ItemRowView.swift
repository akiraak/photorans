import SwiftUI

/// `.processing` / `.completed` / `.failed` で表示を分岐する Item 行 View (S6 b / c / Plan Step 3.7)。
///
/// - `.processing`: `TranslationProgressIndicator(style: .row)` + 撮影日時、行全体に `accessibilityLabel("処理中")`。
/// - `.completed`: 訳文プレビュー + 撮影日時 (旧 `HistoryRowView` 相当の最低限表示)。
/// - `.failed`: 失敗メッセージ + リトライボタン。`retryCount >= maxRetryCount` の Item は
///   `TranslationCoordinator.retry` 側で no-op になるためボタンを `disabled` にし、
///   「これ以上自動リトライしません」を併記する。
///
/// 全ステータスで行 leading に 56pt サムネを表示する (`docs/plans/list-thumbnails.md` Step 3)。
/// `.processing` でも撮影直後に jpeg は保存済みなのでサムネは出る。
struct ItemRowView: View {
    let item: Item

    @Environment(\.translationCoordinator) private var coordinator

    private static let thumbnailSize = CGSize(width: 56, height: 56)

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ItemThumbnailView(imagePath: item.imagePath, size: Self.thumbnailSize)
            content
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch item.status {
        case .processing:
            processingContent
        case .completed:
            completedContent
        case .failed:
            failedContent
        }
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            TranslationProgressIndicator(style: .row)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("処理中")
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.translatedText ?? "(翻訳なし)")
                .font(.body)
                .lineLimit(2)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var failedContent: some View {
        let canRetry = item.retryCount < Item.maxRetryCount
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(item.failureReason ?? "翻訳に失敗しました")
                        .font(.body)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                }
                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !canRetry {
                    Text("これ以上自動リトライしません")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button {
                guard let coordinator else { return }
                let itemID = item.persistentModelID
                Task { await coordinator.retry(itemID: itemID) }
            } label: {
                Label("リトライ", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canRetry)
        }
    }
}
