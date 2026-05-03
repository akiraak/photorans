import Foundation
import SwiftData

/// 撮影結果 (Item) を任意深さで束ねるフォルダ。
///
/// - `parent` が nil の Group は Root 直下。
/// - `children` / `items` には `.cascade` を設定しているため、ItemGroup 自身を削除すると
///   配下の子 Group と Item も SwiftData 側で連鎖削除される。
///   ただし `Item.imagePath` の写真ファイルは別管理なので、削除前に
///   `ItemGroup.deleteRecursively(modelContext:)` (Step 4.6) で traverse して消す責務がある。
@Model
final class ItemGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    /// 親 Group (Root 直下なら nil)。
    var parent: ItemGroup?

    /// 直下の子 Group。inverse 側で cascade 削除を宣言する。
    @Relationship(deleteRule: .cascade, inverse: \ItemGroup.parent)
    var children: [ItemGroup]

    /// 直下の Item。inverse 側で cascade 削除を宣言する。
    @Relationship(deleteRule: .cascade, inverse: \Item.group)
    var items: [Item]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        parent: ItemGroup? = nil,
        children: [ItemGroup] = [],
        items: [Item] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.parent = parent
        self.children = children
        self.items = items
    }
}

extension ItemGroup {
    /// この Group とその配下を再帰的に削除する (Plan Step 4.6 / リスク欄「SwiftData の cascade と画像ファイル削除のずれ」)。
    ///
    /// 順序が重要:
    /// 1. 配下 (自身 + 全子孫 Group) の Item の `imagePath` を traverse して `FileManager` から jpeg を消す。
    ///    SwiftData の `.cascade` deleteRule は SwiftData 上の Item / 子 Group は連鎖削除してくれるが、
    ///    `Item.imagePath` の jpeg は SwiftData 管理外なので **必ず** SwiftData 削除より先に列挙する。
    /// 2. `modelContext.delete(self)` で本 Group を削除。`children` / `items` への `.cascade` 設定により
    ///    子孫 Group と Item は SwiftData が連鎖削除する。
    ///
    /// `photoURLResolver` / `fileManager` はテスト用 DI ポイント。本番デフォルトは
    /// `PhotoStorage.absoluteURL(for:)` と `.default`。`save()` は呼び出し側の責務 (削除単位を制御するため)。
    func deleteRecursively(
        modelContext: ModelContext,
        photoURLResolver: (String) -> URL = PhotoStorage.absoluteURL(for:),
        fileManager: FileManager = .default
    ) {
        for relativePath in collectImagePaths() {
            let url = photoURLResolver(relativePath)
            try? fileManager.removeItem(at: url)
        }
        modelContext.delete(self)
    }

    /// 配下 (自身 + 全子孫 Group) の Item の `imagePath` を集める。
    private func collectImagePaths() -> [String] {
        var paths: [String] = items.map(\.imagePath)
        for child in children {
            paths.append(contentsOf: child.collectImagePaths())
        }
        return paths
    }
}
