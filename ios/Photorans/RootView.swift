import SwiftData
import SwiftUI

// TODO: Phase 2 で NavigationStack + HomeView(scope: .root) に差し替える。
// 本ファイルは Phase 1 の scaffolding 段階の一時スタブ。
struct RootView: View {
    var body: some View {
        EmptyView()
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Item.self, ItemGroup.self], inMemory: true)
}
