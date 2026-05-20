# 管理画面の改善 — OCR / 翻訳モデルの切替と料金比較

`/admin` (Hono サーバの管理画面) を 2 ペイン構造に再設計し、OCR と翻訳のモデルをそれぞれ独立に切り替えられるようにする。あわせてモデル別の料金比較、1 件あたり平均料金、OCR / 翻訳それぞれの平均料金を可視化する。

ステータス: **着手前** / 開始予定: 2026-05-04 〜

## 目的・背景

- TODO.md より:
  - 管理画面を「左ペインに見出し、右ペインにコンテンツ」の 2 ペイン構造にする
  - OCR と翻訳のモデルを変更可能にする
  - モデル別の料金比較
  - 1 アイテムごとの平均料金
  - OCR 料金平均と翻訳料金平均
  - その他必要なものを表示
- 現状 `server/src/index.ts:19` で `MODEL_ID = 'claude-sonnet-4-6'` がハードコード。`/translate` は **1 回の Anthropic 呼び出しで OCR + 翻訳 + 言語判定をまとめて実行** している (`server/src/index.ts:65-125`) ため、OCR と翻訳の usage / 料金を分けて計測する手段がない
- DONE 済みの `admin-usage-cost.md` で usage 4 列 (`inputTokens` / `outputTokens` / `cacheCreationInputTokens` / `cacheReadInputTokens`) の記録と料金集計まで入っているが、これは「合算」の usage であり、OCR と翻訳を分離する手前で止まっている
- Akira さんが OCR (vision 必須・高解像度入力) と翻訳 (テキストのみ・短文中心) で異なるモデルを試し、コストとオフライン精度のトレードオフを判断できる土台を整えるのが本タスクの主眼

## 対応方針

1. **`/translate` を OCR と翻訳の 2 呼び出しに分割する**
   - OCR 呼び出し: 画像 + プロンプト → `originalText` + `sourceLanguage` (json_schema, vision 必須モデル)
   - 翻訳呼び出し: `originalText` + `sourceLanguage` → `translatedText` + `targetLanguage` (json_schema, text-only モデル可)
   - クライアント (iOS) へのレスポンス JSON 形状は **互換維持** (`originalText` / `translatedText` / `sourceLanguage` / `targetLanguage` / `model`)。`model` は OCR モデル ID を返す。追加の `ocrModel` / `translationModel` を含めるが iOS 側は無視可能
2. **history スキーマを OCR / 翻訳別 usage に拡張**
   - 既存列 (`model`, `inputTokens` 等) は legacy として保持し、古い行も読めるようにする
   - 新規列 (NULL 許容) を 10 列追加:
     - `ocrModel`, `ocrInputTokens`, `ocrOutputTokens`, `ocrCacheCreationInputTokens`, `ocrCacheReadInputTokens`
     - `translationModel`, `translationInputTokens`, `translationOutputTokens`, `translationCacheCreationInputTokens`, `translationCacheReadInputTokens`
   - 起動時に `PRAGMA table_info(history)` で欠けている列を `ALTER TABLE ADD COLUMN` する既存パターンを踏襲
3. **モデル設定の永続化**
   - SQLite に `settings` テーブル (`key TEXT PRIMARY KEY, value TEXT NOT NULL, updatedAt TEXT NOT NULL`) を追加
   - キー `ocrModel` / `translationModel` を保存。デフォルトは `claude-sonnet-4-6`
   - 設定変更は `/admin/settings` の POST フォームから行い、即時に次回 `/translate` 呼び出しへ反映される
4. **`pricing.ts` にモデル候補を拡張**
   - 現状 `claude-sonnet-4-6` のみ → `claude-opus-4-7`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001` を登録
   - 単価は **Phase1 着手時点で Anthropic 公式値を再確認** (本プラン記載の数値はメモ)
   - `supportsVision: boolean` を追加し、OCR モデルの `<select>` ではこれが `true` のものだけ列挙
5. **管理画面 UI を 2 ペイン化**
   - 左ペイン (固定幅 220px 程度): 縦ナビ。「履歴」「サマリ」「モデル別比較」「モデル設定」
   - 右ペイン: 選択中セクションのコンテンツ
   - URL 設計:
     - `/admin` (= 履歴一覧, 既存挙動の延長)
     - `/admin/summary`
     - `/admin/models`
     - `/admin/settings`
     - `/admin/:id` (詳細, 既存)
     - `/admin/:id/image` (画像, 既存)
   - 共通レイアウト関数 `renderAdminLayout(activeNav, contentHtml)` を新設し、既存 `renderListPage` / `renderDetailPage` もこのレイアウトに乗せる
6. **モデル別比較**
   - `/admin/models` で過去履歴を `ocrModel` / `translationModel` でそれぞれ group by
   - 各モデルの「件数 / 累計 input トークン / 累計 output トークン / 累計料金 USD / 1 件あたり平均料金」を 2 つのテーブルで横並び表示
   - legacy 行 (OCR / 翻訳分離前) は `(legacy)` グループでまとめてカウント
7. **平均料金**
   - `/admin/summary` のサマリブロックを拡張
   - 「1 件あたり平均料金 (合計)」「OCR 1 件あたり平均料金」「翻訳 1 件あたり平均料金」を全期間と当月で表示
   - 既存の件数 / トークン累計 / 料金累計と並べる

## 影響範囲

- `server/src/history.ts` — スキーマ拡張、`SaveHistoryInput` / `HistoryRecord` 型に 10 列追加、INSERT / SELECT 更新、settings テーブル新設 (or 別ファイル化)
- `server/src/index.ts` — `/translate` を 2 段呼び出しに書き換え。admin ルート群を 2 ペイン化、新ルート `/admin/summary` / `/admin/models` / `/admin/settings` (GET) / POST `/admin/settings` を追加
- `server/src/pricing.ts` — モデル候補追加、`supportsVision` 追加、`getAvailableModels()` を export
- 既存 SQLite (`server/data/history.db`) — `ALTER TABLE history ADD COLUMN ...` を起動時に冪等実行 / `CREATE TABLE IF NOT EXISTS settings`
- iOS クライアント側は無変更 (`/translate` のレスポンス JSON 形状は互換維持。`ocrModel` / `translationModel` を追加するが既存 `TranslateResponse` のデコードに影響しないよう必ず追加フィールドのみ)

## 未確定事項 / 前提

- **OCR と翻訳の API 呼び出し分割**: 1 呼び出し → 2 呼び出しになるため、upstream 呼び出し回数 +1 / latency +1 round trip / 翻訳呼び出しのプロンプト分の input トークンも増える。代わりに OCR / 翻訳それぞれを最適なモデルに割り当てられる利得を取る (例: OCR は Sonnet / Opus、翻訳は Haiku) → ネットでコスト減を狙える設計
- **言語判定の所属**: 現状はまとめてやっている `sourceLanguage` 推定を OCR 呼び出し側に持たせる。翻訳呼び出しは `sourceLanguage` を入力としてもらう (= 翻訳側で再判定しない)
- **prompt caching**: 翻訳呼び出しはシステムプロンプトが固定で caching が効きやすい。本タスクでは導入しない (列だけ予約済み) が、将来導入時の数字も `pricing.ts` の `cacheWritePerMTok` / `cacheReadPerMTok` で計算できる状態にする
- **legacy 行の扱い**: OCR / 翻訳列が NULL の旧行はモデル別比較で `(legacy)` グループに集約。平均計算では「OCR 平均 / 翻訳平均」の母数からは除外し、「合計平均」の母数にのみ含める
- **モデル切替の認証**: 現状 `/admin` は無認証 (Akira さん 1 人運用 + ngrok 経由)。POST `/admin/settings` も同水準で OK。将来トークンガードを入れる場合は別 TODO
- **単価表のソース**: Phase1 着手時に Anthropic 公式ドキュメントで現行レートを再確認する (本プラン記載値はメモ。実装直前に検証)
- **モデル ID の表記揺れ**: Haiku 4.5 は ID 末尾に日付が入る (`claude-haiku-4-5-20251001`)、Sonnet 4.6 / Opus 4.7 は日付なし。`pricing.ts` のキーは Anthropic SDK が受け付ける ID と一致させる
- **TestFlight 経由の実機確認は不要**: 本タスクは server-only の変更で、iOS のレスポンス JSON 形状は不変。タグ push は不要

## テスト方針

- 各 Phase 完了時に `server/` で `npm run dev` を立ち上げ直し、ブラウザ + `curl` で疎通確認
- 新規 `/translate` を `curl -F image=@debug-ss/nasiogio-01.jpg http://localhost:3000/translate` で 1 件投入し、admin 詳細で OCR / 翻訳の usage が分離して表示されること
- 旧 DB (`server/data/history.db`) を残したまま起動し、ALTER TABLE が冪等に走り、legacy 行が崩れずに表示されること
- 設定変更後の `/translate` が選択モデルで実行されること (ログの `model=` または admin 詳細で確認)
- 自動テストは導入しない (現状サーバにテストフレームワーク無し)
- 実機 (TestFlight) 検証は不要 (server-side のみ、レスポンス JSON 不変)

## Phase 分解

### Phase 1: `pricing.ts` のモデル候補拡張

- `pricing.ts` の `PRICING` に以下を追加 (単価は実装直前に Anthropic 公式値で確認):
  - `claude-opus-4-7`
  - `claude-haiku-4-5-20251001`
- `ModelPricing` に `supportsVision: boolean` を追加 (OCR モデル選択肢のフィルタ用)
- `getAvailableModels(): Array<{ id: string; pricing: ModelPricing }>` を export
- 確認: `pricing.ts` を `tsx` で簡易呼び出しし、各モデルの `calculateCost` が手計算と一致

### Phase 2: history スキーマを OCR / 翻訳別 usage に拡張

- `server/src/history.ts`:
  - `CREATE TABLE` を新規列込みで定義 (新 DB 用)
  - `PRAGMA table_info(history)` で欠けている列を `ALTER TABLE history ADD COLUMN` (既存パターン)
  - 追加列: `ocrModel TEXT`, `ocrInputTokens INTEGER`, `ocrOutputTokens INTEGER`, `ocrCacheCreationInputTokens INTEGER`, `ocrCacheReadInputTokens INTEGER`, `translationModel TEXT`, `translationInputTokens INTEGER`, `translationOutputTokens INTEGER`, `translationCacheCreationInputTokens INTEGER`, `translationCacheReadInputTokens INTEGER`
  - `SaveHistoryInput` / `HistoryRecord` に同名の `number | null` / `string | null` フィールドを追加
  - `insertStmt` の VALUES と `listStmt` / `getStmt` の SELECT 列に追加
- 確認: 旧 DB を起動して ALTER TABLE が冪等に走ること、新規 INSERT で値が NULL のまま保存できること

### Phase 3: `settings` テーブルと読み書き API

- `server/src/settings.ts` を新設 (or `history.ts` 末尾) し、以下を実装:
  - `CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updatedAt TEXT NOT NULL)`
  - `getSetting(key: string): string | null`
  - `setSetting(key: string, value: string): void`
  - 起動時に `ocrModel` / `translationModel` がなければ `claude-sonnet-4-6` で seed
- 確認: `setSetting('ocrModel', 'claude-haiku-4-5-20251001')` 後 `getSetting('ocrModel')` が同じ値を返すこと

### Phase 4: `/translate` を OCR / 翻訳 2 段呼び出しに分割

- `server/src/index.ts:29-201` の `/translate` ハンドラを以下に書き換え:
  1. `getSetting('ocrModel')` / `getSetting('translationModel')` でモデル ID を取得 (フォールバックは `claude-sonnet-4-6`)
  2. **OCR 呼び出し**: 画像 + プロンプト → `originalText` + `sourceLanguage` を json_schema で取得
     - プロンプト: 「画像内のテキストの主要言語を判定 / 改行段落構造保持 / `originalText` と `sourceLanguage` ('en' | 'ja') を返す」
     - schema: `{ originalText: string, sourceLanguage: 'en' | 'ja' }`
  3. **翻訳呼び出し**: OCR 結果を入力に → `translatedText` + `targetLanguage` を json_schema で取得
     - プロンプト: `sourceLanguage='en'` なら自然な日本語に / `'ja'` なら自然な英語に翻訳。改行段落構造保持
     - schema: `{ translatedText: string, targetLanguage: 'en' | 'ja' }`
  4. `saveHistory` 呼び出しに `ocrModel` / `ocrInputTokens` / ... / `translationModel` / `translationInputTokens` / ... を渡す
  5. legacy 列 (`model`, `inputTokens` 等) には OCR usage を埋めて互換維持 (旧 admin / pricing 集計が崩れないように)
  6. レスポンス JSON は既存 5 フィールド + `ocrModel` / `translationModel` を返す
- 失敗時のロールバック: OCR 成功 / 翻訳失敗の場合は 502 を返す。history は保存しない (= 部分成功は記録しない)
- 確認: `nasiogio-01.jpg` で `/translate` を流し、結果文言が今までと同等、admin 詳細で OCR / 翻訳両方の usage が分離して表示

### Phase 5: 管理画面の 2 ペイン構造化

- ADMIN_STYLE に `display: grid; grid-template-columns: 220px 1fr; gap: 24px` を持つレイアウト用クラスを追加
- 共通関数 `renderAdminLayout(active: 'history' | 'summary' | 'models' | 'settings', content: string): string` を新設
  - 左ペイン: `<nav>` で 4 リンクを縦並び、active なものを強調
  - 右ペイン: `content` をそのまま流し込み
- 既存 `renderListPage` / `renderDetailPage` の `<body>` を `renderAdminLayout('history', ...)` でラップ
- 新ルート `/admin/summary`, `/admin/models`, `/admin/settings` を **空のプレースホルダ** で先に追加 (中身は次 Phase で実装)
- 確認: ブラウザで `/admin`, `/admin/:id`, `/admin/summary`, `/admin/models`, `/admin/settings` を開き、いずれも 2 ペインで表示、ナビの強調が正しく切り替わる

### Phase 6: モデル設定 UI (`/admin/settings`)

- GET `/admin/settings`:
  - `getAvailableModels()` から候補を取得し、OCR 用 `<select>` (vision 対応のみ) と翻訳用 `<select>` (全候補) を表示
  - 現在の `getSetting('ocrModel')` / `getSetting('translationModel')` を `selected` にする
  - フォーム送信先 `POST /admin/settings`、CSRF は当面なし (1 人運用)
- POST `/admin/settings`:
  - body の `ocrModel` / `translationModel` をバリデート (= `getAvailableModels` に含まれる ID か, OCR は `supportsVision: true` か)
  - 通れば `setSetting` を呼んで `/admin/settings?saved=1` にリダイレクト
  - 失敗時はエラーメッセージ付きで再描画
- 確認: 設定変更 → 直後の `/translate` が新モデルで動く (ログ `[translate] anthropic ok: model=...` で確認)

### Phase 7: サマリ・モデル別比較セクション

- `/admin/summary`:
  - 既存サマリ (全期間 / 当月) を移植
  - 行を増やす:
    - 1 件あたり平均料金 (合計コスト ÷ 全件数)
    - OCR 1 件あたり平均料金 (OCR コスト合計 ÷ OCR 列が NULL でない件数)
    - 翻訳 1 件あたり平均料金 (翻訳コスト合計 ÷ 翻訳列が NULL でない件数)
  - 件数が 0 のときは `-` 表示で 0 除算を回避
- `/admin/models`:
  - 「OCR モデル別」テーブルと「翻訳モデル別」テーブルを縦並びで表示
  - 列: モデル / 件数 / input 合計 / output 合計 / 料金合計 / 1 件あたり平均
  - `null` モデル (legacy 行) は `(legacy)` でグルーピング
  - 集計は JS で reduce (件数上限 10,000 件なので十分)
- 確認: 空 DB / NULL のみの DB / 新規 + legacy 混在 のいずれでも崩れない

### Phase 8: 一覧・詳細ページの料金表示を OCR / 翻訳別に

- 詳細ページ (`renderDetailPage`):
  - `meta` ブロックに「OCR モデル: X / 使用トークン input X / output Y / 料金 $Z」「翻訳 モデル: X / 使用トークン... / 料金 $Z」「合計料金 $Z」を OCR / 翻訳 / 合計の 3 行で表示
  - legacy 行 (OCR / 翻訳列がいずれも NULL) は既存表示にフォールバック
- 一覧ページ (`renderListPage`):
  - 「料金」列は合計のみのまま (細かすぎる場合)
  - モデル列を「OCR / 翻訳」表記に変更 (OCR モデルと翻訳モデルが同じ場合はまとめて 1 つ表示でも可)
- 確認: 既存表示は崩れず、新規行は OCR / 翻訳分けて確認できる

### Phase 9: 疎通確認 (まとめ)

- `server/data/history.db` を一度退避し、まっさらな状態でも起動して全 `/admin/*` ルートが空状態で描画できること
- 既存 DB を戻して再起動 → ALTER TABLE が冪等に走ること、legacy 行が一覧 / 詳細 / モデル別比較で崩れずに表示されること
- `/admin/settings` で OCR モデルを Sonnet → Haiku に変更 → `/translate` を 1 件流し、admin 詳細で `ocrModel = claude-haiku-4-5-20251001` が記録され料金がそのレートで計算されていること
- `/admin/summary` の 1 件あたり平均 / OCR 平均 / 翻訳平均が想定通りに増分すること

## 完了の定義 (DoD)

- 管理画面が左ペイン (履歴 / サマリ / モデル別比較 / モデル設定) + 右ペインの 2 ペイン構造になっている
- `/admin/settings` で OCR / 翻訳のモデルを切り替えられ、即座に次の `/translate` 呼び出しに反映される
- OCR と翻訳の usage / 料金が DB に別々に記録されている
- `/admin/summary` で 1 件あたり平均料金, OCR 平均料金, 翻訳平均料金が見える
- `/admin/models` で OCR モデル別 / 翻訳モデル別の累計と平均が見える
- 旧 1 呼び出し時代のレコードを混在させても admin 全画面が崩れない
- iOS 側のレスポンス JSON 形状は不変 (アプリ側に影響しない)
