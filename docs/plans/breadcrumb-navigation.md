# ナビバー削除 + パンくずリンク プラン (調査メモ)

> このファイルは **調査結果の概要** のみ。実装プラン (Phase / Step) は別タイミングで詳細化する。

## 目的

TODO「ナビバーを削除しパンくずリンクで階層を表示する」を実現する。

- 上部の navigation bar 領域 (Root では "Photorans"、Group 詳細ではグループ名) を **完全に消して 0pt** にする
- Group 詳細では代わりに `[グループ | 未分類]` セグメントの下にパンくずリンクを表示し、中間階層へ直接遷移できるようにする

## 背景

H4 実装後の現状:

- `RootView.swift:13` で `HomeView(scope: .root)` に `.navigationTitle("Photorans")` (large title mode、約 96pt) を付与
- `GroupDetailView.swift:23-24` で `.navigationTitle(group.name) + .navigationBarTitleDisplayMode(.inline)` (約 44pt)
- Phase 5 Step 5.1 で `HomeView` 1 箇所に `.searchable(...)` を集約 (NavigationStack の navigation bar に依存)
- `ItemGroup.parent: ItemGroup?` / `.children` のリレーションで任意深さネスト可能 (Phase 1 / 仕様 S12 Q1)

## 調査結果サマリ

### ナビバー削除 (Root + Group 詳細とも 0pt)

- `.toolbar(.hidden, for: .navigationBar)` (iOS 16+) を per-view で当てれば bar 領域を 0pt にできる
- `RootView` 経由で `HomeView(scope: .root)` に当てる + `GroupDetailView` 側にも当てる必要あり (per-view モディファイアなので push/pop で独立)
- ステータスバー (時刻 / 電波 / バッテリー) はシステム safe area として残る

### `.searchable` の扱い

- bar を消すと `.searchable` の検索フィールドも消える (NavigationStack の navigation bar 内に配置される SwiftUI 標準機能のため)
- 代替案: `HomeView` の body 内に独自 `TextField` を Picker / パンくずの周辺に配置
  - `searchText` の `@State` バインディングは既存のまま流用可
  - `HomeQueries` のフィルタ純関数 (Phase 5 Step 5.5) は変更不要 → 既存テスト 6 ケースも無影響
  - 失うのは「下にプルして検索バーを出す」標準インタラクションのみ
- 検索を常時表示するか、検索ボタンタップで sheet 展開にするかは未確定 (Phase 詳細化時に決定)

### パンくずリンク

- データ層: `ItemGroup.parent` を while ループで遡れば `[ItemGroup]` のパス配列が作れる (新規スキーマ追加不要)
- UI 層: `HStack` または `ScrollView(.horizontal)` で `Root > 親 > 子 > 孫` を描画、各セグメントを Button にしてタップで該当階層へジャンプ
- NavigationStack の path 管理化が必要:
  - 現状 `RootView` は `NavigationStack { ... }` を path 引数なしで使用
  - パンくず中間タップから「特定階層まで一気に pop」を実現するには `NavigationStack(path: $path)` 形式に変更し、`path: [ItemGroup]` を `RootView` の `@State` として保持する必要あり
  - これは Phase 0 PoC Step 0.3「destination は RootView 集約」設計と整合 (パスも RootView で持つのが自然)
- Group 詳細のときのみパンくずを出し、Root では出さない (Root にいるならパンくずは無意味)

### Group 詳細での「戻る」導線

- ナビバーを消すと標準の戻るチェブロンが消える
- パンくずタップで上位階層へ戻れるので **パンくずが事実上の「戻る」を兼ねる** ことになる
- Item 詳細から Group 詳細への戻りなど、push 1 段の戻りはどう扱うか未確定 (Item 詳細にだけバーを残す案 / 全画面でカスタム閉じるボタン案 など)

## 未確定事項 (Phase 詳細化時に決める)

- パンくずのデザイン:
  - Root の表現 ("ホーム" / アイコン / "/" など)
  - セパレータ (`>` / `›` / `/`)
  - 末尾 (現在地) を表示するか / タップ無効化するか
  - 長いパスの扱い (横スクロール / 中央省略 / 折り返し)
- 検索 UI の配置:
  - 常時表示 TextField (Picker の上 or パンくずの上)
  - 検索 FAB + sheet
  - タブ別表示の出し分け (未分類セグメントのみとか)
- ナビバーを消す範囲:
  - Root + Group 詳細のみ?
  - Item 詳細 / Sheet 系 (`GroupCreateSheet` / `GroupRenameSheet` / `MoveToGroupSheet`) はバーを残す方が自然か
- 「未分類」セグメント表示中のパンくずの挙動:
  - Group 詳細で未分類セグメントを選んでも `scope == .group(X)` のままなので、パンくずは現在の Group 階層をそのまま表示で良いはず

## 影響範囲

### 既存ファイル
- `RootView.swift` — `NavigationStack(path:)` 化、`.toolbar(.hidden, ...)` 追加、`.navigationTitle("Photorans")` 削除
- `Features/Home/HomeView.swift` — `.searchable` を独自 TextField に置換、scope=.group 時にパンくず組み込み
- `Features/Group/GroupDetailView.swift` — `.toolbar(.hidden, ...)` 追加、`.navigationTitle(group.name)` の扱い再検討

### 新規ファイル (想定)
- `Features/Home/BreadcrumbView.swift` — パンくず描画 (推定 30〜50 行)
- 検索 TextField を独立 View に切り出すか HomeView 内に直書きかは Phase 詳細化時に判断

### 規模感

| パート | コード変更量 (見積り) |
|--------|---------------------|
| BreadcrumbView 新規 | ~50 行 |
| RootView を NavigationStack(path:) 化 + bar hide | ~10 行 |
| HomeView の `.searchable` → 独自 TextField + パンくず組み込み | ~30 行 |
| GroupDetailView の bar hide | ~3 行 |
| **合計** | **70 行未満** |

## テスト方針 (暫定)

- 既存 6 ケース (`StoreBootstrapTests` / `SegmentQueryTests` / `CaptureContextTests` / `TranslationCoordinatorTests` / `ItemGroupDeleteRecursivelyTests` / `PendingItemRecoveryTests`) は影響なし
- 追加候補:
  - `BreadcrumbPathTests` — `ItemGroup.parent` を遡るパス構築ロジックの純関数テスト
  - パンくず中間タップによる NavigationPath 操作テスト (UI テストか、純関数化して単体テストか は Phase 詳細化時に判断)

## 次のステップ

別タイミングで Phase / Step に詳細化する。詳細化時に確認すべき項目:

1. 未確定事項の各論を一つずつユーザー確認
2. 確定後、CLAUDE.md ルール通り Phase 0 (PoC) → Phase 1 (実装) → Phase 2 (TestFlight) のような構造に展開
3. TODO.md に Phase 子タスクを追加
