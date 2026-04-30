# TestFlight での実行

`com.akiraak.photorans` を App Store Connect に登録し、`eas build` → `eas submit` 経由で TestFlight Internal Testing で Akira さんの iPhone に配信できるようにする。

ステータス: **着手前** / 開始予定: 2026-04-30 〜

## 目的・背景

- 現状は EAS internal distribution の Dev Client (`developmentClient: true`) で動作確認済み (DONE.md Phase3-2)
- 次の到達点は **TestFlight 経由で Production ビルドの photorans を実機にインストールし、自宅外でも動かせる状態** にすること
- API は別プロジェクトで `https://photorans.chobi.me` に公開予定。クライアントはここに接続する
- Dev Client 用の LAN IP 直指定は廃止せず、Production プロファイルだけ本番 URL を指すよう切り替える

## 対応方針

1. **API URL の本番切替** — `eas.json` の `production` プロファイルに `env.EXPO_PUBLIC_API_URL=https://photorans.chobi.me` を埋め込み、ビルド時に固定する。`development` プロファイル側は `.env` から LAN IP を読む現状維持
2. **App Store Connect でアプリレコード作成** — Bundle ID `com.akiraak.photorans` を Apple Developer Portal の App ID に登録 (Dev Client 用に登録済みなら流用) し、App Store Connect で新規アプリを作成。一次言語は日本語、カテゴリは Productivity 想定
3. **EAS production プロファイル整備** — `eas.json` に `production` を追加 (`distribution: store`、`autoIncrement: true` で buildNumber 自動加算)
4. **production ビルド** — `eas build -p ios --profile production` で App Store 配布用 IPA を生成
5. **TestFlight 提出** — `eas submit -p ios --latest` で App Store Connect にアップロード。Apple の処理 (5〜30 分) 後、TestFlight タブから Internal Testing グループに配信
6. **実機確認** — iPhone の TestFlight アプリで photorans をインストールし、撮影 → `https://photorans.chobi.me/translate` → 一覧 → 詳細が通ることを確認

## 影響範囲

- `client/eas.json` — `production` プロファイル追加
- `client/app.json` — 必要なら `name` を「photorans」に変更 (現状 `client` のまま、TestFlight の表示名に影響)、`version`/`buildNumber` 運用方針を明記
- App Store Connect 側のアプリレコード (リポジトリ外、Apple Developer アカウント `akiraak@gmail.com` で作業)
- サーバ (`photorans.chobi.me`) は別プロジェクトで構築済みであることが前提 (Phase4-5 までに公開されていること)

## 未確定事項 / 前提

- サーバ `https://photorans.chobi.me` のデプロイ完了タイミングは別プロジェクト側に依存。Phase4-5 着手前に到達確認 (`curl https://photorans.chobi.me/admin` 200) する
- Apple Developer Program は登録済み前提 (Dev Client 用 EAS Build が通っているので確定済みのはず)
- アイコン / Splash は既存の Expo デフォルト (`./assets/icon.png` / `./assets/splash-icon.png`) を流用。差し替えは TestFlight で動かしてから別 TODO に切る

## テスト方針

- 各 Phase 完了時の確認内容を Phase 内に明記 (ビルド成功 / アップロード成功 / TestFlight 着信 / 実機動作)
- 最終 DoD: iPhone の TestFlight からインストールした photorans で、自宅 LAN 外 (例: モバイル回線) から撮影 → 翻訳が通る

## Phase 分解

### Phase4-1 production プロファイルと API URL 切替

- `client/eas.json` に `production` プロファイルを追加
  - `distribution: "store"`
  - `autoIncrement: true`
  - `env.EXPO_PUBLIC_API_URL=https://photorans.chobi.me`
- `npm run typecheck` パス
- 既存 `development` プロファイルが壊れていないこと (`eas build:configure` で構造確認のみ)

### Phase4-2 App Store Connect アプリレコード作成

- Apple Developer Portal で `com.akiraak.photorans` の App ID を確認 (Dev Client 配布時に登録済みなら流用)
- App Store Connect で新規アプリを作成
  - 名前: `photorans` (TestFlight 表示名)
  - 一次言語: 日本語
  - Bundle ID: `com.akiraak.photorans`
  - SKU: 任意 (`photorans-001` 等)
- TestFlight タブで Internal Testing グループ作成、Akira さんを App Store Connect Users に追加してグループに割当
- 確認: App Store Connect でアプリレコードが「準備中」で表示されること

### Phase4-3 production ビルド

- `eas build -p ios --profile production` を実行
- 初回は EAS が App Store 配布用の証明書 / Provisioning Profile を自動生成 (対話確認あり)
- ビルド成功 → IPA URL が EAS ダッシュボードに出ること

### Phase4-4 TestFlight 提出

- `eas submit -p ios --latest` で最新ビルドを App Store Connect にアップロード
- Apple のプロセシング完了通知 (メール) を待つ
- App Store Connect の TestFlight タブでビルドが「配布可能」状態になること
- Internal Testing グループに自動配信されることを確認

### Phase4-5 実機 TestFlight 動作確認

- 前提: `https://photorans.chobi.me/admin` に Linux/PC からアクセスして 200 が返ること (= サーバ稼働中)
- iPhone の TestFlight アプリで photorans をインストール
- LAN 内: 撮影 → 翻訳 → 一覧 → 詳細が通ること
- LAN 外 (モバイル回線で Wi-Fi オフ): 同じフローが通ること
- `https://photorans.chobi.me/admin` に履歴が積まれていること

## 完了の定義 (DoD)

- iPhone の TestFlight 経由でインストールした photorans が、Wi-Fi / モバイル回線どちらでも撮影 → 翻訳 → 一覧 → 詳細まで動く
- App Store Connect の TestFlight に Akira さんが Internal Tester として登録されており、以降 `eas submit` するだけで新ビルドが配信される状態
