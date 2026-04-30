# iOS ネイティブで作り直す

photorans のクライアントを Expo + React Native + `react-native-vision-camera` 構成から、Swift によるフルネイティブ iOS アプリに作り直す。サーバ (`server/`, Hono + Claude Sonnet 4.6) はそのまま流用する。

ステータス: **実装中 (Phase1 完了 / Phase2 未着手)** / 開始日: 2026-04-30

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

#### Step3 サムネ表示 + フォーカス改善 (近接 AF / タップ AF)

- 撮影画面に直前のサムネ表示 (CameraView の隅に小さく)
- `device.autoFocusRangeRestriction = .near` + タップ AF (タップ位置を `pointOfInterest` に変換)
- 必要なら `setFocusModeLockedWithLensPosition` のスパイク
- 確認: Bitrise でビルド成功。AF 改善の効果検証は Phase7 (実機) で行う

### Phase3 ネットワーク層 (`/translate` 連携)

- `URLSession` ベースの multipart クライアント (`Sources/Networking/TranslateAPI.swift`)
- `EXPO_PUBLIC_API_URL` 相当のエンドポイントは `Info.plist` の `API_BASE_URL` (Build Configuration ごとに切替) で持つ
  - Debug: `http://10.0.1.137:3000` (LAN IP)
  - Release: `https://photorans.chobi.me`
- ATS: Debug ビルドのみ `NSAllowsArbitraryLoads = true` (LAN HTTP 用)、Release は HTTPS のみ
- `async throws -> TranslateResponse` で `originalText / translatedText / model` を返す
- 60s タイムアウト、ローカライズ済みエラーメッセージ
- 確認: 撮影画像を投げて 200 が返る、エラー系 (4xx / タイムアウト) のハンドリング

### Phase4 ローカル DB (SwiftData / Core Data)

- `HistoryEntry { id, createdAt, imagePath, originalText, translatedText, model }` モデル
- 撮影 → API 成功時に保存
- `ModelContainer` をアプリ起動時に初期化
- 確認: アプリ再起動後も履歴が残る

### Phase5 履歴一覧 + 詳細画面

- 一覧: `List` + `@Query` (SwiftData) で新着順、サムネ + 訳文先頭 2 行
- 詳細: 画像 (3:4) + 訳文 + 原文 + モデル名、テキストは長押しコピー可
- カメラタブから戻った時の自動更新 (`@Query` の自動反映で十分なはず)
- 確認: 撮影直後に一覧へ自動遷移、タップで詳細遷移、削除はスワイプ (実装するなら)

### Phase6 Bitrise コード署名 + TestFlight 提出 Workflow

- **App Store Connect API Key 発行** (akiraak@gmail.com の Apple Developer アカウント)
  - Issuer ID / Key ID / `AuthKey_*.p8` を Bitrise Secrets に登録
- **証明書 / プロビジョニングプロファイル**:
  - 既存 EAS 用の Distribution 証明書が App Store Connect にあるなら流用、なければ新規発行
  - Bitrise の `Manage iOS Code Signing` Step で自動管理 (推奨)、または `Code Signing & Files` に手動アップロード
- **`release` Workflow を追加**:
  - トリガ: `git tag v*` push
  - Step: `Certificate and profile installer` → `Xcode Archive & Export for iOS` (export method: `app-store`) → `Deploy to App Store Connect`
  - `buildNumber` は `$BITRISE_BUILD_NUMBER` で自動採番、既存 RN ビルドの最大値より大きい初期値を設定
- App Store Connect は既存 `com.akiraak.photorans` レコードを流用 ([testflight.md](testflight.md) Phase4-2 で作成済み)
- 確認: `git tag v0.1.0 && git push --tags` で Bitrise が IPA 生成 → TestFlight アップロード → Apple 処理完了 (5〜30 分) → iPhone の TestFlight アプリにビルドが届く

### Phase7 実機 TestFlight 動作確認

- 前提: `https://photorans.chobi.me/admin` に到達できること (testflight.md Phase4-5 と同条件)
- iPhone の TestFlight アプリでネイティブ photorans をインストール
- LAN 内: 撮影 → 翻訳 → 一覧 → 詳細
- LAN 外 (モバイル回線): 同フロー
- `https://photorans.chobi.me/admin` に履歴が積まれること
- 既存 TODO の AF / 横向き orientation 問題が解消されていること

### Phase8 旧 RN クライアントの撤去

- 並走期間 (Phase7 動作確認 + 1〜2 週間) を経て `client/` を削除
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
