# TestFlight production ビルド失敗修正 (VisionCamera Release WMO クラッシュ)

`testflight.md` の Phase4-3 (`eas build -p ios --profile production`) が swift コンパイラの内部エラーで失敗したため、その回避策を別タスクとして切り出す。Phase4-3 の前提として完了させる必要がある。

ステータス: **着手前** / 開始予定: 2026-04-30 〜

## 目的・背景

- 初回の production ビルド (Build ID `7d2cb005-4268-4316-bee3-6de30ae683d8`) が `Run fastlane` 段階で失敗
- Xcode logs を解析した結果、`Pods/VisionCamera` の Swift コンパイル中に LLVM が内部クラッシュ:
  ```
  Command SwiftCompile failed with a nonzero exit code
  Global is external, but doesn't have external or weak linkage!
  ptr @90
  ```
- swiftc フラグは `-O -whole-module-optimization -cxx-interoperability-mode=default`、SDK は `iPhoneOS26.0.sdk` (Xcode 26)
- Debug ビルド (Dev Client) は `-Onone` のため WMO されず通っていた。Phase3-2 が成功していたのはそのため
- vision-camera v5 系 (Nitrogen ベース) と Xcode 26 + 新アーキ + Release WMO の組み合わせで再現性のある既知パターン

該当パッケージ:

| パッケージ | バージョン |
|---|---|
| react-native-vision-camera | 5.0.8 |
| react-native-nitro-modules | 0.35.6 |
| react-native-nitro-image | 0.14.0 |

## 対応方針

**Expo config plugin で Podfile に post_install フックを差し込み、対象 Pod の Swift Compilation Mode を `singlefile` に切り替える** (= WMO を無効化)。

- 対象 Pod: `VisionCamera`, `NitroModules`, `NitroImage` の 3 つに限定
- 副作用: これら Pod の Release ビルドがわずかに遅くなる程度。ランタイム性能・バイナリ機能には影響なし
- 適用範囲: 全プロファイル (Debug は元々 singlefile 相当なので実害なし)

### 採用しなかった代替案

| 案 | 不採用理由 |
|---|---|
| vision-camera を別バージョンに変更 | 5.0.8 はほぼ最新で、修正コミットが入った版の特定に時間がかかる |
| `newArchEnabled: false` に戻す | 既に新アーキで Dev Client が安定動作しており、戻すと機能後退 |
| EAS image を Xcode 16 系にピン | Xcode 上げ直しで再発する一時しのぎ |

## 影響範囲

- **新規** `client/plugins/withVisionCameraReleaseFix.js` — config plugin 本体
- **修正** `client/app.json` — `plugins` 配列にプラグイン参照を追加 (`"./plugins/withVisionCameraReleaseFix"`)
- ネイティブコード本体・JS コード・依存パッケージへの変更なし

## テスト方針

- Step1 完了時: `npx expo prebuild -p ios --no-install` をローカルで試して、生成 Podfile に `SWIFT_COMPILATION_MODE = 'singlefile'` のフックが入っていること (※ ローカルに macOS が無い場合はスキップして EAS ビルド結果で判定)
- Step2 完了時: `eas build -p ios --profile production` が成功 (IPA URL が出る) こと
- 確認後、`testflight.md` の Phase4-3 を完了扱いにし Phase4-4 へ進む

## Step 分解

### Step1 config plugin を作成

- `client/plugins/withVisionCameraReleaseFix.js` を作成
  - `withDangerousMod` で iOS Podfile を読み込み、`post_install do |installer|` ブロック内に冪等なスニペットを挿入
  - 対象 target 名は `['VisionCamera', 'NitroModules', 'NitroImage']`
  - 既に挿入済み (マーカー文字列で判定) なら再挿入しない
- `client/app.json` の `plugins` 配列に `"./plugins/withVisionCameraReleaseFix"` を追加
- `npm run typecheck` パス

### Step2 production ビルド再実行

- `cd client && eas build -p ios --profile production` を実行
- ビルド成功 (IPA URL が出る) を確認
- 失敗時: Xcode logs を再取得 (`artifacts.xcodeBuildLogsUrl` 経由) して原因確認、Step1 を必要に応じて修正

## 完了の定義 (DoD)

- `eas build -p ios --profile production` が成功し、IPA が生成される
- `testflight.md` Phase4-3 のチェックを ON にして Phase4-4 へ進める状態
