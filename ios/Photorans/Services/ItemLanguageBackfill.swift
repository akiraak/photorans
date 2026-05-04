import Foundation
import SwiftData

/// 起動時に `sourceLanguage` / `targetLanguage` が nil の Item を旧固定方向 (`"en"` / `"ja"`)
/// で埋めるバックフィルサービス (Plan 双方向翻訳 Phase 2 Step 2-3)。
///
/// 設計の要点:
/// - 双方向翻訳対応より前に作られた Item は両フィールドが nil。これらは過去の固定方向
///   (英→日) で取得されたものなので、`sourceLanguage = "en"` / `targetLanguage = "ja"` を埋める。
/// - 既に値が入っている Item には触れない (再起動時の冪等性確保)。
/// - `PendingItemRecovery.runIfNeeded` の前段で呼ぶ。recovery 経由で `.processing` の Item が
///   `.completed` に書き戻される際にも `TranslationCoordinator` が新しい言語値を入れるため、
///   バックフィルとレースしても整合性は保たれる (recovery は backfill より後に走る)。
/// - `ModelContext` は actor 越境させず、本関数内で `ModelContext(container)` を生成して使い切る
///   (`PendingItemRecovery` と同じ方針)。
/// - 件数フィルタは行わず単純に全件 fetch。個人スケール (せいぜい数百件) を前提にしている
///   ため性能問題なし (`TranslationCoordinator.fetchItem` の前例と同じ判断)。
enum ItemLanguageBackfill {
    /// 旧固定方向の言語コード。
    static let legacySourceLanguage = "en"
    static let legacyTargetLanguage = "ja"

    /// nil の Item を一括で旧固定方向で埋める。失敗時は silent (起動シーケンスを止めない)。
    static func runIfNeeded(container: ModelContainer) async {
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }

        var didChange = false
        for item in items where item.sourceLanguage == nil && item.targetLanguage == nil {
            item.sourceLanguage = legacySourceLanguage
            item.targetLanguage = legacyTargetLanguage
            didChange = true
        }
        if didChange {
            try? context.save()
        }
    }
}
