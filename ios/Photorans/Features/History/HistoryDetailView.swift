import SwiftData
import SwiftUI

struct HistoryDetailView: View {
    let entry: HistoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photo
                section(title: "訳文 (日本語)", body: entry.translatedText)
                section(title: "原文", body: entry.originalText)
                metadata
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var photo: some View {
        let url = PhotoStorage.absoluteURL(for: entry.imagePath)
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.2))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("画像が見つかりません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("モデル: \(entry.model)")
            Text("撮影日時: \(entry.createdAt.formatted(date: .long, time: .standard))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
