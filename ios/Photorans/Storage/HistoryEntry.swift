import Foundation
import SwiftData

@Model
final class HistoryEntry {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    /// Documents 配下の相対パス (例: `photos/<uuid>.jpg`)。
    /// アプリの再インストールや OS による Documents パス変更後も解決できるよう、絶対 URL ではなく相対パスを保持する。
    var imagePath: String
    var originalText: String
    var translatedText: String
    var model: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        imagePath: String,
        originalText: String,
        translatedText: String,
        model: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.originalText = originalText
        self.translatedText = translatedText
        self.model = model
    }
}
