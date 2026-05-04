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

    // MARK: - directContents (Group X 直下の子 Group + 子 Item 混在表示)
    //
    // Plan: docs/plans/unclassified-segment-empty-bug.md。`GroupListView` の `.group(X)` branch で
    // X.children と X.items を `[HomeRowEntry]` の 1 リストに混ぜて createdAt 降順で表示する。

    func testDirectContentsMergesChildrenAndItemsByCreatedAtDesc() throws {
        // 親 P に 子 Group / 子 Item を交互に配置し、createdAt 降順での混在マージを検証する。
        let base = Date(timeIntervalSince1970: 1_700_100_000)
        let minute: TimeInterval = 60
        let parent = ItemGroup(name: "P", createdAt: base)
        let childGroupNew = ItemGroup(name: "child-new", createdAt: base.addingTimeInterval(30 * minute), parent: parent)
        let childGroupOld = ItemGroup(name: "child-old", createdAt: base.addingTimeInterval(5 * minute), parent: parent)
        let childItemMid = Item(
            createdAt: base.addingTimeInterval(20 * minute),
            imagePath: "photos/p_item_mid.jpg",
            status: .completed,
            originalText: "mid",
            translatedText: "中",
            model: "test",
            group: parent
        )
        let childItemOldest = Item(
            createdAt: base.addingTimeInterval(1 * minute),
            imagePath: "photos/p_item_old.jpg",
            status: .completed,
            originalText: "old",
            translatedText: "古",
            model: "test",
            group: parent
        )
        context.insert(parent)
        context.insert(childGroupNew)
        context.insert(childGroupOld)
        context.insert(childItemMid)
        context.insert(childItemOldest)
        try context.save()

        let result = HomeQueries.directContents(group: parent)

        // 期待順: childGroupNew (+30) → childItemMid (+20) → childGroupOld (+5) → childItemOldest (+1)
        XCTAssertEqual(result.count, 4)
        assertIsGroup(result[0], expectedID: childGroupNew.id)
        assertIsItem(result[1], expectedID: childItemMid.id)
        assertIsGroup(result[2], expectedID: childGroupOld.id)
        assertIsItem(result[3], expectedID: childItemOldest.id)
    }

    func testDirectContentsWithOnlyChildren() throws {
        // 子 Item ゼロ・子 Group のみのケース。createdAt 降順で Group が並ぶ。
        let base = Date(timeIntervalSince1970: 1_700_200_000)
        let minute: TimeInterval = 60
        let parent = ItemGroup(name: "OnlyGroups", createdAt: base)
        let cgNew = ItemGroup(name: "g-new", createdAt: base.addingTimeInterval(10 * minute), parent: parent)
        let cgOld = ItemGroup(name: "g-old", createdAt: base.addingTimeInterval(2 * minute), parent: parent)
        context.insert(parent)
        context.insert(cgNew)
        context.insert(cgOld)
        try context.save()

        let result = HomeQueries.directContents(group: parent)

        XCTAssertEqual(result.count, 2)
        assertIsGroup(result[0], expectedID: cgNew.id)
        assertIsGroup(result[1], expectedID: cgOld.id)
    }

    func testDirectContentsWithOnlyItems() throws {
        // 子 Group ゼロ・子 Item のみのケース。createdAt 降順で Item が並ぶ。
        let base = Date(timeIntervalSince1970: 1_700_300_000)
        let minute: TimeInterval = 60
        let parent = ItemGroup(name: "OnlyItems", createdAt: base)
        let itemNew = Item(
            createdAt: base.addingTimeInterval(10 * minute),
            imagePath: "photos/oi_new.jpg",
            status: .completed,
            originalText: "n",
            translatedText: "新",
            model: "test",
            group: parent
        )
        let itemOld = Item(
            createdAt: base.addingTimeInterval(1 * minute),
            imagePath: "photos/oi_old.jpg",
            status: .completed,
            originalText: "o",
            translatedText: "古",
            model: "test",
            group: parent
        )
        context.insert(parent)
        context.insert(itemNew)
        context.insert(itemOld)
        try context.save()

        let result = HomeQueries.directContents(group: parent)

        XCTAssertEqual(result.count, 2)
        assertIsItem(result[0], expectedID: itemNew.id)
        assertIsItem(result[1], expectedID: itemOld.id)
    }

    func testDirectContentsWithEmptyChildrenAndItems() throws {
        // 子 Group / 子 Item 両方空の Group は空配列を返す (空状態 UI へのフォールバックは呼び出し側責務)。
        let parent = ItemGroup(name: "Empty", createdAt: Date(timeIntervalSince1970: 1_700_400_000))
        context.insert(parent)
        try context.save()

        XCTAssertTrue(HomeQueries.directContents(group: parent).isEmpty)
    }

    // MARK: - directContents helpers

    private func assertIsGroup(
        _ entry: HomeRowEntry,
        expectedID: UUID,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        switch entry {
        case .group(let g):
            XCTAssertEqual(g.id, expectedID, file: file, line: line)
        case .item:
            XCTFail("Expected .group(\(expectedID)) but got .item", file: file, line: line)
        }
    }

    private func assertIsItem(
        _ entry: HomeRowEntry,
        expectedID: UUID,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        switch entry {
        case .item(let i):
            XCTAssertEqual(i.id, expectedID, file: file, line: line)
        case .group:
            XCTFail("Expected .item(\(expectedID)) but got .group", file: file, line: line)
        }
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
// 注: 旧 `HomeQueries.filterItems` は本ファイル冒頭の `directContents` 改修プラン
// (docs/plans/unclassified-segment-empty-bug.md) で関数ごと撤去済。下記の「filterItems」項目は
// 旧テスト名 + 旧実装上の挙動の **仕様リファレンス** として残す。再導入時はそれぞれ
// 「未分類モード本文用の検索クエリ」「グループモード本文用の検索クエリ」を新規設計する想定。
//
// filterItems (Item 一覧の検索文字列を受け取る branch — 旧 HomeQueries.filterItems 相当):
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
// filterGroups (検索文字列を受け取る branch — 現存 `HomeQueries.filterGroups` の検索拡張版):
// - testFilterGroupsSearchAtRootIncludesAllDescendants
//     → Root scope では `allGroups` 全件 (子孫すべて) が検索対象。"A" で A / A1 / A1a がヒット。
// - testFilterGroupsSearchAtGroupExcludesSelfAndOutsideScope
//     → Group X scope では X 自身および X の子孫以外を除外し、子孫 Group のみが検索対象。
// - testFilterGroupsSearchIsCaseInsensitive
//     → `localizedCaseInsensitiveContains` 相当 ("bグループ" で "Bグループ" にマッチ)。
//
// 再導入時の関連実装 (※ Picker は `RootView` 直下に固定 / `HomeView` は グループモード専用 / `UnclassifiedListView`
// は scope 非依存 という現状の構造に合わせて再設計する必要あり):
// - 「未分類モード用」Item 検索クエリ (旧 `filterItems(allItems:scope:searchText:)` の役割) を新設
// - `filterGroups(allGroups:scope:searchText:)` への `searchText` 引数復活
// - Group 検索の子孫展開ヘルパ `descendantGroups(allGroups:scope:)` + `collectDescendants(of:into:)` の復活
// - `RootView` (or 該当モード View) の `@State searchText` + `.searchable(text:prompt:)` の復活、
//   各リスト View の `searchText: String` 引数 + `ContentUnavailableView.search(text:)` 分岐の復活
