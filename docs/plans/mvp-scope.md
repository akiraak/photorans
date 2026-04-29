# MVP スコープ (ローカル実行版・最小構成)

`docs/plans/app-spec.md` の決定事項を踏まえた、最初のマイルストーン (= ローカル実機で動かす) の実装スコープ。
**「最小構成で動かす」** ことを最優先し、アダプタ層・複数モデル切替・整形ツール類などは MVP から外す。

ステータス: **着手前** / 開始予定: 2026-04-29 〜

## ゴール

Akira さんの iPhone を Expo Dev Client で起動し、自宅 LAN 内の Linux PC 上で動かすサーバ経由で **撮影 → 文字起こし → 翻訳 → 端末側に保存・一覧** が完結する状態にする。サーバ側にも管理画面で処理履歴を確認できる。

> 本プランの範囲はアプリ実装まで。コンテナ化 / デプロイは別プロジェクト（デプロイシステム）で管理する。

## やること / やらないこと

### やる (MVP IN)

- クライアント (Expo): **2 タブ + 詳細画面の計 3 画面**
  - タブ 1: カメラ撮影画面
  - タブ 2: 写真一覧画面
  - 一覧タップで詳細画面 (写真 / 原文 / 訳文)
- サーバ:
  - 画像を受け取り、Claude Sonnet 4.6 で OCR + 英→日翻訳して JSON で返す
  - 処理履歴を保存し、ブラウザで参照できる管理画面
- Linux PC 上でサーバ (`npm run dev` 等) を起動し、API + 管理画面を提供
- LAN 内 IP 直指定でクライアントから接続

### やらない (MVP OUT — 次フェーズ以降)

- モデルアダプタ層 / Gemini 切替 (Sonnet 4.6 直叩きで先行)
- 認証・濫用対策 (LAN 内利用前提)
- コピー / シェア / TTS / ダークモード
- 利用規約 / プライバシーポリシー画面
- ストア提出向けアセット
- 外部公開トンネル / DDNS
- ESLint / Prettier / テスト整備 (動くまで優先)
- コンテナ化 / デプロイ構成 (Dockerfile, compose, CI/CD 等は別プロジェクトで管理)

## アーキテクチャ

```
[Expo Dev Client (iOS)]
   ├─ タブ 1: カメラ → POST /translate (multipart: image)
   ├─ タブ 2: 一覧 (端末ローカル DB)
   └─ 詳細: 画像 + 原文 + 訳文
        │
        ▼
[自宅 Linux PC]
   └── api (Node.js + TypeScript + Hono)
        ├── POST /translate         … OCR + 翻訳して JSON 返却 + 履歴保存
        ├── GET  /admin             … 履歴一覧 (HTML)
        └── 履歴ストア: SQLite ファイル (./data/history.db)
        ▼
[Anthropic API] (Claude Sonnet 4.6)
```

> 注: app-spec.md の「サーバで即時破棄」方針は、管理画面実装に伴い **MVP では履歴保存ありに緩和** する。LAN 内 / 個人利用前提のため許容。ストア公開フェーズで再検討。

## ディレクトリ構成

```
photorans/
├── client/         # Expo React Native アプリ
├── server/         # Node.js API + 管理画面
├── docs/plans/
├── vibeboard/
├── CLAUDE.md
├── TODO.md
└── DONE.md
```

## タスク分解

> 進め方: Phase 1 → Phase 2 → Phase 3。各タスクは TODO.md の `Phase{N}-{連番}` と対応。

### Phase 1: サーバ (server/)

1. **Phase1-1 server/ 初期化** — Node.js + TypeScript + Hono の最小セット (`package.json`, `tsconfig.json`, `src/index.ts` で hello world が動くまで)
2. **Phase1-2 `/translate` エンドポイント** — multipart 画像 1 枚を受け取り、`{ originalText, translatedText, model }` を返す
3. **Phase1-3 Claude Sonnet 4.6 呼び出し実装** — Anthropic SDK で画像入力 + OCR/翻訳プロンプトを実装
4. **Phase1-4 履歴保存 (SQLite)** — `/translate` 成功時に `id, createdAt, imagePath, originalText, translatedText` を保存
5. **Phase1-5 管理画面 `/admin`** — 履歴一覧 (新しい順) と詳細 (画像 + 原文 + 訳文) を素の HTML で表示
6. **Phase1-7 疎通確認** — ホストで `npm run dev` 起動 → `curl -F image=@sample.jpg http://localhost:3000/translate` と、ブラウザで `/admin` が見えること

> Phase1-6 (Dockerfile + docker-compose.yml) はデプロイシステム側で管理するため、本プロジェクトのスコープから外す。番号は履歴維持のため欠番のままとする。

### Phase 2: クライアント (client/)

1. **Phase2-1 Expo 初期化** — `create-expo-app` (Dev Client 構成、TypeScript)
2. **Phase2-2 ナビゲーション** — Bottom Tabs (カメラ / 一覧) + 一覧 → 詳細の Stack
3. **Phase2-3 カメラ画面** — `react-native-vision-camera` で撮影 → API 送信 → 結果を端末 DB に保存
4. **Phase2-4 写真一覧画面** — ローカル DB (expo-sqlite) から新着順で表示 (サムネイル + 訳文先頭数行)
5. **Phase2-5 詳細画面** — 写真 + 原文 + 訳文を表示
6. **Phase2-6 API クライアント** — `EXPO_PUBLIC_API_URL` で LAN IP 指定、multipart で `/translate`

### Phase 3: 統合・実機確認

1. **Phase3-1** Linux PC でサーバ起動 → LAN から `/translate` と `/admin` に到達できること
2. **Phase3-2** iPhone Dev Client で撮影 → 一覧に保存 → 詳細表示まで通ること
3. **Phase3-3** サンプル画像 5〜10 種で品質確認 (郵便 / 医療 / 契約 / 日常 / 交通案内)

## 完了の定義 (DoD)

- iPhone で英語書類を撮影 → 数秒で詳細画面に日本語訳が出る
- 一覧タブに過去の撮影が並び、タップで詳細を再表示できる
- ブラウザで `http://<LAN-IP>:3000/admin` を開くと処理履歴が見える
- 上記が 5〜10 種類の書類で成立する (品質は実用レベルであれば可)
