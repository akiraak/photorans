import SwiftData
import SwiftUI

/// 特定の `ItemGroup` 詳細画面 (S13-2)。
///
/// 中身は `HomeView(scope: .group(group))` を呼ぶだけのラッパに留める:
/// - Root と Group 詳細で UI 構造を完全一致させ、学習コストとコード重複を抑える (S13-2)。
/// - `navigationDestination` は **宣言しない** (Step 0.3。`RootView` の NavigationStack root に集約)。
/// - ナビゲーションタイトルは Group 名。
struct GroupDetailView: View {
    let group: ItemGroup

    var body: some View {
        HomeView(scope: .group(group))
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}
