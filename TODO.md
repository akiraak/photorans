# TODO

## 進行中

- [ ] アプリの仕様を決める — プラン: [docs/plans/app-spec.md](docs/plans/app-spec.md) (主要項目は確定、残り Q20/Q21 は MVP 着手前に最終確認)

## MVP (ローカル実行版・最小構成) — プラン: [docs/plans/mvp-scope.md](docs/plans/mvp-scope.md)

### Phase 1 - サーバ (server/)

- [ ] Phase1-6 Dockerfile + docker-compose.yml
- [ ] Phase1-7 curl とブラウザで疎通確認

### Phase 2 - クライアント (client/)

- [ ] Phase2-1 Expo 初期化 (Dev Client / TypeScript)
- [ ] Phase2-2 ナビゲーション (Bottom Tabs + Stack)
- [ ] Phase2-3 カメラ画面 (撮影 → API 送信 → ローカル DB 保存)
- [ ] Phase2-4 写真一覧画面 (expo-sqlite から新着順)
- [ ] Phase2-5 詳細画面 (写真 + 原文 + 訳文)
- [ ] Phase2-6 API クライアント (`EXPO_PUBLIC_API_URL` で LAN IP)

### Phase 3 - 統合・実機確認

- [ ] Phase3-1 docker compose up → LAN から `/translate` と `/admin` 到達
- [ ] Phase3-2 iPhone Dev Client で撮影 → 一覧 → 詳細まで通す
- [ ] Phase3-3 サンプル画像 5〜10 種で品質確認

## 次フェーズ候補 (MVP 完了後)

- モデルアダプタ層 + Gemini 2.5 Flash 切替
- コピー / シェア / TTS
- ダークモード
- 利用規約 / プライバシーポリシー画面
- 外部公開用トンネル (Cloudflare Tunnel / Tailscale Funnel)
- App Attest / Play Integrity でのリクエスト検証
- サーバ側の履歴削除ポリシー / 即時破棄モードへの切替
- ストア提出向けアセット
