# DONE

## 2026-04

- 2026-04-28: vibeboard をリポジトリに取り込み、`run-vibeboard.sh` と運用ルールを整備
- 2026-04-28: CLAUDE.md にプロジェクト概要と未確定項目を整理
- 2026-04-29: Phase1-1 server/ 初期化 (Node.js 22 + TypeScript + Hono の最小セット、`npm run dev` で hello world 確認)
- 2026-04-29: Phase1-2 `POST /translate` エンドポイント (multipart 画像受付 + バリデーション + `{originalText, translatedText, model}` 形式の JSON 返却。Claude 呼び出しは Phase1-3 で実装するためスタブ)
- 2026-04-29: Phase1-3 Claude Sonnet 4.6 呼び出し実装 (Anthropic SDK + base64 画像入力 + structured output で OCR/英→日翻訳。`ANTHROPIC_API_KEY` 環境変数が必要)
