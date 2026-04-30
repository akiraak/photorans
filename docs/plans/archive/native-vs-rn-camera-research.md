# Native カメラ vs React Native カメラの機能差分調査

## 目的・背景

photorans は現在 Expo + React Native + `react-native-vision-camera` v5 でカメラ機能を実装している。Phase4 の TestFlight 提出で VisionCamera Release WMO クラッシュ問題（[plan](testflight-vision-camera-release-fix.md)）に直面しており、Native（Swift / Kotlin）実装へ切り替えるべきかの判断材料を得るためにも、両者の機能差分を整理しておきたい。

具体的に答えを得たい問い:

1. iOS / Android の Native カメラ API（AVFoundation / Camera2 / CameraX）でしか実現できない機能は何か
2. 逆に React Native（特に vision-camera）でしか or の方が容易に実現できる機能は何か
3. 既出 TODO（カメラ横向き対応、フォーカス問題、TestFlight Release クラッシュ）が Native 実装でどう変わるか

## 対応方針

ドキュメントベースの調査タスクとし、コードは変更しない。成果物は本ファイルへ「調査結果」セクションとして追記する。

調査ソース:
- React Native vision-camera 公式ドキュメント (https://react-native-vision-camera.com/)
- expo-camera 公式ドキュメント (Expo SDK 対応版の参考として)
- Apple AVFoundation / AVCaptureSession ドキュメント
- Android CameraX / Camera2 ドキュメント
- 必要に応じて GitHub Issues (vision-camera) で既知の制約を確認

## 調査範囲

以下の観点で機能マトリクスを作成する。

| カテゴリ | 比較項目 |
| --- | --- |
| 撮影基本 | 解像度・FPS・写真フォーマット (HEIC/JPEG/RAW/ProRAW) |
| フォーカス | タップ AF、連続 AF、距離指定、マニュアルフォーカス |
| 露出・WB | 露出補正、ISO/シャッター固定、ホワイトバランス制御 |
| ズーム | デジタル/光学、マルチカム切替、超広角・望遠選択 |
| センサー | 向き検出、ジャイロ連動、HDR、Night mode |
| 解析・処理 | フレームプロセッサ、ML 推論連携、リアルタイム OCR |
| OS 機能 | Live Photos, Portrait, Cinematic, Apple ProRAW, Android Pro Mode |
| 配信・連携 | プレビュー描画パイプライン、Skia/Metal 連携、撮影音制御 |
| 配布・運用 | iOS Release ビルドの安定性（TestFlight クラッシュ含む）、Expo 互換性、新アーキ対応 |

photorans の現在 TODO に直結する項目は別途強調する:
- カメラ横向き対応（EXIF orientation の扱い）
- AF 不発の根本原因（VisionCamera の制約か iOS API か）
- Release WMO クラッシュ（VisionCamera 固有 / Native では発生しない）

## 影響範囲

- 本タスク自体はコード変更なし
- 調査結果に基づき、別タスクとして以下のいずれかが派生し得る
  - VisionCamera 維持 + 個別問題のワークアラウンド
  - expo-camera への切替検討
  - iOS のみ Native（Swift）モジュール化、Android は RN 維持などのハイブリッド方針

## 成果物

- 本ファイル末尾に「調査結果」「比較表」「推奨方針」セクションを追記
- 重要な結論・派生タスクは `TODO.md` に転記

## Phase / Step

- Step1 機能マトリクス作成（vision-camera / expo-camera / iOS Native / Android Native）
- Step2 photorans 既出 TODO 3 件への影響評価
- Step3 推奨方針サマリと派生 TODO 抽出

---

## 調査結果

### 用語

- **VC** = `react-native-vision-camera` v5 系（Margelo Nitro Modules ベース）
- **EXC** = `expo-camera`（Expo SDK 同梱）
- **iOS-N** = AVFoundation / AVCaptureSession を直接叩く Swift ネイティブ実装
- **And-N** = CameraX または Camera2 を直接叩く Kotlin ネイティブ実装

### Step1 機能マトリクス

凡例: ✅ 一級サポート / ⚠️ 部分対応・制限あり / ❌ 不可 or 非公開

| # | カテゴリ / 機能 | VC | EXC | iOS-N | And-N |
|---|---|---|---|---|---|
| 1 | JPEG / HEIC 静止画 | ✅ | ⚠️ JPG/PNG のみ | ✅ | ✅ |
| 2 | RAW（Bayer / DNG） | ✅ | ❌ | ✅ | ✅ Camera2 |
| 3 | Apple ProRAW | ✅ | ❌ | ✅ | — |
| 4 | Apple ProRes 動画 | ❌ | ❌ | ✅ | — |
| 5 | Apple Log（iOS17+） | ❌ | ❌ | ✅ | — |
| 6 | Live Photos | ❌ | ❌ | ✅ | — |
| 7 | Portrait（被写界深度マット） | ⚠️ depth ストリームのみ | ❌ | ✅ | ⚠️ OEM 依存 |
| 8 | Cinematic Video（iOS17+） | ❌ | ❌ | ✅ | — |
| 9 | Spatial Video（iPhone15 Pro+） | ❌ | ❌ | ✅ | — |
| 10 | HDR / Dolby Vision 動画 | ⚠️ HDR は constraint で要求可、Dolby Vision 不可 | ❌ | ✅ | ⚠️ CameraX/OEM 依存 |
| 11 | Night / Smart HDR / Deep Fusion | ❌ 直接 API 無し（OS が透過適用） | ❌ | ✅ | — |
| 12 | タップ AF | ✅ `enableNativeTapToFocusGesture` または `focusTo()` | ⚠️ on/off のみ | ✅ | ✅ |
| 13 | 連続 AF | ✅ デフォルト continuous metering | ⚠️ on/off | ✅ | ✅ |
| 14 | マニュアル lens position（焦点距離指定） | ❌ 公開 API 無し | ❌ | ✅ `setFocusModeLockedWithLensPosition` | ✅ Camera2 LENS_FOCUS_DISTANCE |
| 15 | Auto Focus Range Restriction（近接 / 遠景） | ❌ | ❌ | ✅ | ⚠️ |
| 16 | iPhone15 Pro マクロ自動切替 | ❌ 既知 issue #2246（minFocusDistance + zoom 手動調整で代替） | ❌ | ✅ OS が自動切替 | — |
| 17 | フロントカメラの tap-to-focus | ❌ 既知 issue #2622 | ❌ | ✅ | ✅ |
| 18 | 露出補正 / マニュアル ISO / シャッター | ✅ V5 で full manual | ❌ | ✅ | ✅ |
| 19 | ホワイトバランスマニュアル | ✅ | ❌ | ✅ | ✅ |
| 20 | デジタルズーム | ✅ | ✅ 0–1 | ✅ | ✅ |
| 21 | 物理レンズ切替（ultra-wide/tele/macro） | ✅ multi-physical-device | ⚠️ iOS のみ `selectedLens` | ✅ | ✅ Android11+ |
| 22 | 同時マルチカム（前後同時撮影） | ✅ | ❌ | ✅ AVCaptureMultiCamSession | ✅ Android11+ Concurrent |
| 23 | フレームプロセッサ / 生フレーム処理 | ✅ C++/JSI、GPU-backed | ❌（生フレーム露出無し） | ✅ AVCaptureVideoDataOutput | ✅ ImageAnalysis |
| 24 | リアルタイム OCR（端末上） | ✅ Frame Processor + MLKit/Vision plugin | ❌ | ✅ Vision フレームワーク統合 | ✅ MLKit |
| 25 | バーコード / QR スキャン | ✅ | ✅ 種類豊富 | ✅ Vision/AVMetadataOutput | ✅ MLKit |
| 26 | プレビュー描画パイプライン | ✅ Skia/Metal 連携、GPU 直結 | ⚠️ JS bridge 経由でラグ | ✅ Metal 直結 | ✅ OpenGL/Vulkan |
| 27 | 撮影音 mute（iOS シャッター音） | ⚠️ region 依存（OS 制約） | ⚠️ | ⚠️ 同上 | ✅ |
| 28 | 端末向き検出 / EXIF orientation | ✅ orientation prop + EXIF | ✅ 自動回転 | ✅ | ✅ |
| 29 | Zero-Shutter-Lag / DeferredPhotoProxy | ❌ | ❌ | ✅ iOS17+ | ⚠️ |
| 30 | Expo（Dev Client / EAS）互換 | ✅ Config plugin 標準 | ✅ ファーストクラス | ❌ 自前 native module 化が必要 | ❌ 同左 |
| 31 | 新アーキ（Fabric / TurboModule） | ✅ V5 | ✅ | — | — |
| 32 | iOS Release WMO ビルド安定性 | ⚠️ 5.0.x 系で Xcode26 + RN0.78 + Release WMO クラッシュ既知 | ✅ | ✅ | — |
| 33 | クロスプラットフォーム単一実装 | ✅ | ✅ | ❌ | ❌ |

### Step2 既出 TODO への影響評価

#### (a) 横向き撮影時に画像と表示も横向きにする
- **VC で実現可能**。`Camera` の `orientation` prop と `takePhoto()` 戻り値の EXIF orientation で対応可能。実装側で EXIF を尊重して表示・送信前に正規化すれば良い。
- Native 化しても得られるメリットは大きくない（API 自由度は上がるが解決方法は同質）。
- 既知の歴史的バグ（issue #818, vision-camera 2.x 系）は v5 では解消済み。

#### (b) フォーカスが合わない
- 原因は OCR ターゲットが至近距離にあり、AF が遠景に張り付くケース。
- VC v5 の制約: lens position 指定不可、AF Range Restriction 不可、iPhone15 Pro のマクロ自動切替不可。回避策は `device.minimumFocusDistance` から逆算した `zoom` を当てて被写体距離を物理的に確保する（issue #2246 で公式回答）。
- iOS Native なら `setFocusModeLockedWithLensPosition` や `autoFocusRangeRestriction = .near`、マクロ自動切替（OS 任せ）まで使える。**ここが Native 化の唯一の実利**。
- 結論: まずは VC + zoom 補正で改善を試み、それでも不足なら iOS のみ Native モジュール化を検討する余地あり。

#### (c) TestFlight production ビルドの VisionCamera Release WMO クラッシュ
- VC 固有問題。Native 化すれば消滅。
- ただし既存プラン `testflight-vision-camera-release-fix.md` の config plugin（対象 Pod のみ WMO 無効化）で十分対処できる範囲。
- Native 化は本件単独では割に合わない（影響面が大きすぎる）。

### Step3 推奨方針

1. **当面は VC v5 を維持**する。photorans の用途（OCR 画像取得 → サーバ送信）には manual exposure / focus / multi-lens / フレームプロセッサ等、必要十分な API が揃っている。Native 化は得られる果実（Live Photos, Cinematic, lens position 直接指定）に対してコストが高すぎる。
2. **Native 化を検討する条件**は次のいずれかが起きた時:
   - フォーカス問題が `minimumFocusDistance` ベースの zoom 補正でも解決しない
   - OCR 精度向上のため iOS Vision フレームワークの近接距離専用 AF や RAW + Smart HDR が必要になった
   - VC のメンテナンス停滞や RN 新アーキ非互換が長期化した
3. **iOS のみ部分 Native 化**は将来の選択肢として残す。React Native との橋渡しは TurboModule または Native Module で `AVCaptureSession` を包み、撮影だけ Native、それ以外（一覧 / 詳細 / 翻訳）は RN のままにできる。
4. **expo-camera への切替は非推奨**。生フレーム不可・マニュアル制御不足・RAW 不可で、photorans の用途・将来拡張（端末上 OCR への切替可能性）と相性が悪い。

### 派生 TODO 候補

- カメラ AF 不発対応として `device.minimumFocusDistance` ベースの自動 zoom を実装し、近接被写体での合焦率を確認する
- 横向き撮影時の EXIF orientation 正規化（撮影直後 / 表示時 / 送信時の各レイヤで一貫させる）
- 上記対応後も AF 改善が不十分な場合、iOS のみ Native カメラ Module 化のスパイク
- vision-camera のバージョン追従ポリシー（5.x の patch 取り込み判断基準）を README / CLAUDE.md に明記

### 参考リンク

- [VisionCamera Getting Started](https://visioncamera.margelo.com/docs)
- [VisionCamera v5 announcement / features](https://react-native-vision-camera.com/docs/guides/vision-camera-v5)
- [VisionCamera Focusing guide](https://visioncamera.margelo.com/docs/guides/focusing)
- [VisionCamera Frame Processors guide](https://visioncamera.margelo.com/docs/guides/frame-processors)
- [VisionCamera Camera Formats / Constraints](https://visioncamera.margelo.com/docs/guides/formats)
- [Issue #818 takePhoto landscape orientation on iOS](https://github.com/mrousavy/react-native-vision-camera/issues/818)
- [Issue #2246 iPhone15 Pro macro auto-switch not working](https://github.com/mrousavy/react-native-vision-camera/issues/2246)
- [Issue #2622 front camera tap-to-focus](https://github.com/mrousavy/react-native-vision-camera/issues/2622)
- [Issue #1938 Camera.focus has no effect](https://github.com/mrousavy/react-native-vision-camera/issues/1938)
- [Expo Camera SDK reference](https://docs.expo.dev/versions/latest/sdk/camera/)
- [AVFoundation: Capturing still and Live Photos](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/capturing_still_and_live_photos)
- [WWDC23 — Create a more responsive camera experience](https://developer.apple.com/videos/play/wwdc2023/10105/)
- [Expo vs VisionCamera 比較記事](https://blog.patrickskinner.tech/react-native-camera-expo-vs-visioncamera-what-you-need-to-know)
