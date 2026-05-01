import SwiftData
import SwiftUI

@main
struct PhotoransApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: HistoryEntry.self)
        } catch {
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
