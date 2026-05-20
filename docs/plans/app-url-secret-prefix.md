# アプリ接続先の secret prefix 対応 — iOS native 側

g3plus-ops Phase1 (commit `acb3610`) で導入した `URL_SECRET` path prefix を、iOS native アプリの `API_BASE_URL` にも反映する。`URL_SECRET` 自体は **GitHub に commit せず**、ローカルは untracked xcconfig、Bitrise CI は Workspace Secret 経由で注入する。

ステータス: **着手前** / 開始予定: 2026-05-21 〜

## 目的・背景

- 現状: サーバ (`server/src/index.ts:14-22`) は `URL_SECRET` (16+ 文字、`[A-Za-z0-9_-]`) を必須化し、全ルートを `/${URL_SECRET}` 配下に mount。prefix 外は 404
- 一方で iOS アプリの `API_BASE_URL` (`ios/project.yml:24,27`) は prefix を含まず、現状は **prefix を有効化したサーバには接続できない** 状態
- TODO 該当項目:
  ```
  - [ ] アプリの接続先を変更する。XXXXXXXXXXXXは変更する
        https://photorans.chobi.me/XXXXXXXXXXXX/
        https://photorans.chobi.me/XXXXXXXXXXXX/admin
  ```
  → app 側 (`/XXXXXXXXXXXX/translate`)、admin は既に prefix で稼働中 (本タスクの対象外)

## 対応方針 (ユーザ確認済み 2026-05-20)

1. **本番ホストを ngrok → `photorans.chobi.me` に切替**
   - Release `API_BASE_URL` は `https://photorans.chobi.me/<SECRET>`
2. **Debug にも prefix を付与**
   - Debug `API_BASE_URL` は `http://10.0.1.137:3000/<SECRET>` (LAN 内ローカルサーバも同 secret 前提)
3. **secret は GitHub に上げない (正攻法)**
   - `ios/Config/Secrets.xcconfig` (untracked) に `URL_SECRET = ...` を置く
   - Build Setting 経由で `API_BASE_URL` を組み立てる
   - Bitrise の Workspace Secret に `URL_SECRET` を登録し、ビルド前 script step で `Secrets.xcconfig` を生成
4. **対応範囲は iOS native のみ**
   - `client/` (Expo) は触らない (deprecated 扱い・別タスクで判断)

## 設計: xcconfig 階層

```
ios/Config/
├── Debug.xcconfig       # tracked: API_BASE_URL = http://10.0.1.137:3000/$(URL_SECRET)
├── Release.xcconfig     # tracked: API_BASE_URL = https://photorans.chobi.me/$(URL_SECRET)
├── Secrets.xcconfig.sample  # tracked: URL_SECRET 用テンプレ
└── Secrets.xcconfig     # untracked (.gitignore): URL_SECRET = <値>
```

- `Debug.xcconfig` / `Release.xcconfig` の冒頭で `#include? "Secrets.xcconfig"` を行い、`Secrets.xcconfig` が無い環境ではビルドエラーにせず `URL_SECRET` 未定義のままにする (`?` 付き optional include)。CI / ローカル両方で `Secrets.xcconfig` が存在することを別途担保する
- `project.yml` の `targets.Photorans.configFiles` に `Debug: Config/Debug.xcconfig` / `Release: Config/Release.xcconfig` を指定
- 既存の `settings.configs.{Debug,Release}.API_BASE_URL` build setting (`project.yml:24,27`) は **削除** (xcconfig からの定義に一本化)
- `Info.plist` 側の `$(API_BASE_URL)` 展開、`TranslateAPI.swift:88-97` の Bundle 読み出しは変更不要

### 注意: build setting 優先順位

Xcode の優先順位は Target > Project > xcconfig。今回は `project.yml` に `API_BASE_URL` を書かず、xcconfig 1 箇所だけで定義することで衝突を避ける。`API_BASE_URL = .../$(URL_SECRET)` の展開は同一 xcconfig 内で完結する。

## 影響範囲

- 変更:
  - `ios/project.yml` (build setting 削除 + configFiles 追加)
  - `ios/Photorans.xcodeproj/project.pbxproj` (xcodegen 再生成)
  - `ios/Config/Debug.xcconfig`, `ios/Config/Release.xcconfig`, `ios/Config/Secrets.xcconfig.sample` (新規)
  - `.gitignore` (`ios/Config/Secrets.xcconfig` 追加)
  - `bitrise.yml` (`primary` / `release` workflow 双方の冒頭に script step 追加)
  - `ios/README.md` (API_BASE_URL 表 + secret セットアップ手順)
- 非変更:
  - `ios/Photorans/Networking/TranslateAPI.swift` (URL 連結ロジックそのまま)
  - `ios/Photorans/Info.plist` (`$(API_BASE_URL)` 展開のまま)
  - server, client (Expo), 既存 admin 経路

## テスト方針

- **ローカル (Debug)**:
  1. `server/.env` の `URL_SECRET` と `ios/Config/Secrets.xcconfig` の `URL_SECRET` を一致させる
  2. `./server.sh` で server 起動 → `curl http://10.0.1.137:3000/$URL_SECRET/` が 200、prefix 無しが 404 になることを確認
  3. WSL2 から xcodegen 再生成 → Bitrise primary Workflow で simulator ビルドが通ることを確認 (ローカルに Xcode が無いため CI 経由)
- **TestFlight (Release)**:
  - Akira さん依頼でタグ push → TestFlight 配信 → 実機 photorans アプリで撮影 → `https://photorans.chobi.me/<SECRET>/translate` 経由で OCR + 翻訳が成功することを確認
- **回帰**:
  - admin (`https://photorans.chobi.me/<SECRET>/admin`) にブラウザでアクセスし、新規 `/translate` 投入分が一覧に出ることを確認

## Phase / Step

### Phase1: xcconfig 構造の追加 (tracked 部分)
- Step1-1: `ios/Config/Debug.xcconfig` 新規 (`#include? "Secrets.xcconfig"` + `API_BASE_URL = http://10.0.1.137:3000/$(URL_SECRET)`)
- Step1-2: `ios/Config/Release.xcconfig` 新規 (同構造で `https://photorans.chobi.me/$(URL_SECRET)`)
- Step1-3: `ios/Config/Secrets.xcconfig.sample` 新規 (`URL_SECRET = <16+ chars, [A-Za-z0-9_-]>` のテンプレ + 取得元コメント)
- Step1-4: `.gitignore` に `ios/Config/Secrets.xcconfig` を追加

### Phase2: project.yml 改修 + xcodegen 再生成
- Step2-1: `ios/project.yml` の `settings.configs.Debug.API_BASE_URL` / `settings.configs.Release.API_BASE_URL` を削除
- Step2-2: `ios/project.yml` の `targets.Photorans` に `configFiles: { Debug: Config/Debug.xcconfig, Release: Config/Release.xcconfig }` を追加
- Step2-3: WSL2 上で `cd ios && xcodegen generate` 実行 → `Photorans.xcodeproj/project.pbxproj` の差分を確認
- Step2-4: 生成された pbxproj に `baseConfigurationReference` (Debug/Release それぞれ Config/*.xcconfig 指していること) と `API_BASE_URL` build setting が消えていることを確認

### Phase3: ローカル動作確認 (Debug)
- Step3-1: `ios/Config/Secrets.xcconfig` を作成 (`URL_SECRET` = `server/.env` と同値)
- Step3-2: `./server.sh` 起動 → `curl http://10.0.1.137:3000/$URL_SECRET/` が `photorans server: hello`、`curl http://10.0.1.137:3000/` が 404 を確認
- Step3-3: Bitrise primary Workflow を手動起動し simulator ビルドが通ることを確認 (Secrets.xcconfig 注入は Phase4 で対応するため、この時点では Step4-1 完了が前提)

### Phase4: Bitrise CI 対応
- Step4-1: Akira さんに依頼: Bitrise の Workspace Secret に `URL_SECRET=<値>` を登録 (sensitive チェック ON、Expose for Pull Requests OFF)
- Step4-2: `bitrise.yml` の `primary` / `release` 両 Workflow の `git-clone@8` 直後に script step を追加し、`$URL_SECRET` から `ios/Config/Secrets.xcconfig` を生成:
  ```yaml
  - script@1:
      title: Generate ios/Config/Secrets.xcconfig
      inputs:
      - content: |-
          #!/usr/bin/env bash
          set -euo pipefail
          : "${URL_SECRET:?URL_SECRET env not set in Bitrise Secrets}"
          mkdir -p ios/Config
          printf 'URL_SECRET = %s\n' "$URL_SECRET" > ios/Config/Secrets.xcconfig
  ```
- Step4-3: 検証: `primary` Workflow を一度手動起動し、simulator ビルドが通ることを確認 (= xcconfig が正しく注入されている)

### Phase5: 実機確認 (Release / TestFlight)
- Step5-1: Akira さんの確認を取った上で annotated tag (`v0.1.X`) を push し、`release` Workflow を起動 (タグ命名規約は CLAUDE.md 準拠)
- Step5-2: App Store Connect → TestFlight → 実機で photorans アプリ起動 → 撮影 → 結果表示が正常であることを Akira さんに確認依頼
- Step5-3: ブラウザで `https://photorans.chobi.me/<SECRET>/admin` を開き、Step5-2 で投入した履歴が出ていることを確認

### Phase6: ドキュメント更新
- Step6-1: `ios/README.md` の `API_BASE_URL` 表を新値 (Debug: `http://10.0.1.137:3000/<URL_SECRET>`、Release: `https://photorans.chobi.me/<URL_SECRET>`) に差し替え
- Step6-2: `ios/README.md` に「ローカル開発時の Secrets.xcconfig セットアップ手順」セクションを追加 (`cp Config/Secrets.xcconfig.sample Config/Secrets.xcconfig` → server と同値の URL_SECRET を記入)
- Step6-3: Bitrise の Workspace Secret 登録手順を README または `docs/` に明記
- Step6-4: 親 TODO を `DONE.md` に移送、本プランファイルを `docs/plans/archive/` に移動

## オープン項目

- `photorans.chobi.me` の TLS / 到達性確認: Phase5 前に Akira さん側で `curl -I https://photorans.chobi.me/<SECRET>/` が 200 を返すこと
- `Secrets.xcconfig` を CI で生成する際に Bitrise log に値が表示されないこと (Bitrise の Secret は自動マスクされる前提だが、script step では echo しない)
- ローカルで `xcodegen generate` 後に Xcode を一度も開いていない状態で Bitrise ビルドが通るかは未検証 (これまでも同様の運用なので問題ない見込み)
