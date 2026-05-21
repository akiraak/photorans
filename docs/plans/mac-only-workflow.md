# Expo 撤去 + Mac 単独運用への移行

開発機を WSL2 (Linux) から Mac (macOS) に切り替え、Expo (`client/`) を完全に撤去して iOS native 単体構成にする。これにより Mac の Xcode でローカル simulator / 実機ビルドが直接可能になり、xcodegen 再生成も Linux ソースビルド経由ではなく Homebrew で完結する。Bitrise / TestFlight 経路は配信用として維持する。

ステータス: **着手前** / 開始予定: 2026-05-21 〜

## 目的・背景

- 現状の二重構成:
  - `client/` — Expo (React Native) 実装。`expo-dev-client` + EAS ビルド前提。`app-url-secret-prefix.md` で **deprecated 扱い** と明記、`expo` `expo-sqlite` `expo-crypto` 等を依存に含むが本番リリース対象外
  - `ios/` — Swift 6 / SwiftUI / iOS 17+ のネイティブ実装。Bitrise + TestFlight の本流
- 現状の WSL2 制約 (CLAUDE.md):
  - Xcode が無いため、xcodegen は Swift Linux toolchain でソースビルド
  - ローカル `xcodebuild` 不可、実機インストール経路無し → 実機リグレッションは **TestFlight 経由でのみ可能**
  - server / vibeboard / Bitrise トリガは WSL2 で完結するが、iOS ビルド検証は毎回 Bitrise クレジット消費
- 移行後 (Mac 単独運用):
  - Mac で `brew install xcodegen` → `xcodegen generate` → Xcode 起動 → simulator / 実機ビルド即時可能
  - 開発フェーズの実機確認が TestFlight 経由不要になり、Bitrise は **Release 配信専用** に役割を絞れる
  - Expo / EAS / `expo-dev-client` 等の依存とビルド経路を完全に廃止

## 対応方針 (ユーザ確認済み 2026-05-20)

1. **`client/` を git rm で完全削除** (archive 化はしない / 履歴は git log から参照可能)
   - `client/`、`client-dev.sh`、関連 `.gitignore` エントリ、ドキュメント参照を一括除去
2. **Mac 開発環境セットアップ手順を新規整備**
   - `brew` 経由の xcodegen、`Secrets.xcconfig` 配置、`./server.sh` 起動、simulator / 実機ビルド手順
3. **`server.sh` の Mac 互換化**
   - 現状 `fuser` (Linux only) でポート開放 → Mac で動かないため `lsof -ti:PORT | xargs kill` 系に置換 (Linux でも動く形に揃える)
4. **ドキュメント刷新**
   - `CLAUDE.md` の WSL2 前提記述を Mac 主軸に書き換え (TestFlight 経由「のみ」→「配信用」)
   - `ios/README.md` の xcodegen 手順を Mac 主軸、WSL2 は補助として残す (将来再度 Linux に戻る場合の備忘)
5. **Bitrise / TestFlight 経路は維持**
   - `bitrise.yml` の `primary` (simulator ビルド) / `release` (TestFlight アップロード) はそのまま
   - 実機リグレッションは「Mac でローカル install」を一次手段、「TestFlight」を最終配信前確認、と二段構成に整理

## 前提 / 他プランとの依存

- **`app-url-secret-prefix.md` Phase2 (project.yml の `API_BASE_URL` build setting 削除 + `configFiles` 追加 + xcodegen 再生成) が、本プランの Phase4 (疎通) より先に完了している必要がある**
  - 現状 `ios/project.yml:24,27` は `API_BASE_URL` を build setting で直書きしており、`Secrets.xcconfig` 中の `URL_SECRET` は参照されない
  - この状態で本プラン Phase4 を実行しても、アプリは `http://<IP>:3000/translate` を叩く一方 server は `/${URL_SECRET}/translate` でしか応答せず **404 になる**
  - 推奨実施順: 本プラン Phase1〜3 → `app-url-secret-prefix.md` Phase2〜3 → 本プラン Phase4〜6

- **Mac の LAN IP が旧 WSL2 ホスト (`10.0.1.137`) と異なる**
  - 本プラン着手時点で `ifconfig` で確認した Mac の IP は `10.0.1.221` (DHCP のため変動の可能性あり)
  - 旧 IP `10.0.1.137` は次の箇所にハードコードされており、Mac 単独運用に切り替える際に **全て実 IP へ置換が必要** (Phase3-6 で実施):
    - `ios/project.yml:24` (Debug `API_BASE_URL`)
    - `ios/Config/Debug.xcconfig:3`
    - `ios/Photorans/Info.plist` の `NSExceptionDomains` (ATS の HTTP 許可ホスト)
    - `ios/README.md:47` (Debug 表)

## 影響範囲

- 削除:
  - `client/` ディレクトリ一式 (App.tsx, index.ts, package.json, package-lock.json, app.json, eas.json, tsconfig.json, src/, assets/)
  - `client-dev.sh` (Expo 起動スクリプト)
- 変更:
  - `.gitignore` — `client/` 関連エントリがあれば除去 (現状 `.gitignore` には `server/node_modules/` 等のみで client 直接記述は無いが念のため確認)
  - `server.sh` — `fuser -s/-k -TERM PORT/tcp` 用法 (util-linux 固有) を `lsof -ti:PORT | xargs kill` 系へ置換 (Mac の BSD fuser はオプション `[-cfu]` のみで再現不可、Linux でも動く形に揃える)
  - `ios/project.yml` — Debug `API_BASE_URL` 内の旧 IP `10.0.1.137` を Mac の実 IP へ置換 (`app-url-secret-prefix.md` Phase2 で xcconfig 化される前 / 後どちらの段階でも整合させる)
  - `ios/Config/Debug.xcconfig` — 旧 IP `10.0.1.137` を Mac の実 IP へ置換
  - `ios/Photorans/Info.plist` — `NSExceptionDomains` の `10.0.1.137` を Mac の実 IP へ置換 (HTTP 通信の ATS 例外)
  - `CLAUDE.md` — WSL2 関連記述を Mac 主軸に刷新、TestFlight 節を「配信前確認」位置付けへ書き直し
  - `ios/README.md` — xcodegen 手順を `brew install xcodegen` 主軸に、WSL2 補足は短縮して維持。`API_BASE_URL` 表の Debug 行も実 IP へ更新
  - `bitrise.yml` — `primary` workflow の description「.xcodeproj は WSL2 上の XcodeGen Linux ビルドで再生成する想定で」を Mac 主軸の文言へ更新 (workflow ステップ構成自体は非変更)
  - `README.md` — 必要に応じてプロジェクト構成記述を最新化 (現状 2 行のみなので最小調整)
- 非変更:
  - `ios/` 配下のソース (Photorans/, PhotoransTests/, Photorans.xcodeproj/)
  - `bitrise.yml` の workflow ステップ構成 (description 文言のみ更新)
  - `server/`, `vibeboard/`, `ngrok.sh`, `run-vibeboard.sh`
  - Bitrise Workspace / Project 設定、Apple Developer / App Store Connect 構成

## テスト方針

- **ローカル (Mac)**:
  1. リポジトリを Mac で clone (もしくは既存の WSL2 リポジトリを移送)
  2. `brew install xcodegen` → `cd ios && xcodegen generate` で pbxproj に差分が出ない (= 既存生成物と等価、IP 置換コミット後の状態) ことを確認
  3. `Secrets.xcconfig` を `server/.env` と同値の `URL_SECRET` で配置 (現状の `app-url-secret-prefix.md` Phase1 で導入済み構造前提)
  4. `./server.sh` で server 起動 → ポート開放処理が `fuser` (BSD / util-linux) 非依存で動作することを確認 (Mac + Linux 両方で smoke test)
  5. Xcode で `Photorans.xcodeproj` 起動 → simulator (iPhone 15 等) で Debug ビルド成功 → 撮影 → `/translate` 疎通 (※ `app-url-secret-prefix.md` Phase2-3 完了済みであること)
  6. 開発機 iPhone (Akira さんの実機) を USB 接続 → Xcode から Run で Debug ビルド直接インストール → 撮影フロー疎通
- **Bitrise (回帰)**:
  - 任意の no-op commit を main に push → Bitrise `primary` Workflow を手動起動し、simulator ビルドが従来通り通ることを確認
  - 実機リグレッションが必要な変更が main に入ったタイミングで通常通り tag push → `release` Workflow → TestFlight 配信できることを確認 (このプラン単体ではタグ push しない)
- **回帰 (server)**:
  - WSL2 環境 (移行過渡期) で `./server.sh` を実行し、`fuser` 廃止後も既存挙動 (起動済みプロセスのポート開放) が崩れていないことを確認

## Phase / Step

### Phase1: `client/` 関連の完全削除
- Step1-1: `git rm -r client/` で Expo 実装一式を削除
- Step1-2: `git rm client-dev.sh` で Expo 起動スクリプトを削除
- Step1-3: `.gitignore` を再確認し、`client/` 関連の除外行があれば削除 (`client/node_modules/` 等)
- Step1-4: リポジトリ全体に `grep -rEn 'client/|expo|Expo|EAS|eas\.' .` をかけ、ドキュメント / スクリプトに残る Expo 参照を洗い出し (`CLAUDE.md` / `README.md` / `docs/plans/` / `docs/plans/archive/` 内のヒットは Phase4-5 で個別対応するためここではリスト化のみ)
- Step1-5: 削除コミット (commit message 例: `Expo (client/) 一式を撤去`)

### Phase2: `server.sh` の Mac 互換化
- 補足: Mac にも `/usr/bin/fuser` (POSIX BSD-style) は存在するがオプションが `[-cfu]` のみで、現 `server.sh` が使う `-s` / `-k -TERM` / `PORT/tcp` 表記は util-linux 固有のため再現不可。`lsof` ベースなら Mac / Linux 双方で動く
- Step2-1: `server.sh` の `fuser`/`fuser -k` ブロックを `lsof -ti:"${PORT}" | xargs -r kill -TERM` → ループ wait → 残れば `kill -KILL` の形に書き換え (`xargs -r` は Mac の BSD xargs では非対応のため、空入力対策は `pids=$(lsof -ti:"${PORT}")` → `[ -n "$pids" ] && kill -TERM $pids` 形にする)
- Step2-2: 動作確認:
  - Mac: `npm run dev` 起動中の状態で別ターミナルから `./server.sh` 実行 → 既存プロセス kill → 新規 dev サーバ起動を確認
  - Linux (WSL2 過渡期): 同 smoke test → fuser 廃止後も同等挙動を確認
- Step2-3: 単独コミット (`server.sh: ポート開放処理を lsof ベースに置換 (Mac 対応)`)

### Phase3: Mac 開発環境セットアップ手順整備 + 実 IP 反映
- Step3-1: Mac (Akira さん) に Homebrew が無ければ導入 (`https://brew.sh`)
- Step3-2: `brew install xcodegen` → `xcodegen --version` 確認
- Step3-3: Apple Developer アカウントで Xcode を起動し、Signing Team を設定 (`com.akiraak.photorans` の自動署名)
- Step3-4: `Secrets.xcconfig` を `cp ios/Config/Secrets.xcconfig.sample ios/Config/Secrets.xcconfig` で生成し、`server/.env` と同値の `URL_SECRET` を記入 (※ `app-url-secret-prefix.md` Phase1 完了前提)
- Step3-5: Mac の LAN IP を確認 (`ifconfig | grep "inet " | grep -v 127.0.0.1`、参考値 `10.0.1.221`)。以下 4 箇所の `10.0.1.137` を実 IP に置換:
  - `ios/project.yml:24` (Debug `API_BASE_URL`)
  - `ios/Config/Debug.xcconfig:3`
  - `ios/Photorans/Info.plist` の `NSExceptionDomains` キー
  - `ios/README.md:47` (Debug 表の URL)
- Step3-6: `cd ios && xcodegen generate` → 生成された pbxproj の `API_BASE_URL` 行も新 IP に置き換わっていることを確認 (この段階では `app-url-secret-prefix.md` Phase2 がまだ未着手なら `API_BASE_URL` は build setting のままで OK、Phase2 完了後は xcconfig 経由になる)
- Step3-7: IP 置換 + xcodegen 再生成のコミット (`Mac LAN IP に合わせて Debug API_BASE_URL / NSExceptionDomains を更新`)

### Phase4: ローカルビルド検証 (Mac) ※前提: `app-url-secret-prefix.md` Phase2-3 が完了している
- Step4-1: Xcode で `ios/Photorans.xcodeproj` 起動 → Debug + iPhone 15 simulator で Run、起動成功 (`API_BASE_URL = http://<MAC_IP>:3000/<URL_SECRET>` 想定で server 未起動なら起動)
- Step4-2: 撮影 → OCR → 翻訳のフルパスを simulator 上で 1 件成功させ、admin (`http://<MAC_IP>:3000/<SECRET>/admin`) に履歴が出ることを確認
- Step4-3: Akira さんの iPhone を USB 接続 (初回は端末側「このコンピュータを信頼」を承認) → Xcode で Run → 実機に Debug ビルド直接インストールして起動を確認
- Step4-4: 実機からも撮影フローが成功することを確認 (LAN 内の `<MAC_IP>:3000` に到達できる前提)
- Step4-5: 疎通失敗時の切り分けポイント (参考):
  - 404 → `URL_SECRET` 不一致 or `app-url-secret-prefix.md` Phase2 未完 (pbxproj に xcconfig 参照が無い)
  - timeout / unreachable → IP 不一致、Mac firewall、別 LAN、または `NSExceptionDomains` 旧 IP のまま (ATS で HTTPS 強制 → HTTP 拒否)

### Phase5: ドキュメント刷新
- Step5-1: `ios/README.md`:
  - 「### macOS で再生成」セクションを冒頭に昇格、主手順として詳細化 (`brew install xcodegen` → `xcodegen generate` → `open Photorans.xcodeproj`)
  - 「### WSL2 / Linux で再生成」セクションは末尾に短縮して残す (将来 Linux に戻る場合の備忘)
  - 「## ビルド」セクションの「WSL2 上では `xcodebuild` は走らせられない」記述を「Mac ではローカルビルドが主、Bitrise は CI / 配信用」に書き換え
  - Mac 開発環境の前提条件 (Xcode / Homebrew / Apple Developer 署名 / Secrets.xcconfig) を 1 セクションで明文化
  - `API_BASE_URL` 表の Debug 行を Step3-5 で置換した実 IP に整合
- Step5-2: `CLAUDE.md`:
  - 「## 実機確認ルート (TestFlight)」の「TestFlight 経由でのみ実施可能」「Akira さんの開発機は WSL2 (Linux) であり」記述を「Mac (macOS) で開発する前提。Debug の実機確認は Xcode から直接、Release 配信は TestFlight 経由」へ書き直し
  - タグ push → Bitrise → TestFlight の手順自体は維持 (Release 配信用)
  - Expo / `client/` 関連の言及があれば除去 (現状 CLAUDE.md には直接無し、念のため確認)
- Step5-3: `bitrise.yml` の `primary` workflow `description` 内の「.xcodeproj は WSL2 上の XcodeGen Linux ビルドで再生成する想定で、CI 側では生成ステップを持たない。」を「.xcodeproj は Mac で `brew install xcodegen` → `xcodegen generate` により再生成し commit する。CI 側では生成ステップを持たない。」に更新 (workflow ステップ自体は触らない)
- Step5-4: `README.md` を最新化 (現状 2 行のみ。プロジェクト構成 / セットアップ手順への簡単なリンクを追加する程度に留める)
- Step5-5: `docs/plans/archive/` 配下の歴史的プランは内容を書き換えない (アーカイブの整合性維持)。ただし `docs/plans/app-url-secret-prefix.md` 内の「`client/` (Expo) は触らない (deprecated 扱い・別タスクで判断)」記述は本タスクで決着がついたため、適切なコメント追記 or 触らず放置を判断 (アクティブ plan 側を改変しない方が後段の Phase 進行と干渉しないため、原則 **触らない**)

### Phase6: 全体疎通確認 + 後片付け
- Step6-1: Bitrise `primary` Workflow を Web UI から手動起動し、`client/` 削除後も simulator ビルドが通ることを確認 (CI 設定が `ios/` 単独構成で機能していることの検証)
- Step6-2: `TODO.md` の親項目「Expo 使わずに Mac のみで運用できるようにする」を `DONE.md` に移送 (CLAUDE.md「作業着手ルール 4」)
- Step6-3: 本プランファイルを `docs/plans/archive/mac-only-workflow.md` に移動

## オープン項目

- **Apple Developer 自動署名の前提**: Bitrise は API Key 認証で自動署名済み。Mac ローカルでの自動署名 (Xcode の "Automatically manage signing") を有効化する際、同じ Apple ID / Team に紐付ける必要あり。Akira さんが Mac で Apple ID にサインイン済み + Xcode で Team 選択可能なことを Phase3 前に確認
- **EAS プロジェクトの後始末**: `client/app.json` の `extra.eas.projectId` (`f048f995-ca0e-4708-b37c-8ff6a9d89cb2`) は Expo 側に残り続ける。本リポジトリの範囲外だが、Akira さんが Expo dashboard から手動でプロジェクト削除するかは別途判断 (削除しなくても課金 / セキュリティ影響は無い見込み)
- **LAN ポリシー**: Mac 開発機 ↔ Akira さんの iPhone が同一 LAN (Mac の実 IP `10.0.1.0/24` 帯 / 着手時点では `10.0.1.221` を確認) 上で `<MAC_IP>:3000` に到達できること。違うネットワークの場合 Phase4-3 / Phase4-4 は ngrok 経由に切り替える必要あり (現状 Release 用 ngrok と兼用は混乱を招くため、Debug 用には別ホスト or 別経路を別途検討)
- **DHCP による IP 変動**: Mac の LAN IP が DHCP 割当の場合、ルータ再起動などで変わると `Debug.xcconfig` / `Info.plist` / `project.yml` の追従が毎回必要。ルータ側で MAC アドレス固定 IP の割当を行うか、`mDNS` (`<hostname>.local`) ベースで `API_BASE_URL` を設計する選択肢を別途検討
- **Bitrise `primary` Workflow の今後**: Mac でローカル simulator ビルドが日常的に可能になると、`primary` の存在意義が減る (主に PR 前の CI チェック用途に縮退)。撤去するかは Phase6 完了後に別タスクとして判断
