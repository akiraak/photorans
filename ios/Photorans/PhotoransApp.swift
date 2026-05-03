import SwiftData
import SwiftUI

@main
struct PhotoransApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try StoreBootstrap.makeContainer()
        } catch {
            // フラグ true 以降のコンテナ生成失敗は本物の I/O / 権限障害なので
            // ユーザーデータを誤って破壊しないよう即時停止する (S10)。
            fatalError("Failed to initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
