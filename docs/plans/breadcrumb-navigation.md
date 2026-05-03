# ナビバー削除 + パンくずリンク 実装プラン

> 2026-05-03 詳細化。確定済みの設計を Phase / Step に展開。Phase 0 (PoC 部品) → Phase 1〜4 (本実装) → Phase 5 (検証) → Phase 6 (TestFlight)。

## 目的

TODO「ナビバーを削除しパンくずリンクで階層を表示する」を実現する。

- 上部の navigation bar 領域 (Root では "Photorans" 大タイトル、Group 詳細ではグループ名インラインタイトル) を **完全に消して 0pt** にする
- Group 詳細では `[未分類 | グループ]` Picker の **直下** に `親 › 子 › [現在地]` 形式のパンくずを置き、中間階層へ直接ジャンプできるようにする (左上には `chevron.left` のカスタム戻るボタンを別途配置)

## 確定した設計 (2026-05-03)

| 項目 | 確定値 | 補足 |
|------|--------|------|
| ナビバー削除範囲 | Root + Group 詳細のみ | Item 詳細 / Sheet 系 (GroupCreateSheet, GroupRenameSheet, MoveToGroupSheet) は **標準ナビバー維持** |
| 検索 UI | 一旦削除 | `.searchable` を削る。`HomeQueries` の純関数も searchText 引数を削除して簡素化。再導入は別 TODO |
| パンくず Root の表現 | 出さない | パンくずは「親 > 子 > [現在地]」から始める (root を表す アイコン / 文字は置かない) |
| セパレータ | `chevron.right` SF Symbol | `Image(systemName: "chevron.right")` を ItemGroup 名の間に挟む |
| 末尾 (現在地) | 表示する / タップ無効 | 末尾だけ Text のみ (Button にしない)、ウェイトを `.semibold` にして判別 |
| 長いパス | 左側 (Root に近い側) を `...` で省略 | `...` は Text のみ、タップ不可 |
| 「未分類」セグメント時 | パンくず非表示 | Group 詳細でも未分類タブを開いている間はパンくずを描画しない |
| 画面タイトル | 持たない | 現在地名はパンくず末尾でのみ表す。`.navigationTitle` は両画面で削除 |
| Group 詳細の戻る | パンくず + 左上カスタム戻る | `chevron.left` アイコンのみ。タップ領域 44pt 確保。`dismiss()` を呼ぶ |

### Group 詳細レイアウト (確定)

グループタブ表示中:
```
[ ← ]                            ⋯       ← 上部行: 戻る + 既存メニュー
[未分類 | グループ]                        ← 既存 Picker (並び順は別 TODO で反転済み前提)
親  ›  子  ›  [現在地]                     ← パンくず (Picker の下、グループタブ時のみ)
一覧コンテンツ...
                                  [+] [📷]   ← 既存 FAB
```

未分類タブ表示中 (パンくず非表示):
```
[ ← ]                            ⋯
[未分類 | グループ]
                                          ← パンくず行は出さず詰める
一覧コンテンツ (未分類)...
                                  [+] [📷]
```

Root レイアウト:
```
(ナビバー領域 0pt、パンくずなし、戻るボタンなし)
[未分類 | グループ]
一覧コンテンツ...
                                  [+] [📷]
```

## 影響範囲

### 既存ファイル
- `RootView.swift` — `NavigationStack` を path 化、`.navigationTitle` 削除、`.toolbar(.hidden,...)` 追加
- `Features/Home/HomeView.swift` — `.searchable` 削除、`path: Binding<NavigationPath>?` 引数追加、Picker 直下にパンくず描画 (条件付き) を追加
- `Features/Home/GroupListView.swift` / `UnclassifiedListView.swift` — `searchText` 引数を削除
- `Features/Home/HomeQueries.swift` — `searchText` パラメータを削除 (フィルタ純関数を簡素化)
- `Features/Group/GroupDetailView.swift` — `.navigationTitle` / `.navigationBarTitleDisplayMode(.inline)` 削除、上部にカスタム戻る + 既存メニューを配置、`.toolbar(.hidden,...)` 追加、`path: Binding<NavigationPath>` を受け取り `HomeView` へ中継
- `ios/PhotoransTests/SegmentQueryTests.swift` — searchText 関連ケースを削除 / 更新

### 新規ファイル
- `Features/Home/BreadcrumbView.swift` — パンくず描画 (推定 60〜80 行)
- `Features/Home/BreadcrumbPath.swift` — `ItemGroup` から `[ItemGroup]` (Root 側→現在地順) を生成する純関数 (推定 20 行)
- `ios/PhotoransTests/BreadcrumbPathTests.swift` — パス構築ロジックの単体テスト

### XcodeGen (CLAUDE.md ルール)
- `.swift` ファイルの追加削除は **同 commit に `pbxproj` 再生成** を含める

## NavigationStack の path 管理方針

- 現状: `RootView` の `NavigationStack { ... }` は path 引数なし。`NavigationLink(value: group)` / `NavigationLink(value: item)` で push、`dismiss()` で pop。
- 変更: `@State private var path = NavigationPath()` を持ち、`NavigationStack(path: $path) { ... }` に書き換える。
  - `NavigationPath` を選ぶ理由: 既存の push 対象が `ItemGroup` と `Item` の **両方** で型が混在するため。`[ItemGroup]` 型の path にすると Item を push できなくなる。
  - パンくずタップ時の pop: `path.removeLast(k)` で k 段戻す。k は `(現在の親チェーン長) - (タップ先の祖先チェーン内 index) - 1`。
- パンくず可視時 (Group 詳細・グループタブ) の前提: path の末尾は `ItemGroup` であり、その親チェーン長 = path の ItemGroup 要素数 (Item は Item 詳細でしか push されず、その間はパンくずを描画しない画面に居る)。

## API 検証メモ (CLAUDE.md「Swift API は推測で書かない」)

実装着手前に Apple 公式ドキュメントで以下を確認する:

1. `.toolbar(.hidden, for: .navigationBar)` (iOS 16+) — `ToolbarPlacement.navigationBar` が `Visibility.hidden` を受け、当該 View でナビバー領域が 0pt になることを再確認
2. `NavigationPath.removeLast(_ k: Int = 1)` — public mutating method として存在することを Apple Developer Documentation の `NavigationPath` ページで再確認 (デフォルト引数 `k=1`)
3. `NavigationStack(path:)` の Binding 型 (`Binding<NavigationPath>`) と `NavigationLink(value:)` の併用パターン
4. `ViewThatFits(in: .horizontal) { ... }` (iOS 16+) — 子 View を順に評価し、最初に収まったものを採用する挙動。Phase 4 の左側省略レイアウトで使う
5. **`.toolbar(.hidden, for: .navigationBar)` と interactive pop gesture (edge swipe) の相互作用** — 検証で未確定の項目。一般論では `NavigationStack` (iOS 16+) はバー非表示でも edge swipe を保持する設計だが、Apple 公式に明文の保証がない。実機 (Phase 6 TestFlight) で挙動確認するまでは **「edge swipe は使えるかもしれないが当てにしない」** 前提で進める

## Phase / Step

### Phase 0: 共有部品 (BreadcrumbPath + BreadcrumbView 単独) を作る

- [ ] **Step 0.1**: `Features/Home/BreadcrumbPath.swift` を新規作成。`static func ancestorChain(of group: ItemGroup) -> [ItemGroup]` を公開。`group.parent` を辿って末尾が `group` 本体になる順序で配列を返す。循環は理論上発生し得ないが防御として 64 段で打ち切り
- [ ] **Step 0.2**: `Features/Home/BreadcrumbView.swift` を新規作成。引数: `chain: [ItemGroup]`, `onTap: (ItemGroup) -> Void`。横幅判定なし版で `HStack { Button { Text(name) } / chevron.right / ... 末尾は Text }` を並べる。末尾要素は Button にしない
- [ ] **Step 0.3**: `BreadcrumbPathTests.swift` を新規作成。0 階層 (Root 直下: `ancestorChain(.X)` = `[X]`)、1 階層、3 階層、parent ループ防御 (parent を自己参照する不正データ) の 4 ケース
- [ ] **Step 0.4**: XcodeGen で 3 ファイルを `pbxproj` に登録、`xcodebuild -scheme Photorans test` でテスト通過確認

### Phase 1: NavigationStack を path 化 + ナビバー削除 + カスタム戻る

- [ ] **Step 1.1**: `RootView` に `@State private var path = NavigationPath()` を追加し `NavigationStack(path: $path) { ... }` に書き換える。既存の `NavigationLink(value:)` 経由の push が機能することを Preview で確認
- [ ] **Step 1.2**: `RootView` の `.navigationTitle("Photorans")` を削除、`HomeView(scope: .root)` に `.toolbar(.hidden, for: .navigationBar)` を当てる。Status bar (時刻 / 電波 / バッテリー) の safe area は残ることを確認
- [ ] **Step 1.3**: `GroupDetailView` から `.navigationTitle(group.name)` / `.navigationBarTitleDisplayMode(.inline)` / 既存 `.toolbar { ToolbarItem(.topBarTrailing) { Menu... } }` を削除し、その代替として **カスタム上部行** を `HomeView(scope: .group(group))` の上に挿入する
  - `HStack { Button(action: dismiss) { Image(systemName: "chevron.left") } / Spacer() / Menu { ... } label: { Image(systemName: "ellipsis.circle") } }`
  - 既存メニュー (名前を編集 / グループを削除) はこの Menu に移植
  - **パンくずはここには乗せない** (Phase 3 で `HomeView` 内の Picker 直下に置く)
- [ ] **Step 1.4**: `GroupDetailView` の本体に `.toolbar(.hidden, for: .navigationBar)` を当て、戻るボタンが `dismiss()` で 1 段 pop することを Preview で確認
- [ ] **Step 1.5**: edge swipe (画面左端からスワイプで戻る) の挙動確認。`.toolbar(.hidden, ...)` と組み合わせた際に gesture が保持されるかは Apple 公式に明文がないため、**Preview ではなく Phase 6 の TestFlight 実機検証で確定** とする。仮に edge swipe が無効でも、Step 1.3 のカスタム戻るボタン + パンくず中間タップ (Phase 3) でフォールバック済みなので機能ブロッカーにはならない

### Phase 2: 検索 UI を削除 (`.searchable` + searchText 経路)

- [ ] **Step 2.1**: `HomeView.swift` から `.searchable(text: $searchText, prompt: ...)` を削除、`@State private var searchText` も削除。冒頭ドキュメントコメントの `.searchable` 解説も削除
- [ ] **Step 2.2**: `GroupListView` / `UnclassifiedListView` の `searchText: String` 引数を削除し、`HomeView` 側の呼び出しからも除去。各ファイルの `emptyView` 内 `if !searchText.trimmingCharacters(...).isEmpty { ContentUnavailableView.search(text:) }` 分岐も削除 (検索 UI が無くなるので空文字列以外が来ない)。冒頭ドキュメントコメントの searchText 解説も整理
- [ ] **Step 2.3**: `HomeQueries.swift` の `filterItems` / `filterGroups` から `searchText` パラメータを削除し、各々が空文字列時のロジック (`directItems` / `sortDirectGroups(directGroups(...))`) のみを残す。`descendantGroups` は他から使われていないなら削除候補
- [ ] **Step 2.4**: `SegmentQueryTests.swift` のケース整理 (内訳明示):
  - **残す (5 ケース、`searchText:` 引数を削るだけ)**:
    - `testFilterItemsEmptySearchAtRootReturnsOnlyUngroupedSortedDesc` (リネームを推奨: `testFilterItemsAtRootReturnsOnlyUngroupedSortedDesc`)
    - `testFilterItemsEmptySearchAtGroupReturnsOnlyDirectChildrenItems` (同様にリネーム)
    - `testFilterGroupsEmptySearchAtRootShowsRootDirectGroupsSortedByLatestItem` (同様にリネーム)
    - `testFilterGroupsEmptySearchAtGroupShowsOnlyDirectChildren` (同様にリネーム)
    - `testFilterGroupsEmptyEmptyItemGroupsSortedToTail` (`Empty` 重複なのでリネーム機会)
  - **完全削除 (8 ケース)**:
    - `testFilterItemsWhitespaceOnlySearchTreatedAsEmpty` (検索 semantics が消える)
    - `testFilterItemsSearchCrossesAllScopesAndOnlyCompleted`
    - `testFilterItemsSearchMatchesTranslatedText`
    - `testFilterItemsSearchIsCaseInsensitive`
    - `testFilterItemsSearchExcludesProcessingAndFailed`
    - `testFilterGroupsSearchAtRootIncludesAllDescendants`
    - `testFilterGroupsSearchAtGroupExcludesSelfAndOutsideScope`
    - `testFilterGroupsSearchIsCaseInsensitive`
- [ ] **Step 2.5**: `xcodebuild -scheme Photorans test` で全テスト通過 (SegmentQueryTests 5 ケース + 他 5 ファイル = 6 テストファイル分)

### Phase 3: HomeView の Picker 直下にパンくずを統合 + 未分類時の非表示制御

- [ ] **Step 3.1**: `RootView` の `@State path: NavigationPath` を `Binding` で `GroupDetailView` まで配線
  - `RootView` の `.navigationDestination(for: ItemGroup.self) { group in GroupDetailView(group: group, path: $path) }` に変更
  - `GroupDetailView` に `let path: Binding<NavigationPath>` を追加
- [ ] **Step 3.2**: `HomeView` のシグネチャに `path: Binding<NavigationPath>?` を追加 (Root 用は省略可)。`GroupDetailView` から `HomeView(scope: .group(group), path: path)` で渡す
- [ ] **Step 3.3**: `HomeView` の `VStack(spacing: 0) { Picker; content }` を `VStack(spacing: 0) { Picker; breadcrumb (条件付き); content }` に書き換え。breadcrumb 表示条件は **すべて満たす** とき:
  - `scope` が `.group(let X)` (Root では絶対に出さない)
  - `selectedSegment == .groups` (未分類タブでは出さない)
  - `path != nil`
  - chain は `BreadcrumbPath.ancestorChain(of: X)` をそのまま使う。「Root を出さない」要件は「アプリの Root を表すアイコン/文字を頭に付けない」という意味で、ItemGroup そのもの (parent==nil の最上位 Group も含む) は全て chain に並べる
  - 例: 現在地が parent==nil の Group X → chain = `[X]` → 表示 `[X]` (現在地のみ、chevron なし)
  - 例: 現在地が 2 階層目 → chain = `[P, X]` → 表示 `P › [X]`
  - 例: 現在地が 3 階層目 → chain = `[GP, P, X]` → 表示 `GP › P › [X]`
- [ ] **Step 3.4**: パンくず中間タップ時の pop ロジック: `BreadcrumbView` の onTap で `path?.wrappedValue.removeLast(k)` を呼ぶ
  - k の計算: chain 内の対象 index を `i`、現在の chain 長を `n` とすると `k = n - i - 1`
  - 「Root に近い祖先タップ → そこまで一気に戻る」が達成できることを Preview で確認
- [ ] **Step 3.5**: 末尾 (現在地) は Text のみで描画、Button にしない (タップ無効、ウェイト `.semibold`)
- [ ] **Step 3.6**: chain 長 1 (現在地が Root 直下) の場合は `[現在地]` のみで chevron は出ない
- [ ] **Step 3.7**: 未分類タブ選択中はパンくず行を完全に詰める (Spacer / EmptyView 切替で 0pt にし、Picker と content が直接隣接するレイアウト)

### Phase 4: 左側省略レイアウト (Root に近い側を `...`)

> 検証メモ: SwiftUI の `GeometryReader` はコンテナ幅しか返さず、子 `Text` の描画幅は取れない。素朴な「末尾から積み上げ」は実装困難なので、`ViewThatFits(in: .horizontal)` で **「省略段数の異なる N 個のバリアント」** を順に並べ、先に収まるものを採用する設計に変更する。

- [ ] **Step 4.1**: `BreadcrumbView` 内に「省略段数 `dropCount` を引数に取り `[...] [chain[dropCount]] [chevron] ... [chain.last]` を描画する private 関数」を実装。`dropCount = 0` のときは `...` を出さず chain 全体を描画
- [ ] **Step 4.2**: `body` を `ViewThatFits(in: .horizontal) { ForEach(0..<chain.count) { dropCount in variant(dropCount) } }` 形式に書き換え
  - `dropCount = 0` (全表示) → `dropCount = 1` (1 つ省略) → ... → `dropCount = chain.count - 1` (現在地のみ) の順に並べる
  - SwiftUI が利用可能幅にフィットする最初のバリアントを選ぶ
- [ ] **Step 4.3**: 4 階層 / 5 階層のサンプルデータ + 短い横幅でプレビューを切り、左側 `...` 省略が機能することを確認
- [ ] **Step 4.4**: chain 長 1 (現在地のみ) のケースは Phase 3 Step 3.6 と整合 — `ViewThatFits` のバリアントが 1 つだけでも問題なく動くことを確認

### Phase 5: 動作確認 + テスト

- [ ] **Step 5.1**: TodoApp Preview で 4 シーンを通し確認
  - Root (グループタブ / 未分類タブ)
  - Group 詳細 1 階層 (グループタブ / 未分類タブ)
  - Group 詳細 3 階層 (グループタブ / 未分類タブ + パンくず祖先タップ)
  - Group 詳細 5 階層 (左側 `...` 省略)
- [ ] **Step 5.2**: `xcodebuild -scheme Photorans test` で全テスト通過 (Phase 2 整理後の SegmentQueryTests 5 ケース + 他 5 テストファイル + 新規 BreadcrumbPathTests 4 ケース)
- [ ] **Step 5.3**: 既存メニュー機能 (名前編集 / グループ削除) が Step 1.3 移植後も同じ挙動で動くことを確認
- [ ] **Step 5.4**: カスタム戻るボタン / パンくずタップ の 2 経路で戻りが破綻しないことを Preview で確認 (edge swipe は Phase 6 の TestFlight 実機検証に回す)

### Phase 6: TestFlight (実機リグレッション)

- [ ] **Step 6.1**: Akira さん確認の上で `git tag -a v0.1.X` を作成 + push (Bitrise が release Workflow 起動)
- [ ] **Step 6.2**: TestFlight 配信完了を待つ (Apple 処理 ~30 分)
- [ ] **Step 6.3**: Akira さん実機確認結果共有待ち (OK / NG)。確認項目に **edge swipe で戻れるか / 戻れないか** を含める (Phase 1 Step 1.5 で保留した検証ポイント)
- [ ] **Step 6.4**: edge swipe が無効だった場合は、現状のカスタム戻るボタン + パンくずでフォールバックが効いているのでそのまま受け入れる方針で良いか Akira さんに確認
- [ ] **Step 6.5**: NG なら修正 commit 追加 + 再タグ。OK なら `TODO.md` の該当項目を `DONE.md` へ移送、本プランファイルを `docs/plans/archive/` へ移動

## テスト方針

- Phase 2 (`.searchable` 削除) で `SegmentQueryTests` を 5 ケース残し / 8 ケース完全削除に整理 (Step 2.4 に内訳明示)
- 他 5 テストファイル (`StoreBootstrapTests` / `CaptureContextTests` / `TranslationCoordinatorTests` / `ItemGroupDeleteRecursivelyTests` / `PendingItemRecoveryTests`) は無影響
- 新規 `BreadcrumbPathTests` (Phase 0): 0 / 1 / 3 階層 + parent ループ防御 = 4 ケース
- パンくずタップによる `NavigationPath.removeLast(k)` の検証: UI テスト化はせず、`k` 計算ロジックを純関数に切り出して単体テスト化することを Phase 3 で検討 (Step 3.4 内サブ)

## 規模感

| パート | コード変更量 (見積り) |
|--------|---------------------|
| BreadcrumbPath + BreadcrumbView 新規 | ~80 行 |
| BreadcrumbPathTests | ~50 行 |
| RootView を path 化 + bar hide | ~10 行 |
| GroupDetailView のカスタム上部行 + bar hide + メニュー移植 | ~40 行 |
| HomeView の `.searchable` 削除 + path Binding 受け取り + パンくず統合 | ~25 行 |
| HomeQueries / GroupListView / UnclassifiedListView の searchText 引数削除 + コメント整理 + ContentUnavailableView.search 分岐削除 | ~50 行 |
| SegmentQueryTests 整理 (5 ケース引数削除 + 8 ケース完全削除) | ~80 行削除 + ~30 行更新 |
| **合計 (本体)** | **~205 行** (うち削除 ~80 行 / 追加 + 更新 ~285 行) |

## リスク

- `NavigationPath.removeLast(k)` の `k` 計算ミスで「タップしたつもりの階層よりひとつ深い/浅い」へ pop される可能性。Preview で複数階層深さを確認する Step 5.1 で見つける
- `.toolbar(.hidden, for: .navigationBar)` を当てると、その中の `.toolbar { ToolbarItem(...) }` も非表示になる。Step 1.3 で既存メニューをカスタム上部行に **移植** することで回避する (toolbar 系 modifier はもう使わない)
- パンくずを `HomeView` 内 (Picker と content の間) に置くため、`selectedSegment` の `@State` は既存通り `HomeView` 所有のまま。Root / 各 Group 詳細インスタンスごとの独立性は変わらない
- `path: Binding<NavigationPath>?` の伝播経路は `RootView (@State) → GroupDetailView (Binding) → HomeView (Binding?)` の 1 本だけ。Root 用 `HomeView` には nil で渡るため、Root でパンくずを誤描画しない条件チェックを Step 3.3 で確実に入れる
- 左側省略レイアウトに `ViewThatFits` を使うため、chain 長 N のとき N 個のバリアントを描画候補として並べることになる。N が 64 (BreadcrumbPath の打ち切り上限) まで深くなるとレイアウト計算コストが増えるが、現実的な階層深さ (1〜10 程度) では十分高速
- `.toolbar(.hidden, for: .navigationBar)` と interactive pop gesture (edge swipe) の相互作用は Apple 公式に明文がない。Phase 6 TestFlight で実機検証するまで edge swipe を「使えるかもしれないが当てにしない」前提で進める。最悪ケースでもカスタム戻るボタン + パンくずでフォールバックが効く
