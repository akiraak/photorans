# DONE

## 2026-04

- 2026-04-28: vibeboard をリポジトリに取り込み、`run-vibeboard.sh` と運用ルールを整備
- 2026-04-28: CLAUDE.md にプロジェクト概要と未確定項目を整理
- 2026-04-29: Phase1-1 server/ 初期化 (Node.js 22 + TypeScript + Hono の最小セット、`npm run dev` で hello world 確認)
- 2026-04-29: Phase1-2 `POST /translate` エンドポイント (multipart 画像受付 + バリデーション + `{originalText, translatedText, model}` 形式の JSON 返却。Claude 呼び出しは Phase1-3 で実装するためスタブ)
- 2026-04-29: Phase1-3 Claude Sonnet 4.6 呼び出し実装 (Anthropic SDK + base64 画像入力 + structured output で OCR/英→日翻訳。`ANTHROPIC_API_KEY` 環境変数が必要)
- 2026-04-29: Phase1-4 履歴保存 (SQLite) (`better-sqlite3` で `${DATA_DIR}/history.db` を初期化、画像本体は `${DATA_DIR}/images/<uuid>.<ext>` に保存。`/translate` 成功時に `id, createdAt, imagePath, imageMimeType, originalText, translatedText, model` を記録。保存失敗はログ出力のみで応答自体はブロックしない)
- 2026-04-29: Phase1-5 管理画面 `/admin` (`/admin` で新着順の履歴一覧、`/admin/:id` で詳細 (画像 + 原文 + 訳文)、`/admin/:id/image` で画像配信。素の HTML + 内蔵 CSS、UUID バリデーションと HTML エスケープ、不正 / 未登録 ID は 404 を返す)
- 2026-04-29: Phase1-7 疎通確認 (`npm run dev` で `tsx watch --env-file=.env` 経由で起動、`server/.env` から `ANTHROPIC_API_KEY` を読み込み、`server/.env.example` を雛形として追加。`curl -F image=@debug-ss/nasiogio-01.jpg /translate` で 200 (28.7s) → 自然な日本語訳、`/admin` 一覧 / `/admin/:id` 詳細 / `/admin/:id/image` の各 GET、バリデーション系 (image 欠落 400 / 未対応 MIME 400 / 不正 ID 404) まで確認。SQLite と画像ファイルが `server/data/` 以下に生成されることも確認)
- 2026-04-29: Phase2-2 ナビゲーション (Bottom Tabs + Stack) (`@react-navigation/native@7` + `bottom-tabs` + `native-stack` を `expo install` で導入、`react-native-screens@~4.16` / `react-native-safe-area-context@~5.6` を SDK 54 互換版で追加。`client/src/navigation/{RootNavigator,HistoryStack,types}.tsx` で Bottom Tabs (カメラ / 一覧) + 一覧→詳細 Stack を構築、`HistoryStackParamList` でルートパラメータを型付け。`App.tsx` を `SafeAreaProvider` + `NavigationContainer` でラップ。`CameraScreen` / `HistoryListScreen` / `HistoryDetailScreen` のプレースホルダを追加 (一覧→詳細はダミー id でナビゲーション可)、`tsc --noEmit` パス)
- 2026-04-29: Phase2-1 Expo 初期化 (`create-expo-app@3.5.3` の `blank-typescript` テンプレートで `client/` を作成、Expo SDK 54.0.0 / React 19.1 / RN 0.81.5 / TypeScript strict、`expo-dev-client@~6.0.21` を `expo install` で追加、`npm run start/ios/android` を `--dev-client` 付きに変更、`typecheck` スクリプト追加。`tsc --noEmit` パス、`npx expo-doctor` 17/17 通過、`expo start --dev-client` で Metro Bundler が `localhost:19000` で待機することまで確認)
