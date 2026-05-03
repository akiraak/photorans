import Foundation
import SwiftData

/// 撮影 + 翻訳 1 件分。楽観的 UI で `.processing` として即時挿入し、背景で翻訳結果を埋める。
///
/// - `status == .processing` の間は `originalText` / `translatedText` / `model` が nil。
/// - `status == .completed` で 3 つとも非 nil になる。
/// - `status == .failed` のときは `failureReason` にメッセージが入る。`retryCount` が
///   `Item.maxRetryCount` 未満なら自動 / 手動リトライ可。写真ファイル不在の致命エラーでは
///   `retryCount = maxRetryCount` を直接立てて以後の retry を no-op に固定する。
@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var createdAt: Date

    /// Documents 配下の相対パス (例: `photos/<uuid>.jpg`)。
    /// 旧 HistoryEntry と同じく、再インストール後も解決できるよう絶対 URL ではなく相対パスで保持する。
    var imagePath: String

    /// `ItemStatus` の生値 (rawValue) を SwiftData に保存する。`status` computed property 経由で読み書きする。
    /// `@Model` が enum を直接保存できる場面もあるが、文字列バックでマイグレーション時の取り回しを良くする。
    private var statusRaw: String

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    /// `.completed` 時のみ非 nil。
    var originalText: String?
    var translatedText: String?
    var model: String?

    /// `.failed` 時のみ非 nil。ユーザーに見せるエラーメッセージ。
    var failureReason: String?

    /// 自動 / 手動リトライの回数。`maxRetryCount` 以上は no-op。
    var retryCount: Int

    /// 所属 Group。nil なら未分類セグメントに表示される。
    var group: ItemGroup?

    /// 自動リトライの上限回数。これ以上は `TranslationCoordinator.retry` 側で no-op。
    static let maxRetryCount: Int = 3

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        imagePath: String,
        status: ItemStatus = .processing,
        originalText: String? = nil,
        translatedText: String? = nil,
        model: String? = nil,
        failureReason: String? = nil,
        retryCount: Int = 0,
        group: ItemGroup? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imagePath = imagePath
        self.statusRaw = status.rawValue
        self.originalText = originalText
        self.translatedText = translatedText
        self.model = model
        self.failureReason = failureReason
        self.retryCount = retryCount
        self.group = group
    }
}
