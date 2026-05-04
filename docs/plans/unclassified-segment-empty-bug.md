# Group 詳細の「未分類」タブが空に見えるバグの修正 + Picker 構造分離 実装プラン

> 2026-05-04 起票。Akira さんのバグ報告:
> 「未分類にアイテムがいくつか存在するのに、グループに一度入った後に画面トップの未分類ボタンから移動するとアイテムが何もない」
>
> 2026-05-04 仕様確定 (Akira さんとの対話)。Picker のセマンティクス決定 → Picker を NavigationStack の外に出す構造改修を追加。詳細は「確定した設計」「確定した構造」節を参照。

## 現象 (再現手順)

1. Root → 未分類タブ。`group == nil` の Item がいくつか並んでいる
2. グループタブに切り替え → 任意のグループ X をタップして Group 詳細に push
3. Group X 詳細画面で `[未分類 | グループ]` Picker の **「未分類」をタップ**
4. リストが空になる (`UnclassifiedListView` の `.group` 分岐の empty `ContentUnavailableView` が出る)

ユーザー期待: Root で見えていた未分類 Item がそのまま見える (= 未分類は **アプリ全体の未分類** という単一概念)。

## 原因分析

`HomeQueries.directItems` が scope で分岐し、`未分類` セグメントの表示を:

- `.root` → `group == nil` の Item
- `.group(X)` → `X.items`

と切り替えていた。Akira さんの設計意図では「Group X の 未分類」という概念は存在せず、`未分類` は常に `group == nil` の Item を指す。

加えて構造的には Picker が `HomeView` の内部に置かれており、Group 詳細に push されると Picker ごとアニメーションでスライドインする (= Picker がリストと一体化している)。Picker は本来「アプリ全体のグローバルなモードトグル」なので、構造的にもリストから分離するのが自然。

## 確定した設計

### データモデル (前提)

```
ルート
 - アイテム1 (group == nil / 未分類)
 - アイテム2 (group == nil / 未分類)
 - グループA (parent == nil)
   - アイテムA1 (group == A)
   - グループAA (parent == A)
     - アイテムAA1 (group == AA)
     - グループAAA (parent == AA)
 - グループB (parent == nil)
   - アイテムB1 (group == B)
```

- すべての Item は **「`group == nil` (未分類)」 か「あるグループに所属」** のどちらかちょうど一方
- 「Group X の 未分類」という中間概念は **存在しない**
- アプリで言う `未分類` は常に `group == nil` のアイテム集合を指す単一概念

### Picker `[未分類 | グループ]` の役割

- アプリ全体の **モードフィルタ**。表示する内容のカテゴリを切り替える
- 通常の Segmented Picker (現在モードがハイライト、もう一方が選択可能) で OK。表示自体は標準挙動でユーザー要望「現在モードは選択不可、もう一方しか選択できない」を満たす
- **モード状態は階層をまたいで保持** (ルート → A → A1 と push したあと `未分類` に切替 → `グループ` に戻すと A1 に戻る)

### 各モードの表示内容

| モード | 階層 | 表示 |
|--------|------|------|
| 未分類 | (階層概念なし) | `group == nil` の Item を `createdAt` 降順で平坦表示 (常に同じ画面) |
| グループ | ルート | `parent == nil` の Group のみ (Item は **表示しない** — ルートの直下 Item は未分類モードに分離されているため) |
| グループ | Group X | X.children (子グループ) + X.items (X 直下の Item) を **混在表示** |

混在表示の並び順 (Group X 配下):
- 子グループと子 Item を `createdAt` 降順で 1 リストに混ぜる (シンプル優先)
- ※「Group を上、Item を下」「Item を上、Group を下」のセクション分けにしない (要望は (a) 1 リスト混在)

### モード切替時の navigation 挙動

- `グループ → 未分類` 切替: 未分類モードに切替。グループモードの `NavigationPath` は **維持** (戻したときに復元できる)
- `未分類 → グループ` 切替: グループモードで最後にいた階層に **戻る** (例: Root → A → A1 で 未分類 に切替後 グループ に戻すと A1 に戻る)
- これを実現するには、Picker と `NavigationStack` の path を **`RootView` レベルの状態** に集約し、モード切替時に `NavigationStack` 自体は破棄せず opacity / hit-testing で表示切替する (= identity を維持して path を残す)

### 採用しなかった案 (前バージョンプランの Option A 〜 D)

- Option A (Group ラベルだけ `[アイテム | グループ]` に変える) — 不採用。スコープ依存の `未分類` 概念を残す方針なので、Akira さんの「Group 内の 未分類は存在しない」と矛盾
- Option B (Group 詳細では Picker 廃止) — 不採用。Picker は全階層で表示し、グローバルなモードトグルとして機能させる
- Option C (`未分類` タップで Root に戻る) — 不採用。NavigationPath は維持し、グループモードに戻ったときに元の階層を復元する仕様に確定
- Option D (Group 詳細の `未分類` も group==nil を表示) — 採用。**ただし単独採用ではなく、グループモード側の表示も再設計する** (X.items を `グループ` タブの混在表示に統合)

## 確定した構造 (UI 階層)

Picker を **NavigationStack の外側 (= `RootView` 直下) に固定** し、グループモード内の階層 push では Picker ごとスライドしないようにする。breadcrumb / FAB は従来どおりリスト側 (= 各階層) に残し、push アニメーションと一緒に動く。

```
RootView {
  @State path = NavigationPath()
  @State selectedSegment: HomeSegment = .unclassified

  VStack(spacing: 0) {
    Picker(selection: $selectedSegment) ...   // ← NavigationStack の外。固定
      .pickerStyle(.segmented)

    ZStack {
      // 未分類モード (階層なしの単一画面)
      UnclassifiedListView()
        .opacity(selectedSegment == .unclassified ? 1 : 0)
        .allowsHitTesting(selectedSegment == .unclassified)

      // グループモード (NavigationStack で階層 push)
      NavigationStack(path: $path) {
        HomeView(scope: .root)            // ← root 用 (Picker を持たない)
          .navigationDestination(for: ItemGroup.self) { g in
            GroupDetailView(group: g, path: $path)   // ← 子 Group push 先
          }
          .navigationDestination(for: Item.self) { item in
            ItemDetailView(item: item)
          }
      }
      .opacity(selectedSegment == .groups ? 1 : 0)
      .allowsHitTesting(selectedSegment == .groups)
    }
  }
}
```

`HomeView` (グループモード専用に再定義):

```
HomeView(scope: SegmentScope) {
  VStack {
    breadcrumb (scope == .group のときのみ)
    GroupListView(scope: scope)            // root → 子 Group のみ / .group(X) → 子 Group + 子 Item 混在
  }
  .overlay HomeFAB(scope: scope)
}
```

`UnclassifiedListView` (scope 非依存):

```
UnclassifiedListView {
  @Query group == nil の Item
  List(items) { item in NavigationLink(value: item) ... }
  .overlay HomeFAB(scope: .root)            // 撮影 FAB は root 直下に保存
}
```

ポイント:
- **Picker は階層 push でアニメーションしない**: `RootView` の VStack 直下、NavigationStack の外側にあるため、子 Group に進んでも位置が変わらない
- **モード切替で path / NavigationStack identity を維持**: `if/else` で NavigationStack を出し入れせず `ZStack + opacity` を採用 (再構築が走ると path が消えるため)
- **breadcrumb / FAB はリスト側に置く**: グループモード深部で右からスライドする視覚効果に巻き込む。Picker と FAB の "両方を固定" するとレイアウトが二段になり、画面が狭くなるため FAB は従来どおりリスト側に残す
- **`UnclassifiedListView` にも FAB を配置**: 未分類モードでの撮影は `group == nil` で保存され、未分類リストに即時反映される

## 影響範囲

### 変更ファイル

| ファイル | 変更内容 |
|----------|---------|
| `RootView.swift` | 構造改修。`@State selectedSegment` 追加、`@State path` 維持。Picker を VStack 直下に配置し、`ZStack + opacity` で `UnclassifiedListView` / `NavigationStack { HomeView(scope: .root) }` を切替 |
| `Features/Home/HomeView.swift` | **Picker 描画を削除** (RootView に移管)。`HomeSegment` enum を扱う責務を切る。`@State selectedSegment` も削除。breadcrumb + content + FAB のレイアウトのみに簡略化。冒頭ドキュメントコメント全面書き直し |
| `Features/Home/SegmentScope.swift` | `defaultSegment` を削除 (Picker 状態がグローバルになり scope ベース既定値が無意味)。`SegmentScope` 自体は HomeView / FAB / GroupListView の引数として残す |
| `Features/Home/UnclassifiedListView.swift` | scope 引数を削除。常に `@Query` で `group == nil` の Item を表示。empty 文言の `.group` 分岐削除。`HomeFAB(scope: .root)` を overlay 追加 |
| `Features/Home/HomeQueries.swift` | `directItems` の `.group` 分岐削除 (`.root` 専用へ収束、または関数自体を削除して `UnclassifiedListView` の `@Query` でフィルタ)。グループ用に `directContents(group:)` (子 Group + 子 Item を `createdAt` 降順でマージ) を新規追加 |
| `Features/Home/GroupListView.swift` | Group X scope 時に X.children と X.items を混在表示するレンダリングに改修。Item / Group それぞれ別の NavigationLink を発行 (現状は ItemGroup のみ)。Item は `ItemRowView`、Group は既存 `rowView(for:)` で行レンダリング分岐 |
| `Features/Home/HomeSegment.swift` (移動先未定 — 現状 `HomeView.swift` 内) | `HomeSegment` enum を `HomeView.swift` から切り出して `Features/Home/HomeSegment.swift` に独立させる (新ファイル)。理由: Picker が `RootView` に移ったため、`HomeView` ではなくモード状態側のファイルに置く方が自然 |
| `Features/Group/GroupDetailView.swift` | `path` Binding 引数の取り回しは現状維持。`HomeView(scope: .group(g), path:, onRenameGroup:, onDeleteGroup:)` 呼び出しは無変更 (HomeView 側の Picker 削除に伴うパラメータ調整のみ) |
| `PhotoransTests/SegmentQueryTests.swift` | `testFilterItemsAtGroupReturnsOnlyDirectChildrenItems` を削除 (仕様撤廃)。Group 混在表示用 `directContents(group:)` の新テスト追加 |

### 変更しないファイル

- `Storage/Item.swift` / `Storage/ItemGroup.swift` — データモデルは不変
- `Features/Home/HomeFAB.swift` — `scope.targetGroup` での保存先解決ロジックは無変更。配置場所が `UnclassifiedListView` / `HomeView` 内に分散するだけ
- `Features/Home/BreadcrumbView.swift` — グループモード深部のパンくず描画ロジックは無変更
- `Features/Item/ItemDetailView.swift` (推定) — destination から開かれる Item 詳細画面は無変更

### XcodeGen / project.yml

- `HomeSegment.swift` を新規ファイルとして切り出す場合は `xcodegen generate` で pbxproj 再生成が必要 (memory: `feedback_xcodegen_regenerate` 参照)
- `HomeSegment` を `HomeView.swift` 内 or `SegmentScope.swift` 内に置いたままにすれば再生成不要。**最初の実装では現位置 (`HomeView.swift` 内) を維持し、ファイル切り出しは見送る** (差分を最小化)

→ XcodeGen 再生成は **不要見込み** に倒す。`HomeSegment` の移動は本プランから除外。

## Phase / Step

差分は中規模 (~150〜200 行 + テスト)。Phase 1 で実装、Phase 2 で TestFlight 確認。

- [ ] **Phase 1**: 実装
  - [ ] **Step 1.1**: `RootView` に `@State selectedSegment: HomeSegment` を追加。Picker を VStack 直下に配置し、`ZStack + opacity` で 2 モードを切替できる骨組みを組む (中身は仮で空でも OK)
  - [ ] **Step 1.2**: `HomeView` から Picker 描画 (`Picker("セグメント", selection: $selectedSegment)` + `pickerStyle(.segmented)`) と `@State selectedSegment` を削除。`init` から `selectedSegment` 初期化を撤去。`content` は `GroupListView(scope:)` に直結 (`UnclassifiedListView` 分岐削除)
  - [ ] **Step 1.3**: `RootView` の グループモード branch に `NavigationStack(path: $path) { HomeView(scope: .root) ... }` を配線。`navigationDestination` (ItemGroup / Item) は `RootView` 集約のまま維持
  - [ ] **Step 1.4**: `RootView` の 未分類モード branch に `UnclassifiedListView()` を配線
  - [ ] **Step 1.5**: `SegmentScope` から `defaultSegment` を削除
  - [ ] **Step 1.6**: `HomeQueries.directItems` の `.group` 分岐削除 (`.root` 専用化、または関数を `UnclassifiedListView` の `@Query` filter に吸収して関数自体削除)。グループ混在用 `directContents(group:)` を新規追加
  - [ ] **Step 1.7**: `UnclassifiedListView` を scope 非依存に書き換え (`@Query` で `group == nil` フィルタ、empty 文言一本化、`HomeFAB(scope: .root)` overlay 追加)
  - [ ] **Step 1.8**: `GroupListView` を Group X scope 時に「子 Group + 子 Item」混在表示に改修。Item は `ItemRowView`、Group は既存 `rowView(for:)`、それぞれ NavigationLink 発行
  - [ ] **Step 1.9**: `SegmentQueryTests` の `testFilterItemsAtGroupReturnsOnlyDirectChildrenItems` 削除。`directContents(group:)` の新テスト追加 (子 Group / 子 Item の createdAt 降順マージ、空のときの挙動など)
  - [ ] **Step 1.10**: ドキュメントコメント整合 (`HomeView` 冒頭、`RootView` 冒頭、`UnclassifiedListView` 冒頭、`GroupListView` 冒頭)。過去プラン archive (`group-default-segment.md` 等) 内の参照は読み手向けに「本プランで変わった」旨を残すかは判断
- [ ] **Phase 2**: TestFlight 確認
  - [ ] **Step 2.1**: ローカルビルド + Preview / シミュレータ確認 (Akira さん側、WSL2 では Xcode 不可)
  - [ ] **Step 2.2**: Akira さん確認の上で `git tag -a v0.1.X` 作成 + push (Bitrise → TestFlight)
  - [ ] **Step 2.3**: 実機確認結果を待つ。確認項目:
    - **アニメーション**: グループモードで子 Group に進むとき、**Picker は動かず** リスト + breadcrumb + FAB のみが右からスライドする
    - **未分類モードの内容**: Root 起動時、`group == nil` の Item が並ぶ。Group 内で `未分類` タップ → 同じく `group == nil` の Item (Group の中身ではない)
    - **グループモード root**: `parent == nil` の Group のみ (Item は出ない)
    - **グループモード Group X**: X の子 Group と X 直下 Item が混在表示される (createdAt 降順)
    - **モード状態保持**: Root → A → A1 で `未分類` 切替 → 戻ると A1 に居る (`NavigationPath` 維持)
    - **撮影 FAB**: 未分類モードで撮影 → `group == nil` で保存され未分類リストに即時表示 / グループモード Group X で撮影 → `group == X` で保存され Group X の混在リストに表示
  - [ ] **Step 2.4**: NG なら原因切り分けてプラン書き直し、OK なら Step 2.5 へ
  - [ ] **Step 2.5**: `TODO.md` 該当項目を `DONE.md` へ移送、本プランファイルを `docs/plans/archive/` へ移動

## テスト方針

- `HomeQueries` 配下 (純関数) は `SegmentQueryTests` で網羅:
  - `filterItems(scope: .root)`: 既存ケース維持 (`group == nil` のみ降順)。`.group` 分岐削除に伴うケース整理
  - `filterGroups(scope: .root)`: 既存ケース維持
  - 新規 `directContents(group:)`: Group X の 子 Group と 子 Item を `createdAt` 降順でマージするケースを 2〜3 件 (混在の順序、Group のみ / Item のみのケース、両方空のケース)
- Picker / Binding / NavigationStack identity 維持の挙動は XCTest 化が難しいので Phase 2 の実機確認に頼る (特に `ZStack + opacity` 切替で path が破棄されないことを実機で確認)
- `BreadcrumbPathTests` は無影響 (BreadcrumbView 自体は変更しない)

## リスク

- **`ZStack + opacity` で NavigationStack の identity が維持される前提**: SwiftUI が hidden 側の NavigationStack を保持し続けるかは実装依存の挙動。実機でモード切替 → 戻るで階層が保持されているかを Step 2.3 で重点確認。もし破棄される場合は `.opacity` ではなく `.hidden` でも `ZStack` 内に常駐させる、または `Group { if .. else .. }` ではなく独自の view modifier で表示制御する代替を検討
- **未分類モードで FAB を二重に持つこと**: 現状 `HomeView` の overlay にある FAB を `UnclassifiedListView` 側にも配置するため、コード上は 2 箇所に存在することになる。`HomeFAB(scope:)` は引数で動作分岐するので機能的問題はないが、変更が片方に閉じないリスク (片方だけ修正する事故)。共通の "FAB を overlay する" view modifier に切り出すかは Phase 1 終盤で判断
- **`GroupListView` の Item / Group 混在 List**: 行レンダリングの分岐 (Item は `ItemRowView`、Group は `rowView(for:)`) と NavigationLink の destination 型が混在。`navigationDestination(for: Item.self)` / `navigationDestination(for: ItemGroup.self)` の両方が `RootView` で集約済みなので原理的に問題ないはずだが、混在 List の Preview 確認は事前に
- **`SegmentScope.defaultSegment` 削除で過去プラン参照が古くなる**: archive `group-default-segment.md` の前提が崩れる。プラン archive 自体は履歴として残す方針なので「本プランで上書きされた」旨を archive 末尾に追記するかは Step 1.10 で判断

## 関連プラン / TODO

- `docs/plans/archive/screen-architecture.md` — Picker 統一の元設計 (本変更で Picker のセマンティクスと配置位置を更新)
- `docs/plans/archive/breadcrumb-navigation.md` — パンくず行 + ナビバー削除 (グループモード深部の表示は本変更で維持。breadcrumb はリスト側に残る)
- `docs/plans/archive/group-default-segment.md` — Group 詳細の初期セグメントを `.groups` にした前回変更 (本変更でモード状態がグローバル化するため、scope ベースの初期値分岐は不要に)
- `TODO.md`「グループの中に入った場合の空だった時の表示を…」 — Group 詳細の empty UX 改善。本変更でグループモードのリストに「子 Group + 子 Item」が混在するため、空状態の文言は別途見直し (本プランでは扱わない)
- `TODO.md`「グループをフォルダという名称に変更」 — 用語見直し。本変更とは独立だが Picker ラベルにも影響 (フォルダ採用なら `[未分類 | フォルダ]`)
