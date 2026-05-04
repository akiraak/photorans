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
| Debug         | http://10.0.1.137:3000                                  |
| Release       | https://synergistic-wilburn-overclean.ngrok-free.dev    |

`API_BASE_URL` は `project.yml` の Build Setting で定義し、`Info.plist` で `$(API_BASE_URL)` 参照する。アプリからは `Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL")` で取得する。

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
