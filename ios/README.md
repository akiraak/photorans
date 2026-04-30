# Photorans iOS

Swift 6 / SwiftUI / iOS 17+ で実装するネイティブ iOS クライアント。

## プロジェクト生成

`.xcodeproj` は git 管理せず、[XcodeGen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から都度生成する。

```bash
# 初回のみ (macOS)
brew install xcodegen

# 生成 (ios ディレクトリで実行)
cd ios
xcodegen generate
open Photorans.xcodeproj
```

WSL2 上ではビルド・生成は行わない。CI (Bitrise) 上で `xcodegen generate` → `xcodebuild` を回す。

## ビルド構成

| Configuration | `API_BASE_URL`             |
| ------------- | -------------------------- |
| Debug         | http://10.0.1.137:3000     |
| Release       | https://photorans.chobi.me |

`API_BASE_URL` は `project.yml` の Build Setting で定義し、`Info.plist` の `API_BASE_URL` キーで `$(API_BASE_URL)` 参照する。アプリからは `Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL")` で取得する想定。

## ディレクトリ

```
ios/
├── project.yml             # XcodeGen 入力
├── Photorans/              # アプリ本体
│   ├── PhotoransApp.swift
│   ├── RootView.swift
│   └── Info.plist
└── PhotoransTests/         # 単体テスト
    └── PhotoransTests.swift
```

詳細プラン: [`docs/plans/ios-native-rewrite.md`](../docs/plans/ios-native-rewrite.md)
