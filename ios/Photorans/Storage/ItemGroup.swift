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
