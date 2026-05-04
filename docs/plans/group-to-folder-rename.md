# 「グループ」呼称を「フォルダ」に変更する

photorans の iOS クライアントでユーザーに見える「グループ」という日本語呼称を「フォルダ」に置き換える。SwiftData 永続化・コード識別子 (`ItemGroup` クラス名 / `Item.group` プロパティ / `HomeSegment.groups` ケース / `Features/Group/` ディレクトリ / `GroupListView` 等のファイル名) は **本タスクのスコープ外** とし、UI 文字列・アクセシビリティラベル・SwiftUI コメント外の表示テキストのみを差し替える。

ステータス: **未着手** / 起票日: 2026-05-04

## 目的・背景

Akira さんの判断で、photorans の階層フォルダ機能の呼称を「グループ」から「フォルダ」に変更する。背景:

- iOS 純正 (Files / Photos / Notes) は階層的な保管単位を「フォルダ」と呼んでおり、ユーザーがメンタルモデルを既に持っている語彙
- 現状の SF Symbol アイコンは既に `folder` / `folder.fill` / `folder.badge.plus` を使っており (`HomeFAB.groupCreateButton` / `GroupListView.folderPlaceholder` / `GroupListView.rootEmptyView` の Label / `ItemDetailView` の「グループへ移動」メニュー項目)、視覚言語と用語が一致していなかったのを揃える
- 「グループ」は SwiftUI の `Section` / `Group` view と紛らわしい (コードレビュー時の認知負荷)

スコープを **UI 文字列のみ** に限定する根拠:

- `ItemGroup` を Swift クラス名 / SwiftData `@Model` 名ごと `ItemFolder` に改名すると、SwiftData は内部的にエンティティ名を別物として扱い、既存ストア (`Application Support/default.store`) を新規ストアとして開き直すか、`ModelContainer` 生成時にスキーマ不一致でエラーを投げる
- `StoreBootstrap.makeContainer()` のフォールバックは `didMigrateFromHistoryEntryV1` フラグ **未** 立てのときだけストア破棄に倒れる設計で、Akira さんの実機は v0.1.16 以降で同フラグが立っているため、エンティティ名変更は `containerCreationFailed` で fatal 落ちする
- 適切に対応するには `VersionedSchema` + `SchemaMigrationPlan` を導入して旧 `ItemGroup` → 新 `ItemFolder` のカスタム移行ステージを書く必要があるが、本リポジトリでは `VersionedSchema` の前例がなく、WSL2 で migration を実機通すまで動作確認できない (memory `feedback_swift_api_verification.md`)
- TestFlight 実機 (Akira さん) には既に多数の翻訳 Item と複数階層の Group がある (`v0.1.24` 以降で実機確認に使用)。データ消失を伴うリネームは受容不可
- 一方で UI 文字列だけのリネームは差分が純機械的 (20 か所程度の `Text` / `accessibilityLabel` / `navigationTitle`) で永続化に触れず、不可逆リスクがゼロ

将来 Swift 識別子・ファイル名・SwiftData エンティティを揃えたくなったら、別タスク「`ItemGroup` を `ItemFolder` にリネーム + SwiftData migration」として独立に起票する。本プランの完了によって UI と内部用語の二枚舌になるが、ユーザーに見える側で先に統一しておくほうが Akira さんの普段使いの体験改善が早い。

## 対応方針

### 判断 A: スコープの境界

**変える (本タスク):**
- ユーザーに表示される日本語文字列 (`Text(...)` / `Label("...", ...)` / `navigationTitle(...)` / `Section("...")` / `TextField("placeholder", ...)`)
- VoiceOver 用 `accessibilityLabel(...)` 文字列
- 上記に隣接する文章中の「グループ」表現すべて

**変えない (本タスク外):**
- Swift クラス・型名: `ItemGroup`, `GroupListView`, `GroupDetailView`, `GroupCreateSheet`, `GroupRenameSheet`, `MoveToGroupSheet`
- Swift プロパティ・メソッド名: `Item.group`, `ItemGroup.children`, `HomeSegment.groups`, `SegmentScope.group(_)`, `HomeQueries.filterGroups`, `HomeFAB.groupCreateButton`, `isShowingGroupCreate` 等
- ファイル / ディレクトリ名: `ios/Photorans/Storage/ItemGroup.swift`, `ios/Photorans/Features/Group/`, `GroupListView.swift` 他
- SwiftData 永続化エンティティ名 (= Swift クラス名と連動)
- コメント・doc コメント中の「グループ」「Group」(コード識別子の説明として残す)
- 過去のプラン (`docs/plans/archive/*.md`)・DONE.md 履歴 (履歴は遡及的に書き換えない)
- CLAUDE.md (TestFlight の "Internal Testing グループ" は本アプリの概念ではないので無関係)
- README.md (現時点で「グループ」記述なし、確認のみ)
- TODO.md の本タスク以外の既存項目

### 判断 B: SF Symbol アイコンの確認

すでに `folder` 系を使っているため変更不要:
- `HomeFAB.groupCreateButton` → `folder.badge.plus`
- `GroupListView.folderPlaceholder` overlay → `folder.fill`
- `GroupListView.rootEmptyView` Label → `folder`
- `ItemDetailView` の「グループへ移動」メニュー → `folder`
- `GroupListView.groupEmptyView` Label → `tray` (前タスクで採用、空状態の中立アイコンとして据え置き)

判断 D で `tray` を維持する理由は前タスク (`docs/plans/archive/group-empty-state.md`) と同じ — Group 詳細空状態は撮影 / フォルダ作成のどちらでも埋まる中立アイコンが適切で、`folder` には変えない。

### 判断 C: `グループ化` という動詞表現の置換

`GroupListView.rootEmptyView` の説明テキストに「グループ化して整理できます」とあるが、「フォルダ化」は日本語として不自然。**「フォルダで整理できます」** に書き換える。具体的な変更箇所:

```
旧: 翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。
新: 翻訳をテーマや用途ごとにフォルダで整理できます。右下の「+」ボタンから新しいフォルダを作ってください。
```

### 判断 D: Picker レイアウト幅

`HomeSegment.label` を `.groups → "フォルダ"` に変更すると Segmented Picker の左右ラベル幅は **未分類 (3 文字) / フォルダ (4 文字、カタカナ)** で旧「グループ (4 文字、カタカナ)」と完全に同幅。レイアウト崩れリスクなし。

### 判断 E: `metadataRow(label: "グループ", value: item.group?.name ?? "未分類")`

`ItemDetailView.swift:183` で Item の所属表示に使われている行。`label` を `"フォルダ"` にし、`value` フォールバックの `"未分類"` は別概念 (= ルート直下) なので据え置き。`item.group` のプロパティ名はコード識別子 (本タスク外) のため変えない。

### 判断 F: 文字列差し替えの正確な対象一覧

機械的に置換する 20 か所:

| # | ファイル | 行 | 旧文字列 | 新文字列 |
|---|---|---|---|---|
| 1 | `HomeView.swift` | 114 | `return "グループ"` | `return "フォルダ"` |
| 2 | `HomeView.swift` | 85 | `Label("グループを削除", ...)` | `Label("フォルダを削除", ...)` |
| 3 | `HomeView.swift` | 93 | `accessibilityLabel("グループ メニュー")` | `accessibilityLabel("フォルダ メニュー")` |
| 4 | `HomeFAB.swift` | 47 | `accessibilityLabel("グループを作成")` | `accessibilityLabel("フォルダを作成")` |
| 5 | `GroupCreateSheet.swift` | 20 | `TextField("グループ名", ...)` | `TextField("フォルダ名", ...)` |
| 6 | `GroupCreateSheet.swift` | 32 | `navigationTitle("新しいグループ")` | `navigationTitle("新しいフォルダ")` |
| 7 | `GroupRenameSheet.swift` | 19 | `TextField("グループ名", ...)` | `TextField("フォルダ名", ...)` |
| 8 | `GroupRenameSheet.swift` | 25 | `navigationTitle("グループ名を編集")` | `navigationTitle("フォルダ名を編集")` |
| 9 | `GroupDetailView.swift` | 52 | `"サブグループ \(group.children.count) 件と、配下の翻訳もすべて削除されます。元には戻せません。"` | `"サブフォルダ \(group.children.count) 件と、配下の翻訳もすべて削除されます。元には戻せません。"` |
| 10 | `GroupDetailView.swift` | 55 | `"このグループに含まれる翻訳 \(group.items.count) 件もすべて削除されます。元には戻せません。"` | `"このフォルダに含まれる翻訳 \(group.items.count) 件もすべて削除されます。元には戻せません。"` |
| 11 | `GroupDetailView.swift` | 57 | `"このグループを削除します。元には戻せません。"` | `"このフォルダを削除します。元には戻せません。"` |
| 12 | `GroupListView.swift` | 72 | `Label("グループはまだありません", systemImage: "folder")` | `Label("フォルダはまだありません", systemImage: "folder")` |
| 13 | `GroupListView.swift` | 74 | `Text("翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。")` | `Text("翻訳をテーマや用途ごとにフォルダで整理できます。右下の「+」ボタンから新しいフォルダを作ってください。")` |
| 14 | `GroupListView.swift` | 81 | `Label("翻訳もグループもまだありません", systemImage: "tray")` | `Label("翻訳もフォルダもまだありません", systemImage: "tray")` |
| 15 | `GroupListView.swift` | 83 | `Text("右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいグループを作成できます。")` | `Text("右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいフォルダを作成できます。")` |
| 16 | `GroupListView.swift` | 132 | `"\(itemCount) 件 ・ サブグループ \(childCount)"` | `"\(itemCount) 件 ・ サブフォルダ \(childCount)"` |
| 17 | `MoveToGroupSheet.swift` | 36 | `Section("グループ")` | `Section("フォルダ")` |
| 18 | `MoveToGroupSheet.swift` | 47 | `navigationTitle("グループへ移動")` | `navigationTitle("フォルダへ移動")` |
| 19 | `ItemDetailView.swift` | 45 | `Label("グループへ移動", systemImage: "folder")` | `Label("フォルダへ移動", systemImage: "folder")` |
| 20 | `ItemDetailView.swift` | 183 | `metadataRow(label: "グループ", value: item.group?.name ?? "未分類")` | `metadataRow(label: "フォルダ", value: item.group?.name ?? "未分類")` |

完了後に `rg 'グループ' ios/Photorans --type swift` を実行して、ヒットが「コメント / doc コメント / コード識別子の説明」だけに限定されていることを確認する。テストファイル `ios/PhotoransTests/SegmentQueryTests.swift` の `"Aグループ"` / `"Bグループ"` / `"Cグループ(空)"` / `"空グループ"` などはテストフィクスチャ名 (永続化に乗らないテスト時データ) なので据え置き。

## 影響範囲

- `ios/Photorans/Features/Home/HomeView.swift` — 3 か所
- `ios/Photorans/Features/Home/HomeFAB.swift` — 1 か所
- `ios/Photorans/Features/Home/GroupListView.swift` — 5 か所
- `ios/Photorans/Features/Group/GroupCreateSheet.swift` — 2 か所
- `ios/Photorans/Features/Group/GroupRenameSheet.swift` — 2 か所
- `ios/Photorans/Features/Group/GroupDetailView.swift` — 3 か所
- `ios/Photorans/Features/Item/MoveToGroupSheet.swift` — 2 か所
- `ios/Photorans/Features/Item/ItemDetailView.swift` — 2 か所

合計 8 ファイル / 20 か所。

- テストコード — 文字列アサートは無し (前タスク `group-empty-state.md` と同様、SwiftUI ビュー文言は実機確認の責務)。テストフィクスチャ内の `"Aグループ"` 等は機能に影響しないので据え置き
- XcodeGen — `.swift` 追加削除なし、ファイル名変更もなし → 再生成不要 (memory `feedback_xcodegen_regenerate.md` の対象外)
- SwiftData マイグレーション — エンティティ名 / プロパティ名は不変なので不要
- アイコン素材 / Asset Catalog — 不変
- Info.plist (`CFBundleDisplayName` 等) — 「Photorans」表示で「グループ」は出ないので不変

リスク:

- 抜け漏れ: 想定外の場所 (例: 動的に生成される文字列 / 補完されるエラーメッセージ) でユーザーに「グループ」が出る可能性 → 完了後 `rg 'グループ' ios/Photorans --type swift` で全件確認、コメント以外のヒットがあれば追加対応
- 文章の自然さ: 「フォルダ化」が不自然な日本語のため判断 C で書き換えたが、他の文も読み直して違和感が無いか確認 (上記表 #12〜#16)
- ユーザー側の期待値ミスマッチ: 既存ユーザーは Akira さん 1 名のため低リスク。外部テスター展開前に終わらせる
- 内部用語との二枚舌: コード上は `ItemGroup` / `groups` / `Features/Group/` のまま。レビュー時の認知負荷は残るが、本タスク完了直後に follow-up TODO「`ItemGroup` → `ItemFolder` リネーム + SwiftData migration」を起票しておけば中期的に解消できる
- Picker レイアウト崩れ: 判断 D で同幅確認済み

## テスト方針

実機 (Akira さんの iPhone) で:

1. **ホーム Picker**: `[未分類 | フォルダ]` と表示される (旧「グループ」が消えている)
2. **ルート空状態**: フォルダタブに切替 (DB に Group が無い状態で) → 「フォルダはまだありません」+「翻訳をテーマや用途ごとにフォルダで整理できます。右下の「+」ボタンから新しいフォルダを作ってください。」
3. **フォルダ作成シート**: 右下の「+」FAB をタップ → ナビゲーションタイトル「新しいフォルダ」、TextField placeholder「フォルダ名」
4. **フォルダ詳細空状態**: 新規 `テスト` フォルダに入る → 前タスクの新文言「翻訳もフォルダもまだありません」+「右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいフォルダを作成できます。」
5. **フォルダ行サブタイトル**: サブフォルダを持つフォルダの行 → 「N 件 ・ サブフォルダ M」形式 (旧「サブグループ」が消えている)
6. **フォルダ名編集シート**: フォルダ詳細のメニュー → 「名前を編集」 → ナビゲーションタイトル「フォルダ名を編集」、TextField placeholder「フォルダ名」
7. **フォルダ削除確認 alert**: フォルダ詳細のメニュー → 「フォルダを削除」(旧「グループを削除」) → confirmation dialog の文言が以下のいずれか:
   - サブフォルダ + 翻訳ありの場合: 「サブフォルダ N 件と、配下の翻訳もすべて削除されます。元には戻せません。」
   - 翻訳ありのみ: 「このフォルダに含まれる翻訳 N 件もすべて削除されます。元には戻せません。」
   - 空フォルダ: 「このフォルダを削除します。元には戻せません。」
8. **Item 詳細 → 移動シート**: 任意の翻訳タップ → 「フォルダへ移動」メニュー (旧「グループへ移動」) → シートのナビゲーションタイトル「フォルダへ移動」、Section ヘッダ「フォルダ」
9. **Item 詳細 metadata**: 「フォルダ: \<フォルダ名 or 未分類\>」表示 (旧「グループ: 〜」)
10. **VoiceOver / アクセシビリティ**: 右下の Group 作成 FAB を VoiceOver で読み上げ → 「フォルダを作成」、フォルダ詳細のメニューボタン → 「フォルダ メニュー」
11. **未分類タブ無変化**: 未分類タブ側 (`UnclassifiedListView`) の文言・FAB・遷移はすべて変化なし (本変更はフォルダタブ側のみ)
12. **Akira さんが普段使いで違和感なく操作できる** (用語の自然さの最終判定)

WSL2 シミュレータ確認は不可のため、Akira さんの実機 (iPhone 16 Pro / iOS 26) のみで上記 1〜12 を確認。文章の不自然さがあればその場で個別に修正して再 push。

## Phase / Step

- **Phase1 文字列差し替え**
  - Step1-1 判断 F の表 #1〜#3 (`HomeView.swift` の 3 か所)
  - Step1-2 判断 F の表 #4 (`HomeFAB.swift`)
  - Step1-3 判断 F の表 #5〜#6 (`GroupCreateSheet.swift`)
  - Step1-4 判断 F の表 #7〜#8 (`GroupRenameSheet.swift`)
  - Step1-5 判断 F の表 #9〜#11 (`GroupDetailView.swift`)
  - Step1-6 判断 F の表 #12〜#16 (`GroupListView.swift`、判断 C の動詞表現書き換え含む)
  - Step1-7 判断 F の表 #17〜#18 (`MoveToGroupSheet.swift`)
  - Step1-8 判断 F の表 #19〜#20 (`ItemDetailView.swift`)
  - Step1-9 完了後 `rg 'グループ' ios/Photorans --type swift` を実行し、ヒットがコメント / doc コメント / コード識別子の説明だけに限定されていることを確認 (テスト用フィクスチャ文字列は据え置きのため `ios/PhotoransTests/` は対象外)
  - Step1-10 コードレビュー (WSL2 ではビルド不可、文字列差し替えのみなので静的レビューで十分)
- **Phase2 実機確認**
  - Step2-1 タグ push (Akira さん事前確認) → Bitrise → TestFlight
  - Step2-2 テスト方針 1〜12 を実機で確認、文章違和感があれば個別修正して再 push
- **Phase3 仕上げ**
  - Step3-1 TODO.md → DONE.md に移送、本プランを `docs/plans/archive/` に移動
  - Step3-2 (オプション) フォローアップ TODO「`ItemGroup` を `ItemFolder` にリネーム + SwiftData VersionedSchema migration」を TODO.md に追加 (Akira さんの判断で起票するか決定)

判断履歴:
- 起票時 (2026-05-04): 判断 A (UI 文字列のみスコープ) + 判断 B (アイコン据え置き) + 判断 C (`グループ化` → `フォルダで整理`) + 判断 D (Picker 同幅) + 判断 E (metadata label のみ変更) + 判断 F (20 か所一覧) で開始
