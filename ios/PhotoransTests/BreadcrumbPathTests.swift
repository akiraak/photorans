import SwiftData
import XCTest
@testable import Photorans

/// `BreadcrumbView.ancestorChain` / `popCount` の純関数を検証する (Plan Phase 0 Step 0.3)。
///
/// `ancestorChain`: 0 / 1 / 3 階層 + parent 自己参照ループ (64 段打ち切り) の 4 ケース。
/// `popCount`: chainLength × tappedIndex の組み合わせ 3 ケース。
@MainActor
final class BreadcrumbPathTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: configuration)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - ancestorChain

    func testAncestorChainOfRootLevelGroupReturnsSingleElement() throws {
        let g = ItemGroup(name: "X")
        context.insert(g)
        try context.save()

        let chain = BreadcrumbView.ancestorChain(of: g)
        XCTAssertEqual(chain.map(\.id), [g.id], "parent==nil の単独 Group は [自身] を返す")
    }

    func testAncestorChainOfOneLevelDeepGroupReturnsParentThenSelf() throws {
        let parent = ItemGroup(name: "P")
        let child = ItemGroup(name: "C", parent: parent)
        context.insert(parent)
        context.insert(child)
        try context.save()

        let chain = BreadcrumbView.ancestorChain(of: child)
        XCTAssertEqual(chain.map(\.id), [parent.id, child.id])
    }

    func testAncestorChainOfThreeLevelDeepGroupReturnsRootToSelfOrder() throws {
        let gp = ItemGroup(name: "GP")
        let p = ItemGroup(name: "P", parent: gp)
        let x = ItemGroup(name: "X", parent: p)
        context.insert(gp)
        context.insert(p)
        context.insert(x)
        try context.save()

        let chain = BreadcrumbView.ancestorChain(of: x)
        XCTAssertEqual(chain.map(\.id), [gp.id, p.id, x.id], "末尾が現在地、先頭が最上位祖先の順")
    }

    func testAncestorChainBreaksParentSelfReferenceLoopAt64Steps() throws {
        // データ整合性破壊で parent が自分自身を指してしまった想定。
        // 64 段で打ち切られ、無限ループにならず長さ 64 の chain で返ることを検証する。
        let g = ItemGroup(name: "Loop")
        context.insert(g)
        try context.save()
        g.parent = g

        let chain = BreadcrumbView.ancestorChain(of: g)
        XCTAssertEqual(chain.count, 64, "自己参照ループでも 64 段で打ち切られる")
    }

    // MARK: - popCount

    func testPopCountWith3ChainTappedAtIndex0Returns2() {
        XCTAssertEqual(BreadcrumbView.popCount(chainLength: 3, tappedIndex: 0), 2)
    }

    func testPopCountWith3ChainTappedAtIndex1Returns1() {
        XCTAssertEqual(BreadcrumbView.popCount(chainLength: 3, tappedIndex: 1), 1)
    }

    func testPopCountWith2ChainTappedAtIndex0Returns1() {
        XCTAssertEqual(BreadcrumbView.popCount(chainLength: 2, tappedIndex: 0), 1)
    }
}
