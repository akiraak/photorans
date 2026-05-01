# iOS ネイティブで作り直す

photorans のクライアントを Expo + React Native + `react-native-vision-camera` 構成から、Swift によるフルネイティブ iOS アプリに作り直す。サーバ (`server/`, Hono + Claude Sonnet 4.6) はそのまま流用する。

ステータス: **実装中 (Phase1〜6 完了 / Phase7 着手前、LAN サーバ接続版での確認に方針変更 2026-05-01)** / 開始日: 2026-04-30

## 目的・背景

現状の Expo + RN + VisionCamera 構成で蓄積した課題:

- **TestFlight production ビルドが VisionCamera の Swift Compiler バグでクラッシュ** ([plan](testflight-vision-camera-release-fix.md))。config plugin で WMO を無効化する回避策はあるが、対症療法
- **カメラのフォーカスが合わない** (TODO 参照)。`device.minimumFocusDistance` 逆算 zoom で対処予定だが、VC v5 は `setFocusModeLockedWithLensPosition` / `autoFocusRangeRestriction` / iPhone15 Pro マクロ自動切替などが使えない ([研究結果](archive/native-vs-rn-camera-research.md) Step2)
- **横向き撮影時の EXIF orientation 一貫性** (TODO 参照)。VC 自体は対応可能だが、撮影直後 / 表示時 / 送信時の各層で EXIF を尊重させるラッパーが現在は薄い
- **RN / Expo / Nitro Modules / Xcode の組み合わせ起因のビルド事故が今後も頻発する見込み**。SDK アップデートで再発するたびに調査・回避策を入れる運用は中長期で重い

ネイティブ化で得られるもの:

1. **AVFoundation を直に叩ける** → 近接 AF (`autoFocusRangeRestriction = .near`)、lens position 直指定、iPhone15 Pro マクロ自動切替、Live Photos / RAW など、OCR 精度に効く API フルアクセス
2. **ビルドパイプラインの単純化** → Xcode 単体でビルド・配布が完結。Expo / RN / Nitro / Hermes / Metro の依存スタックが消える
3. **iOS Vision フレームワーク併用の余地** → サーバ送信前にオンデバイス OCR で前処理、低画質画像は事前に弾くなど、将来の最適化選択肢が広がる
4. **TestFlight Release WMO 問題が消滅**

トレードオフ:

- **Android を切り捨てる** (または別途 Kotlin で書く工数が増える)。ターゲットは「海外在住の日本人」なので iPhone ユーザーが多く、iOS only でも MVP として成立すると判断する余地はある
- **クロスプラットフォーム単一実装の利点を失う**
- **既存 `client/` の実装 (RN + Expo SDK 54、約 8 ファイル) を捨てる**。コード量自体は少ないので痛手は限定的

## 対応方針

### 技術選定 (草案・未確定)

| 項目 | 第一候補 | 代替 / 備考 |
|---|---|---|
| 言語 | Swift 6 | — |
| UI | SwiftUI (iOS 17+) | UIKit (より低レベル制御が必要なら部分採用) |
| 最低サポート OS | **iOS 17.0** (確定) | SwiftData 前提。Akira さんの iPhone と TestFlight 想定実機で確定済み |
| カメラ | AVFoundation (`AVCaptureSession` + `AVCapturePhotoOutput`) | — |
| ローカル DB | SwiftData (iOS 17+) | Core Data / GRDB / sqlite3 直叩き。既存 server 側の SQLite スキーマと揃える必要なし (端末ローカル) |
| HTTP | `URLSession` + `async/await` (multipart 自前構築) | `Alamofire` 等の外部依存は当面入れない |
| ナビゲーション | SwiftUI `NavigationStack` + `TabView` | — |
| 画像保存 | `FileManager` で App Group / Documents 配下 | — |
| Xcode プロジェクト生成 | **XcodeGen** (`project.yml` も `.xcodeproj` も git 管理。WSL2 上で Swift toolchain (Linux) + XcodeGen をソースビルドし、`project.yml` 変更時に `xcodegen generate` で再生成。Bitrise 側では生成済み `.xcodeproj` をそのまま使う) | Tuist (オーバースペック) / 手書き pbxproj (コンフリクト多発で却下) |
| ビルド / 配布 | **Bitrise** (macOS スタック、`xcodebuild archive` + `xcrun altool` で TestFlight 自動 upload) | GitHub Actions (macos-latest) / Xcode Cloud / Codemagic。EAS は廃止 |
| ローカル開発環境 | WSL2 Ubuntu 上で Swift コード + `project.yml` 編集 → CI で `xcodegen generate` + フルビルド | 後述の「WSL2 開発ワークフロー」節 |
| Android 対応 | **当面切り捨て** (Phase8 まで RN 維持、その後削除) | 将来再開時は別フェーズで Kotlin 実装 |
| ディレクトリ名 | **`ios/`** (Android 切捨て前提) | 再開可能性を残すなら `client-ios/`、現時点では不要 |

### 既存資産の扱い

- **`server/` はそのまま** — `/translate` (multipart) と `/admin` の API 仕様は変えない
- **`client/` は移行完了まで残す** — 完成後にリポジトリから削除 (もしくは `client-rn-archive/` にリネーム)
- **`com.akiraak.photorans` の Bundle ID は流用** — App Store Connect レコード ([testflight.md](testflight.md) Phase4-2 で作成済み) もそのまま使う
- **アイコン / Splash** — 既存 `client/assets/icon.png` 等をそのまま流用

### WSL2 開発ワークフロー (前提)

開発機は WSL2 Ubuntu のため **Xcode / iOS Simulator / `xcodebuild` がローカルで使えない**。これを踏まえた制約と運用:

#### できること (WSL2 上)

- Swift コードの編集 (VSCode + [Swift extension](https://marketplace.visualstudio.com/items?itemName=sswg.swift-lang) + sourcekit-lsp)
- Linux Swift toolchain (`swiftly` で `~/.local/share/swiftly/` に Swift 6.3.1 導入済み) で **Apple フレームワーク非依存の Swift コード** を `swift build` / `swift test`
- **XcodeGen を Linux ビルドして `xcodegen generate` を実行** (Apple SDK に依存しないため WSL2 上で動作)。`.xcodeproj` の生成・更新は WSL2 で完結し、CI に投げ直す必要なし
- `swift-format` / `swiftlint` (Linux ビルド) によるフォーマット・lint
- Xcode プロジェクトファイル (`project.pbxproj`) や `Info.plist`、Asset Catalog (JSON) の編集
- CI スクリプトと Fastlane / Bitrise YAML の編集

#### できないこと (= CI に投げる必要)

- UIKit / SwiftUI / AVFoundation / SwiftData を含む実コードのビルド
- iOS Simulator 起動・UI テスト
- `xcodebuild archive`、`.ipa` 生成、TestFlight upload
- Interface Builder (Storyboard / xib) 編集 (本プランでは SwiftUI 一本化なので不要)

#### イテレーションループ

```
WSL2 で編集 → git push → Bitrise が Simulator/Device ビルド → 成果物 (.app/.ipa) を artifact で受領
                                              ↘ TestFlight に直接 upload (production trigger 時)
```

実機確認は **Bitrise → TestFlight → iPhone** で回す。シミュレータでの確認はスキップ (CI 上での `xcodebuild test` のログのみ確認)。これにより、変更 1 サイクル ≒ Bitrise ビルド時間 (5〜15 分想定)。

#### 補助案 (任意)

- **クラウド Mac の常設**: MacStadium / MacinCloud の Mac mini を月額借り、WSL2 から SSH + Xcode CLI で対話的にビルド・シミュレータ確認。月 $79〜 程度。Bitrise 初期構築で詰まったら検討
- **Tart + Apple Silicon Mac** を自前で持つ選択肢もあるが、購入コストが見合わないので除外

### ビルド・配布パイプライン (Bitrise 軸)

#### 候補比較

| サービス | 無料枠 | TestFlight 連携 | 設定形式 | 学習コスト | 備考 |
|---|---|---|---|---|---|
| **Bitrise** | 月 200 ビルド分 / 並列 1 / OSS で拡張あり | ✅ Step 標準 (`Deploy to App Store Connect`) | `bitrise.yml` (Workflow Editor あり) | 低 (iOS テンプレ豊富) | iOS CI のデファクト。証明書 / プロビジョニング管理機能 (Code Signing) が手厚い |
| GitHub Actions (macos-latest) | Public 無料 / Private は macOS が **10x 課金** (= 月 200 min ≒ 2000 分相当を消費) | ⚠️ 自前で `xcrun altool` または `fastlane pilot` を書く | `.github/workflows/*.yml` | 中 | リポジトリと同居でき、PR 連携が楽。シークレット管理は GitHub Secrets |
| Xcode Cloud | 月 25 時間 | ✅ Apple 純正で最もスムーズ | Workflow を App Store Connect 上で GUI 設定 | 低 | Apple 純正だが、ビルドスクリプト / ログ取得の自由度が CI 系で最も低い |
| Codemagic | 月 500 分 (M1 mini) | ✅ | `codemagic.yaml` | 中 | Flutter 寄りだが iOS も一級。価格は中 |
| CircleCI | macOS は無料枠ほぼなし | ⚠️ 自前 | `.circleci/config.yml` | 中 | macOS 課金が高め |

**第一候補は Bitrise**。理由:

- 個人開発の月 200 分無料枠で TestFlight 反復には十分 (1 ビルド 5〜10 分想定)
- Code Signing (証明書 / プロビジョニングプロファイル) を Bitrise 側で自動管理する Step があり、ローカル macOS が無くても運用できる
- TestFlight アップロード Step (`Deploy to App Store Connect`) が標準提供
- WSL2 ↔ GitHub 連携で完結 (Bitrise の Webhook で push トリガ)

**次点: GitHub Actions**。リポジトリ同居の利便性は高いが、Private リポジトリで macOS runner を多用すると無料枠を一気に食う点に注意。Public 化できるなら GitHub Actions も有力。

**Xcode Cloud は本命と並行して検討**。Apple 純正で TestFlight 直結だが、設定が GUI 中心で再現性 / コードレビュー性が落ちる。

#### Bitrise セットアップ概要 (Phase で詳細化)

1. Bitrise にサインアップ (akiraak@gmail.com で OK)、リポジトリを接続
2. Workflow Editor で iOS テンプレートから初期化
3. **Code Signing**: Apple Developer Portal の証明書 / Provisioning Profile を Bitrise の Code Signing & Files にアップロード (または `automatic provisioning` を有効化)
4. **Secrets**: App Store Connect API Key (`AuthKey_*.p8` + Issuer ID + Key ID) を Bitrise Secrets に登録
5. **Workflow**:
   - `primary` (PR push 時): `xcodebuild build` + `xcodebuild test` (シミュレータ) + Slack 通知 (任意)
   - `release` (tag `v*` push 時): `xcodebuild archive` → `Export IPA` → `Deploy to App Store Connect` (TestFlight)
6. `bitrise.yml` をリポジトリにコミット (Workflow Editor の出力をそのまま使う)

#### Fastlane の扱い

Bitrise の標準 Step だけで TestFlight 配信まで完結するため、**Fastlane は当面入れない**。将来的にメタデータ (App Store 説明文 / スクリーンショット) を自動化する段階で `fastlane deliver` / `fastlane pilot` を導入する。

### ディレクトリ構成 (案)

```
photorans/
├── client/             # 既存 (RN, 移行完了まで保持)
├── ios/                # 新規 Xcode プロジェクト
│   ├── Photorans.xcodeproj
│   ├── Photorans/
│   │   ├── PhotoransApp.swift
│   │   ├── Features/
│   │   │   ├── Camera/
│   │   │   ├── History/
│   │   │   └── Detail/
│   │   ├── Networking/
│   │   ├── Storage/
│   │   └── Resources/
│   └── PhotoransTests/
├── bitrise.yml         # Bitrise Workflow 定義 (リポジトリルートに配置)
├── server/
└── docs/plans/
```

> 命名は `ios/` でいくか `client-ios/` にするかは未確定。Android 想定が完全消滅するなら `ios/`、可能性を残すなら `client-ios/` が無難。

## 影響範囲

- **新規**: `ios/` ディレクトリ配下の Xcode プロジェクト一式、`bitrise.yml`
- **修正**: `CLAUDE.md` (技術スタック節をネイティブ向けに、ビルド節を Bitrise 向けに更新)、`README.md`
- **削除候補**: 移行完了後の `client/`、`client/eas.json`、TestFlight VisionCamera 修正プラン (不要になる)
- **不変**: `server/`、`vibeboard/`、API 仕様
- **外部サービス**: Bitrise アカウント、App Store Connect API Key (Bitrise Secrets に登録)

## 未確定事項 / オープンクエスチョン

### 確定済み (Phase1 着手前)

- [x] **Android を切るかどうか** → 当面切り捨て (Phase8 で RN クライアント削除)
- [x] **最低サポート iOS バージョン** → iOS 17.0
- [x] **Xcode プロジェクト生成方式** → XcodeGen (`project.yml` + `.xcodeproj` 両方を git 管理。WSL2 で Swift toolchain (Linux) + XcodeGen Linux ビルドで再生成。Bitrise 接続を安全に通すため、当初の「CI で生成・非コミット」方針から変更)
- [x] **ディレクトリ命名** → `ios/`
- [x] **CI サービス** → Bitrise (月 200 分で足りるかは Phase8 で実測、不足なら GitHub Actions に振替検討)
- [x] **既存 TestFlight アプリレコードを流用するか** → 流用 (`com.akiraak.photorans` をそのまま)

### 未確定 (該当 Phase で決定)

- [ ] **DB に SwiftData / Core Data / GRDB のどれを使うか** (Phase4)。第一候補は SwiftData
- [ ] **EAS / `client/` をいつ捨てるか** (Phase8)。Phase7 動作確認 + 1〜2 週間並走後に削除
- [ ] **Swift Package Manager で外部依存を入れる方針** (随時)。当面は標準 SDK のみで進める
- [ ] **i18n** (Phase5)。UI は日本語のみハードコードで OK か最終確認
- [ ] **コード署名方式** (Phase6)。Bitrise の `Manage iOS Code Signing` Step を第一候補とする
- [ ] **ローカル macOS 環境を借りるか** (随時)。Bitrise で詰まる場面が多発したら MacinCloud 等を一時利用

## テスト方針

- WSL2 ローカルではビルドできないため、**全フェーズで Bitrise を介して動作確認** する
- 各 Phase の確認手段:
  - **静的**: WSL2 上で `swift build` / `swiftlint` / `swift-format --lint`
  - **シミュレータ**: Bitrise の `xcodebuild test` ステップで `iPhone 16 (iOS 18)` シミュレータ向けビルド + ログ確認
  - **実機**: Bitrise → TestFlight → Akira さんの iPhone (Phase6 以降は毎フェーズここで確認)
- 単体テストは Networking / Storage 層に最小限 (XCTest)、CI で並走
- DoD: TestFlight 経由でインストールしたネイティブ photorans が、撮影 → `/translate` → 一覧 → 詳細まで通り、サーバ `/admin` に履歴が反映される

## Phase 分解

### Phase1 Xcode プロジェクト基盤 + Bitrise 接続 (✅ 完了 2026-04-30)

XcodeGen による `project.yml` ベースの構成。`.xcodeproj` は WSL2 上の XcodeGen Linux ビルドで生成し、生成物も git 管理する (技術選定表参照)。Bitrise はリポジトリ内の生成済み `.xcodeproj` を直接読む。

#### Step1 XcodeGen 入力 + SwiftUI スケルトン (✅ 完了 2026-04-30)

- `ios/project.yml` を作成 (XcodeGen フォーマット)
  - `name: Photorans`、Bundle ID `com.akiraak.photorans`、Deployment Target iOS 17.0
  - Target: `Photorans` (iOS App, SwiftUI)、`PhotoransTests` (Unit Test)
  - Build Configuration: `Debug` / `Release`、`API_BASE_URL` を Build Setting で持つ (Debug = `http://10.0.1.137:3000`、Release = `https://photorans.chobi.me`)
  - `schemes.Photorans` で shared scheme を明示定義 (Bitrise の scheme バリデーション要件)
- `ios/Photorans/` 配下に SwiftUI スケルトン
  - `PhotoransApp.swift` (App entry point)
  - `RootView.swift` (`TabView` で「カメラ」「履歴」2 タブ、中身は Hello World)
  - `Info.plist` に `NSCameraUsageDescription` (日本語の利用目的説明)、`API_BASE_URL` を `$(API_BASE_URL)` で参照
- `ios/README.md` に「`xcodegen generate` で `.xcodeproj` を生成する」旨を記載
- 確認: WSL2 上で `project.yml` の YAML 構文と Info.plist の plist 構文のみチェック (この時点で `.xcodeproj` 生成はまだ行わない)
- コミット: `c0e9fa2 Phase1-1 Add iOS Xcode project skeleton (XcodeGen)`、`b969b55 Phase1-2 Add bitrise.yml for manual iOS builds` (このコミットで作った `bitrise.yml` は Step2 で xcodegen ステップを削る形に修正される)

#### Step2 WSL2 で XcodeGen Linux ビルド + `.xcodeproj` 生成 (✅ 完了 2026-04-30)

- **Swift toolchain (Linux) インストール** (✅ 完了): swiftly を `/tmp/swiftly` で展開し `swiftly init --assume-yes` で `~/.local/share/swiftly/toolchains/6.3.1` に Swift 6.3.1 を配置。`. ~/.local/share/swiftly/env.sh` で PATH に `swift` が通る
- **XcodeGen ソースビルド** (✅ 完了):
  - `git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git /tmp/XcodeGen`
  - `cd /tmp/XcodeGen && swift build -c release` (約 192 秒、Yams 等の依存も含めビルド成功)
  - 生成物 `/tmp/XcodeGen/.build/release/xcodegen` を `install -m 0755 ... ~/.local/bin/xcodegen` で配置
  - 動作確認: `xcodegen --version` → `Version: 2.45.4`
- **`.xcodeproj` 生成** (✅ 完了): `cd ios && xcodegen generate` で `Photorans.xcodeproj/` を生成。中身は `project.pbxproj` / `project.xcworkspace/contents.xcworkspacedata` / `xcshareddata/xcschemes/Photorans.xcscheme` の 3 ファイル (shared scheme 含む)
- **`.gitignore` 修正** (✅ 完了): `ios/Photorans.xcodeproj/` の除外行を削除し、`xcuserdata/` のみ除外する形に変更。`ios/build/`、`ios/DerivedData/` 等のビルド成果物の除外は維持
- **`bitrise.yml` 修正** (✅ 完了): `Install XcodeGen` と `Generate Xcode project` の 2 Step を削除 (リポジトリに `.xcodeproj` が含まれるので不要)。`xcode-build-for-simulator` Step は維持
- **`ios/README.md` 修正** (✅ 完了): 「WSL2 で swiftly + XcodeGen Linux ビルドを使って再生成」する手順に更新。`.xcodeproj` を git 管理する旨を明記
- **コミット**: `Phase1-3 Build XcodeGen on Linux and commit generated .xcodeproj`
- 確認: `git check-ignore` で `ios/Photorans.xcodeproj/project.pbxproj` が ignore されないこと (rc=1)、`xcodegen generate` が WSL2 で再現可能、`bitrise.yml` から xcodegen ステップが消えていることを確認済み

#### Step3 Bitrise セットアップ + `bitrise.yml` 緑化 (✅ 完了 2026-04-30)

- **Bitrise アカウント作成 + リポジトリ接続** (✅ 完了): akiraak@gmail.com でサインアップ → Workspace 作成 → Hobby plan (300 credits/月、CC 不要) で開始 → GitHub App 連携で `akiraak/photorans` を接続
- **Configuration YAML をリポジトリ側に切替** (✅ 完了): Workflow Editor → Configuration YAML → Change → リポジトリの `bitrise.yml` を参照
- **手動ビルド** (✅ 完了): Web UI の **Start build** → Workflow `primary`
- **詰まりポイントと解決**:
  - `xcode-build-for-simulator@0` (= 0.12.2) で `Build Succeeded` の後 `failed to copy the generated app to the Deploy dir` エラー。新しい Xcode の Derived Data レイアウトに古い Step が追従していない既知の挙動
  - **解決**: `xcode-build-for-simulator@3` (3.0.3) に bump。v3 では入力フォーマット変更 (`simulator_device` / `_os_version` 廃止 → `destination` 直接指定)。スモークテスト用途では default の `generic/platform=iOS Simulator` で十分なので最小入力に
  - コミット: `bbf464f Phase1-3 Bump xcode-build-for-simulator to v3`
- **確認**: `primary` Workflow が緑。リポジトリ内の `ios/Photorans.xcodeproj` を直接読み、`xcode-build-for-simulator@3` がシミュレータ向け未署名ビルドに成功

### Phase2 カメラ画面 (AVFoundation)

3 Step に分割。Step ごとに Bitrise でビルド緑化を確認してから次に進む (credit 節約のため手動トリガのまま)。

#### Step1 AVCaptureSession セットアップ + プレビュー表示 (撮影なし) (✅ 完了 2026-04-30)

- `ios/Photorans/Features/Camera/` 配下に 4 ファイル
  - `CameraSession.swift` — `AVCaptureSession` を `@unchecked Sendable` で薄くラップ。専用 `DispatchQueue` 上で configure / start / stop。Swift 6 strict concurrency 対応のため、MainActor からは `start()` / `stop()` のみ呼ぶ
  - `CameraPreviewView.swift` — `UIViewRepresentable` で `AVCaptureVideoPreviewLayer` を SwiftUI に橋渡し。UIView の `layerClass` を override して root layer を直接 preview layer に
  - `CameraViewModel.swift` — `@MainActor @Observable`。`AVCaptureDevice.authorizationStatus` を握り、未確定時は `requestAccess` を await。authorized なら `camera.start()`
  - `CameraView.swift` — ZStack でプレビュー全画面 + denied 時の overlay
- `RootView.swift` のカメラ tab を `CameraView()` に差し替え (NavigationStack は外す)
- `xcodegen generate` で .xcodeproj を更新 (4 ファイルが Sources に追加される)
- 確認: Bitrise の `primary` Workflow で `Build Succeeded`。実機動作確認は Phase6 (TestFlight) 以降

#### Step2 撮影 + ローカル保存 (JPEG + EXIF orientation) (✅ 完了 2026-04-30)

- `CameraSession` に `AVCapturePhotoOutput` を追加。`capturePhoto(rotationAngle:) async throws -> Data` を Continuation で実装。`PhotoCaptureDelegate` (fileprivate NSObject + AVCapturePhotoCaptureDelegate, `@unchecked Sendable`) を `pendingDelegates: [UUID: ...]` で sessionQueue 上で管理 (AVCapturePhotoOutput は delegate を retain しないため)
- `PhotoStorage.swift` で `Documents/photos/<uuid>.jpg` に保存 (`FileManager.urls(for: .documentDirectory, ...)` 経由)
- `CameraViewModel` に `isCapturing` / `lastError` / `lastSavedURL` 観測プロパティを追加。`UIDevice.beginGeneratingDeviceOrientationNotifications` で端末向き通知を購読し、`capturePhoto()` 時に `UIDevice.current.orientation` から `videoRotationAngle` を計算 (portrait=90, landscapeLeft=0, landscapeRight=180, portraitUpsideDown=270)
- `CameraView` に下部中央のシャッターボタンを追加。撮影中は disable + ProgressView。エラー発生時は `.alert` で表示
- 確認: Bitrise でビルド成功。実際の撮影 / EXIF 検証は Phase7 (実機 TestFlight) で行う

> **注**: 撮影画像の容量制約 5MB 以下は当面チェックしない。`.photo` preset で iPhone の通常写真サイズ (3〜5MB 程度) に収まる想定。サーバ側の `/translate` で過大画像が問題になったら Step3 か別タスクで圧縮ロジックを追加

#### Step3 サムネ表示 + フォーカス改善 (近接 AF / タップ AF) (✅ 完了 2026-04-30)

- **近接 AF 初期設定** (✅ 完了): `CameraSession.configureFocus(on:)` を新設し、初期 configure 内で `device.lockForConfiguration` → `focusMode = .continuousAutoFocus` + `autoFocusRangeRestriction = .near` + `exposureMode = .continuousAutoExposure` を設定 (各 `is*Supported` を確認してから適用)。`device` を sessionQueue 上で保持して以降の操作で再利用
- **タップ AF API** (✅ 完了): `CameraSession.focus(at devicePoint:)` を sessionQueue 上で実装。`focusPointOfInterest` / `focusMode = .autoFocus` / `exposurePointOfInterest` / `exposureMode = .autoExpose` をセット (端末サポート時のみ)
- **プレビューのタップ取り込み** (✅ 完了): `CameraPreviewView` を Coordinator パターンに変更。`UITapGestureRecognizer` を内部で持ち、`onTap: (@MainActor (CGPoint, CGPoint) -> Void)?` で layer 座標と `previewLayer.captureDevicePointConverted` 変換後の device 座標 (0...1) を SwiftUI 側に渡す。Coordinator 自体を `@MainActor` に annotate して strict concurrency と整合
- **タップ AF UI** (✅ 完了): `CameraView` でタップ位置に黄色の `FocusReticleView` (角丸矩形 72pt、`scale 1.4 → 1.0` の easeOut アニメ) を 0.9 秒表示。重ね打ち時は最新タップを優先 (`FocusReticleState.id` で判定)
- **直前撮影サムネ表示** (✅ 完了): `CameraViewModel.lastThumbnail: UIImage?` を追加し、capture 成功時に `UIImage(data:)` で生成。`CameraView` の下端中央 shutter ボタンと並べて、左寄せ 56×56 角丸 8pt のサムネを表示。撮影前 (= nil) は同サイズの透明プレースホルダ
- 確認: WSL2 上で `xcodegen generate` が成功 (project.yml の変更は無し、新規ソースも無し)。Bitrise の `primary` ビルドはコミット → push 後に確認
- コミット: `Phase2-3 Add thumbnail + tap-to-focus and near AF`

### Phase3 ネットワーク層 (`/translate` 連携) (✅ 完了 2026-04-30)

- `Photorans/Networking/TranslateAPI.swift` を追加。`actor TranslateAPI` で `URLSession` を保持、`translate(jpegData:) async throws -> TranslateResponse` を提供
- multipart 構築は手書き (`PhotoransBoundary-<uuid>` boundary、`image` フィールド + `image/jpeg` で送出)
- エンドポイントは `Bundle.main.infoDictionary["API_BASE_URL"]` 経由で `Info.plist` の `API_BASE_URL` を読む。`project.yml` で Debug/Release 切替済 (Debug: `http://10.0.1.137:3000`、Release: `https://photorans.chobi.me`)
- ATS: 当初プランの「Debug のみ `NSAllowsArbitraryLoads = true`」から **より制限的な `NSExceptionDomains` 方式に変更**。`10.0.1.137` のみ HTTP を許可し、Release ビルドの `photorans.chobi.me` には HTTPS が引き続き強制される。`INFOPLIST_PREPROCESS` の cpp line marker による plist 破損リスクを避ける目的
- `URLSessionConfiguration.timeoutIntervalForRequest = 60` でタイムアウト、`URLError.timedOut` を `TranslateError.timeout` に変換。`TranslateError` は `LocalizedError` で日本語メッセージ
- サーバ JSON エラー (`{"error": "..."}`) は status code と一緒に `TranslateError.server` に詰めて表示
- `CameraViewModel` に `isTranslating` / `lastResult` を追加。`capturePhoto()` 成功直後に `TranslateAPI.shared.translate(jpegData:)` を呼び、結果は暫定 `TranslateResultView` (sheet) で表示。Phase4-5 で SwiftData + 履歴 UI に置換予定
- 確認: WSL2 上で `xcodegen generate` 成功 (Networking グループと TranslateResultView が pbxproj に追加)。Bitrise の `primary` Workflow ビルドはコミット → push 後に確認。実機での `/translate` 200 / 4xx / タイムアウト確認は Phase6-7 (TestFlight) で行う
- コミット: `Phase3 Add /translate networking layer`

### Phase4 ローカル DB (SwiftData) (✅ 完了 2026-04-30)

- **DB に SwiftData を採用** (✅ 完了): iOS 17.0 最低サポート前提、外部依存ゼロで済むため第一候補のまま採用
- **`HistoryEntry` モデル追加** (✅ 完了): `ios/Photorans/Storage/HistoryEntry.swift` に `@Model final class HistoryEntry`。フィールド: `@Attribute(.unique) id: UUID` / `createdAt: Date` / `imagePath: String` / `originalText: String` / `translatedText: String` / `model: String`
- **`PhotoStorage` を相対パスベースに拡張** (✅ 完了): `save(jpegData:)` の戻り値を `SavedPhoto { relativePath, absoluteURL }` に変更し、`absoluteURL(for relativePath:)` ヘルパも追加。SwiftData には `photos/<uuid>.jpg` 形式の相対パスを保存することで、アプリ再インストールや OS による Documents パス変更後も解決可能に
- **`ModelContainer` 初期化** (✅ 完了): `PhotoransApp.init` で `ModelContainer(for: HistoryEntry.self)` を作成し、`.modelContainer(container)` でシーン全体に注入。失敗時は `fatalError`
- **撮影 → 翻訳成功時に永続化** (✅ 完了): `CameraView` に `@Environment(\.modelContext)` を追加し `viewModel.capturePhoto(modelContext:)` 経由で渡す。`CameraViewModel` 側は `TranslateAPI.shared.translate` 成功直後に `HistoryEntry` を `modelContext.insert` → `try modelContext.save()`。保存失敗は `lastError` 経由で alert に出す (UI フローは止めない)
- **Preview の対応** (✅ 完了): `RootView` / `CameraView` の `#Preview` に `.modelContainer(for: HistoryEntry.self, inMemory: true)` を追加 (Phase5 までは履歴 UI 自体は未実装)
- **xcodegen 再生成** (✅ 完了): `cd ios && xcodegen generate` で `Storage/HistoryEntry.swift` が `Photorans` ターゲットの Sources に追加されたことを `project.pbxproj` 上で確認
- 確認: WSL2 上のビルド検証は不可。Bitrise の `primary` Workflow ビルドはコミット → push 後に確認。アプリ再起動後の永続化は Phase6-7 (TestFlight) の実機確認で検証

### Phase5 履歴一覧 + 詳細画面

`HistoryEntry` (Phase4 で永続化) を SwiftUI 側で表示する。`@Query` の自動反映により、カメラタブで撮影 → 履歴タブに切替えれば最新の履歴が自動で出る前提。

#### Step1 履歴一覧 + 詳細画面 + スワイプ削除

- `ios/Photorans/Features/History/` 配下に 2 ファイル新設
  - `HistoryListView.swift`
    - `@Query(sort: \HistoryEntry.createdAt, order: .reverse)` で全件取得
    - `List` で行表示 (`HistoryRowView`)
      - 左: 64×64 サムネ角丸 8pt (`PhotoStorage.absoluteURL(for:)` → `UIImage(contentsOfFile:)`)。読み込み失敗時はプレースホルダ
      - 右: 訳文 (font=body, `lineLimit(2)`) + 日時 (font=caption, `.dateTime` short style)
    - `NavigationLink` で `HistoryDetailView` へ
    - `.onDelete` でスワイプ削除 (`modelContext.delete(entry)` → `try? modelContext.save()`、対象画像ファイルも `FileManager.removeItem` で削除)
    - 履歴 0 件時は `ContentUnavailableView` で「まだ履歴はありません」
    - `NavigationStack` 内で表示する想定 (親で包む)
  - `HistoryDetailView.swift`
    - 入力: `HistoryEntry`
    - 画像 (3:4 アスペクト、横幅いっぱい、`UIImage(contentsOfFile:)` で読込) を上部に
    - 訳文ブロック / 原文ブロック (タイトル + 本文、`textSelection(.enabled)` で長押しコピー)
    - 末尾にモデル名と作成日時を caption で
    - `navigationTitle` は作成日時の short 表記
- `RootView` の `HistoryTabView` プレースホルダを `NavigationStack { HistoryListView() }` に置換

#### Step2 撮影直後の履歴タブ自動遷移 + 結果 sheet 撤去

- `RootView` に `@State selectedTab: Tab = .camera` を持たせ `TabView(selection:)` で双方向バインド
- `CameraView` に `onTranslated: () -> Void` クロージャを追加し、`viewModel.lastResult` 変化を `.onChange` で監視 → 親に通知
- `RootView` 側はクロージャ内で `selectedTab = .history` に切替
- `CameraView` の暫定 `TranslateResultView` sheet と `TranslateResultItem` / `TranslateResultView.swift` を撤去 (履歴タブが恒久 UI になる)
- `CameraViewModel.lastResult` は遷移トリガとしてのみ残す (型はそのまま `TranslateResponse?`)

#### 確認

- WSL2 上で `xcodegen generate` 成功、追加ファイル 2 つが Sources に含まれる
- 既存 `TranslateResultView.swift` 参照削除
- Bitrise の `primary` Workflow 緑化はコミット → push 後に確認
- 実機での「撮影 → 自動で履歴タブ → タップで詳細 → 長押しでコピー → スワイプで削除」は Phase7 (TestFlight) で検証

### Phase6 Bitrise コード署名 + TestFlight 提出 Workflow

App Store Connect は既存 `com.akiraak.photorans` レコードを流用 ([testflight.md](testflight.md) Phase4-2 で作成済み)。`com.akiraak.photorans` の Bundle ID で TestFlight に Internal Testing グループ + Akira さん登録済みの想定。

> Bitrise UI 用語: 階層は **Workspace > Project**。`photorans` は Project 名で、"App" という呼称は Bitrise UI には存在しない (CLAUDE.md「Bitrise 用語」節参照)。

#### Step1 App Store Connect API Key 発行 + Bitrise への接続 (Akira さん作業) (✅ 完了 2026-04-30)

- App Store Connect で API Key を発行 → Bitrise の **Workspace settings → Apple service connection** に登録済み
- `release` Workflow の `xcode-archive@6` (`automatic_code_signing: api-key`) と `deploy-to-itunesconnect-application-loader@1` の双方で本接続を利用

#### Step2 コード署名方式の決定 (✅ 完了 2026-04-30) — Manual

当初プランの第一候補だった `Manage iOS Code Signing` Step による Automatic Code Signing は採らず、**手動アップロード方式** で確定。

- WSL2 上で生成: `~/.config/photorans/cert/` に `ios_distribution.key` (RSA 2048bit) → `ios_distribution.csr` → Apple Developer に CSR を送って `distribution.cer` を取得 → `.cer` を PEM に変換 → 秘密鍵と PKCS#12 (`-legacy` で互換重視) にマージして **`ios_distribution.p12`** を生成
- Apple Developer Portal で **App Store Provisioning Profile** (`Photorans App Store`、`com.akiraak.photorans` + 上記 Distribution cert) を発行 → `Photorans_App_Store.mobileprovision`
- Bitrise の `photorans` Project → **Project Setting → Code signing** に両ファイルをアップロード (Exposed = ON)

> 開発体験メモ: Bitrise UI は Workspace settings 配下にも Code Signing & Files があるが、Workflow は **Project Setting → Code signing** にあるファイルしか自動注入しない。最初 Workspace 側にアップしてしまい `certificate_url_list: <unset>` のエラーで詰まった経緯がある。

#### Step3 `release` Workflow を `bitrise.yml` に追加 (✅ 完了 2026-04-30、コミット `5e7d331`)

- トリガ: `trigger_map` で tag `v*` push → `release` Workflow
- 既存 `primary` Workflow は `push_branch` トリガを追加せず手動運用のまま維持
- Step 構成 (確定版):
  - `git-clone@8`
  - `xcode-archive@6` — `project_path` / `scheme` / `configuration: Release` / `distribution_method: app-store` / `automatic_code_signing: api-key` / `xcconfig_content` で `CURRENT_PROJECT_VERSION = $BITRISE_BUILD_NUMBER` を注入
  - `deploy-to-itunesconnect-application-loader@1` (= TestFlight 提出)
  - `deploy-to-bitrise-io@2` — Artifacts として `.ipa`/`.dSYM` を残す
- `Info.plist` に `ITSAppUsesNonExemptEncryption: false` を追加 (HTTPS のみ使用、exempt)
- 当初プランから外したもの: `manage-ios-code-signing` Step (Step2 を Manual にしたため不要) / `set-xcode-build-number` Step (`xcconfig_content` で代替)

#### Step4 初回 release ビルド + TestFlight 着信確認 (✅ 完了 2026-04-30)

##### Sub1 初回 release ビルド実行 (✅ 完了 2026-04-30)

- `git tag v0.1.0 && git push origin v0.1.0` で Webhook 起動 (タグ push は Step3 のコミット `5e7d331` で実施済み)
- 結果: `Xcode Archive & Export for iOS` は成功 (.ipa 生成済み)。`Deploy to App Store Connect - Application Loader` で **altool が 3 つの validation error を返して失敗**

| # | エラー (altool 返答) | 原因 |
|---|---|---|
| 1 | Missing required icon file. The bundle does not contain an app icon for iPhone / iPod Touch of exactly '120x120' pixels | iOS プロジェクトに AppIcon Asset Catalog (`.xcassets`) が存在しない |
| 2 | Missing Info.plist value. A value for the Info.plist key 'CFBundleIconName' is missing in the bundle | 同上 (Asset Catalog があれば Xcode が自動注入する key) |
| 3 | SDK version issue. This app was built with the iOS 18.0 SDK. All iOS and iPadOS apps must be built with the iOS 26 SDK or later | Bitrise stack `osx-xcode-16.0.x` に Xcode 16 / iOS 18 SDK しか含まれない。Apple は 2026-04 から iOS 26 SDK を必須化 |

##### Sub2 AppIcon Asset Catalog 追加 (✅ 完了 2026-04-30)

- 配置: `ios/Photorans/Resources/Assets.xcassets/`
  - `Contents.json` (catalog root メタ)
  - `AppIcon.appiconset/Contents.json` — 単一 `universal / ios / 1024x1024` を宣言 (モダン Xcode は 1024 一枚から全サイズを自動生成)
  - `AppIcon.appiconset/icon-1024.png` — `client/assets/icon.png` (1024×1024) をコピー
- `client/assets/icon.png` の透過チェック: `identify -format "alpha=%A opaque=%[opaque]"` → `alpha=False opaque=true` で完全不透明。altool の transparency 弾きには引っかからないためそのまま流用
- `project.yml` 側は **`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` が既に設定済み** + `sources: - path: Photorans` で xcassets が自動拾われるため、変更不要
- WSL2 上で `cd ios && xcodegen generate` を再実行し、`project.pbxproj` で以下を確認済み:
  - `Assets.xcassets` が `PBXFileReference` (`folder.assetcatalog`) として登録
  - `Photorans` ターゲットの Resources ビルドフェーズに `Assets.xcassets in Resources` が含まれる
  - Debug/Release 両 config に `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` が反映

##### Sub3 Bitrise stack 26 系に bump (✅ 完了 2026-04-30)

- `bitrise.yml` の `meta.bitrise.io.stack` を `osx-xcode-16.0.x` → **`osx-xcode-26.4.x`** に変更 (2026-04 時点の最新安定 Xcode 26 系)
- `machine_type_id: g2-m1.4core` は据え置き
- Xcode 26 / iOS 26 SDK は iOS 17.0 deployment target をそのまま受け入れる (deployment target と SDK は独立)

##### Sub4 タグを打ち直して再ビルド (✅ 完了 2026-04-30)

- Sub2 (`ee745c1 Phase6-4-2 Add AppIcon asset catalog`) と Sub3 (`3e22195 Phase6-4-3 Bump Bitrise stack to Xcode 26.4`) を別コミットで反映 (1 コミット集約案からは逸脱したが結果同等)
- `v0.1.0` タグを `3e22195` に再 push
- Bitrise の `release` Workflow が緑化、`.ipa` が `deploy-to-itunesconnect-application-loader@1` で TestFlight に到達
- App Store Connect → TestFlight 経由で Akira さんの iPhone にインストール成功 (起動・動作確認は Phase7 で実施)

### Phase7 LAN サーバ接続版を TestFlight で実機確認

WSL2 上のローカルサーバ (`http://10.0.1.137:3000`) に接続するビルドを TestFlight 経由で iPhone に配布し、LAN 内で動作確認する。本番サーバ (`https://photorans.chobi.me`) 経由の確認は Phase8 で行う。

> 方針変更経緯 (2026-05-01): 当初 Phase7 は本番サーバ向け Release ビルドでの動作確認を想定していたが、LAN サーバを叩く構成での挙動を先に確認したい意向に切替。`xcode-archive@6` の `xcconfig_content` で API_BASE_URL を上書きする「方法 B」(専用 Workflow) は採らず、**`project.yml` の Release configuration を直接書き換える「方法 A」**で進める (一時的な検証目的のため、bitrise.yml に Workflow を増やすほどでもない)。確認完了後 Phase8 Step1 で本番 URL に戻す。

#### Step1 Release の `API_BASE_URL` を LAN URL に切替 (✅ 完了 2026-05-01)

- `ios/project.yml` の `configs.Release.API_BASE_URL` を `https://photorans.chobi.me` → `http://10.0.1.137:3000` に変更
- ATS は Phase3 で `NSExceptionDomains` に `10.0.1.137` の HTTP 許可を追加済みのため追加対応不要 (Info.plist 触らず)
- `cd ios && xcodegen generate` で `.xcodeproj` を再生成 (pbxproj の差分は Release config の `API_BASE_URL` 行のみ)
- コミット予定メッセージ: `Phase7-1 Switch Release API_BASE_URL to LAN for TestFlight verification`

#### Step2 タグ `v0.1.1` push → release Workflow → TestFlight 配布

- `git tag v0.1.1 && git push origin v0.1.1` で `release` Workflow をトリガ
- Bitrise の `release` Workflow が緑化、`.ipa` が `deploy-to-itunesconnect-application-loader@1` で TestFlight Internal Testing に到達
- iPhone の TestFlight アプリで `v0.1.1` をインストール

> Internal Testing は Apple Review 不要なので、Release 構成でも HTTP の LAN URL を埋め込んだビルドを配布可能。

#### Step3 LAN 内動作確認

- iPhone を WSL2 ホストと同じ Wi-Fi に接続 (`10.0.1.137` に到達できること)
- 撮影 → 翻訳 (`/translate`) が成功 → 履歴一覧に反映 → 詳細表示 → コピー / 削除
- WSL2 サーバの `/admin` (LAN 内アクセス) に履歴が積まれること
- 既存 TODO の AF (近接 / タップ) が効くこと、横向き撮影時の orientation 一貫性

### Phase8 本番サーバ接続版の再確認 + 旧 RN クライアント撤去

#### Step1 Release の `API_BASE_URL` を本番に戻す + 再配布

- `ios/project.yml` の Release `API_BASE_URL` を `https://photorans.chobi.me` に戻し、`xcodegen generate` → コミット
- タグ `v0.1.2` push で `release` Workflow → TestFlight 配布
- iPhone の TestFlight で `v0.1.2` に更新

#### Step2 LAN 外 (本番) 動作確認

- iPhone をモバイル回線 (Wi-Fi off) に切替
- 撮影 → 翻訳 → 一覧 → 詳細フローが本番サーバ向けでも通ること
- `https://photorans.chobi.me/admin` に履歴が積まれること

#### Step3 旧 RN クライアント撤去

- 並走期間 (Phase7 + Phase8 Step1-2 動作確認 + 1〜2 週間) を経て `client/` を削除
- `CLAUDE.md` の RN 関連記述を整理し、Bitrise / iOS ネイティブのビルド・配布手順に置き換える
- `docs/plans/testflight-vision-camera-release-fix.md` は archive へ (不要になる)
- `docs/plans/testflight.md` も EAS 前提なので archive へ移動 (Bitrise 版の手順は CLAUDE.md に集約)

## 完了の定義 (DoD)

- iPhone の TestFlight 経由で配布したネイティブ photorans が、Wi-Fi / モバイル回線どちらでも撮影 → 翻訳 → 一覧 → 詳細まで動く
- サーバ `/admin` に履歴が反映される
- 既存 TODO の「フォーカスが合わない」「横向き撮影の EXIF 一貫性」が解消されている
- TestFlight ビルドが Swift / VisionCamera 起因のクラッシュを起こさない
- `client/` (旧 RN クライアント) がリポジトリから削除されている

## 参考

- [Native vs RN カメラ研究 (archive)](archive/native-vs-rn-camera-research.md) — Native 化検討トリガーの整理
- [TestFlight プラン](testflight.md) — Bundle ID / App Store Connect レコードの再利用元
- [TestFlight VisionCamera 修正プラン](testflight-vision-camera-release-fix.md) — Native 化により不要になる
