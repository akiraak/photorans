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

    // MARK: - filterItems (scope 直下のみ)

    func testFilterItemsAtRootReturnsOnlyUngroupedSortedDesc() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .root)

        // Root では group == nil の Item のみ。`.processing` / `.failed` も含む点に注意 (S14: フィルタ無し)。
        let ids = result.map { $0.id }
        XCTAssertEqual(
            ids,
            [
                rootItemCompletedRecent.id,  // +10 min
                rootItemProcessing.id,       // +5 min
                rootItemFailed.id,           // +3 min
                rootItemCompletedOld.id      // +1 min
            ],
            "Root は group == nil の Item を createdAt 降順で返す"
        )
    }

    func testFilterItemsAtGroupReturnsOnlyDirectChildrenItems() throws {
        let allItems = try context.fetch(FetchDescriptor<Item>())
        let result = HomeQueries.filterItems(allItems: allItems, scope: .group(groupA))

        // Group A の直下 Item のみ。子孫 (groupA1, groupA1a) の Item は含めない。
        XCTAssertEqual(result.map { $0.id }, [groupAItemCompleted.id])
    }

    // MARK: - filterGroups (scope 直下 + 並び順)

    func testFilterGroupsAtRootShowsRootDirectGroupsSortedByLatestItem() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root)

        // Root 直下 = parent == nil の Group (= A, B)。
        // groupA の最新 Item は groupAItemCompleted (+20 min)、groupB は groupBItemCompleted (+4 min)。
        // → A が先、B が後。
        XCTAssertEqual(result.map { $0.id }, [groupA.id, groupB.id])
    }

    func testFilterGroupsAtGroupShowsOnlyDirectChildren() throws {
        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .group(groupA))
        // groupA の直下子は groupA1 のみ。groupA1a は孫なので含まれない。
        XCTAssertEqual(result.map { $0.id }, [groupA1.id])
    }

    func testFilterGroupsEmptyItemGroupsSortedToTail() throws {
        // 直下 Item ゼロの中間 Group が末尾固定になることを別フィクスチャで確認。
        let emptyMid = ItemGroup(name: "Cグループ(空)", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(emptyMid)
        try context.save()

        let allGroups = try context.fetch(FetchDescriptor<ItemGroup>())
        let result = HomeQueries.filterGroups(allGroups: allGroups, scope: .root)
        // A, B (Item あり) → emptyMid (Item ゼロ) の順。
        XCTAssertEqual(result.map { $0.id }, [groupA.id, groupB.id, emptyMid.id])
    }

    // MARK: - representativeItem (グループ行サムネ用)

    func testRepresentativeItemReturnsNilForGroupWithNoItems() throws {
        // サブグループしか持たない中間 Group (groupA1 は groupA1a を子孫に持つが、A1 直下に Item あり)。
        // Item ゼロのフィクスチャを別途用意する。
        let emptyGroup = ItemGroup(name: "空グループ", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(emptyGroup)
        try context.save()

        XCTAssertNil(HomeQueries.representativeItem(of: emptyGroup))
    }

    func testRepresentativeItemReturnsTheItemForSingleItemGroup() {
        // groupB は groupBItemCompleted 1 件のみ。
        XCTAssertEqual(
            HomeQueries.representativeItem(of: groupB)?.id,
            groupBItemCompleted.id
        )
    }

    func testRepresentativeItemReturnsLatestByCreatedAt() {
        // groupA は groupAItemCompleted (+20 min) が直下 1 件 (A1 / A1a の Item は子孫扱いで対象外)。
        // 別 Item を直下に追加して、最新 createdAt が選ばれることを確認する。
        let older = Item(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            imagePath: "photos/a_old.jpg",
            status: .completed,
            originalText: "Older",
            translatedText: "古い",
            model: "test",
            group: groupA
        )
        context.insert(older)

        XCTAssertEqual(
            HomeQueries.representativeItem(of: groupA)?.id,
            groupAItemCompleted.id,
            "直下 Item の中で createdAt が最大のものを返す"
        )
    }

    func testRepresentativeItemDoesNotRecurseIntoChildren() {
        // groupA1 は直下に groupA1ItemCompleted (+2 min) のみ。子孫 (groupA1a) には groupA1aItemCompleted (+15 min) があるが、
        // representativeItem は再帰しないので A1 直下のみが対象。
        XCTAssertEqual(
            HomeQueries.representativeItem(of: groupA1)?.id,
            groupA1ItemCompleted.id,
            "子孫 Group の Item には踏み込まない"
        )
    }
}

// MARK: - Removed (search UI). Re-add per TODO「検索 UI 再導入」
//
// パンくず実装 (Plan: docs/plans/breadcrumb-navigation.md) で `.searchable` を一旦削除した際、
// 以下 8 ケースを XCTest メソッドとしては削除した。再導入時の検証仕様リファレンスとして
// 各ケースが検証していた仕様を箇条書きで残す。
//
// filterItems (検索文字列を受け取る branch):
// - testFilterItemsWhitespaceOnlySearchTreatedAsEmpty
//     → 空白のみの searchText は trim 後に空文字列扱い (= scope 直下のみを返す)。
// - testFilterItemsSearchCrossesAllScopesAndOnlyCompleted
//     → 非空 searchText では scope を無視し、全 `.completed` Item を横断。`.processing` / `.failed` は対象外 (S14-4)。
//       結果は createdAt 降順。
// - testFilterItemsSearchMatchesTranslatedText
//     → originalText / translatedText の両方を contains 対象にする (例: "りんご" で translatedText マッチ)。
// - testFilterItemsSearchIsCaseInsensitive
//     → `localizedCaseInsensitiveContains` 相当 ("APPLE" で "Apple" にマッチ)。
// - testFilterItemsSearchExcludesProcessingAndFailed
//     → `.processing` / `.failed` Item は originalText / translatedText が nil なので contains に当たらない
//       ことを確認 (status フィルタの間接保証)。
//
// filterGroups (検索文字列を受け取る branch):
// - testFilterGroupsSearchAtRootIncludesAllDescendants
//     → Root scope では `allGroups` 全件 (子孫すべて) が検索対象。"A" で A / A1 / A1a がヒット。
// - testFilterGroupsSearchAtGroupExcludesSelfAndOutsideScope
//     → Group X scope では X 自身および X の子孫以外を除外し、子孫 Group のみが検索対象。
// - testFilterGroupsSearchIsCaseInsensitive
//     → `localizedCaseInsensitiveContains` 相当 ("bグループ" で "Bグループ" にマッチ)。
//
// 再導入時の関連実装:
// - `HomeQueries.filterItems(allItems:scope:searchText:)` / `filterGroups(allGroups:scope:searchText:)` の searchText 引数復活
// - Group 検索の子孫展開ヘルパ `descendantGroups(allGroups:scope:)` + `collectDescendants(of:into:)` の復活
// - `HomeView` の `@State searchText` + `.searchable(text:prompt:)` の復活、`GroupListView` / `UnclassifiedListView`
//   の `searchText: String` 引数 + `ContentUnavailableView.search(text:)` 分岐の復活
