import SwiftData
import SwiftUI

@main
struct PhotoransApp: App {
    let container: ModelContainer
    /// `TranslationCoordinator` は actor。View 再生成で cancel されないよう App 階層の
    /// `@State` で 1 インスタンスを保持し、environment 経由で配布する (Plan Step 3.1)。
    @State private var coordinator: TranslationCoordinator

    init() {
        let container: ModelContainer
        do {
            container = try StoreBootstrap.makeContainer()
        } catch {
            // フラグ true 以降のコンテナ生成失敗は本物の I/O / 権限障害なので
            // ユーザーデータを誤って破壊しないよう即時停止する (S10)。
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
        self.container = container
        _coordinator = State(initialValue: TranslationCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.translationCoordinator, coordinator)
                .task { [coordinator, container] in
                    // 起動時に `.processing` で残っている Item を再開する (Plan Step 5.3 / 5.4 / S6 a)。
                    // `StoreBootstrap` のフォールバック直後でも、新ストアは空のためゼロ件で no-op。
                    // `[coordinator, container]` で actor / Sendable 値だけを明示的に捕捉し、
                    // App 構造体 (self) を @Sendable 越境させない (Swift 6 strict concurrency 配慮)。
                    await PendingItemRecovery.runIfNeeded(
                        container: container,
                        retry: { id in await coordinator.retry(itemID: id) }
                    )
                }
        }
        .modelContainer(container)
    }
}
