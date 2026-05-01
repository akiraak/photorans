import SwiftUI

struct TranslateResultItem: Identifiable, Equatable {
    let id: UUID = UUID()
    let originalText: String
    let translatedText: String
    let model: String

    init(originalText: String, translatedText: String, model: String) {
        self.originalText = originalText
        self.translatedText = translatedText
        self.model = model
    }

    init(_ response: TranslateResponse) {
        self.originalText = response.originalText
        self.translatedText = response.translatedText
        self.model = response.model
    }
}

struct TranslateResultView: View {
    let result: TranslateResultItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(title: "訳文 (日本語)", body: result.translatedText)
                    section(title: "原文 (英語)", body: result.originalText)
                    Text("モデル: \(result.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("翻訳結果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
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
}
