# ホーム画面 H4 実装プラン

## 位置づけ

- 親プラン (完了 → archive): `docs/plans/archive/screen-architecture.md` (画面構成パターン A 採用、Root 構成 H4 採用)
- 仕様プラン (完了 → archive): `docs/plans/archive/home-screen-h4-spec.md` (S1〜S14 の挙動を確定済み)
- 本プランのスコープ: 確定仕様をコードへ落とし込むためのファイル単位の作業ステップ。各 Step は単独でビルド可能 / レビュー可能な単位に切る

## 前提 (仕様プランからの抜粋)

- データモデル: `Item` + `ItemGroup` + `ItemStatus` (S9 / S13-1)
- 階層: 任意深さで Group をネスト可能 (S12 Q1)
- 画面構成: `TabView` 廃止 → `NavigationStack` 単一 + 右下 FAB (S5 / パターン A)
- Root / Group 詳細とも `[グループ | 未分類]` の 2 セグメント (S1 / S13-2)
- カメラ FAB の保存先 = 現在表示中の階層 (S4 / S13-4)
- Group 作成 FAB の保存先 = 現在表示中の階層直下 (S13-5)
- 撮影フロー: 楽観的 UI (S6) — 撮影直後にカメラを閉じ、`.processing` Item を即時挿入し背景で OCR + 翻訳
- マイグレーション: 旧 `HistoryEntry` ストアと `Documents/photos` を破棄 (S10)
- 検索: `.searchable` ベース、Item は全件横断 / Group 名は現在階層配下のみ (S14)

## 影響範囲

### 既存ファイル
- `ios/Photorans/PhotoransApp.swift` — ModelContainer の対象モデル変更 + 旧ストア破棄ロジック追加
- `ios/Photorans/RootView.swift` — TabView 廃止し `HomeView` を NavigationStack で表示
- `ios/Photorans/Features/Camera/CameraView.swift` — 楽観的 dismiss、保存先コンテキスト受け取り
- `ios/Photorans/Features/Camera/CameraViewModel.swift` — 撮影 → `Item(.processing)` 即時挿入、翻訳の責務をサービス側へ移譲
- `ios/Photorans/Storage/HistoryEntry.swift` — 削除
- `ios/Photorans/Features/History/HistoryListView.swift` — 削除 (`UnclassifiedListView` に置換)
- `ios/Photorans/Features/History/HistoryDetailView.swift` — 削除 (`ItemDetailView` に置換)

### 新規ファイル
- `ios/Photorans/Storage/Item.swift`
- `ios/Photorans/Storage/ItemGroup.swift`
- `ios/Photorans/Storage/ItemStatus.swift`
- `ios/Photorans/Storage/StoreBootstrap.swift` — `ModelContainer` 構築 + 旧ストア破棄フォールバック
- `ios/Photorans/Features/Home/HomeView.swift` — Root / Group 詳細で共通利用するセグメントスクリーン
- `ios/Photorans/Features/Home/SegmentScope.swift` — 「Root か Group か」を表すコンテキスト型
- `ios/Photorans/Features/Home/GroupListView.swift` — `グループ` セグメント本文
- `ios/Photorans/Features/Home/UnclassifiedListView.swift` — `未分類` セグメント本文
- `ios/Photorans/Features/Home/HomeFAB.swift` — カメラ FAB + Group 作成 FAB の二段スタック
- `ios/Photorans/Features/Group/GroupDetailView.swift`
- `ios/Photorans/Features/Group/GroupCreateSheet.swift`
- `ios/Photorans/Features/Group/GroupRenameSheet.swift`
- `ios/Photorans/Features/Item/ItemDetailView.swift`
- `ios/Photorans/Features/Item/MoveToGroupSheet.swift`
- `ios/Photorans/Features/Item/ItemRowView.swift` — `.processing` / `.completed` / `.failed` 行表示の分岐
- `ios/Photorans/Features/Item/ShimmerOverlay.swift` — 処理中シマー
- `ios/Photorans/Services/TranslationCoordinator.swift` — `Item.id` を受け取り背景で翻訳 → 結果反映、失敗時はリトライ可能な状態へ
- `ios/Photorans/Services/PendingItemRecovery.swift` — 起動時に `.processing` を検出し再開
- `ios/Photorans/Features/Home/HomeQueries.swift` — セグメントフィルタ + ソートの純関数 (Step 5.5 のテスト対象)
- `ios/PhotoransTests/StoreBootstrapTests.swift`
- `ios/PhotoransTests/SegmentQueryTests.swift`
- `ios/PhotoransTests/CaptureContextTests.swift`
- `ios/PhotoransTests/TranslationCoordinatorTests.swift`
- `ios/PhotoransTests/ItemGroupDeleteRecursivelyTests.swift`
- `ios/PhotoransTests/PendingItemRecoveryTests.swift`
- `ios/PhotoransTests/Fixtures/legacy_history_v1.sqlite` (バイナリ。Step 1.7 のフィクスチャ)

`ios/project.yml` の更新 (XcodeGen) は新規 `.swift` ファイル追加時に自動で拾われる構成かを Phase 0 の中で最初に確認し、必要なら同 PR で更新する。

## Phase / Step 一覧

各 Step の末尾に `(✅ ビルド可能 / 🧪 テスト追加 / 🔧 リファクタのみ)` のラベルを添える。

### Phase 0: PoC + 設計確定 (Phase 1 着手前の検証)

**目的**: Phase 1 以降で「設計を後戻り」させないために、SwiftData / SwiftUI / Swift 6 strict concurrency 上の不確実性を最小コードで先に潰す。各検証は最終コードに残さなくて良い (検証ブランチで結果だけメモ → 本プランに追記)。

- **Step 0.1** — **`Predicate<ItemGroup>` で `parent == nil` / `parent?.id == X` が iOS 17 deployment で動くか PoC**。動かない場合は `@Query` を諦めて `ItemGroup.children` リレーション直読みに倒す方針を Step 2.5 / 3.x に反映 (🔧)
- **Step 0.2** — **Background `ModelContext` での `Sendable` 越境 PoC**。`actor` から `ModelContainer` を借りて `let ctx = ModelContext(container); ctx.model(for: persistentID)` → 書き戻し → `ctx.save()` が `SWIFT_STRICT_CONCURRENCY: complete` で警告無くコンパイル + 動作することを確認。`ModelContext` を Task に渡す案は **NG** として TranslationCoordinator のシグネチャから除外 (🔧)
- **Step 0.3** — **NavigationStack の destination 配置 PoC**。`NavigationStack` root に `.navigationDestination(for: ItemGroup.self)` を 1 度だけ置き、その下の View が再帰的に `NavigationLink(value: ItemGroup)` を push する構成が iOS 17 で問題なく動くか確認。Step 2.3 / 2.9 / 4.4 の destination は **RootView (NavigationStack root) に集約**で確定 (🔧)
- **Step 0.4** — **deleteRule の確定**。仕様プラン S9 のスキーマを `@Relationship(deleteRule: .cascade, inverse: \Item.group)` および `@Relationship(deleteRule: .cascade, inverse: \ItemGroup.parent)` に変更し、本プランと突き合わせて整合させる。Step 4.6 の Group 削除はカスケードに任せ、UI 層では削除前に Item を traverse して写真ファイルだけ消す責務に限定 (🔧)

Phase 0 完了条件: Step 0.1〜0.4 の結果を本プラン末尾の「PoC 結果」セクションに追記し、影響を受ける Step (2.5 / 3.1 / 4.6 等) の文言を実コード前に更新する。

### Phase 1: データモデル + ストア基盤

**目的**: 旧 `HistoryEntry` を完全に置き換える新モデルを敷設し、起動時のフォールバックを動かせる状態にする。UI は一旦壊れても良い (Phase 2 で復旧)。

- **Step 1.1** — `Storage/ItemStatus.swift` を追加 (`enum ItemStatus: String, Codable { case processing, completed, failed }`) (✅)
- **Step 1.2** — `Storage/ItemGroup.swift` を追加。`parent` / `children` / `items` のリレーションを `@Relationship(deleteRule: .cascade, ...)` で定義 (S9 / S13-1 / Step 0.4) (✅)
- **Step 1.3** — `Storage/Item.swift` を追加。`originalText` / `translatedText` / `model` を `String?` に、`status` / `failureReason` / `group` を保持 (S9) (✅)
- **Step 1.4** — `Storage/StoreBootstrap.swift` を追加。`ModelContainer(for: Item.self, ItemGroup.self)` を構築する。**フォールバックは「初回起動の旧 schema → 新 schema 移行時のみ」に限定**: `UserDefaults` の `didMigrateFromHistoryEntryV1` フラグが false かつコンテナ生成が失敗したときに限り store ファイル一式 + `Documents/photos` を削除 → 再生成 → フラグ true 化。フラグ true 以降にコンテナ生成が失敗するのはディスクフル / 権限 / I/O エラー等の本物の障害なので **そのまま fatalError** で止める (誤って後続のユーザーデータを破壊しないため) (S10) (✅)
- **Step 1.5** — `PhotoransApp.swift` を `StoreBootstrap.makeContainer()` 経由に書き換え、`HistoryEntry` 参照を全削除 (✅)
- **Step 1.6** — `Storage/HistoryEntry.swift` および `HistoryListView.swift` / `HistoryDetailView.swift` の旧コードを削除し、`RootView` / `CameraView` / `CameraViewModel` の `HistoryEntry` 参照を一時的にスタブ化 (例: `// TODO: replaced in Phase 2/3` コメント付きで body を `EmptyView()` に差し替え) してビルドを通す。**Phase 1 と Phase 2 Step 2.1〜2.3 を 1 つの「scaffolding 用 PR」にまとめ**、PR 内の各 commit がビルド通る必要は無いが PR の最終 commit で必ずビルド通る運用とする (🔧)
- **Step 1.7** — `StoreBootstrapTests` を追加 (🧪):
  - フィクスチャ作成: 旧 `HistoryEntry` を内包した `.sqlite` ファイルをテストバンドルに同梱 (生成スクリプトは `PhotoransTests/Fixtures/make_legacy_store.sh` 等で別途用意し、commit 時にバイナリも commit)。`HistoryEntry.swift` は本コード側からは削除済みなのでフィクスチャは事前生成 + バイナリ commit がもっとも素直
  - 検証: `didMigrateFromHistoryEntryV1` が false かつ旧 store がある状態で `StoreBootstrap.makeContainer()` を呼ぶと、ファイルが消えて空の新ストアになり、フラグが true になる
  - 検証: フラグが true で破損した store がある状態で呼ぶと `fatalError` 相当 (テストでは `precondition` を `assertFailure` にする等の代替で検証)

### Phase 2: ホーム画面の骨格 (UI 復旧 + セグメント切替)

**目的**: TabView を廃止し、`HomeView` を NavigationStack で表示できる状態まで戻す。撮影フローはまだ旧コードに繋がない (FAB は仮の sheet)。

- **Step 2.1** — `Features/Home/SegmentScope.swift` を追加。`enum SegmentScope { case root; case group(ItemGroup) }` で Root / Group 詳細に共通の文脈を表現 (S13-2)。あわせて `var targetGroup: ItemGroup? { ... }` を実装 (Root → nil / Group → 当該 Group) し、Step 3.5 / 3.9 のテスト対象とする (✅)
- **Step 2.2** — `Features/Home/HomeView.swift` を追加。引数 `scope: SegmentScope` を取り、上部に `Picker(.segmented)` で `[グループ | 未分類]` を出す。デフォルト = `未分類` (S2)。本文は Step 2.4 / 2.5 で差し込み (✅)
- **Step 2.3** — `RootView.swift` を `NavigationStack { HomeView(scope: .root) }.navigationDestination(for: ItemGroup.self) { GroupDetailView(group: $0) }.navigationDestination(for: Item.self) { ItemDetailView(item: $0) }` に書き換える。**destination は NavigationStack の root に集約し、子 View 側では再宣言しない** (Step 0.3 で確定)。旧 TabView と `HistoryListView` 参照を削除 (✅)
- **Step 2.4** — `Features/Home/UnclassifiedListView.swift` を追加。Step 0.1 の PoC 結果 (iOS 17 では SwiftData `#Predicate` の `group == nil` がサポートされない) を踏まえ、**Predicate を使わずリレーション直読み + in-memory フィルタに統一**:
  - Root (`scope == .root`): `@Query(sort: \Item.createdAt, order: .reverse) private var allItems: [Item]` で全件取得し、`body` で `allItems.filter { $0.group == nil }` を表示
  - Group X (`scope == .group(let g)`): `g.items` を直読みし、`sorted(by: { $0.createdAt > $1.createdAt })` で in-memory ソート
  - 個人ユーザー規模では全件 fetch のコストは許容範囲。検索パフォーマンスが問題化したら Phase 5 以降で再検討
  - 空状態は `ContentUnavailableView` 文言 S11 を採用 (S3-2) (✅)
- **Step 2.5** — `Features/Home/GroupListView.swift` を追加。Step 0.1 の PoC 結果に従い、**`@Query` Predicate を使わずリレーション直読み + in-memory フィルタ + ソートに統一**:
  - Root (`scope == .root`): `@Query private var allGroups: [ItemGroup]` で全件取得し、`body` で `allGroups.filter { $0.parent == nil }`
  - Group X (`scope == .group(let g)`): `g.children` を直読み
  - 並び順は **直下 Item の最新 createdAt で降順、直下 Item ゼロの中間 Group は `nil` 扱い → 末尾固定**。in-memory で `sorted` を実装 (関係越しの max は SwiftData Predicate で表現困難 + そもそも Predicate を使わない方針)
  - 空状態は ContentUnavailableView (S11) (✅)
- **Step 2.6** — `Features/Home/HomeFAB.swift` を追加。カメラ FAB と Group 作成 FAB を縦に積む (S7 + S5)。Group 作成 FAB タップで `GroupCreateSheet` を提示。カメラ FAB は本 Phase ではスタブ (NSLog のみ)。**押し間違い対策**: カメラ FAB = `Color.accentColor` + `camera.fill`、Group 作成 FAB = `Color.secondary` + `folder.badge.plus`、両者の中心間距離 ≥ 72pt、それぞれに `accessibilityLabel("撮影") / .accessibilityLabel("グループを作成")` を必ず付与 (✅)
- **Step 2.7** — `Features/Group/GroupCreateSheet.swift` を追加。`scope` を受け取り `parent` を解決して新規 `ItemGroup` を挿入 (S13-5) (✅)
- **Step 2.8** — `Features/Group/GroupDetailView.swift` を追加。中身は `HomeView(scope: .group(self.group))` を呼ぶだけのラッパ (S13-2)。ナビゲーションタイトル = Group 名。**`navigationDestination` は宣言しない** (RootView 集約。Step 0.3) (✅)
- **Step 2.9** — `GroupListView` の行タップから `NavigationLink(value: ItemGroup)` で `GroupDetailView` に push し、Root / Group 詳細で同一 UI が動くことを確認 (✅)

### Phase 3: 楽観的撮影フロー

**目的**: 撮影 → 即 dismiss + `.processing` Item 挿入 → 背景翻訳 → inplace 更新までを通す。

- **Step 3.1** — `Services/TranslationCoordinator.swift` を追加。**`actor TranslationCoordinator` として実装** し、`init(container: ModelContainer)` で `ModelContainer` のみを保持 (Step 0.2 で確定。`ModelContext` は `Sendable` でないため Task 越境させない)。入口: `func enqueue(itemID: PersistentIdentifier, jpegData: Data) async`。実装は `let ctx = ModelContext(container); guard let item = ctx[itemID, as: Item.self] else { return }` で存在確認 → `TranslateAPI.shared.translate(jpegData:)` 呼び出し → 完了後に再度 `ctx[itemID]` で **存在確認 (途中削除されていれば silent no-op)** → `.completed` 更新 + `ctx.save()`。失敗時は `.failed` + `failureReason` を書き込む (S6 a/b/c)。**ライフサイクル**: `PhotoransApp` の `@State` で 1 インスタンスだけ生成し `.environment(\.translationCoordinator, ...)` で配布、View 再生成で cancel されないようにする (✅)
- **Step 3.2** — `Services/TranslationCoordinator` にリトライ API `func retry(itemID: PersistentIdentifier) async` を追加。`Item.imagePath` から jpeg を再ロードして内部処理を再実行 (S6 c)。**リトライ回数上限**: `Item` に `var retryCount: Int = 0` を追加 (Step 1.3 のスキーマ修正)、`retry` 呼び出し毎に increment、`retryCount >= 3` なら `.failed` のまま retry を no-op にして UI 側で「これ以上自動リトライしません」と表示。`PendingItemRecovery` (Step 5.3) からの自動リトライも同じ上限に従う。**写真ファイル不在時**は `failureReason = "画像ファイルが見つかりません"` で `.failed` 確定し retryCount = max にして無限ループを防ぐ (✅)
- **Step 3.3** — `CameraView.swift` の引数を `targetGroup: ItemGroup?` + `onCaptured: () -> Void` に変更。シャッター成功直後に `onCaptured` を呼ぶ。`onTranslated` は廃止 (S4 / S6) (✅)
- **Step 3.4** — `CameraViewModel.capturePhoto` を二段階に分割: ① 撮影 + 写真保存 + `Item(.processing, group: targetGroup)` 挿入 (synchronous の `modelContext.save`)、② `await translationCoordinator.enqueue(itemID: item.persistentModelID, jpegData: compressed)` を呼ぶだけ。`isTranslating` 状態と `lastResult` 観測は廃止。**MainActor の `modelContext` で insert + save を完了してから** background actor に渡すことで、background 側 fetch 時に必ず存在することを保証 (✅)
- **Step 3.5** — `HomeFAB` のカメラボタンから `fullScreenCover(isPresented:) { CameraView(targetGroup: scope.targetGroup, onCaptured: { dismiss() }) }` を提示する。`scope.targetGroup` は Step 2.1 の computed property を使用 (S4 / S13-4) (✅)
- **Step 3.6** — `Features/Item/ShimmerOverlay.swift` を追加。グラデーションを X 軸でアニメーションさせる SwiftUI モディファイアを実装 (S6 b)。`accessibilityHidden(true)` を付け、行全体に `.accessibilityLabel("処理中")` を別途付与 (✅)
- **Step 3.7** — `Features/Item/ItemRowView.swift` を追加。`status` で表示分岐: `.processing` → サムネ + プレースホルダ + ShimmerOverlay、`.completed` → 既存 HistoryRowView 相当、`.failed` → 赤バッジ + リトライボタン (S6 b/c)。リトライボタン押下で `Task { await translationCoordinator.retry(itemID: item.persistentModelID) }` (✅)
- **Step 3.8** — `UnclassifiedListView` の行 View を `ItemRowView` に差し替え (✅)
- **Step 3.9** — テスト追加 (🧪):
  - `CaptureContextTests`: `SegmentScope.targetGroup` の純関数テスト (Root → nil / Group(X) → X)、および `CameraViewModel.capturePhoto` 後に挿入された `Item.group` が `targetGroup` と一致することを in-memory `ModelContainer` で検証
  - `TranslationCoordinatorTests`: ① 正常系 = `.processing` → `.completed` 更新、② 途中で Item を delete → 書き戻しが silent no-op、③ retry 上限 = 3 回で停止、④ 写真ファイル不在 = `.failed` で retry も no-op

### Phase 4: アイテム / グループの CRUD

**目的**: 撮影 → 結果確認 → 削除 / 移動の動線を完成させる。

- **Step 4.1** — `Features/Item/ItemDetailView.swift` を追加。`HistoryDetailView` の表示要素 (写真 / 訳文 / 原文 / メタデータ) を踏襲しつつ、`status == .processing` 時は本文をシマー、`.failed` 時は失敗メッセージ + リトライを表示 (S6 / S8) (✅)
- **Step 4.2** — `ItemDetailView` のツールバーに「削除」「グループへ移動」を追加。削除は確認ダイアログ → 写真ファイルを `try? FileManager.default.removeItem` で消した後 `modelContext.delete(item)` (S8) (✅)
- **Step 4.3** — `Features/Item/MoveToGroupSheet.swift` を追加。全 Group のフラットリスト + 「未分類に移動」を提示し、選択で `Item.group` を更新 (S8) (✅)
- **Step 4.4** — `UnclassifiedListView` の行から `NavigationLink(value: Item)` で `ItemDetailView` に push (destination 解決は RootView 集約。Step 0.3 / 2.3) (✅)
- **Step 4.5** — `Features/Group/GroupRenameSheet.swift` を追加し、`GroupDetailView` ツールバーから提示 (S7) (✅)
- **Step 4.6** — `GroupDetailView` ツールバーに「削除」を追加。確認ダイアログの文言は子 Group 有無で分岐 (S13-3)。削除実行は **`ItemGroup.deleteRecursively(modelContext:)` 純関数を呼ぶ**: ① 配下を traverse して全 Item の写真ファイルを `FileManager.default.removeItem` で削除 → ② `modelContext.delete(self)` で ItemGroup を削除し、SwiftData の `.cascade` (Step 0.4 / 1.2) で子 Group と Item が連鎖削除される。**この純関数は Step 4.6 のテスト対象として必須** (任意ではない) (✅)
- **Step 4.7** — `HistoryListView.swift` / `HistoryDetailView.swift` を削除し、参照が無いことを確認 (🔧)
- **Step 4.8** — テスト追加 (🧪):
  - `ItemGroup.deleteRecursively` の単体テスト: ネスト 3 階層 + 各階層に Item 複数のフィクスチャを作り、削除後に SwiftData 上で全配下が消え、写真ファイルパスも全て `FileManager` 上から消えていることを検証

### Phase 5: 検索 + 起動時リカバリ

**目的**: 残りの仕様 (S14, S6 a の kill 復帰) を埋めて完成形にする。

- **Step 5.1** — `HomeView` に `.searchable(text: $searchText, prompt: "翻訳・グループ名を検索")` を **1 度だけ** 追加 (子 View 側では宣言しない。NavigationStack の `.searchable` は祖先で 1 度に統一しないと検索 UI が点滅するため)。`searchText` は `HomeView` の `@State`、現在セグメントに応じて子 View に `searchText` を渡し、子 View はフィルタにのみ使う (S14-1) (✅)
- **Step 5.2** — `UnclassifiedListView` / `GroupListView` を `searchText: String` を受け取る形に変更。Item フィルタ = `originalText` / `translatedText` を `contains` かつ `.completed` のみ対象 (S14-2 / S14-4)。Group フィルタ = `scope` 配下 (Root → 全 Group の子孫 / Group X → X の子孫) の Group 名 `contains` (S14-2)。空文字列のときはフィルタ無し (✅)
- **Step 5.3** — `Services/PendingItemRecovery.swift` を追加。起動時に `Item.status == .processing` を全件取得し、各 Item に対して `await translationCoordinator.retry(itemID:)` を順次呼ぶ。`retryCount >= 3` の Item は Step 3.2 の上限により retry 側で no-op になるため、ここでは件数フィルタしない (S6 a の kill 復帰) (✅)
- **Step 5.4** — `PhotoransApp` 起動シーケンスから `PendingItemRecovery.runIfNeeded(container:, coordinator:)` を呼ぶ (`WindowGroup` の `.task`)。`StoreBootstrap` でストア破壊フォールバックが走った直後でも安全 (該当時は `.processing` ゼロ件) (✅)
- **Step 5.5** — `SegmentQueryTests` を追加。`scope` ごとの GroupListView / UnclassifiedListView のフィルタ + ソートロジックを純関数 (`HomeQueries.swift` 等) に切り出し、ネスト 3 階層 + Item 多数のフィクスチャで検証。検索文字列ありのケース (Step 5.2) も同テストでカバー (🧪)
- **Step 5.6** — `PendingItemRecoveryTests` を追加。`.processing` × N 件、`.failed` × M 件、`.completed` × K 件のフィクスチャで起動シーケンスを実行し、`.processing` のみが retry 経路に流れることを (TranslationCoordinator のモックで) 検証 (🧪)

### Phase 6: TestFlight 確認 + 後片付け

- **Step 6.1** — Akira さんに「次のビルドで履歴が全消去されます」を事前通知 (S10) してから annotated tag を切る (☁️ TestFlight)
- **Step 6.2** — TestFlight 実機で以下を確認: 旧履歴の消滅、Root / Group 詳細でのセグメント切替、撮影 → 楽観的 UI、kill → 再起動でのリカバリ、Group 階層化、検索、削除挙動 (☁️)
- **Step 6.3** — Akira さんから OK が出たら `TODO.md` の Phase 5 (= 親プランの完了マーク) を進め、本プランを `docs/plans/archive/` に移送 (🔧)

## 依存関係 / 並列化の余地

- **Phase 0 → Phase 1 → Phase 2 → Phase 3 は直列** (UI が都度ビルドできる状態を維持するため)。Phase 0 の PoC 結果は Step 2.4 / 2.5 / 3.1 / 4.6 の文言を確定させる
- Phase 4 と Phase 5 は Phase 3 完了後に **限定的に並列可能**。ただし以下は同じ View / 純関数を触るので衝突注意:
  - Phase 4 Step 4.4 (UnclassifiedListView から push) と Phase 5 Step 5.2 (UnclassifiedListView の searchText 受け取り化)
  - Phase 4 Step 4.6 (純関数化された `ItemGroup.deleteRecursively`) と Phase 5 Step 5.5 (純関数化された `HomeQueries`)
- テスト追加 Step (1.7 / 3.9 / 4.8 / 5.5 / 5.6) は対応 Phase の最後にまとめて入れても良いし、TDD で先行させても良い

## リスクと未解決事項

- **SwiftData の cascade と画像ファイル削除のずれ** (Phase 0 / Step 4.6 で対処): `@Relationship(deleteRule: .cascade)` で SwiftData の再帰削除はできるが、`Item.imagePath` の jpeg 削除は連動しない。`ItemGroup.deleteRecursively` で **traverse → ファイル削除 → SwiftData delete** の順序で対処
- **写真ファイル削除中のクラッシュ** (許容): Group 削除中に kill された場合、SwiftData は未削除なので孤児ファイルが残る。許容範囲だが、起動時の cleanup ジョブを後続フェーズで検討する余地あり
- **`@Query` のネスト対応** (Step 0.1 で確定): SwiftData の `Predicate<ItemGroup>` で `parent?.id == ...` が iOS 17 で動かない場合、`ItemGroup.children` 直読み + in-memory フィルタに倒す
- **TranslationCoordinator のライフサイクル** (Step 0.2 / 3.1 で確定): `actor TranslationCoordinator(container:)` を `PhotoransApp` の `@State` で 1 インスタンス保持し、environment 経由で配布。`ModelContext` は Task 越境させず、background は `ModelContext(container)` を都度生成
- **`.processing` Item の途中削除レース** (Step 3.1 で対処): 楽観的 UI の Item をユーザーが詳細から削除した直後に翻訳が完了するケース。`TranslationCoordinator` が書き戻し前に `ctx[itemID]` で存在確認し、nil なら silent no-op
- **リトライ無限ループ防止** (Step 3.2 / 1.3 で対処): `Item.retryCount` を追加し上限 3 回。写真ファイル不在は即 max にして自動リトライ停止
- **`StoreBootstrap` のフォールバック誤発動** (Step 1.4 で対処): `UserDefaults` フラグで「初回 schema 移行のみ」に限定し、それ以降の I/O エラーで誤って store 破壊しないようにする
- **`.searchable` 二重配置による点滅** (Step 5.1 で対処): 子 View ではなく `HomeView` 1 箇所に集約
- **検索のパフォーマンス**: Item 全件横断検索は件数増加で遅くなる可能性があるが、当面 `.searchable` の標準フィルタリングで様子を見る (S14)
- **NavigationStack destination の配置** (Step 0.3 で確定): RootView の NavigationStack 直下で `.navigationDestination(for: ItemGroup.self) / .navigationDestination(for: Item.self)` を 1 度だけ宣言。子 View での再宣言は警告/重複登録の原因になるため禁止

## テスト方針

仕様プランで挙げた以下を実装プランの中で網羅する (いずれも **必須**):

- SwiftData マイグレーションの単体テスト (`StoreBootstrapTests` / Step 1.7) — フィクスチャ用に旧 schema の `.sqlite` をバンドル同梱
- セグメントごとのフィルタ + ソートロジックの単体テスト (`SegmentQueryTests` / Step 5.5) — 純関数 `HomeQueries` をテスト対象化
- カメラ起動コンテキスト → 保存先解決ロジックの単体テスト (`CaptureContextTests` / Step 3.9)
- TranslationCoordinator の正常系 / 途中削除 silent no-op / retry 上限 / 写真ファイル不在 (`TranslationCoordinatorTests` / Step 3.9)
- Group 再帰削除 + 写真ファイル削除の単体テスト (`ItemGroup.deleteRecursively` のテスト / Step 4.8)
- 起動時リカバリの単体テスト (`PendingItemRecoveryTests` / Step 5.6)
- 画面遷移の手動テストシナリオ — Phase 6 の TestFlight チェックリスト

## TODO.md への展開 (2026-05-02 適用済み)

親プラン側の Phase 5「実装タスクを TODO に展開して着手」を、**ルート TODO「ホーム画面 H4 実装」に独立タスクとして分離**して着手する。impl prefix は外し、本プランの Phase 番号 (0〜6) と TODO.md の Phase 番号を一致させる:

```
- [ ] ホーム画面 H4 実装 [plan](docs/plans/home-screen-h4-impl.md)
    - 親プラン (完了): [screen-architecture](docs/plans/archive/screen-architecture.md) / 仕様プラン (完了): [home-screen-h4-spec](docs/plans/archive/home-screen-h4-spec.md)
    - [x] Phase 0: PoC + 設計確定 (Step 0.1〜0.4) — 事前完了 2026-05-02
    - [ ] Phase 1: データモデル + ストア基盤 (Step 1.1〜1.7)
    - [ ] Phase 2: ホーム画面骨格 (Step 2.1〜2.9)
    - [ ] Phase 3: 楽観的撮影フロー (Step 3.1〜3.9)
    - [ ] Phase 4: CRUD (Step 4.1〜4.8)
    - [ ] Phase 5: 検索 + リカバリ (Step 5.1〜5.6)
    - [ ] Phase 6: TestFlight + 後片付け (Step 6.1〜6.3)
```

## PoC 結果 (Phase 0 完了時に追記)

検証環境の制約: Akira さんの開発機は WSL2 (Linux) で Xcode を直接実行できないため、Phase 0 は **Apple 公式ドキュメント / Apple Developer Forums / 信頼できる解説記事 (Use Your Loaf, Hacking with Swift, Donny Wals 等) の一次情報に基づくドキュメント検証** で確定させた。実機での最終確認は Phase 6 の TestFlight チェックリストに含める。

- **Step 0.1** `Predicate<ItemGroup>` / `Predicate<Item>` の optional keypath: ☑ 検証完了 (2026-05-02)
  - **結論**: SwiftData の `#Predicate` は iOS 17 deployment では optional to-one relationship の `nil` 比較 (`group == nil`, `parent == nil`) を **サポートしていない** (Apple Developer Forums [thread/732111](https://developer.apple.com/forums/thread/732111) で Apple エンジニアが回避策を提示。final iOS 17 でも未修正)。`group?.id == localID` 形式 (ローカル変数経由 + Optional の `id` 比較) は動くが、`nil` 判定だけは別経路が必要。iOS 17.5+ で改善された情報もあるが、本アプリの deployment target は iOS 17.0 なので保守的に判断
  - **採用方針**: **`@Query` Predicate を諦め、リレーション直読み + in-memory フィルタに統一**。Root では `@Query` で全件取得 → `.filter { $0.group == nil }` / `.filter { $0.parent == nil }`、Group X 詳細では `g.items` / `g.children` を直読み
  - **影響を受けた Step**: Step 2.4 / 2.5 (本プラン同時更新済み)。実装が均質化されるメリットもある
  - **根拠リンク**:
    - [SwiftData #Predicate cannot test for nil relationship — Apple Developer Forums](https://developer.apple.com/forums/thread/732111)
    - [SwiftData Predicates For Parent Relationships — Use Your Loaf](https://useyourloaf.com/blog/swiftdata-predicates-for-parent-relationships/)
    - [Common SwiftData errors and their solutions — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/common-swiftdata-errors-and-their-solutions)

- **Step 0.2** Background `ModelContext` × strict concurrency: ☑ 検証完了 (2026-05-02)
  - **結論**: `ModelContainer` および `PersistentIdentifier` は `Sendable`。`ModelContext` および `@Model` インスタンスは `Sendable` ではなく **actor 越境禁止**。`SWIFT_STRICT_CONCURRENCY: complete` 下では Apple 推奨パターン = 「actor に `ModelContainer` を渡し、各 task 内で `let ctx = ModelContext(container)` を生成、`PersistentIdentifier` を境界で受け渡し → `ctx[id, as: Item.self]` で再 fetch」が確立されている
  - **採用方針**: プラン Step 3.1 の `actor TranslationCoordinator(container: ModelContainer)` 設計と完全一致。`ModelContext` を Task に渡す案は **NG** として TranslationCoordinator のシグネチャから除外する方針も維持
  - **影響を受けた Step**: Step 3.1 / 3.4 / 5.3 はすでに本方針で書かれているため文言修正なし
  - **根拠リンク**:
    - [How SwiftData works with Swift concurrency — Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-swiftdata-works-with-swift-concurrency)
    - [SwiftData Background Tasks — Use Your Loaf](https://useyourloaf.com/blog/swiftdata-background-tasks/)
    - [How to run Swift Data and Core Data operations in the background — Pol Piella](https://www.polpiella.dev/core-data-swift-data-concurrency)

- **Step 0.3** NavigationStack destination 集約: ☑ 検証完了 (2026-05-02)
  - **結論**: 公式ドキュメント `NavigationStack` / `navigationDestination(for:destination:)` および各種解説記事が「**1 つの NavigationStack root に複数の `.navigationDestination(for:)` を集約する**」を推奨パターンとして明示。同じ型に対する destination を子 View で再宣言すると後勝ちで上書きされ、警告は出ないが意図しない遷移につながる
  - **採用方針**: プラン Step 2.3 通り、`RootView` の `NavigationStack` 直下で `.navigationDestination(for: ItemGroup.self) / .navigationDestination(for: Item.self)` を 1 度だけ宣言。`GroupDetailView` (Step 2.8) では宣言しない
  - **影響を受けた Step**: Step 2.3 / 2.8 / 2.9 / 4.4 はすでに本方針で書かれているため文言修正なし
  - **根拠リンク**:
    - [NavigationStack — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/NavigationStack)
    - [navigationDestination(for:destination:) — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/navigationdestination(for:destination:))
    - [Handling navigation the smart way with navigationDestination() — Hacking with Swift](https://www.hackingwithswift.com/books/ios-swiftui/handling-navigation-the-smart-way-with-navigationdestination)

- **Step 0.4** deleteRule 確定: ☑ 仕様プラン S9 を `.cascade` に修正済み (2026-05-02、本プラン更新と同時に反映完了)

## 次のステップ

Phase 0 (PoC) は事前完了済み (2026-05-02)、ルート TODO「ホーム画面 H4 実装」に分離済み。**Phase 1 (データモデル + ストア基盤) から実装着手** する。
