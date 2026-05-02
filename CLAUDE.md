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
- 作業着手前のプラン作成や、TODO / DONE の更新手順の詳細は次節「作業着手ルール」に従う

## Bitrise 用語

本リポジトリの CI は Bitrise を利用する。Bitrise UI の階層は **Workspace > Project** であり、`photorans` は Project 名。

- **App という呼称は使わない**（Bitrise UI には存在しない概念）。Claude Code は説明・案内文で必ず "Project" / "Workspace" を使うこと
- 設定の置き場所も同様: `Project settings`、`Workspace settings`。`App settings` という言い方はしない

## 実機確認ルート (TestFlight)

iOS の実機リグレッション確認は **TestFlight 経由でのみ実施可能**。Akira さんの開発機は WSL2 (Linux) であり、Xcode で直接 iPhone にインストールする経路は無いので、すべてのデバイス検証はタグ push → Bitrise → TestFlight を通る。

配信フロー:

1. **タグ作成 & push**: main 上で annotated tag を切る (`git tag -a v0.1.X -m "<対応 commit の subject>"`) → `git push origin v0.1.X`。タグ命名は patch インクリメント (`v0.1.0` 起点、最新タグは `git tag --sort=-creatordate -l 'v*' | head -1` で確認)
2. **Bitrise 自動起動**: `bitrise.yml` の `trigger_map: tag: v*` が `release` Workflow を起動。`xcode-archive@6` (Release configuration、API Key 自動署名) → `deploy-to-itunesconnect-application-loader@1` で App Store Connect にアップロード
3. **App Store Connect 処理 (数分〜30 分)**: Apple 側のプロセシング完了で Akira さんにメール通知。TestFlight タブでビルドが「配布可能」になる
4. **TestFlight 配信**: Internal Testing グループに自動配信、iPhone の TestFlight アプリで最新ビルドが出る
5. **Akira さんが実機で確認 → 結果を Claude Code に共有 (OK / NG)**

バージョン体系:
- `MARKETING_VERSION` (`ios/project.yml`) は `0.1.0` 固定 (現状)
- ビルド番号 (`CURRENT_PROJECT_VERSION`) は Bitrise が `$BITRISE_BUILD_NUMBER` を xcconfig override で都度注入
- タグはマーケティングバージョンとは独立に patch インクリメントしているだけのリリース印

Claude Code 側の運用:
- 実機リグレッションが必要な変更が main に入ったら、タグ push は **Akira さんの確認を取った上で** 行う (Bitrise クレジット消費 + TestFlight に外部影響が出るため、勝手に push しない)
- タグメッセージは対応 commit の 1 行 subject を流用する
- Akira さんの実機確認結果が返るまで、関連 TODO の Phase / Step を完了 (`[x]`) に変えない

## 作業着手ルール

作業（実装・調査いずれも）を始めるときは、コードに手を入れる前に以下を行う。

1. **プランファイルを作成する**: `docs/plans/<task-name>.md` に実装プラン or 調査プランを作成する
   - 目的・背景、対応方針、影響範囲、テスト方針を最低限記載する
   - 複数 Phase / Step に分かれる場合はファイル内でも Phase / Step を明示する
2. **`TODO.md` に該当項目があるか確認する**
   - 無ければ適切なセクションに追加する
   - 既存項目があれば、その項目に作成したプランファイルへのリンクを追記する（例: `[plan](docs/plans/<task-name>.md)`）
3. **複数 Phase / Step がある場合は `TODO.md` に子タスクとして追加する**
   - 親項目の下にインデントしたチェックボックスで Phase / Step を列挙する
   - Phase / Step が完了するごとにチェックを入れ、全完了で親項目を `DONE.md` に移す
4. **作業完了時の後片付け**
   - 親タスクを `DONE.md` に移動する
   - 対応するプランファイルは `docs/plans/archive/` に移動する
