# グループ詳細の初期セグメントをグループタブ既定にする 実装プラン

> 2026-05-03 起票。TestFlight 動作で「グループタブから子グループをタップして遷移すると、子グループ画面で `未分類` タブが選択されている」事象に対応。

## 目的・背景

現状: `HomeView.swift` の `selectedSegment` は `@State` の初期値 `.unclassified` 固定。`GroupDetailView` が push されるたびに新しい `HomeView` インスタンスが作られ、`@State` の初期値で開始する。このため、ユーザーが **グループタブから子グループをタップして遷移したのに、遷移先で `未分類` タブから始まる**。

ユーザー体感: グループ階層を辿る操作の連続性が断ち切られる。子グループに入ったらその時点で `未分類` を見たい意図はない (そもそも 未分類タブ では `Item` しか表示されず、Group 詳細への遷移経路は **グループタブ → サブグループタップ → GroupDetailView** の 1 経路のみ)。

修正方針: `GroupDetailView` から呼ばれる `HomeView` (= `scope` が `.group(_)` のインスタンス) の初期セグメントを `.groups` にする。Root (`scope == .root`) は従来通り `.unclassified` で開く。

## 確定した設計

| 項目 | 確定値 | 補足 |
|------|--------|------|
| Root の初期セグメント | `.unclassified` | 既定値維持 (S2)。アプリ起動 / Root 復帰時の挙動は変えない |
| Group 詳細の初期セグメント | `.groups` | 親グループからは必ずグループタブ経由で push されるため |
| 親→子への セグメント状態 引き継ぎ | しない | 親で `未分類` を見ていても、子は `グループ` で開く (子の Item を見たければ手動タブ切替) |
| 戻った後の親の セグメント状態 | 維持 (NavigationStack が destination View を保持) | NavigationStack の標準挙動。実装変更なし |

### 採用しなかった案

- **Option B: 親の selectedSegment を Binding で子に渡す** — `NavigationStack` の destination registration では destination 引数 (`ItemGroup`) しか渡されず、Binding 配線が複雑になる。かつ「未分類タブから Group 詳細に遷移する経路」自体が存在しないため、親の状態を引き継ぐ動機が薄い。
- **Option C: `group.children.isEmpty` のときだけ `.unclassified` 既定** — リーフ Group (子なし) ではグループタブの空状態を回避できるが、「子の有無で初期タブが変わる」挙動はユーザーの予測を裏切る可能性。MVP は Option A、リーフの体感が悪ければ後追い検討。

### Group 詳細レイアウト (変更なし)

```
[ 未分類 | グループ ]               ← 既定で「グループ」が選択される (本変更)
[←]  親 › 子 › [現在地]    [⋯]    ← パンくず行 (Phase 0〜4 で実装済)
一覧コンテンツ (= サブグループ一覧)...
                            [+] [📷]
```

## 影響範囲

### 変更ファイル
- `Features/Home/HomeView.swift` — `selectedSegment` の初期値を scope ベースで分岐させるため `init` を明示し `_selectedSegment = State(initialValue: scope.defaultSegment)` で設定。冒頭ドキュメントコメントを更新
- `Features/Home/SegmentScope.swift` — `var defaultSegment: HomeSegment` extension を追加 (`.root → .unclassified`, `.group → .groups`)

### 変更しないファイル
- `RootView.swift` / `GroupDetailView.swift` — 呼び出し側は無変更
- テスト (`SegmentQueryTests` / `BreadcrumbPathTests` 等) — 純関数テストのため無影響

## Phase / Step

Phase 1 のみ。差分は 10〜15 行程度。

- [x] **Step 1.1**: `SegmentScope` extension に `var defaultSegment: HomeSegment` を追加
- [x] **Step 1.2**: `HomeView` に明示的な `init` を追加し `_selectedSegment = State(initialValue: scope.defaultSegment)` で初期値を scope ベースに設定 (既存の名前付き引数の構造は維持)
- [x] **Step 1.3**: `HomeView` 冒頭ドキュメントコメントを「Root → 未分類 / Group → グループ」に書き換え (旧コメント「Group 詳細でも初期値は `未分類` 統一で揃える」を更新)
- [x] **Step 1.4**: Akira さん確認の上で `git tag -a v0.1.X` を作成 + push (Bitrise release 起動 → TestFlight 配信) — v0.1.20 push 済
- [x] **Step 1.5**: Akira さん実機確認 OK (2026-05-03 / v0.1.20)。確認項目:
  - アプリ起動直後 (Root) は `未分類` タブで開くこと (リグレッション無し)
  - Root → グループタブ → 子グループタップ → 子グループ画面が `グループ` タブで開くこと (本変更の挙動)
  - 子 → 孫タップ → 孫も `グループ` タブで開くこと
  - 任意の Group 詳細でタブを `未分類` に切替 → 戻る → 親グループのタブ状態が維持されていること (NavigationStack の destination 保持を確認)
- [x] **Step 1.6**: `TODO.md` の該当項目を `DONE.md` へ移送、本プランファイルを `docs/plans/archive/` へ移動

## テスト方針

`@State` 初期値は XCTest からは直接観察しにくいため、Preview と TestFlight 実機での動作確認を主とする。

- 既存テスト (`SegmentQueryTests` / `BreadcrumbPathTests` / `StoreBootstrapTests` / `CaptureContextTests` / `TranslationCoordinatorTests` / `ItemGroupDeleteRecursivelyTests` / `PendingItemRecoveryTests`) は無影響
- `SegmentScope.defaultSegment` 自体は単純な enum マッピングなので個別テストは不要 (壊れても Step 1.5 の実機確認で即露見する)

## 規模感

| パート | コード変更量 (見積り) |
|--------|---------------------|
| `SegmentScope.defaultSegment` extension 追加 | ~10 行 |
| `HomeView` の明示的 `init` 追加 + `selectedSegment` 初期値配線 | ~15 行 |
| `HomeView` 冒頭ドキュメントコメント更新 | ~3 行 |
| **合計** | **~28 行** |

## リスク

- リーフ Group (子グループなし、Item のみ) を初めて開いたとき、グループタブの空状態 (`folder` アイコン + 「グループはまだありません」) が表示され、ユーザーは `未分類` タブへ手動切替を 1 回行う必要がある。MVP では受け入れ、リーフ体感が悪ければ Option C (子グループの有無で既定を切替) を後追い検討
- `NavigationStack` の destination 保持挙動に依存 (戻ったときの親の `@State` が維持される)。これは標準挙動なので破綻しないはずだが、Step 1.5 の実機確認で念のため検証
- `HomeView` に明示 `init` を追加することで、既存の named-argument 呼び出し側 (`RootView` / `GroupDetailView`) との API 互換性を維持する必要がある。`scope` / `path` / `onRenameGroup` / `onDeleteGroup` の引数名と順序は維持する
