# 利用トークンと料金を管理画面に表示

`/admin` (Hono サーバの管理画面) に Anthropic API の使用トークン量と料金を可視化する。Akira さんが画像解像度 (= 入力トークン量) と OCR 精度のトレードオフを判断するための目線合わせが目的。

ステータス: **着手前** / 開始予定: 2026-05-02 〜

## 目的・背景

- TODO.md より「利用トークンと料金を管理画面に表示。必要に応じて画像の解像度の調整でトークン量を下げる。文字起こしの性能との兼ね合い」
- 現状 `server/src/index.ts` は `/translate` のレスポンス `response.usage.input_tokens` / `output_tokens` を **コンソールログにしか出していない** (`index.ts:122-124`)。SQLite (`history` テーブル) には保存していないため、後から振り返って累計を出せない
- iOS クライアントは `ImageCompressor` で長辺 2048px / 段階圧縮 (DONE.md `ios-native-rewrite.md` Phase で実装済) しており、これをさらに絞るかどうかの判断材料が欲しい
- 課金は USD で発生するため、admin 表示も USD ベースで揃える (1 人運用、円換算は当面不要)

## 対応方針

1. **`history` テーブルにトークン列を追加** — `inputTokens`, `outputTokens`, `cacheCreationInputTokens`, `cacheReadInputTokens` を `INTEGER` で追加 (NULL 許容、既存レコードは NULL のまま)
2. **`saveHistory` が usage を受け取り INSERT に含める** — `/translate` で `response.usage` を引数で渡す
3. **料金計算ユーティリティ** — `server/src/pricing.ts` を新設し、モデル ID → 単価 (USD per MTok) の表を持つ。`calculateCost(record)` で `totalUsd: number | null` を返す。表に無いモデルは `null`
4. **詳細画面 (`/admin/:id`) に表示** — トークン数と USD 料金をメタ情報の隣に出す。NULL レコード (移行前の履歴) は「-」表示
5. **一覧画面 (`/admin`) のヘッダに集計を追加** — 合計件数・累計トークン (input/output)・累計料金 USD・当月累計を表示。各行にも料金列を追加
6. **動作確認** — 既存 DB で `ALTER TABLE` が走ること、新規撮影で料金が記録されること、NULL 行混在で表示が崩れないこと

## 影響範囲

- `server/src/history.ts` — スキーマ拡張、`SaveHistoryInput` / `HistoryRecord` 型に usage 4 値を追加、`insertStmt` 更新、`listStmt` / `getStmt` の SELECT 列追加
- `server/src/index.ts` — `/translate` で `response.usage` を `saveHistory` に渡す、`renderListPage` / `renderDetailPage` に料金列・サマリ追加、`pricing.ts` の `calculateCost` を使う
- `server/src/pricing.ts` — **新規**。モデル別単価表 + `calculateCost`
- 既存 SQLite (`server/data/history.db`) — `ALTER TABLE history ADD COLUMN ...` を起動時に冪等実行 (`PRAGMA table_info` で列の有無を確認してから add)
- iOS クライアント側は無変更 (`/translate` のレスポンス JSON 形状は変えない)

## 未確定事項 / 前提

- **料金の単価ソース**: `claude-sonnet-4-6` の公式レートを `pricing.ts` にハードコードする (現時点で input $3/MTok・output $15/MTok 想定)。Phase2 着手時に Anthropic 公式ドキュメントで現行レートを再確認する
- **過去レコードの再評価**: pricing 表は **現時点の単価を全履歴に適用** する方式 (= 過去の請求額スナップショットは取らない)。Anthropic がレートを変更した場合、履歴ページの「累計料金」は新レートで再計算される。本物の請求書一致が必要になったら別 TODO で snapshot 方式に切替
- **prompt caching**: `/translate` は現状キャッシュを使っていないため `cache_creation_input_tokens` / `cache_read_input_tokens` は 0 で記録される見込み。将来導入する場合に備えて列とコスト式は用意するが、表示は 0 でない場合のみ
- **円換算**: 不要 (admin は Akira さん 1 人運用)。必要になったら別途
- **モデル拡張**: 現状 `claude-sonnet-4-6` のみ使用。Opus / Haiku 等を後から使う場合は単価表に追加する想定。表に無いモデルは料金欄「-」表示でフェイルセーフ

## テスト方針

- 各 Phase 完了時に `server/` で `npm run dev` を立ち上げ直し、`curl http://localhost:3000/admin` (一覧) と既存履歴の `/admin/:id` で表示確認
- 新規 `/translate` を `curl -F image=@debug-ss/nasiogio-01.jpg http://localhost:3000/translate` で 1 件投入し、admin にトークン数・料金が反映されること
- 既存 DB の NULL 列レコードが Phase1 の migration 後に表示エラーを起こさないこと (起動時に旧 DB を読めること)
- 自動テストは導入しない (現状サーバにテストフレームワーク無し、admin は単純な表示のみ)
- 実機 (TestFlight) は不要 (server-side のみの変更、`/translate` レスポンス JSON は不変)

## Phase 分解

### Phase1 履歴スキーマ拡張 + usage 保存

- `server/src/history.ts` の `db.exec(...)` ブロックに以下を追加:
  - `CREATE TABLE` 側に `inputTokens INTEGER`, `outputTokens INTEGER`, `cacheCreationInputTokens INTEGER`, `cacheReadInputTokens INTEGER` を追記
  - 既存 DB 互換のため、`PRAGMA table_info(history)` で列の有無を判定して欠けていれば `ALTER TABLE history ADD COLUMN <name> INTEGER` を実行する初期化関数を `db.exec` 直後に呼ぶ
- `SaveHistoryInput` / `HistoryRecord` インタフェースに 4 列を `number | null` で追加
- `insertStmt` の VALUES に 4 列を追加し、`saveHistory` で `input.inputTokens ?? null` などを渡す
- `listStmt` / `getStmt` の SELECT に 4 列を追加
- `server/src/index.ts` の `/translate` 成功パスで `saveHistory` 呼び出しに以下を追加:
  ```
  inputTokens: response.usage.input_tokens,
  outputTokens: response.usage.output_tokens,
  cacheCreationInputTokens: response.usage.cache_creation_input_tokens ?? null,
  cacheReadInputTokens: response.usage.cache_read_input_tokens ?? null,
  ```
- 確認: `npm run dev` で再起動して既存 DB に対し ALTER TABLE が走ること (`PRAGMA table_info(history)` を `sqlite3` でも確認)、新規 `/translate` を 1 件流して `SELECT` で値が入っていること

### Phase2 料金計算ユーティリティ

- `server/src/pricing.ts` を新設:
  ```ts
  export interface ModelPricing {
    inputPerMTok: number;          // USD
    outputPerMTok: number;
    cacheWritePerMTok: number;
    cacheReadPerMTok: number;
  }
  const PRICING: Record<string, ModelPricing> = {
    'claude-sonnet-4-6': { inputPerMTok: 3.00, outputPerMTok: 15.00, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30 },
  };
  export function calculateCost(model: string, usage: {...}): number | null
  ```
- 単価は Phase2 着手時点の Anthropic 公式値で再確認する (本プランの数値はメモであり、実装直前に検証)
- `calculateCost` は `usage` の 4 値を受け、表に無いモデルは `null` を返す
- 確認: `pricing.ts` だけ `tsx` で簡易呼び出し、`claude-sonnet-4-6` で input=1000 / output=500 → `0.003 + 0.0075 = 0.0105` USD が返ること (手計算と一致)

### Phase3 管理画面の詳細ページに表示

- `renderDetailPage` (`server/src/index.ts:245`) を拡張:
  - `meta` ブロックに「使用トークン: input X / output Y」を追加。NULL の場合は「-」
  - `cacheCreationInputTokens` / `cacheReadInputTokens` がともに 0/NULL なら表示省略、それ以外は併記
  - 「料金: $0.XXXX (model)」を `calculateCost` の結果で表示。`null` (単価不明) は「-」
- 確認: 新規レコード詳細ページに数値が出ること、Phase1 で NULL のままになっている既存レコードは「-」表示で崩れないこと

### Phase4 管理画面の一覧ページに集計表示

- `renderListPage` (`server/src/index.ts:208`) を拡張:
  - ヘッダ (`<h1>` 下) に集計サマリブロックを追加:
    - 全期間: 件数 / input トークン累計 / output トークン累計 / 料金 USD 累計
    - 当月: 同上 (`r.createdAt.startsWith(YYYY-MM)` で絞り込み)
  - テーブルに「料金」列を追加 (NULL → 「-」)
- 集計は `listStmt` の戻り値を JS で reduce する (件数上限 10,000 件なので十分)
- 確認: ブラウザで `/admin` を開き、サマリ・列が表示されること、空 DB / NULL のみ DB / 新規レコードあり、いずれでも表示が崩れないこと

### Phase5 疎通確認 (まとめ)

- `server/data/history.db` を一度退避し、まっさらな状態でも起動して `/admin` が空状態描画できること
- 既存 DB を戻して再起動 → ALTER TABLE が冪等に走ること、過去レコードが NULL 列のまま `/admin` に並ぶこと
- `curl -F image=@debug-ss/nasiogio-01.jpg http://localhost:3000/translate` を 1 件流して admin の累計が増分すること
- ログの `input_tokens=... output_tokens=...` 値と admin 詳細表示が一致すること

## 完了の定義 (DoD)

- `/admin` を開くと、ヘッダに全期間 / 当月の件数・トークン累計・料金累計が出ている
- 各履歴行に料金列が並び、新規レコードはトークン数 + USD 料金、移行前 NULL レコードは「-」で表示
- `/admin/:id` 詳細にトークン数と料金が出ている
- ALTER TABLE 後の DB が `npm run dev` 再起動を跨いで壊れない
- iOS クライアント側のレスポンス JSON 形状は不変 (アプリ側に影響しない)
