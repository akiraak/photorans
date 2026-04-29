# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code (claude.ai/code) 向けのガイドです。

## プロジェクト概要

photorans は、デバイスのカメラで文字を撮影し、AI（OCR）でテキスト化したうえで翻訳するモバイルアプリです。

ユーザーの基本フロー: 写真撮影 → テキスト抽出 → 翻訳 → 結果表示

## 現状

リポジトリは実装前の段階です。`LICENSE` と仮の `README.md` のみが存在し、ソースコード、ビルド設定、テスト環境はまだありません。

未確定の項目（仮定せず、スキャフォールド前にユーザーへ確認すること）:
- 対象プラットフォーム（iOS / Android / 両方）とフレームワーク（ネイティブ、React Native、Flutter など）
- OCR の方式（オンデバイスモデル、クラウド API、または AI ビジョンモデル）
- 翻訳バックエンド（プロバイダーおよび対応言語ペア）
- 画像データを端末外に送信するかどうか（AI 呼び出しに伴うプライバシー / UX 上の影響）

技術スタックが決定したら、本セクションをビルド・実行・テストのコマンドおよびアーキテクチャ概要に置き換えること。

## 開発ワークフロー: vibeboard

タスク・プラン管理にローカル UI ツール [vibeboard](https://github.com/akiraak/vibeboard) を併用する。`vibeboard/` 自体は本リポジトリにコミット済み（`degit` で取り込み、上流追従はしない方針）。`vibeboard/node_modules/` のみ `.gitignore` で除外。

初回セットアップ（クローン後）:

```bash
cd vibeboard && npm install
```

起動（リポジトリルートから）:

```bash
node vibeboard/dist/cli.js --root .
# → http://localhost:3010
```

管理対象ファイル（無ければ初回起動時に自動生成）:
- `TODO.md` — 進行中・未着手のタスク
- `DONE.md` — 完了したタスク
- `docs/plans/` — 個別プラン / 設計メモ

Claude Code 側の運用ルール:
- 新規作業に着手する際は `TODO.md` を確認し、関連プランがあれば `docs/plans/` の該当ファイルを参照する
- 新たに発生したタスクは `TODO.md` へ追記、完了時は `DONE.md` へ移送する
- 大きめの設計判断は `docs/plans/` 配下に Markdown で残し、`TODO.md` から参照する
