import Foundation

/// Item の翻訳ライフサイクル状態。
///
/// - `processing`: 撮影直後に楽観的 UI で挿入された状態。背景で OCR + 翻訳実行中。
/// - `completed`: 翻訳成功。`originalText` / `translatedText` / `model` が埋まっている。
/// - `failed`: 翻訳失敗。`failureReason` にメッセージが入る。`retryCount` 上限内なら再試行可。
enum ItemStatus: String, Codable {
    case processing
    case completed
    case failed
}
