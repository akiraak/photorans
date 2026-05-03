import SwiftData
import XCTest
@testable import Photorans

/// `StoreBootstrap.makeContainer` のフォールバック挙動を検証する。
///
/// - 旧 `HistoryEntry` schema 風の `legacy_history_v1.sqlite` をテストバンドルに同梱しておき
///   (Plan Step 1.7 / `Fixtures/make_legacy_store.sh` で生成)、新 schema (`Item` / `ItemGroup`)
///   での `ModelContainer` 生成を行うと entity 不一致でフォールバックが発火する。
/// - フォールバックは `UserDefaults` の `didMigrateFromHistoryEntryV1` フラグで一度だけに限定する
///   ことを、フラグ true 時に同じ状況を作って `StoreBootstrapError` が投げられることで確認する。
final class StoreBootstrapTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "StoreBootstrapTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defaultsSuiteName = "StoreBootstrapTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuiteName))
    }

    override func tearDownWithError() throws {
        if let suiteName = defaultsSuiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        defaults = nil
        defaultsSuiteName = nil
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    /// フラグ false + 旧 store + 旧 photos が在る状態で `makeContainer` を呼ぶと、
    /// store ファイルと photos ディレクトリが破棄され、新ストアが空の状態で生成され、
    /// フラグが true になる。
    func testFallbackTriggeredOnFirstMigration() throws {
        let storeURL = temporaryDirectory.appending(path: "default.store", directoryHint: .notDirectory)
        let photosDirectory = temporaryDirectory.appending(path: "photos", directoryHint: .isDirectory)

        try copyLegacyFixture(to: storeURL)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let legacyPhoto = photosDirectory.appending(path: "legacy.jpg", directoryHint: .notDirectory)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: legacyPhoto)

        XCTAssertFalse(defaults.bool(forKey: StoreBootstrap.migrationFlagKey))

        let container = try StoreBootstrap.makeContainer(
            defaults: defaults,
            storeURL: storeURL,
            photosDirectory: photosDirectory
        )

        XCTAssertTrue(defaults.bool(forKey: StoreBootstrap.migrationFlagKey))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyPhoto.path),
            "旧写真ファイルはフォールバックで破棄されるはず"
        )

        let context = ModelContext(container)
        let items = try context.fetch(FetchDescriptor<Item>())
        let groups = try context.fetch(FetchDescriptor<ItemGroup>())
        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(groups.isEmpty)
    }

    /// フラグ true で同じ「旧 schema を内包した非互換 store」がある状態だと、
    /// フォールバックは発火せず `StoreBootstrapError.containerCreationFailed` を投げる。
    /// (Plan: フラグ true 以降のコンテナ生成失敗は本物の I/O / 権限障害として扱い、
    /// ユーザーデータを誤って破壊しないため)
    func testThrowsWhenAlreadyMigratedAndStoreIncompatible() throws {
        let storeURL = temporaryDirectory.appending(path: "default.store", directoryHint: .notDirectory)
        try copyLegacyFixture(to: storeURL)
        defaults.set(true, forKey: StoreBootstrap.migrationFlagKey)

        let photosDirectory = temporaryDirectory.appending(path: "photos", directoryHint: .isDirectory)

        XCTAssertThrowsError(
            try StoreBootstrap.makeContainer(
                defaults: defaults,
                storeURL: storeURL,
                photosDirectory: photosDirectory
            )
        ) { error in
            guard case StoreBootstrapError.containerCreationFailed = error else {
                XCTFail("Expected StoreBootstrapError.containerCreationFailed, got \(error)")
                return
            }
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: storeURL.path),
            "フラグ true 経路では store ファイルを勝手に消さないこと"
        )
    }

    private func copyLegacyFixture(to storeURL: URL) throws {
        let bundle = Bundle(for: type(of: self))
        let fixtureURL = try XCTUnwrap(
            bundle.url(forResource: "legacy_history_v1", withExtension: "sqlite"),
            "legacy_history_v1.sqlite がテストバンドルに同梱されていない"
        )
        try? FileManager.default.removeItem(at: storeURL)
        try FileManager.default.copyItem(at: fixtureURL, to: storeURL)
    }
}
