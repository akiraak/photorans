import SwiftData
import XCTest
@testable import Photorans

/// `PendingItemRecovery.runIfNeeded` の挙動を検証する (Plan Step 5.6 / S6 a の kill 復帰)。
///
/// 検証観点:
/// - `.processing` Item のみが `retry` closure に流れ、`.completed` / `.failed` は流れないこと。
/// - 全件無し / `.processing` 無しのケースで silent no-op になること。
/// - `retryCount >= maxRetryCount` の `.processing` Item も呼び出し対象に含めること
///   (上限管理は coordinator 側に集約する設計のため、recovery 側ではフィルタしない — Plan Step 5.3)。
final class PendingItemRecoveryTests: XCTestCase {
    func testOnlyProcessingItemsAreRetried() async throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let processing1 = Item(imagePath: "photos/p1.jpg", status: .processing)
        let processing2 = Item(imagePath: "photos/p2.jpg", status: .processing)
        let failed1 = Item(imagePath: "photos/f1.jpg", status: .failed, failureReason: "timeout")
        let failed2 = Item(
            imagePath: "photos/f2.jpg",
            status: .failed,
            failureReason: "max",
            retryCount: Item.maxRetryCount
        )
        let completed1 = Item(
            imagePath: "photos/c1.jpg",
            status: .completed,
            originalText: "x",
            translatedText: "y",
            model: "m"
        )

        for item in [processing1, processing2, failed1, failed2, completed1] {
            context.insert(item)
        }
        try context.save()

        let processingIDs = Set([processing1.persistentModelID, processing2.persistentModelID])

        let recorder = CallRecorder()
        await PendingItemRecovery.runIfNeeded(
            container: container,
            retry: { id in await recorder.append(id) }
        )

        let calledIDs = await recorder.values
        XCTAssertEqual(
            Set(calledIDs),
            processingIDs,
            ".processing Item のみが retry に流れること (failed / completed は流れない)"
        )
        XCTAssertEqual(calledIDs.count, 2, ".processing 2 件分のみ呼ばれること")
    }

    func testNoOpWhenNoProcessingItems() async throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let completed = Item(
            imagePath: "photos/c.jpg",
            status: .completed,
            originalText: "x",
            translatedText: "y",
            model: "m"
        )
        let failed = Item(imagePath: "photos/f.jpg", status: .failed, failureReason: "x")
        context.insert(completed)
        context.insert(failed)
        try context.save()

        let recorder = CallRecorder()
        await PendingItemRecovery.runIfNeeded(
            container: container,
            retry: { id in await recorder.append(id) }
        )

        let calls = await recorder.values
        XCTAssertTrue(calls.isEmpty, ".processing が無ければ retry は呼ばれない")
    }

    func testNoOpWhenStoreEmpty() async throws {
        let container = try Self.makeInMemoryContainer()

        let recorder = CallRecorder()
        await PendingItemRecovery.runIfNeeded(
            container: container,
            retry: { id in await recorder.append(id) }
        )

        let calls = await recorder.values
        XCTAssertTrue(calls.isEmpty)
    }

    func testProcessingAtMaxRetryCountStillFlowsToCoordinator() async throws {
        // recovery 側は上限フィルタしないことを明示するテスト (Plan Step 5.3 の設計判断)。
        // `retryCount >= maxRetryCount` の `.processing` も coordinator に流し、coordinator 側で
        // no-op にさせるのが正しい (上限管理を 1 箇所に集約する)。
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let exhausted = Item(
            imagePath: "photos/exhausted.jpg",
            status: .processing,
            retryCount: Item.maxRetryCount
        )
        context.insert(exhausted)
        try context.save()

        let recorder = CallRecorder()
        await PendingItemRecovery.runIfNeeded(
            container: container,
            retry: { id in await recorder.append(id) }
        )

        let calls = await recorder.values
        XCTAssertEqual(
            calls,
            [exhausted.persistentModelID],
            "上限到達した .processing も recovery 側ではフィルタせず coordinator に渡す (上限管理は coordinator 側に集約)"
        )
    }

    // MARK: - Helpers

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}

/// `@Sendable` closure 内で `retry` 呼び出しを記録する actor ベースのレコーダ。
private actor CallRecorder {
    private(set) var values: [PersistentIdentifier] = []
    func append(_ id: PersistentIdentifier) {
        values.append(id)
    }
}
