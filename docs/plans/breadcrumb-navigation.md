# ナビバー削除 + パンくずリンク 実装プラン

> 2026-05-03 詳細化。確定済みの設計を Phase / Step に展開。
> 2026-05-03 再検証反映: Phase 順序を「検索 UI 削除 → ナビバー削除」に入れ替え (中間状態の破綻回避) / edge swipe 早期検証オプションを Phase 2 末に追加 / 検索再導入 TODO 起票を Phase 1 先頭に追加 / アクセシビリティ要件を確定設計と各 Step に明記 / Phase 0 で `popCount` を純関数化決定 / `BreadcrumbPath.swift` を `BreadcrumbView.swift` に統合 / Dynamic Type 検証ステップ追加 / 削除対象テストはコメントブロックで仕様保管。

## 目的

TODO「ナビバーを削除しパンくずリンクで階層を表示する」を実現する。

- 上部の navigation bar 領域 (Root では "Photorans" 大タイトル、Group 詳細ではグループ名インラインタイトル) を **完全に消して 0pt** にする
- Group 詳細では `[未分類 | グループ]` Picker の **直下** に `親 › 子 › [現在地]` 形式のパンくずを置き、中間階層へ直接ジャンプできるようにする (左上には `chevron.left` のカスタム戻るボタンを別途配置)

## 確定した設計 (2026-05-03)

| 項目 | 確定値 | 補足 |
|------|--------|------|
| ナビバー削除範囲 | Root + Group 詳細のみ | Item 詳細 / Sheet 系 (GroupCreateSheet, GroupRenameSheet, MoveToGroupSheet) は **標準ナビバー維持** |
| 検索 UI | 一旦削除 | `.searchable` を削る。`HomeQueries` の純関数も searchText 引数を削除して簡素化。**再導入は別 TODO** (Phase 1 Step 1.0 で `TODO.md` に起票してから削除する) |
| パンくず Root の表現 | 出さない | パンくずは「親 > 子 > [現在地]」から始める (root を表す アイコン / 文字は置かない) |
| セパレータ | `chevron.right` SF Symbol | `Image(systemName: "chevron.right")` を ItemGroup 名の間に挟む |
| 末尾 (現在地) | 表示する / タップ無効 | 末尾だけ Text のみ (Button にしない)、ウェイトを `.semibold` にして判別 |
| 長いパス | 左側 (Root に近い側) を `...` で省略 | `...` は Text のみ、タップ不可 |
| 「未分類」セグメント時 | パンくず非表示 | Group 詳細でも未分類タブを開いている間はパンくずを描画しない |
| 画面タイトル | 持たない | 現在地名はパンくず末尾でのみ表す。`.navigationTitle` は両画面で削除 |
| Group 詳細の戻る | パンくず + 左上カスタム戻る | `chevron.left` アイコンのみ。タップ領域 44pt 確保。`dismiss()` を呼ぶ |
| アクセシビリティ | 全 Button に `.accessibilityLabel` を必須付与 | カスタム戻る = `"戻る"` / パンくず中間タップ = `"「\(name)」へ移動"` / chevron.right Image = `.accessibilityHidden(true)` (装飾) / 末尾 Text には `.accessibilityAddTraits(.isHeader)` を付ける |
| Dynamic Type / RTL / ダークモード | system 色 + system font 維持 | 色は `Color.primary` / `.secondary` / `.accentColor` のみ。chevron は SF Symbol (RTL 自動ミラー)。Dynamic Type 最大時はパンくず行が wrap / 切れる可能性があるため Phase 4 Step 4.5 で確認 |

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
- `Features/Home/HomeQueries.swift` — `searchText` パラメータを削除 (フィルタ純関数を簡素化)、`descendantGroups` も削除 (検索専用ヘルパだったため)
- `Features/Group/GroupDetailView.swift` — `.navigationTitle` / `.navigationBarTitleDisplayMode(.inline)` 削除、上部にカスタム戻る + 既存メニューを配置、`.toolbar(.hidden,...)` 追加、`path: Binding<NavigationPath>` を受け取り `HomeView` へ中継
- `ios/PhotoransTests/SegmentQueryTests.swift` — searchText 関連ケースを削除 / 更新 (削除分は仕様コメントブロックで保管)
- `TODO.md` — 検索 UI 再導入の TODO 項目を追加 (Phase 1 Step 1.0)

### 新規ファイル
- `Features/Home/BreadcrumbView.swift` — パンくず描画 + chain 構築 (`ancestorChain`) + pop 量計算 (`popCount`) を **1 ファイルにまとめる** (推定 100〜120 行)
- `ios/PhotoransTests/BreadcrumbPathTests.swift` — `ancestorChain` + `popCount` の単体テスト

> 旧プランで分離していた `BreadcrumbPath.swift` は `BreadcrumbView.swift` に統合する (関数 1〜2 個の分離は XcodeGen / pbxproj の往復コストに見合わない)。

### XcodeGen (CLAUDE.md ルール)
- `.swift` ファイルの追加削除は **同 commit に `pbxproj` 再生成** を含める

## NavigationStack の path 管理方針

- 現状: `RootView` の `NavigationStack { ... }` は path 引数なし。`NavigationLink(value: group)` / `NavigationLink(value: item)` で push、`dismiss()` で pop。
- 変更: `@State private var path = NavigationPath()` を持ち、`NavigationStack(path: $path) { ... }` に書き換える。
  - `NavigationPath` を選ぶ理由: 既存の push 対象が `ItemGroup` と `Item` の **両方** で型が混在するため。`[ItemGroup]` 型の path にすると Item を push できなくなる。
  - パンくずタップ時の pop: `path.removeLast(k)` で k 段戻す。k は Phase 0 で `BreadcrumbView.popCount(chainLength:tappedIndex:)` 純関数として実装し、単体テストで担保する。
- パンくず可視時 (Group 詳細・グループタブ) の前提: path の末尾は `ItemGroup` であり、その親チェーン長 = path の ItemGroup 要素数 (Item は Item 詳細でしか push されず、その間はパンくずを描画しない画面に居る)。
- **前提の限界 (将来の deep link / path restore)**: chain を `parent` 辿りで作るのに対し path の中身は実際に push された値の積み重ね。現状は `NavigationLink(value:)` 経由の push しか無いので両者は一致するが、deep link や `NavigationPath` の永続化を導入した瞬間に崩れうる。`BreadcrumbView` 冒頭にコメントで明記し、その時点で `popCount` の引数を path 側 index ベースに見直すこと。

## API 検証メモ (CLAUDE.md「Swift API は推測で書かない」)

実装着手前に Apple 公式ドキュメントで以下を確認する:

1. `.toolbar(.hidden, for: .navigationBar)` (iOS 16+) — `ToolbarPlacement.navigationBar` が `Visibility.hidden` を受け、当該 View でナビバー領域が 0pt になることを再確認
2. `NavigationPath.removeLast(_ k: Int = 1)` — public mutating method として存在することを Apple Developer Documentation の `NavigationPath` ページで再確認 (デフォルト引数 `k=1`)
3. `NavigationStack(path:)` の Binding 型 (`Binding<NavigationPath>`) と `NavigationLink(value:)` の併用パターン
4. `ViewThatFits(in: .horizontal) { ... }` (iOS 16+) — 子 View を順に評価し、最初に収まったものを採用する挙動。Phase 4 の左側省略レイアウトで使う
5. **`.toolbar(.hidden, for: .navigationBar)` と interactive pop gesture (edge swipe) の相互作用** — 検証で未確定の項目。一般論では `NavigationStack` (iOS 16+) はバー非表示でも edge swipe を保持する設計だが、Apple 公式に明文の保証がない。Phase 2 Step 2.5 の早期 TestFlight (任意) または Phase 6 の本番 TestFlight で確定するまでは **「edge swipe は使えるかもしれないが当てにしない」** 前提で進める

## Phase / Step

> **Phase 順序の根拠**: 旧プランは Phase 1 (ナビバー削除) → Phase 2 (検索削除) の順だったが、`.searchable` は SwiftUI が navigation bar 領域に検索バーを投影する仕様のため、ナビバー隠し → 検索削除の順序では中間 commit で「検索バーが不可視化されたまま機能だけ残る」状態になる。Phase 1 (検索削除) → Phase 2 (ナビバー削除) に並び替え、各 Phase 単体で commit / merge 可能なクリーン状態を保つ。

### Phase 0: 共有部品 (BreadcrumbView 内に chain 構築 + popCount + 描画) を作る

> 旧プランで分離していた `BreadcrumbPath` は `BreadcrumbView.swift` 内の static 関数群に統合する。

- [ ] **Step 0.1**: `Features/Home/BreadcrumbView.swift` を新規作成。同ファイル内に以下 3 要素を置く:
  1. `static func ancestorChain(of group: ItemGroup) -> [ItemGroup]` — `group.parent` を辿って末尾が `group` 本体になる順序で配列を返す。循環は理論上発生し得ないが防御として 64 段で打ち切り
  2. `static func popCount(chainLength: Int, tappedIndex: Int) -> Int` — `chainLength - tappedIndex - 1` を返す純関数 (off-by-one 防御を単体テストで担保)
  3. `BreadcrumbView` 構造体 — 引数: `chain: [ItemGroup]`, `onTap: (ItemGroup) -> Void`。横幅判定なし版で `HStack { Button { Text(name) } / chevron.right / ... 末尾は Text }` を並べる。末尾要素は Button にしない
  - ファイル冒頭に「path と chain の整合前提」コメントを書く (本プランの「前提の限界」節を要約)
- [ ] **Step 0.2**: アクセシビリティ属性を付与
  - 中間タップ Button: `.accessibilityLabel("「\(group.name)」へ移動")`
  - chevron.right Image: `.accessibilityHidden(true)` (装飾要素)
  - 末尾 Text: `.accessibilityAddTraits(.isHeader)` を付与し現在地であることを伝える
- [ ] **Step 0.3**: `BreadcrumbPathTests.swift` を新規作成。以下ケース:
  - **`ancestorChain` (4 ケース)**: 0 階層 (`ancestorChain(.X)` が parent==nil の単独 X で `[X]`) / 1 階層 / 3 階層 / parent 自己参照ループ (64 段で打ち切られ無限ループにならない) を検証
  - **`popCount` (3 ケース)**: `chainLength=3, tappedIndex=0` (= 2 段戻り) / `chainLength=3, tappedIndex=1` (= 1 段戻り) / `chainLength=2, tappedIndex=0` (= 1 段戻り) を検証
- [ ] **Step 0.4**: XcodeGen で 2 ファイル (`BreadcrumbView.swift` + `BreadcrumbPathTests.swift`) を `pbxproj` に登録、`xcodebuild -scheme Photorans test` でテスト通過確認

### Phase 1: 検索 UI を削除 (`.searchable` + searchText 経路)

> 旧 Phase 2 を Phase 1 に繰り上げ。**ナビバー削除より先に検索 UI を消す** ことで、`.toolbar(.hidden)` 適用時に検索バー残骸が浮かぶ中間状態を回避する。

- [ ] **Step 1.0**: `TODO.md` に「**検索 UI を再導入する** (パンくず実装で一旦削除した分。仕様は S14 を踏襲: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains)」項目を追加。**先に起票してから削除に入る** (再導入忘れ防止)
- [ ] **Step 1.1**: `HomeView.swift` から `.searchable(text: $searchText, prompt: ...)` を削除、`@State private var searchText` も削除。冒頭ドキュメントコメントの `.searchable` 解説も削除
- [ ] **Step 1.2**: `GroupListView` / `UnclassifiedListView` の `searchText: String` 引数を削除し、`HomeView` 側の呼び出しからも除去。各ファイルの `emptyView` 内 `if !searchText.trimmingCharacters(...).isEmpty { ContentUnavailableView.search(text:) }` 分岐も削除 (検索 UI が無くなるので空文字列以外が来ない)。冒頭ドキュメントコメントの searchText 解説も整理
- [ ] **Step 1.3**: `HomeQueries.swift` の `filterItems` / `filterGroups` から `searchText` パラメータを削除し、各々が空文字列時のロジック (`directItems` / `sortDirectGroups(directGroups(...))`) のみを残す。`descendantGroups` + `collectDescendants(of:into:)` は検索 branch でしか使われていないので削除 (再導入時に書き直し)
- [ ] **Step 1.4**: `SegmentQueryTests.swift` のケース整理 (内訳明示):
  - **残す (5 ケース、`searchText:` 引数を削るだけ + リネーム)**:
    - `testFilterItemsEmptySearchAtRootReturnsOnlyUngroupedSortedDesc` → `testFilterItemsAtRootReturnsOnlyUngroupedSortedDesc`
    - `testFilterItemsEmptySearchAtGroupReturnsOnlyDirectChildrenItems` → `testFilterItemsAtGroupReturnsOnlyDirectChildrenItems`
    - `testFilterGroupsEmptySearchAtRootShowsRootDirectGroupsSortedByLatestItem` → `testFilterGroupsAtRootShowsRootDirectGroupsSortedByLatestItem`
    - `testFilterGroupsEmptySearchAtGroupShowsOnlyDirectChildren` → `testFilterGroupsAtGroupShowsOnlyDirectChildren`
    - `testFilterGroupsEmptyEmptyItemGroupsSortedToTail` → `testFilterGroupsEmptyItemGroupsSortedToTail`
  - **コード削除 + 仕様コメント保管 (8 ケース)**: 以下 8 ケースは XCTest メソッドとしてはファイルから削除するが、**ファイル末尾に `// MARK: - Removed (search UI). Re-add per TODO「検索 UI 再導入」` コメントブロックを置き、各ケースが検証していた仕様 (S14 系) を箇条書きで残す** (再導入時の検証仕様リファレンスとして)
    - `testFilterItemsWhitespaceOnlySearchTreatedAsEmpty` (空白文字列は空扱い)
    - `testFilterItemsSearchCrossesAllScopesAndOnlyCompleted` (Item 検索は scope 無視 + `.completed` 限定)
    - `testFilterItemsSearchMatchesTranslatedText` (originalText/translatedText 両対象)
    - `testFilterItemsSearchIsCaseInsensitive`
    - `testFilterItemsSearchExcludesProcessingAndFailed`
    - `testFilterGroupsSearchAtRootIncludesAllDescendants` (Root 検索は子孫全件横断)
    - `testFilterGroupsSearchAtGroupExcludesSelfAndOutsideScope` (scope 自身と scope 外を除外)
    - `testFilterGroupsSearchIsCaseInsensitive`
- [ ] **Step 1.5**: `xcodebuild -scheme Photorans test` で全テスト通過 (SegmentQueryTests 5 ケース + 他 5 ファイル + 新規 BreadcrumbPathTests 7 ケース)

### Phase 2: NavigationStack を path 化 + ナビバー削除 + カスタム戻る

> 旧 Phase 1 を後ろにずらした。Phase 1 で検索 UI が消えているので、`.toolbar(.hidden)` 適用時に検索バー残骸が浮かぶ問題は発生しない。

- [ ] **Step 2.1**: `RootView` に `@State private var path = NavigationPath()` を追加し `NavigationStack(path: $path) { ... }` に書き換える。既存の `NavigationLink(value:)` 経由の push が機能することを Preview で確認
- [ ] **Step 2.2**: `RootView` の `.navigationTitle("Photorans")` を削除、`HomeView(scope: .root)` に `.toolbar(.hidden, for: .navigationBar)` を当てる。Status bar (時刻 / 電波 / バッテリー) の safe area は残ることを確認
- [ ] **Step 2.3**: `GroupDetailView` から `.navigationTitle(group.name)` / `.navigationBarTitleDisplayMode(.inline)` / 既存 `.toolbar { ToolbarItem(.topBarTrailing) { Menu... } }` を削除し、その代替として **カスタム上部行** を `HomeView(scope: .group(group))` の上に挿入する
  - `HStack { Button(action: dismiss) { Image(systemName: "chevron.left") } / Spacer() / Menu { ... } label: { Image(systemName: "ellipsis.circle") } }`
  - **カスタム戻る Button に `.accessibilityLabel("戻る")` を付与** (system 戻るボタンの代替)
  - 既存メニュー (名前を編集 / グループを削除) はこの Menu に移植 (`.accessibilityLabel("グループ メニュー")` も移植)
  - **パンくずはここには乗せない** (Phase 3 で `HomeView` 内の Picker 直下に置く)
- [ ] **Step 2.4**: `GroupDetailView` の本体に `.toolbar(.hidden, for: .navigationBar)` を当て、戻るボタンが `dismiss()` で 1 段 pop することを Preview で確認
- [ ] **Step 2.5**: **(任意) edge swipe 早期検証用 TestFlight 中間タグ** — Phase 2 完了時点 (パンくず未実装、ナビバー削除 + カスタム戻るのみ) の状態を一度 TestFlight に出して edge swipe 挙動を実機確認するかを Akira さんに確認
  - 実施する場合: `git tag -a v0.1.X -m "navbar hidden + custom back (Phase 2 isolation for edge swipe verification)"` を Akira さん合意の上で push (Bitrise クレジット消費 + TestFlight に外部影響あり、CLAUDE.md ルール準拠)
  - 実施しない場合: Phase 6 の TestFlight にまとめて検証 (Phase 6 Step 6.3 で edge swipe 確認項目維持)
  - 結果が NG (edge swipe 不可) でも、カスタム戻る + Phase 3 のパンくず中間タップでフォールバック済みなので Phase 3 以降は止めずに進める方針

### Phase 3: HomeView の Picker 直下にパンくずを統合 + 未分類時の非表示制御

- [ ] **Step 3.1**: `RootView` の `@State path: NavigationPath` を `Binding` で `GroupDetailView` まで配線
  - `RootView` の `.navigationDestination(for: ItemGroup.self) { group in GroupDetailView(group: group, path: $path) }` に変更
  - `GroupDetailView` に `let path: Binding<NavigationPath>` を追加
- [ ] **Step 3.2**: `HomeView` のシグネチャに `path: Binding<NavigationPath>?` を追加 (Root 用は省略可)。`GroupDetailView` から `HomeView(scope: .group(group), path: path)` で渡す
- [ ] **Step 3.3**: `HomeView` の `VStack(spacing: 0) { Picker; content }` を `VStack(spacing: 0) { Picker; breadcrumb (条件付き); content }` に書き換え。breadcrumb 表示条件は **すべて満たす** とき:
  - `scope` が `.group(let X)` (Root では絶対に出さない)
  - `selectedSegment == .groups` (未分類タブでは出さない)
  - `path != nil`
  - chain は `BreadcrumbView.ancestorChain(of: X)` をそのまま使う。「Root を出さない」要件は「アプリの Root を表すアイコン/文字を頭に付けない」という意味で、ItemGroup そのもの (parent==nil の最上位 Group も含む) は全て chain に並べる
  - 例: 現在地が parent==nil の Group X → chain = `[X]` → 表示 `[X]` (現在地のみ、chevron なし)
  - 例: 現在地が 2 階層目 → chain = `[P, X]` → 表示 `P › [X]`
  - 例: 現在地が 3 階層目 → chain = `[GP, P, X]` → 表示 `GP › P › [X]`
- [ ] **Step 3.4**: パンくず中間タップ時の pop は **Phase 0 Step 0.1 で純関数化済みの `BreadcrumbView.popCount(chainLength:tappedIndex:)` を呼ぶだけ** に閉じる
  - `onTap` で `path?.wrappedValue.removeLast(BreadcrumbView.popCount(chainLength: chain.count, tappedIndex: i))` を実行
  - off-by-one は Phase 0 Step 0.3 のテストでカバー済みなので Phase 3 では UI 結線のみに集中
  - 「Root に近い祖先タップ → そこまで一気に戻る」が Preview で達成できることを確認
- [ ] **Step 3.5**: 末尾 (現在地) は Text のみで描画、Button にしない (タップ無効、ウェイト `.semibold`、`.accessibilityAddTraits(.isHeader)` は Phase 0 Step 0.2 で付与済み)
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
- [ ] **Step 4.5**: **Dynamic Type 検証** — XL / XXL / アクセシビリティサイズ系で Preview を確認し、最小バリアント (現在地のみ) ですら横幅に収まらないケースが発生した場合の対処方針を決める (`.minimumScaleFactor(0.8)` / `.lineLimit(1)` / 折り返し許容のいずれか)。RTL 環境 (擬似ロケール `ar` 等) でも chevron / Text 並びが破綻しないことも合わせて確認

### Phase 5: 動作確認 + テスト

- [ ] **Step 5.1**: TodoApp Preview で 4 シーンを通し確認
  - Root (グループタブ / 未分類タブ)
  - Group 詳細 1 階層 (グループタブ / 未分類タブ)
  - Group 詳細 3 階層 (グループタブ / 未分類タブ + パンくず祖先タップ)
  - Group 詳細 5 階層 (左側 `...` 省略)
- [ ] **Step 5.2**: `xcodebuild -scheme Photorans test` で全テスト通過 (Phase 1 整理後の SegmentQueryTests 5 ケース + 他 5 テストファイル + 新規 BreadcrumbPathTests 7 ケース)
- [ ] **Step 5.3**: 既存メニュー機能 (名前編集 / グループ削除) が Phase 2 Step 2.3 移植後も同じ挙動で動くことを確認
- [ ] **Step 5.4**: カスタム戻るボタン / パンくずタップ の 2 経路で戻りが破綻しないことを Preview で確認 (edge swipe は Phase 2 Step 2.5 で実施済みなら結果反映、未実施なら Phase 6 検証に回す)
- [ ] **Step 5.5**: VoiceOver で各 Button のラベル読み上げが意図通りであることを Simulator (利用可能なら) または TestFlight 実機で確認

### Phase 6: TestFlight (実機リグレッション)

- [ ] **Step 6.1**: Akira さん確認の上で `git tag -a v0.1.X` を作成 + push (Bitrise が release Workflow 起動)
- [ ] **Step 6.2**: TestFlight 配信完了を待つ (Apple 処理 ~30 分)
- [ ] **Step 6.3**: Akira さん実機確認結果共有待ち (OK / NG)。確認項目:
  - 通常導線 (Root → Group → SubGroup → Item) の表示崩れ無し
  - カスタム戻るボタン / パンくず中間タップで意図通り pop
  - **edge swipe で戻れるか / 戻れないか** (Phase 2 Step 2.5 で先行検証済みなら本番ビルドでの再確認、未実施ならここで初検証)
  - VoiceOver 読み上げが「戻る」「「\(name)」へ移動」「現在地: \(name)」相当で機能すること
  - Dynamic Type アクセシビリティサイズでパンくず行が破綻しないこと
- [ ] **Step 6.4**: edge swipe が無効だった場合は、現状のカスタム戻るボタン + パンくずでフォールバックが効いているのでそのまま受け入れる方針で良いか Akira さんに確認
- [ ] **Step 6.5**: NG なら修正 commit 追加 + 再タグ。OK なら `TODO.md` の該当項目を `DONE.md` へ移送、本プランファイルを `docs/plans/archive/` へ移動 (Step 1.0 で起票した「検索 UI 再導入」項目は別 TODO として残す)

## テスト方針

- Phase 1 (`.searchable` 削除) で `SegmentQueryTests` を 5 ケース残し / 8 ケースはコード削除 + 仕様コメント保管に整理 (Step 1.4 に内訳明示)
- 他 5 テストファイル (`StoreBootstrapTests` / `CaptureContextTests` / `TranslationCoordinatorTests` / `ItemGroupDeleteRecursivelyTests` / `PendingItemRecoveryTests`) は無影響
- 新規 `BreadcrumbPathTests` (Phase 0 Step 0.3): `ancestorChain` 4 ケース + `popCount` 3 ケース = **7 ケース**
- パンくずタップ時の pop 量は `popCount` を純関数として切り出して単体テストで担保 (Phase 0 で確定)。UI 結線部 (Phase 3 Step 3.4) は Preview 確認のみとし、UI テストは導入しない

## 規模感

| パート | コード変更量 (見積り) |
|--------|---------------------|
| BreadcrumbView 新規 (chain + popCount + body 統合) | ~110 行 |
| BreadcrumbPathTests (chain 4 + popCount 3 = 7 ケース) | ~70 行 |
| RootView を path 化 + bar hide | ~10 行 |
| GroupDetailView のカスタム上部行 + bar hide + メニュー移植 + a11y | ~45 行 |
| HomeView の `.searchable` 削除 + path Binding 受け取り + パンくず統合 | ~25 行 |
| HomeQueries / GroupListView / UnclassifiedListView の searchText 引数削除 + コメント整理 + ContentUnavailableView.search 分岐削除 + descendantGroups 削除 | ~55 行 |
| SegmentQueryTests 整理 (5 ケース引数削除 + 8 ケースコード削除 + 仕様コメントブロック追加) | ~80 行削除 + ~30 行更新 + ~30 行コメント追加 |
| TODO.md に検索再導入項目追加 | ~1 行 |
| **合計 (本体)** | **~225 行** (うち削除 ~80 行 / 追加 + 更新 ~305 行) |

## リスク

- `NavigationPath.removeLast(k)` の `k` 計算ミスで「タップしたつもりの階層よりひとつ深い/浅い」へ pop される可能性 → Phase 0 で `popCount` を純関数化 + 単体テストでカバー済み
- `.toolbar(.hidden, for: .navigationBar)` を当てると、その中の `.toolbar { ToolbarItem(...) }` も非表示になる。Phase 2 Step 2.3 で既存メニューをカスタム上部行に **移植** することで回避する (toolbar 系 modifier はもう使わない)
- パンくずを `HomeView` 内 (Picker と content の間) に置くため、`selectedSegment` の `@State` は既存通り `HomeView` 所有のまま。Root / 各 Group 詳細インスタンスごとの独立性は変わらない
- `path: Binding<NavigationPath>?` の伝播経路は `RootView (@State) → GroupDetailView (Binding) → HomeView (Binding?)` の 1 本だけ。Root 用 `HomeView` には nil で渡るため、Root でパンくずを誤描画しない条件チェックを Phase 3 Step 3.3 で確実に入れる
- 左側省略レイアウトに `ViewThatFits` を使うため、chain 長 N のとき N 個のバリアントを描画候補として並べることになる。N が 64 (`ancestorChain` の打ち切り上限) まで深くなるとレイアウト計算コストが増えるが、現実的な階層深さ (1〜10 程度) では十分高速
- `.toolbar(.hidden, for: .navigationBar)` と interactive pop gesture (edge swipe) の相互作用は Apple 公式に明文がない。**Phase 2 Step 2.5 (任意) または Phase 6 で実機検証** するまで edge swipe を「使えるかもしれないが当てにしない」前提で進める。最悪ケースでもカスタム戻るボタン + パンくずでフォールバックが効く
- 検索 UI を一旦削除する分、**Step 1.0 で TODO 起票し忘れると再導入が消滅** するリスクがある。先に起票してからコード削除する順序を必ず守る (Phase 1 Step 1.0 → 1.1 の依存関係)
- パンくず chain と path の整合は現状 (`NavigationLink(value:)` 経由 push のみ) では保たれるが、deep link / `NavigationPath` 永続化を導入した瞬間に崩れる。`BreadcrumbView` 冒頭コメントで明記し、その時点で `popCount` の引数設計を見直すことを残しておく
- アクセシビリティラベル付け忘れがあると VoiceOver で無名ボタンとして読まれる。Phase 0 Step 0.2 / Phase 2 Step 2.3 / Phase 5 Step 5.5 の三段階で確認する
