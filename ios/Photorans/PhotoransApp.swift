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
        }
        .modelContainer(container)
    }
}
