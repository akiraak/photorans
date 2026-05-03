import Foundation
import SwiftData

/// 起動時に `.processing` で残っている Item を全件検出し、`TranslationCoordinator.retry` 経路で
/// 翻訳を再開するサービス (Plan Step 5.3 / S6 a の kill 復帰)。
///
/// 設計の要点:
/// - 件数フィルタ (retryCount 上限到達のスキップ等) は **行わない**。`maxRetryCount` に達した Item は
///   `TranslationCoordinator.retry` 側で no-op になるため、上限管理は coordinator 1 箇所に集約する。
///   ここで二重に判定するとロジックが分散して保守性が下がる。
/// - `retry` を closure として注入することで `PendingItemRecoveryTests` (Plan Step 5.6) から
///   `TranslationCoordinator` を mock した単体テストを可能にする。
/// - `ModelContext` は actor 越境させず、本関数内で `ModelContext(container)` を生成して使い切る
///   (Plan PoC Step 0.2)。`PersistentIdentifier` のみが background actor を越えて流れる。
/// - `StoreBootstrap` のフォールバック直後に呼ばれても安全 (フォールバック時は新ストアが空なので 0 件)。
enum PendingItemRecovery {
    typealias RetryFunction = @Sendable (PersistentIdentifier) async -> Void

    /// `.processing` Item を順次 `retry` に流す。失敗・取得不能時は silent (起動シーケンスを止めない)。
    static func runIfNeeded(
        container: ModelContainer,
        retry: RetryFunction
    ) async {
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<Item>()) else { return }
        let processingIDs = items
            .filter { $0.status == .processing }
            .map { $0.persistentModelID }
        for id in processingIDs {
            await retry(id)
        }
    }
}
