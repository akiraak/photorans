import SwiftData
import XCTest
@testable import Photorans

/// `ItemGroup.deleteRecursively(modelContext:)` の単体テスト (Plan Step 4.6 / 4.8)。
///
/// 検証:
/// 1. ネスト 3 階層 + 各階層に Item 複数 のフィクスチャで、削除後に SwiftData 上の全 Group / 全 Item が消えており、
///    `Item.imagePath` に対応する jpeg も `FileManager` 上から物理削除されていること。
/// 2. リーフ Group を削除しても兄弟 Group とその Item は無傷であること (cascade の境界が正しいこと)。
///
/// `photoURLResolver` を tmp ディレクトリ向けに差し替えることで、本番の `Documents/photos` を汚さずに
/// ファイル削除の副作用を検証する。
@MainActor
final class ItemGroupDeleteRecursivelyTests: XCTestCase {
    func testDeleteRecursivelyRemovesAllDescendantsAndPhotos() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let tmpDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let resolver: (String) -> URL = { relativePath in
            tmpDir.appending(path: relativePath, directoryHint: .notDirectory)
        }

        // 3 階層を構築: root → child → grandchild。各階層に Item 2 件 (合計 3 Group / 6 Item)。
        let root = ItemGroup(name: "root")
        let child = ItemGroup(name: "child", parent: root)
        let grandchild = ItemGroup(name: "grandchild", parent: child)
        context.insert(root)
        context.insert(child)
        context.insert(grandchild)

        var allRelativePaths: [String] = []
        for (groupIndex, group) in [root, child, grandchild].enumerated() {
            for itemIndex in 0..<2 {
                let path = "photos/g\(groupIndex)-i\(itemIndex).jpg"
                allRelativePaths.append(path)
                let item = Item(
                    imagePath: path,
                    status: .completed,
                    originalText: "o",
                    translatedText: "t",
                    model: "m",
                    group: group
                )
                context.insert(item)
                try Self.writeDummyFile(at: resolver(path))
            }
        }
        try context.save()

        // sanity check.
        for path in allRelativePaths {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: resolver(path).path),
                "fixture jpeg が作れていない: \(path)"
            )
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ItemGroup>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 6)

        // 実行: root から delete → cascade で child / grandchild も連鎖削除。
        root.deleteRecursively(
            modelContext: context,
            photoURLResolver: resolver
        )
        try context.save()

        // SwiftData 上: 全 Group / 全 Item が消えている。
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ItemGroup>()), 0,
            "cascade で全 Group が削除されているはず"
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<Item>()), 0,
            "cascade で全 Item が削除されているはず"
        )

        // FileManager 上: 全 jpeg が消えている。
        for path in allRelativePaths {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: resolver(path).path),
                "削除後も jpeg ファイルが残っている: \(path)"
            )
        }
    }

    func testDeleteRecursivelyOnLeafGroupLeavesSiblingsIntact() throws {
        let container = try Self.makeInMemoryContainer()
        let context = ModelContext(container)

        let tmpDir = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let resolver: (String) -> URL = { relativePath in
            tmpDir.appending(path: relativePath, directoryHint: .notDirectory)
        }

        // target / sibling は同じ Root 直下の兄弟 Group。
        let target = ItemGroup(name: "target")
        let sibling = ItemGroup(name: "sibling")
        context.insert(target)
        context.insert(sibling)

        let targetItem1 = Item(imagePath: "photos/t1.jpg", status: .completed, group: target)
        let targetItem2 = Item(imagePath: "photos/t2.jpg", status: .completed, group: target)
        let siblingItem = Item(imagePath: "photos/s1.jpg", status: .completed, group: sibling)
        context.insert(targetItem1)
        context.insert(targetItem2)
        context.insert(siblingItem)
        for path in ["photos/t1.jpg", "photos/t2.jpg", "photos/s1.jpg"] {
            try Self.writeDummyFile(at: resolver(path))
        }
        try context.save()

        target.deleteRecursively(modelContext: context, photoURLResolver: resolver)
        try context.save()

        // target と target の Item だけが消える。
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ItemGroup>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Item>()), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver("photos/t1.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: resolver("photos/t2.jpg").path))
        // 兄弟 Group の Item / jpeg は無傷。
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolver("photos/s1.jpg").path))
    }

    // MARK: - Helpers

    private static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Item.self, ItemGroup.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "photorans-delete-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeDummyFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xFF]).write(to: url)
    }
}
