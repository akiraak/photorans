import SwiftData
import XCTest
@testable import Photorans

/// `HomeQueries` のフィルタ + ソートロジックを純関数として検証する (Plan Step 5.5)。
///
/// フィクスチャ: ネスト 3 階層 (root → A / B、A → A1、A1 → A1a) + 各階層に `.completed` / `.processing`
/// / `.failed` の Item を散らした配置。in-memory `ModelContainer` 上に組み立て、`HomeQueries`
/// に渡して期待リストを検証する。
@MainActor
final class SegmentQueryTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    private var groupA: ItemGroup!
    private var groupB: ItemGroup!
    private var groupA1: ItemGroup!
    private var groupA1a: ItemGroup!

    /// createdAt を制御することで降順ソートの正しさを検証可能にする。
    /// 値が大きいほど新しい (= 先頭側)。
    private var rootItemCompletedRecent: Item!
    private var rootItemCompletedOld: Item!
    private var rootItemProcessing: Item!
    private var rootItemFailed: Item!
    private var groupAItemCompleted: Item!
    private var groupA1ItemCompleted: Item!
    private var groupA1aItemCompleted: Item!
    private var groupBItemCompleted: Item!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: configuration)
        context = ModelContext(container)

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let minute: TimeInterval = 60

        groupA = ItemGroup(name: "Aグループ", createdAt: base.addingTimeInterval(-10 * minute))
        groupB = ItemGroup(name: "Bグループ", createdAt: base.addingTimeInterval(-9 * minute))
        groupA1 = ItemGroup(name: "A1サブ", createdAt: base.addingTimeInterval(-8 * minute), parent: groupA)
        groupA1a = ItemGroup(name: "A1aリーフ", createdAt: base.addingTimeInterval(-7 * minute), parent: groupA1)

        context.insert(groupA)
        context.insert(groupB)
        context.insert(groupA1)
        context.insert(groupA1a)

        rootItemCompletedRecent = Item(
            createdAt: base.addingTimeInterval(10 * minute),
            imagePath: "photos/root_recent.jpg",
            status: .completed,
            originalText: "Hello world",
            translatedText: "こんにちは 世界",
            model: "test"
        )
        rootItemCompletedOld = Item(
            createdAt: base.addingTimeInterval(1 * minute),
            imagePath: "photos/root_old.jpg",
            status: .completed,
            originalText: "Foobar",
            translatedText: "フーバー",
            model: "test"
        )
        rootItemProcessing = Item(
            createdAt: base.addingTimeInterval(5 * minute),
            imagePath: "photos/root_processing.jpg",
            status: .processing
        )
        rootItemFailed = Item(
            createdAt: base.addingTimeInterval(3 * minute),
            imagePath: "photos/root_failed.jpg",
            status: .failed,
            failureReason: "timeout"
        )
        groupAItemCompleted = Item(
            createdAt: base.addingTimeInterval(20 * minute),
            imagePath: "photos/a.jpg",
            status: .completed,
            originalText: "Apple",
            translatedText: "りんご",
            model: "test",
            group: groupA
        )
        groupA1ItemCompleted = Item(
            createdAt: base.addingTimeInterval(2 * minute),
            imagePath: "photos/a1.jpg",
            status: .completed,
            originalText: "Banana",
            translatedText: "バナナ",
            model: "test",
            group: groupA1
        )
        groupA1aItemCompleted = Item(
            createdAt: base.addingTimeInterval(15 * minute),
            imagePath: "photos/a1a.jpg",
            status: .completed,
            originalText: "Cherry hello",
            translatedText: "さくらんぼ",
            model: "test",
            group: groupA1a
        )
        groupBItemCompleted = Item(
            createdAt: base.addingTimeInterval(4 * minute),
            imagePath: "photos/b.jpg",
            status: .completed,
            originalText: "Durian",
            translatedText: "ドリアン",
            model: "test",
            group: groupB
        )

        for item in [
            rootItemCompletedRecent,
            rootItemCompletedOld,
            rootItemProcessing,
            rootItemFailed,
            groupAItemCompleted,
            groupA1ItemCompleted,
            groupA1aItemCompleted,
            groupBItemCompleted
        ] {
            context.insert(item!)
        }
        try context.save()
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        groupA = nil
        groupB = nil
        groupA1 = nil
        groupA1a = nil
        rootItemCompletedRecent = nil
        rootItemCompletedOld = nil
        rootItemProcessing = nil
        rootItemFailed = nil
        groupAItemCompleted = nil
        groupA1ItemCompleted = nil
        groupA1aItemCompleted = nil
        groupBItemCompleted = nil
        try super.tearDownWithError()
    }

    // MARK: - filterItems (空文字列 = scope 直下のみ)

    func testFilterItemsEmptySearchAtRootReturnsOnlyUngroupedSortedDesc() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .root, searchText: "")

        // Root では group == nil の Item のみ。`.processing` / `.failed` も含む点に注意 (S14: 空文字列はフィルタ無し)。
        let ids = result.map { $0.id }
        XCTAssertEqual(
            ids,
            [
                rootItemCompletedRecent.id,  // +10 min
                rootItemProcessing.id,       // +5 min
                rootItemFailed.id,           // +3 min
                rootItemCompletedOld.id      // +1 min
            ],
            "Root + 空検索は group == nil の Item を createdAt 降順で返す"
        )
    }

    func testFilterItemsEmptySearchAtGroupReturnsOnlyDirectChildrenItems() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .group(groupA), searchText: "")

        // Group A の直下 Item のみ。子孫 (groupA1, groupA1a) の Item は含めない。
        XCTAssertEqual(result.map { $0.id }, [groupAItemCompleted.id])
    }

    func testFilterItemsWhitespaceOnlySearchTreatedAsEmpty() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .group(groupA), searchText: "   ")
        XCTAssertEqual(result.map { $0.id }, [groupAItemCompleted.id])
    }

    // MARK: - filterItems (非空文字列 = scope 無視で全 .completed 横断)

    func testFilterItemsSearchCrossesAllScopesAndOnlyCompleted() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        // "hello" は rootItemCompletedRecent (originalText: "Hello world") と
        // groupA1aItemCompleted (originalText: "Cherry hello") にマッチする。
        // .processing / .failed Item は対象外 (S14-4)。
        let result = HomeQueries.filterItems(allItems: allItems, scope: .group(groupB), searchText: "hello")

        let ids = Set(result.map { $0.id })
        XCTAssertEqual(
            ids,
            Set([rootItemCompletedRecent.id, groupA1aItemCompleted.id]),
            "Item 検索は scope を無視して全 .completed Item を横断する (S14)"
        )
        // createdAt 降順
        XCTAssertEqual(result.map { $0.id }, [rootItemCompletedRecent.id, groupA1aItemCompleted.id])
    }

    func testFilterItemsSearchMatchesTranslatedText() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        // 翻訳テキスト「りんご」に対するマッチ。
        let result = HomeQueries.filterItems(allItems: allItems, scope: .root, searchText: "りんご")
        XCTAssertEqual(result.map { $0.id }, [groupAItemCompleted.id])
    }

    func testFilterItemsSearchIsCaseInsensitive() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .root, searchText: "APPLE")
        XCTAssertEqual(result.map { $0.id }, [groupAItemCompleted.id])
    }

    func testFilterItemsSearchExcludesProcessingAndFailed() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        // `.processing` / `.failed` の Item は originalText / translatedText が nil なので
        // contains マッチでも当たらないが、念のため空文字列 "" に近いパターンで検索しても外れることを確認。
        let result = HomeQueries.filterItems(allItems: allItems, scope: .root, searchText: "z")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - filterGroups (空文字列 = scope 直下 + 並び順)

    func testFilterGroupsEmptySearchAtRootShowsRootDirectGroupsSortedByLatestItem() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root, searchText: "")

        // Root 直下 = parent == nil の Group (= A, B)。
        // groupA の最新 Item は groupAItemCompleted (+20 min)、groupB は groupBItemCompleted (+4 min)。
        // → A が先、B が後。
        XCTAssertEqual(result.map { $0.id }, [groupA.id, groupB.id])
    }

    func testFilterGroupsEmptySearchAtGroupShowsOnlyDirectChildren() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .group(groupA), searchText: "")
        // groupA の直下子は groupA1 のみ。groupA1a は孫なので含まれない。
        XCTAssertEqual(result.map { $0.id }, [groupA1.id])
    }

    func testFilterGroupsEmptyEmptyItemGroupsSortedToTail() throws {
        // 直下 Item ゼロの中間 Group が末尾固定になることを別フィクスチャで確認。
        let emptyMid = ItemGroup(name: "Cグループ(空)", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(emptyMid)
        try context.save()

        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root, searchText: "")
        // A, B (Item あり) → emptyMid (Item ゼロ) の順。
        XCTAssertEqual(result.map { $0.id }, [groupA.id, groupB.id, emptyMid.id])
    }

    // MARK: - filterGroups (非空文字列 = scope 配下子孫の名前 contains)

    func testFilterGroupsSearchAtRootIncludesAllDescendants() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root, searchText: "A")
        // 名前に "A" を含む = A, A1, A1a。B は除外。
        XCTAssertEqual(
            Set(result.map { $0.id }),
            Set([groupA.id, groupA1.id, groupA1a.id])
        )
    }

    func testFilterGroupsSearchAtGroupExcludesSelfAndOutsideScope() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        // groupA scope での "A" 検索は groupA の **子孫** のみ (A 自身と Bグループは除外)。
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .group(groupA), searchText: "A")
        XCTAssertEqual(
            Set(result.map { $0.id }),
            Set([groupA1.id, groupA1a.id]),
            "scope 自身および scope 外の Group は除外される (S14)"
        )
    }

    func testFilterGroupsSearchIsCaseInsensitive() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root, searchText: "bグループ")
        XCTAssertEqual(result.map { $0.id }, [groupB.id])
    }
}
