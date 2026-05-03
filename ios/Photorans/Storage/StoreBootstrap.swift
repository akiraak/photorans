import Foundation
import SwiftData

/// アプリ起動時に呼ばれるストア初期化エントリ。
///
/// 旧 `HistoryEntry` schema からの初回移行のみ、ストアファイル一式 + `Documents/photos` を破棄する
/// フォールバックを行う (S10)。フォールバックは `UserDefaults` の `didMigrateFromHistoryEntryV1`
/// フラグで一度だけに限定し、フラグが立っている以降のコンテナ生成失敗 (ディスクフル / 権限 / I/O 障害)
/// はそのまま `StoreBootstrapError` として呼び出し側に投げる。
/// `PhotoransApp` 側で `fatalError` する責務を持たせ、本ファイルは throws のまま終わらせることで
/// Step 1.7 のテストから panic を避けて検証できるようにする。
enum StoreBootstrap {
    static let migrationFlagKey = "didMigrateFromHistoryEntryV1"

    /// ModelContainer を作る。フォールバックの発火条件はファイル冒頭参照。
    /// テストでは `defaults` / `storeURL` / `photosDirectory` を差し替えて副作用を分離する。
    static func makeContainer(
        defaults: UserDefaults = .standard,
        storeURL: URL? = nil,
        photosDirectory: URL? = nil
    ) throws -> ModelContainer {
        let resolvedStoreURL = storeURL ?? defaultStoreURL()
        let resolvedPhotosDirectory = photosDirectory ?? PhotoStorage.photosDirectory
        let configuration = ModelConfiguration(url: resolvedStoreURL)
        let schema = Schema([Item.self, ItemGroup.self])

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            if defaults.bool(forKey: migrationFlagKey) {
                // 初回移行は完了済み。本物の I/O / 権限障害なのでユーザーデータを勝手に消さない。
                throw StoreBootstrapError.containerCreationFailed(error)
            }

            destroyStore(at: resolvedStoreURL)
            destroyPhotos(at: resolvedPhotosDirectory)

            let container = try ModelContainer(for: schema, configurations: configuration)
            defaults.set(true, forKey: migrationFlagKey)
            return container
        }
    }

    /// SwiftData の SQLite + WAL/SHM ファイルを併せて削除する。
    private static func destroyStore(at url: URL) {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent
        for suffix in ["", "-shm", "-wal"] {
            let path = directory.appending(path: baseName + suffix, directoryHint: .notDirectory)
            try? fileManager.removeItem(at: path)
        }
    }

    /// 旧 schema 時代の写真ディレクトリを丸ごと破棄する。新 schema では同じ場所を再利用するが、
    /// 旧 `HistoryEntry.imagePath` が指す jpeg は新 `Item` から参照されないため孤児になる。
    private static func destroyPhotos(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// SwiftData が実引数なし `ModelContainer(for:)` で使うのと同じデフォルトパス。
    /// `Application Support/default.store` を採用する。
    private static func defaultStoreURL() -> URL {
        let supportDirectory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        return supportDirectory.appending(path: "default.store", directoryHint: .notDirectory)
    }
}

enum StoreBootstrapError: Error {
    /// 初回移行フォールバック後 (= フラグ true) のコンテナ生成失敗。本物の I/O / 権限障害想定。
    case containerCreationFailed(Error)
}
