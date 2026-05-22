# photorans

カメラで撮影した文字を OCR でテキスト化し、英⇄日翻訳して表示する iOS アプリ。

## 構成

- `ios/` — iOS ネイティブクライアント (Swift 6 / SwiftUI / iOS 17+)。詳細は [`ios/README.md`](ios/README.md)
- `server/` — Hono + SQLite の `/translate` API + 管理画面。Anthropic Claude を OCR / 翻訳に使用
- `vibeboard/` — タスク・プラン管理用のローカル UI ツール (`TODO.md` / `DONE.md` / `docs/plans/` を編集)
- `bitrise.yml` — CI / Release 配信 (`primary` = simulator ビルド検証 / `release` = タグ `v*` push で TestFlight 配信)

## 開発フロー

開発機は Mac (macOS)。詳細な手順・運用ルールは [`CLAUDE.md`](CLAUDE.md) を参照。
