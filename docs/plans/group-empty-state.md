# グループ詳細の空状態文言を「翻訳 / グループ作成」促し文言に変える

iOS ネイティブクライアント (`ios/Photorans/Features/Home/GroupListView.swift`) のグループモードで、**Group 詳細 (`.group(X)` scope)** に入って中身が空のときの `ContentUnavailableView` 文言を、Root (`.root` scope) と分けて「翻訳を作成するか、新しいグループを作成できる」ことが分かるメッセージに変更する。Root の空状態文言は据え置き。

ステータス: **未着手** / 起票日: 2026-05-04

## 目的・背景

現状、`GroupListView.swift:70-76` の `emptyView` は `.root` と `.group(X)` 双方で共通利用されており、文言は:

```
タイトル: グループはまだありません
説明  : 翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。
```

Root では妥当だが、Group 詳細 (例: `English > Store` のように親グループの中に入った状態) で同じ文言が出ると次の問題がある:

- グループ詳細では `HomeFAB` が **カメラ FAB + Group 作成 FAB の両方** を出している (S13-5: 撮影された Item は `targetGroup = X` で保存、Group 作成は `parent = X` で作成)。つまり「ここに入って撮影すると翻訳が X 配下に並ぶ」「ここで Group 作成すると X の子グループになる」両方ができる
- それなのに空文言が「グループはまだありません」+「『+』ボタンから新しいグループを」だけだと、**翻訳を撮る選択肢が想起されず**、ユーザーが「ここは Group 作成専用の場所」と誤認しうる
- TODO 起票文 (Akira さん): 「グループ内のグループ（English > Store）: 「翻訳作成するかグループを作成するか」」 = 翻訳作成と Group 作成の両方を選べることを伝える文言に変えてほしい

Root はもともと `[未分類 | グループ]` の Picker でグループタブを開いた直後の画面で、撮影は未分類タブ側 (`UnclassifiedListView`) に分離されている (`HomeFAB(scope: .root)` でも撮影自体はできるが、空状態 UX としては「まずグループを作る」促しが自然) のため、Root の文言は現状維持で良いと Akira さんから明示されている。

スコープは GroupListView の Group 詳細 empty view 文言と表示要素のみ。`.root` empty view、`UnclassifiedListView` empty view (`まだ翻訳がありません`)、HomeFAB の挙動はいずれも触らない。

## 対応方針

### 判断 A: empty view を scope 別に分岐

現行の単一 `private var emptyView` を 2 本に分ける:

- `rootEmptyView` — `.root` 用、文言は現状維持
- `groupEmptyView` — `.group(X)` 用、新文言 (判断 C)

`rootBody` / `groupBody(group:)` 各分岐から呼び分ける。

### 判断 B: ContentUnavailableView の構造維持

iOS 17+ の `ContentUnavailableView { Label } description: { Text } actions: { ... }` を引き続き使う。`actions:` クロージャは追加しない (= 空状態に明示ボタンを出さない)。理由:

- 画面右下に既存の `HomeFAB` (カメラ FAB + Group 作成 FAB) が常時 overlay されており、empty view 内に同等のボタンを置くと操作経路が二重化する
- 純正の Photos / Files アプリも空フォルダ状態で説明テキストのみ出しており、HIG 的にも文言誘導が標準的

### 判断 C: 文言案

採用案 (Akira さん起票文の意図を素直に展開):

```
タイトル: 翻訳もグループもまだありません
説明  : 右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいグループを作成できます。
```

代替案 (文字数を削るパターン、起票時には採用しない / 実機確認で長すぎたら検討):

```
タイトル: このグループは空です
説明  : 撮影で翻訳を追加するか、新しいグループを作成できます。
```

採用案でいく根拠: 起票文「翻訳作成するかグループを作成するか」を直接反映、`UnclassifiedListView` の「画面右下のカメラボタンから〜」と語彙を揃え、ユーザーが「右下のボタン群を見ればよい」とすぐ分かる。

### 判断 D: アイコン (Label `systemImage`)

候補:

- `folder` (現状) — グループの空状態を示すが、撮影は連想されない
- `camera` — 撮影は連想されるが、グループ作成は連想されない
- `tray` / `square.dashed` — 中立的な「空」アイコン

採用: **`tray`** (中立的な「空のトレイ」アイコン、純正 Mail / Photos の空状態でも使われる SF Symbol)。Root の `folder` とも視覚的に区別でき、「撮影 / グループ作成のどちらでも埋められる空きスペース」のメタファとして妥当。

### 判断 E: テキスト本体の改行 / 整形

`Text(...)` は改行を入れず ContentUnavailableView の自動レイアウトに任せる (画面幅で折り返される)。`UnclassifiedListView.emptyView` も `Text` 1 本で書かれており慣習に揃える。

### 判断 F: 既存 Root 文言の保護

`rootEmptyView` の文字列は **完全に現状を維持** する (タイトル + 説明 + アイコン `folder`)。リファクタで誤って変えないよう、Step1-1 の差分は「`emptyView` を `rootEmptyView` にリネームした上で `groupEmptyView` を新設する」順序で書く。

## 影響範囲

- `ios/Photorans/Features/Home/GroupListView.swift` —
  - `emptyView` を `rootEmptyView` にリネーム (中身据え置き)
  - 新規 `groupEmptyView` を追加 (判断 C / D)
  - `rootBody` の `emptyView` 参照を `rootEmptyView` に
  - `groupBody(group:)` の `emptyView` 参照を `groupEmptyView` に
- 他ファイル — 変更なし (`UnclassifiedListView.swift` / `HomeFAB.swift` / `HomeView.swift` / `HomeQueries.swift` / `SegmentScope.swift` は無関係)
- テスト — 追加なし。`SegmentQueryTests` 等は `HomeQueries` の純関数を見ており View 文言は対象外。SwiftUI ビジュアル変更のためユニットテストの追加は不要 (memory `feedback_swift_api_verification.md` の方針: WSL2 では SwiftUI ビュー差分は実機でしか検証できない)
- XcodeGen — `.swift` の追加削除なしのため再生成不要 (memory `feedback_xcodegen_regenerate.md` の対象外)

リスク:

- 文言が長くて iPhone SE などの狭幅で 4 行以上に折り返される可能性 → 実機確認で長すぎたら判断 C 代替案に倒す
- `.group(X)` で **子 Group か子 Item のどちらか一方だけある** 状態は `entries.isEmpty == false` なので empty view には到達しない (両方ゼロのときだけ。本変更はこの条件下でのみ発火)
- Root と Group 詳細で別文言になることを Akira さん以外のテスターが「一貫性がない」と感じる可能性 — 起票時の明示要件のため受容

## テスト方針

実機 (Akira さんの iPhone) で:

1. **Root 空状態 (DB 完全初期状態 / 全 Group を削除した直後)**: `グループ` タブで `グループはまだありません` + `翻訳をテーマや用途ごとにグループ化して整理できます。右下の「+」ボタンから新しいグループを作ってください。` + `folder` アイコン (= 現状と完全一致)
2. **Group X 空状態 (新規作成直後の Group に入る)**: 新規グループ `テスト` を作成 → タップして詳細へ → 新文言 `翻訳もグループもまだありません` + `右下のカメラボタンで撮影して翻訳を追加するか、「+」ボタンで新しいグループを作成できます。` + `tray` アイコン
3. **Group X に子 Item を追加すると empty 解除**: 上記 `テスト` 詳細で右下カメラ FAB から撮影 → 行が出て empty view が消える、empty view → リスト遷移にちらつきが出ないか
4. **Group X に子 Group を追加すると empty 解除**: `テスト` 詳細で右下 Group 作成 FAB から子グループ `子` を作成 → 行が出て empty view が消える
5. **Group X から子要素を全削除すると empty 復帰**: 上記 4 の `子` を削除 → empty view (新文言) に戻る
6. **未分類タブ empty 状態への波及なし**: `未分類` タブを空状態にしたとき、文言が `まだ翻訳がありません` + `画面右下のカメラボタンからテキストを撮影すると、自動で翻訳されてここに保存されます。` のままで変わっていない (本変更は GroupListView のみ触るため変化しないはずだが念のため目視確認)
7. **狭幅折り返し**: iPhone SE 系を持っていれば確認、無ければシミュレータでのレイアウト確認は WSL2 では不可なので Akira さんの実機 (iPhone 16 Pro) のみで確認 → 折り返しが許容外なら判断 C 代替案に切替

## Phase / Step

- **Phase1 文言分岐実装**
  - Step1-1 `GroupListView.swift` の `emptyView` を `rootEmptyView` にリネーム (中身据え置き)
  - Step1-2 `groupEmptyView` を新規追加 (タイトル `翻訳もグループもまだありません` / 説明文 / `tray` アイコン)
  - Step1-3 `rootBody` の `emptyView` 参照を `rootEmptyView` に、`groupBody(group:)` の参照を `groupEmptyView` に書き換え
  - Step1-4 コードレビュー (WSL2 では Xcode ビルド検証不可、`AVFoundation` 系のシグネチャは触らないので静的レビューで十分)
- **Phase2 実機確認**
  - Step2-1 タグ push (Akira さん事前確認) → Bitrise → TestFlight
  - Step2-2 テスト方針 1〜7 を実機で確認、文言折り返しが許容外なら判断 C 代替案に切替して再 push
- **Phase3 仕上げ**
  - Step3-1 TODO.md → DONE.md に移送、本プランを `docs/plans/archive/` に移動

判断履歴:
- 起票時 (2026-05-04): 判断 A (scope 別分岐) + 判断 B (`actions:` 不使用、HomeFAB 一本化) + 判断 C 採用案 + 判断 D (`tray` アイコン) + 判断 F (Root 文言保護のためリネーム → 追加の順) で開始
