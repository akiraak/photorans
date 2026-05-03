import Foundation
import SwiftData
import SwiftUI

/// 撮影直後に `.processing` で挿入された `Item` を、background actor で翻訳して結果を書き戻す
/// コーディネータ (Plan Step 3.1 / 3.2)。
///
/// 設計の要点:
/// - `ModelContainer` のみを保持し、`ModelContext` は各エントリポイント内で都度生成する
///   (`ModelContext` / `@Model` は `Sendable` ではないため actor 越境禁止 — Plan PoC Step 0.2)。
/// - `enqueue` は撮影直後の初回翻訳。MainActor 側で既に `.processing` として save 済みの Item に
///   対し、`PersistentIdentifier` 経由で background fetch + 翻訳実行 + 書き戻し。
///   書き戻し前に `ctx[itemID]` で **存在確認** し、途中削除されていれば silent no-op。
/// - `retry` は `.failed` Item の手動 / 自動リトライ。`Item.maxRetryCount` を超えた呼び出しは
///   no-op、写真ファイル不在は致命扱いで `retryCount = max` を立てて以後の retry を止める。
/// - `translate` / `loadImage` を初期化時に DI 可能にしてあり、テスト
///   (`TranslationCoordinatorTests`) では mock を渡してネット / 実 Documents への副作用を分離する。
actor TranslationCoordinator {
    typealias TranslateFunction = @Sendable (Data) async throws -> TranslateResponse
    typealias LoadImageFunction = @Sendable (String) throws -> Data

    private let container: ModelContainer
    private let translate: TranslateFunction
    private let loadImage: LoadImageFunction

    init(
        container: ModelContainer,
        translate: @escaping TranslateFunction = { data in
            try await TranslateAPI.shared.translate(jpegData: data)
        },
        loadImage: @escaping LoadImageFunction = { relativePath in
            try Data(contentsOf: PhotoStorage.absoluteURL(for: relativePath))
        }
    ) {
        self.container = container
        self.translate = translate
        self.loadImage = loadImage
    }

    /// 撮影直後の初回翻訳。CameraViewModel が `.processing` として MainActor 側で
    /// insert + save 済みの Item ID を受け取り、background で翻訳を実行する。
    func enqueue(itemID: PersistentIdentifier, jpegData: Data) async {
        await runTranslation(itemID: itemID, jpegData: jpegData)
    }

    /// `.failed` Item の手動 / 自動リトライ。
    ///
    /// - `retryCount >= maxRetryCount` → 即 no-op (PendingItemRecovery からの起動時自動リトライも同じ上限に従う)。
    /// - 写真ファイル不在 → `failureReason` に固定文言を入れ、`retryCount = maxRetryCount` を立てて
    ///   以後の自動リトライを永久停止する (Plan Step 3.2)。
    func retry(itemID: PersistentIdentifier) async {
        let context = ModelContext(container)
        guard let item = context[itemID, as: Item.self] else { return }
        guard item.retryCount < Item.maxRetryCount else { return }

        item.retryCount += 1
        item.status = .processing
        item.failureReason = nil

        let jpegData: Data
        do {
            jpegData = try loadImage(item.imagePath)
        } catch {
            item.status = .failed
            item.failureReason = "画像ファイルが見つかりません"
            item.retryCount = Item.maxRetryCount
            try? context.save()
            return
        }
        try? context.save()

        await runTranslation(itemID: itemID, jpegData: jpegData)
    }

    /// 翻訳実行 + 結果書き戻しの共通本体。
    /// 翻訳完了 *後* に再度 `ctx[itemID]` で存在確認することで、楽観的 UI 中に
    /// ユーザーが詳細から Item を削除した場合のレースを silent no-op で吸収する (Plan Step 3.1)。
    private func runTranslation(itemID: PersistentIdentifier, jpegData: Data) async {
        let result: Result<TranslateResponse, Error>
        do {
            let response = try await translate(jpegData)
            result = .success(response)
        } catch {
            result = .failure(error)
        }

        let context = ModelContext(container)
        guard let item = context[itemID, as: Item.self] else { return }

        switch result {
        case .success(let response):
            item.status = .completed
            item.originalText = response.originalText
            item.translatedText = response.translatedText
            item.model = response.model
            item.failureReason = nil
        case .failure(let error):
            item.status = .failed
            item.failureReason = error.localizedDescription
        }
        try? context.save()
    }
}

/// `TranslationCoordinator` を SwiftUI Environment 経由で配布するためのキー。
///
/// `PhotoransApp` の `@State` で 1 インスタンスを保持し、ルートで
/// `.environment(\.translationCoordinator, coordinator)` を注入する。
/// View が `@Environment(\.translationCoordinator)` で取り出して使う構成
/// (Plan Step 3.1 — View 再生成で coordinator が cancel されないようライフサイクルを App に集約)。
private struct TranslationCoordinatorKey: EnvironmentKey {
    static let defaultValue: TranslationCoordinator? = nil
}

extension EnvironmentValues {
    var translationCoordinator: TranslationCoordinator? {
        get { self[TranslationCoordinatorKey.self] }
        set { self[TranslationCoordinatorKey.self] = newValue }
    }
}
