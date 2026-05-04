# 双方向翻訳対応 (英 ↔ 日)

## 目的

撮影テキストを **英 → 日 / 日 → 英 の両方向で翻訳できる** ようにする。
方向はユーザーが選ばず、**サーバ側の AI で自動判定** し、入力言語と出力言語の両方を Item レコードに保存する。

## 背景

現状は英→日に固定:

- サーバ (`server/src/index.ts:103-108`) のプロンプトに「画像に写っている英語の文字を OCR で抽出し、自然な日本語に翻訳してください」と記載。
- JSON schema の description にも英→日が固定 (`server/src/index.ts:74-83`)。
- iOS の `Item.swift` には言語を表すフィールドが存在しない。
- UI ラベルは「原文 / 訳文」と方向中立だが、admin 詳細 (`server/src/index.ts:356-359`) は「原文 (英語) / 訳文 (日本語)」固定。

photorans の利用シーンは「英語看板を撮る日本人」「日本語看板を撮る英語話者」のいずれかに偏ると想定されるため、毎回方向を選ばせるよりも自動判定で UX 上シンプルにする方針。

## 確定方針 (ユーザー合意済み)

1. **方向決定**: AI 自動判定。撮影 UI は無変更。
2. **データ保持**: 入力言語 (`sourceLanguage`) と出力言語 (`targetLanguage`) を **両方** Item / history レコードに保存。
3. **UI 表示**: メインは訳文 (現状踏襲)。詳細画面の「翻訳 / 原文」ラベルに言語サフィックスを足し、行 (`ItemRowView`) は訳文を主、言語表示は最小限。

## スコープ

In-scope:

- サーバ `/translate` を双方向対応に変更 (プロンプト・JSON schema・レスポンス)。
- サーバ history (`better-sqlite3`) スキーマに 2 列追加。admin 表示も切替。
- iOS `Item` モデルに 2 フィールド追加 + lightweight migration + 既存データバックフィル。
- iOS `TranslateResponse` / `TranslationCoordinator` に 2 フィールド配線。
- iOS `ItemDetailView` のラベル動的化。
- 単体テスト追加 (TranslationCoordinatorTests, バックフィル)。
- TestFlight で英→日 / 日→英 の golden path を実機検証。

Out-of-scope (別 TODO):

- 自動判定が誤った場合の手動切替 UI (再翻訳機能含む)。
- 英・日以外の言語 (中・韓など) への拡張。
- ユーザー設定で「優先方向」を指定する機能。

## 影響範囲

- `server/src/index.ts` (プロンプト / JSON schema / saveHistory 呼び出し / admin HTML)
- `server/src/history.ts` (テーブル ALTER + Insert/Select 列追加 + 型拡張)
- `ios/Photorans/Networking/TranslateAPI.swift` (`TranslateResponse` 拡張)
- `ios/Photorans/Storage/Item.swift` (フィールド追加)
- `ios/Photorans/Services/TranslationCoordinator.swift` (書き戻し)
- `ios/Photorans/Services/PendingItemRecovery.swift` 周辺 (バックフィル処理を新規追加)
- `ios/Photorans/Features/Item/ItemDetailView.swift` (ラベル動的化)
- `ios/Photorans/Features/Item/ItemRowView.swift` (言語表記の有無を要検討)
- `ios/PhotoransTests/TranslationCoordinatorTests.swift` (mock 更新)
- 新規: `ios/PhotoransTests/ItemLanguageBackfillTests.swift` (バックフィル単体テスト)

## 詳細設計

### 言語コード

`"en"` / `"ja"` の **小文字 ISO 639-1 2 文字コード** を採用。

- 当面はこの 2 値固定。Item / history に保存する型はクライアント・サーバ共に文字列。
- iOS 側の Swift enum は導入せず、**生文字列 + ヘルパで表示名解決** とする (将来言語追加時の DB マイグレーションを単純に保つ)。
- 表示名解決: `"en" → "英語"`, `"ja" → "日本語"`, それ以外は raw を fallback。

### サーバ: プロンプトと JSON schema

新プロンプト (要旨):

```
画像内のテキストの言語を判定してください。
- 英語が中心なら自然な日本語に翻訳。
- 日本語が中心なら自然な英語に翻訳。
OCR は改行・段落構造を保持し、混在する場合は中心となる言語を翻訳対象とする。
読み取れない部分は読み取れた範囲のみで返す。
sourceLanguage / targetLanguage は ISO 639-1 ("en" or "ja") で必ず返す。
```

新 JSON schema (要旨):

```json
{
  "type": "object",
  "properties": {
    "originalText":    { "type": "string" },
    "translatedText":  { "type": "string" },
    "sourceLanguage":  { "type": "string", "enum": ["en", "ja"] },
    "targetLanguage":  { "type": "string", "enum": ["en", "ja"] }
  },
  "required": ["originalText", "translatedText", "sourceLanguage", "targetLanguage"],
  "additionalProperties": false
}
```

レスポンス JSON にも `sourceLanguage` / `targetLanguage` を含める。

### サーバ: history テーブル

`server/src/history.ts:33-40` の既存パターン (起動時に `pragma table_info` で列を確認 → 不足列を `ALTER TABLE ADD COLUMN`) を踏襲し、`sourceLanguage` / `targetLanguage` を追加する。

- 列: `sourceLanguage TEXT`, `targetLanguage TEXT` (NULL 許可)
- 既存行は NULL のまま放置し、admin 表示時に NULL なら `"en"` / `"ja"` (= 旧固定方向) として扱う。
- `SaveHistoryInput` / `HistoryRecord` / 全 SELECT・INSERT 文に 2 列追加。

### サーバ: admin HTML

- 詳細画面 (`renderDetailPage`) の `<h2>原文 (英語)</h2>` / `<h2>訳文 (日本語)</h2>` を、レコードの `sourceLanguage` / `targetLanguage` に応じて動的に "原文 (英語/日本語) / 訳文 (日本語/英語)" に切替。
- 一覧にはモデル列の左に「方向」列を追加し、各行に `EN→JA` / `JA→EN` を表示する (Step 1-5 で確定)。NULL のレガシー行は `EN→JA` をフォールバック表示する。

### iOS: Item モデル

```swift
@Model
final class Item {
    // 既存フィールドは省略
    var sourceLanguage: String?  // "en" or "ja", 既存データは nil → バックフィルで埋める
    var targetLanguage: String?  // 同上
    // ...
}
```

- 新規プロパティを **optional** で追加することで SwiftData の lightweight migration が成立する想定 (実装時に公式ドキュメントで API 名と挙動を裏取り — `Swift API は推測で書かない` メモリーに準拠)。
- `init` のデフォルト引数は nil とし、`TranslationCoordinator` が翻訳完了時にセットする。

### iOS: 既存データのバックフィル

新規バックフィルサービス `ItemLanguageBackfill` を `Services/` に追加。

- 起動時 (`PhotoransApp.body.task`) で **`PendingItemRecovery.runIfNeeded` の前段** に呼ぶ。
- `sourceLanguage == nil` の Item を全件取得し、`sourceLanguage = "en"` / `targetLanguage = "ja"` を埋めて save。
- 1 回限りの全件走査だが、件数は個人スケール (せいぜい数百件) を前提にしているので性能問題なし (`TranslationCoordinator.fetchItem` の前例と同じ判断)。
- テストは `ItemLanguageBackfillTests` で in-memory コンテナを使ってカバー。

### iOS: TranslateResponse / Coordinator

- `TranslateResponse` に `sourceLanguage: String` / `targetLanguage: String` を追加 (non-optional)。
- `TranslationCoordinator.runTranslation` の `.success` ブランチで `item.sourceLanguage` / `item.targetLanguage` をセット。
- `TranslationCoordinatorTests` の mock `TranslateResponse` に新フィールドを足す。

### iOS: UI

- `ItemDetailView.completedBody`:
  - `Text("翻訳")` → `Text("翻訳 (\(targetLangDisplay))")` のように動的に "翻訳 (日本語)" / "翻訳 (英語)" を表示。
  - `Text("原文")` も同様に "原文 (英語)" / "原文 (日本語)" に切替。
  - 言語表示名の解決ヘルパ (`languageDisplayName(_ code: String?) -> String`) を `Item.swift` か新ファイル `LanguageDisplay.swift` に置く (Step で確定)。
- `ItemDetailView.metadataSection`: 「翻訳方向」行を 1 行追加 (例: `EN → JA`)。簡潔に raw コードを矢印で繋ぐ表示。
- `ItemRowView`: 訳文メイン据え置き。撮影日時の隣に `EN→JA` の小さなバッジを足すかは Step 3-2 で要否確定 (一覧で方向を判別したい需要があるかどうか)。

## Phase / Step 構成

### Phase 1: サーバ双方向対応

- [ ] Step 1-1: `/translate` プロンプトを双方向対応に書き換え
- [ ] Step 1-2: `/translate` JSON schema に `sourceLanguage` / `targetLanguage` を追加
- [ ] Step 1-3: history テーブルに `sourceLanguage` / `targetLanguage` 列を追加 (`ALTER TABLE` 起動時マイグレーション)
- [ ] Step 1-4: `SaveHistoryInput` / `HistoryRecord` / 全 SQL 文に 2 列を配線、`saveHistory` 呼び出し側 (`/translate`) で値を渡す
- [ ] Step 1-5: admin 詳細ラベル動的化 + 一覧での方向表示要否を確定して反映
- [ ] Step 1-6: `curl` で英→日 / 日→英 の手動疎通確認 (CI 自動テストは無)

### Phase 2: iOS Item モデル拡張 + バックフィル

- [x] Step 2-1: `Item` に `sourceLanguage` / `targetLanguage` (optional `String`) を追加
- [x] Step 2-2: SwiftData lightweight migration の挙動を公式ドキュメントで裏取りし、必要なら `Schema` / `MigrationPlan` を整備 (推測実装禁止) — 結論: optional プロパティ追加は非破壊変更のため自動処理、明示的な MigrationPlan 不要
- [x] Step 2-3: `ItemLanguageBackfill` を新規追加し、`PhotoransApp.body.task` で `PendingItemRecovery` より前に呼ぶ
- [x] Step 2-4: `TranslateResponse` に 2 フィールド追加、`TranslationCoordinator.runTranslation` で書き戻し
- [x] Step 2-5: `TranslationCoordinatorTests` の mock 更新 + `ItemLanguageBackfillTests` 新規追加
- [x] Step 2-6: `ios/project.yml` の対象ファイル追加に伴い `xcodegen` で pbxproj 再生成して同 commit (XcodeGen メモリ準拠)

### Phase 3: iOS UI ラベル動的化

- [ ] Step 3-1: 言語表示名ヘルパ (`languageDisplayName`) を実装
- [ ] Step 3-2: `ItemDetailView.completedBody` のラベルを言語サフィックス付きに変更、`metadataSection` に翻訳方向行を追加
- [ ] Step 3-3: `ItemRowView` に方向バッジを足すか確定 (案: 撮影日時の隣に `EN→JA` の小さなテキスト)、必要なら実装
- [ ] Step 3-4: 既存 UI のスナップショット系テストがあれば更新 (現状の test 構成を見て判断)

### Phase 4: TestFlight 実機検証

- [ ] Step 4-1: Akira さん確認のうえタグ push (CLAUDE.md TestFlight 運用ルールに従う)
- [ ] Step 4-2: 英語看板を撮影 → 英→日 翻訳 + ラベル「翻訳 (日本語) / 原文 (英語)」を確認
- [ ] Step 4-3: 日本語看板を撮影 → 日→英 翻訳 + ラベル「翻訳 (英語) / 原文 (日本語)」を確認
- [ ] Step 4-4: 既存ビルドで撮影済みの Item がバックフィルで `EN→JA` 表示になることを確認
- [ ] Step 4-5: admin 画面で新規 / 既存両方のレコードが正しいラベルで出ることを確認

## テスト方針

- **単体**:
  - `TranslationCoordinatorTests`: mock `TranslateResponse` の 2 フィールドが Item に伝搬すること、`.failed` 時の挙動が回帰しないこと。
  - `ItemLanguageBackfillTests` (新規): nil の Item が起動後に `"en"` / `"ja"` で埋まること、すでに値が入っている Item は上書きされないこと。
- **手動**:
  - サーバ側は `curl -F image=@en.jpg` / `-F image=@ja.jpg` で英・日両方のサンプルを叩いてレスポンス JSON を目視確認。
  - admin 画面は新規挿入と既存 NULL 行が両方正しく描画されることを確認。
- **実機**:
  - TestFlight 経由で Phase 4 を遂行。

## 未決事項 (実装時に解決)

1. iOS SwiftData lightweight migration の API 名 (`SchemaMigrationPlan` / `VersionedSchema` 等) — 公式ドキュメントで裏取り。
2. `ItemRowView` の方向バッジ要否 — Phase 3 開始時に再判断。
3. ~~admin 一覧の方向表示要否~~ — Phase 1-5 で「モデル列の左に方向列追加」で確定。
4. 言語自動判定が混在テキスト (英日が半々程度) で安定するかの感触 — Phase 1-6 の手動疎通で英 (`nasiogio-01.jpg`) / 日 (合成サンプル) ともに正しく `en→ja` / `ja→en` を返したことを確認。混在素材での感触は Phase 4 実機検証で再評価。

## 完了条件

- 英→日 / 日→英 の両方向で翻訳が成功し、UI とサーバ admin の両方で正しいラベルが表示される。
- 既存データが `EN→JA` 固定として整合的に表示される。
- TestFlight で実機検証が OK。
- TODO の親項目を DONE.md に移送し、本プランを `docs/plans/archive/` に移動。
