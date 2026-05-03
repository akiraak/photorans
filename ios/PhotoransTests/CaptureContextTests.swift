import SwiftData
import XCTest
@testable import Photorans

/// 撮影コンテキスト → 保存先 group 解決ロジックの単体テスト (Plan Step 3.9)。
///
/// 検証対象:
/// - `SegmentScope.targetGroup`: Root → nil、Group(X) → X (S13-2 / S13-4)。
/// - `CameraViewModel.insertProcessingItem`: 与えた `targetGroup` がそのまま `Item.group` に
///   入り、Group 側 `items` リレーションにも逆引きで現れること (Plan Step 3.4)。
@MainActor
final class CaptureContextTests: XCTestCase {
    func testTargetGroupReturnsNilForRoot() {
        let scope: SegmentScope = .root
        XCTAssertNil(scope.targetGroup)
    }

    func testTargetGroupReturnsAttachedGroup() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)
        let group = ItemGroup(name: "テスト")
        context.insert(group)
        try context.save()

        let scope: SegmentScope = .group(group)
        XCTAssertIdentical(scope.targetGroup, group)
    }

    func testInsertProcessingItemAttachesGivenGroup() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)
        let group = ItemGroup(name: "保存先")
        context.insert(group)
        try context.save()

        let viewModel = CameraViewModel()
        let item = try viewModel.insertProcessingItem(
            modelContext: context,
            imagePath: "photos/captured.jpg",
            targetGroup: group
        )

        XCTAssertIdentical(item.group, group)
        XCTAssertEqual(item.status, .processing)
        XCTAssertEqual(item.imagePath, "photos/captured.jpg")
        XCTAssertEqual(item.retryCount, 0)
        XCTAssertEqual(group.items.count, 1)
        XCTAssertIdentical(group.items.first, item)
    }

    func testInsertProcessingItemAtRootHasNoGroup() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let viewModel = CameraViewModel()
        let item = try viewModel.insertProcessingItem(
            modelContext: context,
            imagePath: "photos/root.jpg",
            targetGroup: nil
        )

        XCTAssertNil(item.group)
        XCTAssertEqual(item.status, .processing)
    }

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
