import SwiftData
import XCTest
@testable import Photorans

/// `TranslationCoordinator` 4 シナリオの単体テスト (Plan Step 3.9):
/// 1. 正常系 = `.processing` → `.completed` 更新 + 3 フィールド (originalText / translatedText / model) 反映
/// 2. 途中で Item を delete された場合の書き戻し silent no-op
/// 3. retry 上限 = 3 回で停止 (4 回目以降は translate 自体が呼ばれない)
/// 4. 写真ファイル不在 = `.failed` 確定 + retryCount = max + 以後 retry も no-op
final class TranslationCoordinatorTests: XCTestCase {
    func testEnqueueCompletesItemOnSuccess() async throws {
        let container = try Self.makeInMemoryContainer()
        let itemID = try Self.insertProcessingItem(in: container)

        let response = TranslateResponse(
            originalText: "Hello",
            translatedText: "こんにちは",
            model: "test-model"
        )
        let coordinator = TranslationCoordinator(
            container: container,
            translate: { _ in response },
            loadImage: { _ in Data() }
        )

        await coordinator.enqueue(itemID: itemID, jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))

        let context = ModelContext(container)
        let item = try XCTUnwrap(context[itemID, as: Item.self])
        XCTAssertEqual(item.status, .completed)
        XCTAssertEqual(item.originalText, "Hello")
        XCTAssertEqual(item.translatedText, "こんにちは")
        XCTAssertEqual(item.model, "test-model")
        XCTAssertNil(item.failureReason)
    }

    func testEnqueueIsSilentNoopWhenItemDeletedMidFlight() async throws {
        let container = try Self.makeInMemoryContainer()
        let itemID = try Self.insertProcessingItem(in: container)

        let translateStarted = AsyncSemaphore()
        let proceedTranslate = AsyncSemaphore()
        let coordinator = TranslationCoordinator(
            container: container,
            translate: { _ in
                await translateStarted.signal()
                await proceedTranslate.wait()
                return TranslateResponse(originalText: "x", translatedText: "y", model: "z")
            },
            loadImage: { _ in Data() }
        )

        // enqueue を別タスクで起動し、translate が走り出した時点で MainActor 側から削除する。
        // その後 translate を解放して書き戻し試行 → 削除済 Item に対する silent no-op を確認。
        let task = Task {
            await coordinator.enqueue(itemID: itemID, jpegData: Data([0xFF]))
        }

        await translateStarted.wait()

        let deleteCtx = ModelContext(container)
        if let target = deleteCtx[itemID, as: Item.self] {
            deleteCtx.delete(target)
            try deleteCtx.save()
        }

        await proceedTranslate.signal()
        await task.value

        let verifyCtx = ModelContext(container)
        XCTAssertNil(
            verifyCtx[itemID, as: Item.self],
            "削除済 Item が書き戻しで復活してはならない"
        )
    }

    func testRetryStopsAfterMaxAttempts() async throws {
        let container = try Self.makeInMemoryContainer()
        let itemID = try Self.insertFailedItem(in: container)

        let counter = CallCounter()
        let coordinator = TranslationCoordinator(
            container: container,
            translate: { _ in
                await counter.increment()
                throw TranslateError.timeout
            },
            loadImage: { _ in Data([0xFF, 0xD8, 0xFF, 0xD9]) }
        )

        // 5 回呼び出す。max = 3 を超えた回は coordinator 側で no-op (translate も呼ばれない)。
        for _ in 0..<5 {
            await coordinator.retry(itemID: itemID)
        }

        let context = ModelContext(container)
        let item = try XCTUnwrap(context[itemID, as: Item.self])
        XCTAssertEqual(item.retryCount, Item.maxRetryCount)
        XCTAssertEqual(item.status, .failed)

        let calls = await counter.value
        XCTAssertEqual(
            calls,
            Item.maxRetryCount,
            "translate は maxRetryCount (=\(Item.maxRetryCount)) 回しか呼ばれないはず"
        )
    }

    func testRetryMarksFailedAndStopsWhenImageMissing() async throws {
        let container = try Self.makeInMemoryContainer()
        let itemID = try Self.insertFailedItem(in: container)

        let translateCounter = CallCounter()
        let loadAttempts = CallCounter()
        let coordinator = TranslationCoordinator(
            container: container,
            translate: { _ in
                await translateCounter.increment()
                return TranslateResponse(originalText: "_", translatedText: "_", model: "_")
            },
            loadImage: { _ in
                await loadAttempts.increment()
                throw CocoaError(.fileNoSuchFile)
            }
        )

        await coordinator.retry(itemID: itemID)

        let context = ModelContext(container)
        let item = try XCTUnwrap(context[itemID, as: Item.self])
        XCTAssertEqual(item.status, .failed)
        XCTAssertEqual(item.retryCount, Item.maxRetryCount)
        XCTAssertEqual(item.failureReason, "画像ファイルが見つかりません")

        let translateCalls = await translateCounter.value
        XCTAssertEqual(translateCalls, 0, "ファイルロード失敗時は translate を呼ばないこと")

        // 写真ファイル不在で max を立てた以降は retry 呼び出し自体が no-op。
        // loadImage も呼ばれず、translate も呼ばれない。
        await coordinator.retry(itemID: itemID)
        let secondLoadAttempts = await loadAttempts.value
        XCTAssertEqual(secondLoadAttempts, 1, "max 到達後の retry は loadImage を呼ばない")
        let secondTranslateCalls = await translateCounter.value
        XCTAssertEqual(secondTranslateCalls, 0)
    }

    // MARK: - Helpers

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func insertProcessingItem(in container: ModelContainer) throws -> PersistentIdentifier {
        let context = ModelContext(container)
        let item = Item(imagePath: "photos/test.jpg", status: .processing)
        context.insert(item)
        try context.save()
        return item.persistentModelID
    }

    private static func insertFailedItem(in container: ModelContainer) throws -> PersistentIdentifier {
        let context = ModelContext(container)
        let item = Item(
            imagePath: "photos/test.jpg",
            status: .failed,
            failureReason: "前回の失敗",
            retryCount: 0
        )
        context.insert(item)
        try context.save()
        return item.persistentModelID
    }
}

/// テスト専用の単純な呼び出しカウンタ。`@Sendable` closure 内で副作用を持つために actor 化する。
private actor CallCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// テスト専用の極小 async semaphore。`AsyncStream` でシグナル待ちを表現するだけの最小実装。
/// `XCTestExpectation` を Sendable closure 内から `fulfill` するパターンも可能だが、
/// 「signal が来てから wait 側を解放する」ような順序制御には向かないのでこちらを使う。
private actor AsyncSemaphore {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var pendingSignals: Int = 0

    func wait() async {
        if pendingSignals > 0 {
            pendingSignals -= 1
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuations.append(cont)
        }
    }

    func signal() {
        if continuations.isEmpty {
            pendingSignals += 1
        } else {
            let cont = continuations.removeFirst()
            cont.resume()
        }
    }
}
