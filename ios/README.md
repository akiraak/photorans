# Photorans iOS

Swift 6 / SwiftUI / iOS 17+ で実装するネイティブ iOS クライアント。

## プロジェクト生成

`Photorans.xcodeproj` は [XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成する。**生成物は git 管理する** (Bitrise との接続を安全に通すため)。`project.yml` を変更したら下記手順で再生成し、生成物の差分も合わせてコミットする。

### WSL2 / Linux で再生成 (本リポジトリの主要環境)

WSL2 Ubuntu 上では Apple SDK が無くても XcodeGen 自体はビルドできる。Swift toolchain (Linux) を使ってソースビルドし、生成された `xcodegen` バイナリを `~/.local/bin/` 等に置く。

```bash
# 1. Swift toolchain (一度だけ)
#    swiftly で ~/.local/share/swiftly/ に Swift 6.x を導入
curl -O https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz
mkdir -p /tmp/swiftly && tar -xzf swiftly-$(uname -m).tar.gz -C /tmp/swiftly
/tmp/swiftly/swiftly init --assume-yes
. ~/.local/share/swiftly/env.sh

# 2. XcodeGen ソースビルド (一度だけ)
git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen
cd /tmp/XcodeGen && swift build -c release
install -m 0755 .build/release/xcodegen ~/.local/bin/xcodegen
xcodegen --version

# 3. .xcodeproj 生成 (project.yml を編集したら毎回)
cd <repo>/ios
xcodegen generate
```

### macOS で再生成 (任意)

```bash
brew install xcodegen
cd ios
xcodegen generate
open Photorans.xcodeproj
```

## ビルド

WSL2 上では `xcodebuild` は走らせられないため、ビルド・実機確認は Bitrise (`bitrise.yml` の `primary` Workflow) を介して行う。

| Configuration | `API_BASE_URL`                                          |
| ------------- | ------------------------------------------------------- |
| Debug         | http://10.0.1.221:3000                                  |
| Release       | https://synergistic-wilburn-overclean.ngrok-free.dev    |

`API_BASE_URL` は `Config/Debug.xcconfig` / `Config/Release.xcconfig` で定義 (URL_SECRET 注入は `Config/Secrets.xcconfig`、ローカルは untracked、CI は Bitrise Workspace Secret から `bitrise.yml` の script step で生成)。`Info.plist` で `$(API_BASE_URL)` 参照する。アプリからは `Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL")` で取得する。

### Mac でローカル動作確認

Mac 開発機 + Akira さんの iPhone が同一 LAN にあれば、Bitrise / TestFlight を経由せず直接 Debug ビルドを動かせる。

前提:
- Xcode (`xcodebuild -version` で 26.x 以降)
- `brew install xcodegen`
- `cp Config/Secrets.xcconfig.sample Config/Secrets.xcconfig` → `URL_SECRET` を `server/.env` と同値で書き込む
- Mac の LAN IP が `Config/Debug.xcconfig` / `Photorans/Info.plist` の `NSExceptionDomains` と一致 (`ifconfig | grep "inet "` で確認、DHCP 変動時は両方更新 + xcodegen 再生成)
- リポジトリルートで `./server.sh` を起動済み

Simulator ビルド + 起動:

```bash
cd ios
xcodebuild -project Photorans.xcodeproj -scheme Photorans -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/photorans-dd build

SIM_ID=$(xcrun simctl list devices available | awk '/iPhone 17 \(/ {gsub(/[()]/,"",$3); print $3; exit}')
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" /tmp/photorans-dd/Build/Products/Debug-iphonesimulator/Photorans.app
xcrun simctl launch "$SIM_ID" com.akiraak.photorans
```

Simulator にはカメラが無いため、撮影 → OCR → 翻訳のフルパス疎通は実機 (下記) で確認する。

実機 USB Run (Akira さんの iPhone):

1. Lightning / USB-C ケーブルで Mac に接続、iPhone 側で「このコンピュータを信頼」を承認 (初回のみ)
2. Xcode で `ios/Photorans.xcodeproj` を開く
3. 上部ターゲット選択で接続中の iPhone を選ぶ
4. `Photorans` ターゲット → Signing & Capabilities で Team を Apple Developer アカウントに設定 (自動署名)
5. ⌘R で Run → 実機にインストールされ自動起動
6. 起動後、撮影 → OCR → 翻訳が成功すること、admin (`http://<MAC_IP>:3000/<URL_SECRET>/admin` をブラウザで開く) に履歴が出ることを確認

疎通失敗時の切り分け:
- 404 → `URL_SECRET` が server と xcconfig で不一致 / xcconfig が pbxproj から参照されていない (`/usr/libexec/PlistBuddy -c "Print :API_BASE_URL" <built-app>/Info.plist` で展開値を確認)
- timeout / unreachable → Mac LAN IP が `Debug.xcconfig` / `NSExceptionDomains` と不一致、別 LAN、Mac firewall

## ディレクトリ

```
ios/
├── project.yml             # XcodeGen 入力
├── Photorans.xcodeproj/    # XcodeGen 生成物 (git 管理、xcuserdata 除く)
├── Photorans/              # アプリ本体
│   ├── PhotoransApp.swift
│   ├── RootView.swift
│   └── Info.plist
└── PhotoransTests/         # 単体テスト
    └── PhotoransTests.swift
```

詳細プラン: [`docs/plans/ios-native-rewrite.md`](../docs/plans/ios-native-rewrite.md)
