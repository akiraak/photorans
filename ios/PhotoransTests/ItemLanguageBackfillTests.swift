import SwiftData
import XCTest
@testable import Photorans

/// `ItemLanguageBackfill.runIfNeeded` の挙動を検証する (Plan 双方向翻訳 Phase 2 Step 2-5)。
///
/// 検証観点:
/// - `sourceLanguage` / `targetLanguage` が共に nil の Item は旧固定方向 ("en"/"ja") で埋まる。
/// - 既に値が入っている Item は上書きされない (再起動時の冪等性)。
/// - 全件無し / 全件埋まり済みでも silent no-op。
/// - status (.processing / .completed / .failed) によらずバックフィル対象になる
///   (旧データはどの状態でも英→日固定で動いていたため)。
final class ItemLanguageBackfillTests: XCTestCase {
    func testFillsNilLanguageFieldsWithLegacyDirection() async throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let completed = Item(
            imagePath: "photos/c.jpg",
            status: .completed,
            originalText: "Hello",
            translatedText: "こんにちは",
            model: "old-model"
        )
        let processing = Item(imagePath: "photos/p.jpg", status: .processing)
        let failed = Item(imagePath: "photos/f.jpg", status: .failed, failureReason: "timeout")

        for item in [completed, processing, failed] {
            context.insert(item)
        }
        try context.save()

        await ItemLanguageBackfill.runIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let items = try verifyContext.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(items.count, 3)
        for item in items {
            XCTAssertEqual(item.sourceLanguage, "en", "imagePath=\(item.imagePath) は en に埋まる想定")
            XCTAssertEqual(item.targetLanguage, "ja", "imagePath=\(item.imagePath) は ja に埋まる想定")
        }
    }

    func testDoesNotOverwriteExistingLanguageValues() async throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        // 双方向翻訳対応後に保存された Item (日→英)。バックフィルは触らない。
        let jaToEn = Item(
            imagePath: "photos/ja.jpg",
            status: .completed,
            originalText: "こんにちは",
            translatedText: "Hello",
            model: "new-model",
            sourceLanguage: "ja",
            targetLanguage: "en"
        )
        // 双方向翻訳対応後の英→日。これも触らない。
        let enToJa = Item(
            imagePath: "photos/en.jpg",
            status: .completed,
            originalText: "Hello",
            translatedText: "こんにちは",
            model: "new-model",
            sourceLanguage: "en",
            targetLanguage: "ja"
        )
        // 旧データ (バックフィル対象)。
        let legacy = Item(
            imagePath: "photos/legacy.jpg",
            status: .completed,
            originalText: "Old",
            translatedText: "古い",
            model: "old-model"
        )

        for item in [jaToEn, enToJa, legacy] {
            context.insert(item)
        }
        try context.save()

        await ItemLanguageBackfill.runIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let items = try verifyContext.fetch(FetchDescriptor<Item>())
        let byPath = Dictionary(uniqueKeysWithValues: items.map { ($0.imagePath, $0) })

        let verifiedJaToEn = try XCTUnwrap(byPath["photos/ja.jpg"])
        XCTAssertEqual(verifiedJaToEn.sourceLanguage, "ja", "既存値 ja は上書きされない")
        XCTAssertEqual(verifiedJaToEn.targetLanguage, "en", "既存値 en は上書きされない")

        let verifiedEnToJa = try XCTUnwrap(byPath["photos/en.jpg"])
        XCTAssertEqual(verifiedEnToJa.sourceLanguage, "en")
        XCTAssertEqual(verifiedEnToJa.targetLanguage, "ja")

        let verifiedLegacy = try XCTUnwrap(byPath["photos/legacy.jpg"])
        XCTAssertEqual(verifiedLegacy.sourceLanguage, "en", "旧データは en→ja で埋まる")
        XCTAssertEqual(verifiedLegacy.targetLanguage, "ja")
    }

    func testNoOpWhenStoreEmpty() async throws {
        let container = try Self.makeInMemoryContainer()

        await ItemLanguageBackfill.runIfNeeded(container: container)

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        XCTAssertTrue(items.isEmpty)
    }

    func testIdempotentOnSecondRun() async throws {
        // 1 回目で埋め、2 回目は何もしないこと (再起動時の冪等性)。
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let item = Item(
            imagePath: "photos/x.jpg",
            status: .completed,
            originalText: "x",
            translatedText: "y",
            model: "m"
        )
        context.insert(item)
        try context.save()

        await ItemLanguageBackfill.runIfNeeded(container: container)
        await ItemLanguageBackfill.runIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let items = try verifyContext.fetch(FetchDescriptor<Item>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceLanguage, "en")
        XCTAssertEqual(items.first?.targetLanguage, "ja")
    }

    // MARK: - Helpers

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
