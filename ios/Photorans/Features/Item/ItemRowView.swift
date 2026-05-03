import SwiftUI

/// `.processing` / `.completed` / `.failed` で表示を分岐する Item 行 View (S6 b / c / Plan Step 3.7)。
///
/// - `.processing`: プレースホルダ + `ShimmerOverlay`、行全体に `accessibilityLabel("処理中")`。
/// - `.completed`: 訳文プレビュー + 撮影日時 (旧 `HistoryRowView` 相当の最低限表示)。
/// - `.failed`: 失敗メッセージ + リトライボタン。`retryCount >= maxRetryCount` の Item は
///   `TranslationCoordinator.retry` 側で no-op になるためボタンを `disabled` にし、
///   「これ以上自動リトライしません」を併記する。
struct ItemRowView: View {
    let item: Item

    @Environment(\.translationCoordinator) private var coordinator

    var body: some View {
        switch item.status {
        case .processing:
            processingRow
        case .completed:
            completedRow
        case .failed:
            failedRow
        }
    }

    private var processingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("翻訳中…")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(ShimmerOverlay())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("処理中")
    }

    private var completedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.translatedText ?? "(翻訳なし)")
                .font(.body)
                .lineLimit(2)
            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var failedRow: some View {
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
        .padding(.vertical, 4)
    }
}
