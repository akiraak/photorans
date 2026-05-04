# アイテムとグループの一覧に画像を表示する

photorans のホーム画面 (`HomeView`) で 2 セグメント (`未分類` / `グループ`) のリスト行にサムネイルを表示する実装プラン。

ステータス: **着手前** / 起票日: 2026-05-04

## 目的・背景

- 現状の一覧は文字情報のみ:
  - `ItemRowView` (未分類タブ) は訳文 2 行 + 撮影日時。どの写真の翻訳かは詳細を開かないと分からない
  - `GroupListView` の行は `folder.fill` SF Symbol + 名前 + 件数。グループの中身が視覚的に区別できない
- 旧 RN 実装 (`HistoryListScreen`) ではサムネ表示が実装済みだったが、ネイティブ書き直しで一旦削った経緯あり (`landscape-capture` 計画 Phase6 注釈)。今回はネイティブ側に再導入する
- iOS 純正写真 / メモアプリと同様、**「サムネを見て該当エントリを目視で探せる」** UX を取り戻すのが目的

## 採用方針

### Item 行 (未分類タブ)

| 項目 | 仕様 |
|---|---|
| 配置 | 行の左端、テキスト本文の左にサムネを置く HStack |
| サイズ | 56pt × 56pt (Apple Mail / メモアプリの行サイズに合わせた目安) |
| アスペクト | `aspectRatio(.fill) + clipped()` で **正方形クロップ**。元写真は縦横不定 (3:4 / 4:3) だが、一覧では縦位置を揃えたいので歪ませず中央クロップ |
| 角丸 | `RoundedRectangle(cornerRadius: 6)` でクリップ。純正写真の thumbnail と整合 |
| ステータスごとの表示 | 全ステータス共通で同じサムネを表示 (`.processing` 時点で jpeg は既に `PhotoStorage.save` 済み)。`.failed` でも撮影写真は残っているのでサムネは出す |
| 読み込み中 | `Color.secondary.opacity(0.15)` の placeholder。読み込み完了で fade-in せず即時差し替え (List スクロールでチラつかせない) |
| 画像不在 | `Image(systemName: "photo")` を `.foregroundStyle(.secondary)` で中央配置 |

### Group 行 (グループタブ)

| 項目 | 仕様 |
|---|---|
| 配置 | 現在の `folder.fill` SF Symbol の位置にサムネを置く |
| サムネ元 | **直下 Item の最新 1 件**。`HomeQueries.directItems` で得た Item を `createdAt` 降順で並べた先頭。子孫まで再帰しない (現在のグループソート「直下 Item の最新 createdAt 降順」と整合させ、ロジック分岐を増やさない) |
| 直下 Item ゼロの Group | サブグループしか持たない中間 Group は **`folder.fill` を維持** (現状 UI 据え置き)。MVP の割り切りとして文書化、ユーザー要望が出たら子孫再帰を後追い |
| サイズ / 形 | Item 行と揃える (56pt 正方形、角丸 6pt) |

### サムネ View / キャッシュ

| 項目 | 仕様 |
|---|---|
| 共通 View | 新規 `ItemThumbnailView(imagePath: String, size: CGSize)`。引数 path から PhotoStorage 経由で UIImage を読み、表示。プレースホルダ / 不在時アイコンも内包 |
| キャッシュ | 新規 `ThumbnailCache` (NSCache wrapper、`final class ... : @unchecked Sendable` をシングルトン)。`NSCache<NSString, UIImage>` で `key = "<imagePath>@<intW>x<intH>"`、`countLimit = 200` 程度を上限 |
| 縮小処理 | iOS 17 標準の `UIImage.preparingThumbnail(of:)` を `Task.detached` 内で呼ぶ。元 jpeg は `ImageCompressor` で長辺 ≤ 2048px に圧縮済みだが、56pt 表示には大きすぎてメモリを食うので必ず縮小 |
| 並行性 | キャッシュアクセスは NSCache 自体がスレッドセーフ。`load(path:size:)` は async (Task 内で同期 I/O) で MainActor から呼ぶ。複数行が同時に同じ path をリクエストしても、最後の結果のみ View に反映される (`.task(id:)` で破棄) |
| キャッシュ無効化 | **行わない**。Item / Group 削除時にもキャッシュは触らず、次回参照で `UIImage(contentsOfFile:)` が nil を返したらプレースホルダに切り替える設計。NSCache 自身がメモリ警告で自動 evict するため、明示無効化は過剰 |

### 既存 `ItemDetailView` との関係

- 詳細画面の写真表示は変更しない (フルサイズ + `.scaledToFit()`、サムネ用キャッシュは経由しない)。詳細はキャッシュではなく `UIImage(contentsOfFile:)` 直読みのまま、リスト用サムネとは独立に扱う

## 影響範囲

| ファイル | 変更内容 |
|---|---|
| `ios/Photorans/Features/Item/ThumbnailCache.swift` | **新規**: `final class ThumbnailCache` (NSCache 包み) と `static let shared` |
| `ios/Photorans/Features/Item/ItemThumbnailView.swift` | **新規**: `ItemThumbnailView(imagePath:size:)` SwiftUI View |
| `ios/Photorans/Features/Item/ItemRowView.swift` | 行 leading に `ItemThumbnailView` を配置、`.processing` / `.completed` / `.failed` 全分岐で HStack 化 |
| `ios/Photorans/Features/Home/GroupListView.swift` | `folder.fill` を「`representativeItem` があればサムネ / なければ folder.fill」に分岐 |
| `ios/Photorans/Features/Home/HomeQueries.swift` | `representativeItem(of: ItemGroup) -> Item?` を追加 (`group.items` を `createdAt` 降順で先頭) |
| `ios/Photorans.xcodeproj/...` | XcodeGen 再生成 (`.swift` 新規 2 ファイル追加のため必須 / memory: `feedback_xcodegen_regenerate.md`) |

**変更しない**:
- `Item` / `ItemGroup` のスキーマ (新フィールド不要)
- `PhotoStorage` (既存の `absoluteURL(for:)` で十分)
- `ImageCompressor` / カメラパイプライン (元 jpeg はそのまま、表示時に preparingThumbnail で縮小)
- `ItemDetailView` (フル表示は据え置き)
- パンくず / FAB / セグメント Picker
- `HomeQueries.filterGroups` のソート順 (代表 Item の選び方は `representativeItem` に純関数化、ソートはそのまま「直下 Item の最新 createdAt 降順」)

## Step 分解

### Step 1: `ThumbnailCache` を実装

- `final class ThumbnailCache: @unchecked Sendable` + `static let shared = ThumbnailCache()`
- 内部に `private let cache = NSCache<NSString, UIImage>()`、`init` で `cache.countLimit = 200`
- API:
  - `func cached(path: String, size: CGSize) -> UIImage?` — 同期取得
  - `func store(_ image: UIImage, path: String, size: CGSize)` — 同期保存
  - `func cacheKey(path: String, size: CGSize) -> String` (純関数、テスト用に internal で公開)
- 縮小ロジックは View 側に置く (キャッシュは I/O を持たない方針で責務分離)

### Step 2: `ItemThumbnailView` を実装

- 引数: `imagePath: String`, `size: CGSize`
- `@State private var image: UIImage?`
- `body`:
  - `image` あれば `Image(uiImage:).resizable().aspectRatio(contentMode: .fill).frame(width: size.width, height: size.height).clipped().clipShape(RoundedRectangle(cornerRadius: 6))`
  - `image` 無ければ プレースホルダ (`RoundedRectangle.fill(.secondary.opacity(0.15)) + overlay(Image(systemName: "photo"))`、同サイズ + 同角丸)
- `.task(id: imagePath)` で
  1. `ThumbnailCache.shared.cached(path:size:)` を確認 → あれば即セット
  2. 無ければ `Task.detached { UIImage(contentsOfFile:)?.preparingThumbnail(of: size) }` で生成 → cache に store → MainActor で `image = ...`
  3. ファイル不在で nil なら `image = nil` のまま (プレースホルダ表示)

### Step 3: `ItemRowView` に サムネを統合

- `.processing` / `.completed` / `.failed` の各 `body` を HStack 化し、左に `ItemThumbnailView(imagePath: item.imagePath, size: CGSize(width: 56, height: 56))`
- 既存テキスト群は VStack のまま右側に配置、`Spacer()` で残り幅を埋める
- `.failed` の右端リトライボタン位置は維持 (HStack を入れ子で組む)
- VoiceOver: サムネ自体は `.accessibilityHidden(true)` (行のラベルは既存通り訳文 / 失敗メッセージで済む)

### Step 4: `HomeQueries.representativeItem(of:)` を追加

- `static func representativeItem(of group: ItemGroup) -> Item?`
- `group.items.max(by: { $0.createdAt < $1.createdAt })` を返す
- 既存 `directItems` のソート結果と一貫させるため、`group.items` 直読み (子孫探索しない)

### Step 5: `GroupListView` の leading icon を分岐

- 現在の `Image(systemName: "folder.fill").frame(width: 32)` 部分を以下に置換:
  ```swift
  if let rep = HomeQueries.representativeItem(of: group) {
      ItemThumbnailView(imagePath: rep.imagePath, size: CGSize(width: 56, height: 56))
  } else {
      folderPlaceholder
  }
  ```
- `folderPlaceholder` は `RoundedRectangle(cornerRadius: 6).fill(.secondary.opacity(0.15)).overlay(Image(systemName: "folder.fill"))` の 56pt 正方形 (Item 行とサイズ揃え)

### Step 6: XcodeGen 再生成

- `cd ios && xcodegen generate` を実行
- `.swift` 2 ファイル (`ThumbnailCache.swift` / `ItemThumbnailView.swift`) が新規追加なので memory `feedback_xcodegen_regenerate.md` に従い **同 commit に pbxproj 再生成を含める**
- `git status` で `Photorans.xcodeproj/project.pbxproj` の差分が出ることを確認

### Step 7: 実機確認の段取り (TestFlight)

- Akira さんに動作確認用 TestFlight 配信が必要かを確認
- 必要なら commit → tag push (patch インクリメント) を Akira さんの許可取得後に実施
- Akira さんに iPhone で確認依頼:
  1. 既存 Item 多数のグループを開いてスクロール時、サムネが順次表示されチラつかない
  2. 撮影直後 (`.processing`) の Item にもサムネが出ている
  3. グループタブで、Item を含むグループにはサムネ、Item ゼロ (サブグループのみ) のグループには folder アイコンが出ている
  4. Item 削除後、一覧からその行が消える (キャッシュ起因の幽霊行が出ない)
  5. メモリ使用量が爆発しない (体感で OK)

## テスト方針

- ユニットテスト追加候補:
  - `HomeQueries.representativeItem(of:)` のテスト (`SegmentQueryTests.swift` に追記)
    - Item ゼロの Group → nil
    - Item 1 件の Group → その Item
    - Item 複数の Group → `createdAt` 最大の Item
    - 子孫 Group のみ持つ中間 Group → nil (子孫まで探索しない仕様の固定)
  - `ThumbnailCache.cacheKey(path:size:)` のテスト (path / size の組合わせで一意キーになることの簡易チェック)。これはオプション、なくても可
- WSL2 ではビルド検証不可 (memory: `feedback_swift_api_verification.md`)
  - SwiftUI / UIImage の API シグネチャ (`preparingThumbnail(of:)` iOS 15+, `Task.detached`, `NSCache<NSString, UIImage>`) は Apple 公式ドキュメントを裏取りした上で使用
- 視覚的なリグレッション (チラつき / レイアウト崩れ / メモリ爆発) は TestFlight 実機で確認するしかない。Step 7 のチェックリストで担保

## 後追い検討項目 (本プランでは扱わない)

- サブグループしか持たない中間 Group の代表サムネ (子孫の最新 Item を再帰探索) — 体感が悪ければ後で追加
- `.processing` 中のシマー overlay をサムネ上に重ねるかどうか — 現状はサムネ表示 + テキスト側のみシマーで分かるので不要
- iCloud / Photos からのインポート画像 (将来別 TODO) との整合性
- 一覧用低解像度サムネを撮影時に事前生成してディスクに保存 (現在は表示時に毎回 `preparingThumbnail`)。iPad のような高速機ではボトルネックにならない見込みだが、低速 iPhone でカクついたら検討
