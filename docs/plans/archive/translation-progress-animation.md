# 翻訳中アニメーション (Shimmer 置換)

`.processing` Item の行 / 詳細で表示している `ShimmerOverlay` (X 軸方向に光が流れるシマー) を、別モチーフのアニメーションに差し替える。

ステータス: **Phase0 完了 / Phase1 着手中** / 起票日: 2026-05-04

## 目的・背景

現状、`ItemRowView` (行) と `ItemDetailView` (詳細) の `.processing` 表示は次の構成:

- `ItemRowView.swift:40-53` — `Text("翻訳中…")` + 撮影日時の VStack に `ShimmerOverlay` を `.overlay`、行全体に `accessibilityLabel("処理中")`
- `ItemDetailView.swift:111-123` — `Text("翻訳中…")` + 96pt 高さの灰色 RoundedRectangle、矩形に `ShimmerOverlay` を `.overlay`
- `ShimmerOverlay.swift` — `LinearGradient` (透明 → `white.opacity(0.55)` → 透明) を `phase: -1 → 1` で 1.4 秒 linear 無限ループ、`blendMode(.plusLighter)`

ユーザー (Akira さん) の意向:
- **モチーフ自体を変更**したい (シマー光流れ → 別の表現)
- 参考イメージは特になし、Claude おまかせ提案
- 対象は「現在アニメーションしているところ全て」 = `ItemRowView` 行 + `ItemDetailView` 詳細本文 (CameraView シャッター中の `ProgressView` は撮影中スピナーで「翻訳中」ではないため対象外)

スコープは上記 2 箇所の Processing 表示の **アニメーションモチーフ差し替え** のみ。`Text("翻訳中…")` の文言、`accessibilityLabel("処理中")`、行内に出している撮影日時、リトライ / 失敗系の挙動はいずれも触らない。

## 対応方針

### 判断 A: モチーフ案 (3 案比較 / Phase 0 で最終決定)

`ShimmerOverlay` を共通の新コンポーネント `TranslationProgressIndicator` に置換する。モチーフ案を 3 つに絞り、Phase 0 で Akira さん最終確認 (実装着手前):

#### 案 B (推奨): Typing dots (3 ドット pulse)

`Text("翻訳中")` の右に `…` の代わりに 3 つの円ドット。各ドットが時差で `scaleEffect(0.6 → 1.0)` + `opacity(0.3 → 1.0)` を `delay(0)` / `delay(0.2)` / `delay(0.4)` で repeatForever (autoreverses: true)。

- メリット: メッセージ系 / AI チャット UI で広く認知される「処理中」サイン、シマーよりシグナルが明確、行・詳細どちらでもサイズ調整しやすい
- デメリット: 「翻訳」固有のニュアンスは出ず、汎用的な「考え中」表現
- 実装: SwiftUI 標準 `Circle` + `scaleEffect` / `opacity` + `Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(i * 0.2)`、外部依存ゼロ

#### 案 A (代替): Skeleton lines pulse (Apple 純正系)

訳文プレースホルダとして `Capsule` 数本 (行: 1 本 / 詳細: 3 本縦並び) を opacity 0.3 ↔ 1.0 で同期 pulse。

- メリット: Apple Mail 要約 / Photos 解析中と同じ系統で iOS らしさ◎、訳文が「これから入ってくる」ことが skeleton で示唆される
- デメリット: シマーと同じく地味で抑揚が弱い、「翻訳中…」テキストを置くか skeleton のみにするか UX 設計が増える
- 実装: 標準

#### 案 C (落選想定): Gradient breathing wave (Apple Intelligence 風)

現行 shimmer の進化版。彩度ありグラデが `Text("翻訳中…")` を mask として呼吸する。

- メリット: モダン、AI 文脈に合う
- デメリット: ユーザー要望「モチーフ自体を変更」に対し近すぎる (= 同じシマー系の延長)、本案を採用すると要望に反する可能性
- 落選方針: Phase 0 で明示的に却下候補として並べ、ユーザーが C を希望した場合のみ採用

#### 補助 (B 採用時の追加検討): 先頭 `sparkles` icon (案 D)

案 B に SF Symbols `sparkles` をテキスト先頭に小さく配置し、ドットと連動して pulse させるかどうかは Phase 0 で確認。デフォルトでは付けない (装飾過多防止)。

**Claude の推奨: 案 B (Typing dots) 単独**。理由は (1) ユーザー要望「モチーフ変更」に対し最もシマーから離れる、(2) 実装が最も軽く WSL2 で API 検証リスクが低い、(3) アクセシビリティ的にも `accessibilityHidden(true)` で済む。

### 判断 B: 共通コンポーネント新設

新ファイル `ios/Photorans/Features/Item/TranslationProgressIndicator.swift` を作り、行 / 詳細双方から使う。

- 構造体名: `TranslationProgressIndicator: View` (内部に `Text("翻訳中…")` を含む / 含まないかは判断 C 参照)
- パラメータ: `style: Style { case row, detail }` で行 (細め / inline) と詳細 (大きめ / block) のサイズを切替
- 既存 `ShimmerOverlay.swift` は **削除**。`.overlay(ShimmerOverlay())` の呼び出し箇所も解消する

### 判断 C: テキスト「翻訳中…」と Indicator の同居方法

3 パターンあり、案 B 採用前提で:

- C-1 (推奨): `TranslationProgressIndicator` 内に `HStack { Text("翻訳中"); DotsView() }` を持たせ、外側 (Row / Detail) は撮影日時等のレイアウトのみ担当。`ItemRowView.processingContent` / `ItemDetailView.processingBody` から `Text("翻訳中…")` と `ShimmerOverlay` を取り除き、`TranslationProgressIndicator(style: .row)` / `.detail` を 1 行差し替え
- C-2: 外側に `Text("翻訳中…")` を残し、Indicator は ドットだけ。シンプルだが「…」とドットが二重になる
- C-3: 外側で `Text("翻訳中")` (… 無し) + Indicator (ドットのみ)。C-1 と等価だが分散

採用: **C-1** (コンポーネント完結 / 呼び出し側を 1 行差し替え)。

### 判断 D: アニメーション開始タイミングと停止

- 開始: `.onAppear` で `withAnimation(...) { ... }` を発火 (現行 `ShimmerOverlay` と同じ方式)
- 停止: View が消えるとき (Item が `.completed` / `.failed` に遷移して再評価される or 画面離脱) は SwiftUI 側で自動解放、明示停止は不要
- パフォーマンス: 行リスト内に複数 `.processing` Item が並ぶケース (連続撮影) でも、各行ごとに独立した state を持つ Indicator が animate するだけで、現行 `ShimmerOverlay` と同等のコスト

### 判断 E: アクセシビリティ

現行と同じ:
- `TranslationProgressIndicator` 内部 (ドット / 矩形) は `.accessibilityHidden(true)`
- 外側 (`processingContent` / `processingBody`) で `.accessibilityElement(children: .ignore) + .accessibilityLabel("処理中")` を引き続き付与する
- VoiceOver の発話は変更しない (「処理中」のまま)

### 判断 F: 詳細画面プレースホルダ矩形の扱い

現行 `ItemDetailView.processingBody` は 96pt 高さの灰色 `RoundedRectangle` の中に shimmer を流している。案 B (Typing dots) を素直に当てるとプレースホルダ矩形と相性が悪い (ドットだけポンと置かれる)。3 オプション:

- F-1 (推奨): 矩形を撤去し、`TranslationProgressIndicator(style: .detail)` のみ。`style: .detail` ではフォントを `.headline` 相当 / ドットを少し大きめ / VStack に縦パディング 16pt
- F-2: 矩形は残し、その下に Indicator を置く (skeleton と並走) — 装飾過多
- F-3: 矩形を残し、矩形の中央に Indicator を中央寄せ — 矩形の意味が薄れる

採用: **F-1**。詳細画面のスクロールビュー内で本文部分が「翻訳中 ●●●」と表示される最小構成。

### 判断 G: 既存 `ShimmerOverlay.swift` の扱い

完全削除 (memory `feedback_xcodegen_regenerate.md` により .swift 削除は同コミットで `project.yml` から `ios/project.yml` 経由 XcodeGen 再生成を伴う)。

具体的には:
- `ios/Photorans/Features/Item/ShimmerOverlay.swift` を `git rm`
- `cd ios && xcodegen generate` で `Photorans.xcodeproj/project.pbxproj` 再生成
- 同コミットに pbxproj の差分を含める

## 影響範囲

- `ios/Photorans/Features/Item/TranslationProgressIndicator.swift` (新規)
- `ios/Photorans/Features/Item/ItemRowView.swift` —
  - `processingContent` から `Text("翻訳中…")` 行と `.overlay(ShimmerOverlay())` を取り除き、`TranslationProgressIndicator(style: .row)` を頭に置く
  - 撮影日時 `Text` は残置
  - 旧コメント (`5-7 行目: ShimmerOverlay` 言及) を `TranslationProgressIndicator` に書き換え
- `ios/Photorans/Features/Item/ItemDetailView.swift` —
  - `processingBody` を `TranslationProgressIndicator(style: .detail)` 1 本に置換 (判断 F-1)
  - `accessibilityElement` / `accessibilityLabel` は維持
  - クラスドキュメント (`9 行目: シマー` 言及) を更新
- `ios/Photorans/Features/Item/ShimmerOverlay.swift` (削除)
- `ios/Photorans.xcodeproj/project.pbxproj` (XcodeGen 再生成、.swift 追加 / 削除のため必須)
- 他ファイル — 変更なし (`CameraView` のシャッタースピナー、`PendingItemRecovery`、`TranslationCoordinator` などは無関係)
- テスト — 追加なし (アニメーションは UI ビジュアル要素のためユニットテストでは検証困難、`PhotoransTests` 配下にスナップショット基盤も無い)

リスク:

- WSL2 で SwiftUI ビルド検証不可 — `Animation.easeInOut(...).repeatForever(autoreverses:).delay(_:)` のチェーンと `withAnimation` 内の発火順は memory `feedback_swift_api_verification.md` に従い公式ドキュメントで裏取りしてから実装
- XcodeGen 再生成漏れで Bitrise CI が失敗 — memory `feedback_xcodegen_regenerate.md` 通り、commit 前に `xcodegen generate` を必ず実行
- `ItemDetailView.processingBody` から灰色プレースホルダ矩形を撤去するため、詳細画面の縦方向スペースが従来より少し詰まる → 実機確認で違和感があれば判断 F-2 / F-3 にフォールバック
- 案 B (Typing dots) のドット時差アニメは `Animation.delay(_:)` 経由だと `repeatForever` と組み合わせたとき初回のみ delay が掛かる挙動になる SwiftUI の既知挙動がある → 実機で 2 周目以降のリズムが揃って見えるか要確認、ズレが目立つなら共通の `phase` Timer を `TimelineView` で駆動する方式に切替

## テスト方針

実機 (Akira さんの iPhone 16 Pro 経由で TestFlight) で:

1. **行 (`ItemRowView` `.processing`)**: 撮影直後に Home リスト 1 行目が `[サムネ] 翻訳中 ●●● / 撮影日時` の構成で表示され、ドットが時差 pulse する。シマー (光流れ) は出ない
2. **詳細 (`ItemDetailView` `.processing`)**: 行をタップして詳細画面に入り、本文セクションが `翻訳中 ●●●` の Indicator のみ (灰色プレースホルダ矩形なし)。スクロールしてもアニメが続く
3. **`.completed` 遷移**: 翻訳完了 → 行・詳細とも Indicator が消えて訳文が出る、ちらつきなし
4. **`.failed` 遷移**: ネットワーク切断などで失敗 → Indicator が消えて失敗メッセージ + リトライボタン
5. **連続撮影で複数行 `.processing` が並ぶ**: Indicator が独立に animate、リズムがズレても破綻しない
6. **VoiceOver**: 行 / 詳細とも「処理中」と発話される (Indicator 自体は読み上げない)
7. **メモリ / バッテリー**: 連続 30 秒の `.processing` 状態維持で発熱・カクつきなし (`Animation.repeatForever` 漏れチェック)
8. **画面回転 / Dynamic Type**: portrait 固定 (memory `feedback_camera_ui_portrait_only.md` 対象は CameraView のみ、Home / 詳細は通常の SwiftUI 自動レイアウトに従う) でフォントサイズ XL / XXL でも Indicator のドットがクリップされない

## Phase / Step

- **Phase0 案決定**
  - Step0-1 本プランを Akira さんレビュー → 案 A / B / C / D 補助の最終決定 (ExitPlanMode 相当)
- **Phase1 実装**
  - Step1-1 `TranslationProgressIndicator.swift` 新規作成 (判断 A 確定案 / 判断 B 構造 / 判断 C-1 / 判断 D / 判断 E)
  - Step1-2 `ItemRowView.processingContent` を `TranslationProgressIndicator(style: .row)` に差し替え、コメント更新
  - Step1-3 `ItemDetailView.processingBody` を `TranslationProgressIndicator(style: .detail)` 1 本に置換、クラスドキュメント更新
  - Step1-4 `ShimmerOverlay.swift` を `git rm`
  - Step1-5 `cd ios && xcodegen generate` で `project.pbxproj` 再生成、差分を同 commit に
  - Step1-6 静的レビュー (WSL2 では Xcode ビルド検証不可、`Animation` API シグネチャを Apple Developer ドキュメントで再確認)
- **Phase2 実機確認**
  - Step2-1 タグ push (Akira さん事前確認) → Bitrise → TestFlight
  - Step2-2 テスト方針 1〜8 を実機で確認、リズムずれ / 違和感があれば判断 D の `TimelineView` 方式または判断 F-2 / F-3 へフォールバックして再 push
- **Phase3 仕上げ**
  - Step3-1 TODO.md → DONE.md に移送、本プランを `docs/plans/archive/` に移動

判断履歴:
- 起票時 (2026-05-04): 案 B (Typing dots) を Claude 推奨、案 A 代替、案 C 落選候補で並べる構成。判断 B (共通コンポーネント新設) / 判断 C-1 (コンポーネント完結) / 判断 F-1 (詳細プレースホルダ矩形撤去) / 判断 G (`ShimmerOverlay.swift` 削除) で起票
- 2026-05-04 (Phase0 完了): Akira さん **案 B (Typing dots) 単独採用** で確定。補助 D (sparkles アイコン) は付けない (装飾過多防止)。Phase1 着手。
