import Foundation

/// 翻訳言語コード (ISO 639-1) を UI 表示名に解決するヘルパ (Plan Step 3-1)。
///
/// サーバが返す `"en"` / `"ja"` を「英語」/「日本語」に変換する。
/// ヘルパ単独で運用する想定 (enum / Locale 非依存) で、想定外コードは raw を fallback、
/// nil は空文字を返す。呼び出し側はラベル組み立て時に空文字を見て括弧の有無を切り替える。
func languageDisplayName(_ code: String?) -> String {
    switch code {
    case "en": return "英語"
    case "ja": return "日本語"
    case let raw?: return raw
    case nil: return ""
    }
}
