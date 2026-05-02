# TODO

- [ ] 横向きの写真を撮りたい / 撮影範囲の WYSIWYG 化 ([plan](docs/plans/landscape-capture.md))
  - [x] Phase1 撮影範囲 WYSIWYG 化 (`videoGravity = .resizeAspect` + portrait レイアウト再設計)
    - [x] Step1-1 `CameraPreviewView.makeUIView` で `videoGravity` を `.resizeAspect` に変更
    - [x] Step1-2 `CameraView` を GeometryReader でレイアウト構成に変更し、画面上部に preview を貼って下部余白に bottomControls を配置 (portrait 想定)
    - [x] Step1-3 実機で「枠に映っている範囲 = 撮影される範囲」を確認、`/admin` で撮影画像の構図がプレビューと一致
  - [x] Phase2 プレビュー回転対応 (`CameraPreviewView` の connection 角度追従)
    - [x] Step2-1 `CameraViewModel` に `lastValidRotationAngle: CGFloat` を `@Observable` の var として導入。orientation observer のクロージャから `portrait` / `landscapeLeft` / `landscapeRight` のみを 90 / 0 / 180 に変換して書き込む (それ以外の向きは無視 = 直前値維持)。`capturePhoto` 内の `currentRotationAngle()` 呼び出しも同プロパティ参照に切替
    - [x] Step2-2 `CameraPreviewView.updateUIView` で受け取った角度を `previewLayer.connection?.videoRotationAngle` に反映 (`isVideoRotationAngleSupported` チェック)
    - [x] Step2-3 実機で `rot` / `dev` が landscape で更新されることを確認 (debug overlay)。映像の回転確認は landscape で shutter が押せないため Phase3-3 と統合
  - [x] Phase3 撮影 UI の回転追従 (B3' 純正カメラ portrait lock 準拠。UI / preview は portrait 固定、撮影画像だけ世界向き保存。B2 試行版は v0.1.9 で破棄、UI 回転待ちが 8 秒かかる問題)
    - [x] Step3-1 `Info.plist` の `UISupportedInterfaceOrientations` を portrait のみに戻す
    - [x] Step3-2 `CameraView` の GeometryReader 内を portrait 1 本のレイアウトに戻す (B2 切替を撤回)
    - [x] Step3-3 `CameraPreviewView` の `rotationAngle` 引数を撤去し、preview connection の `videoRotationAngle` を 90° (portrait sensor 向き) で常時固定
    - [x] Step3-4 実機で portrait UI 固定で持ち替えても回転待ちが起きないこと、横持ち撮影画像がサーバ `/admin` で横長保存されていることを確認
  - [x] Phase4 履歴詳細の画像表示をアスペクト比追従に変更
    - [x] Step4-1 `Image` を `.scaledToFit()` + `.frame(maxWidth: .infinity)` に置換
    - [x] Step4-2 プレースホルダは 3:4 (portrait) を維持 — 画像がない時の仮表示はデフォルト用途 (縦) に合わせる
    - [x] ~~Step4-3~~ 履歴一覧サムネ (`HistoryRowView.thumbnail`) の実機確認は別 TODO に分離
  - [x] Phase5 EXIF orientation の正常性検証 (向き崩れなし、追加修正不要)
    - [x] Step5-1 実機で landscape / portrait 撮影 → server `/admin/:id/image` および履歴詳細で正常表示を確認
    - [x] ~~Step5-2~~ orientation 崩れなし、`ImageCompressor` への正規化追加は不要
  - [ ] Phase6 仕上げ (リグレッション確認、TODO クローズ)
    - [ ] Step6-1 portrait 撮影が以前と同等以上 (WYSIWYG 化分は前進)
    - [ ] Step6-2 撮影中の回転 / 高速タップでクラッシュしない
    - [ ] Step6-3 TODO.md → DONE.md (両 TODO 項目を統合してクローズ)、本プランを `docs/plans/archive/` に移動
- [ ] 利用トークンと料金を管理画面に表示
    必要に応じて画像の解像度の調整でトークン量を下げる。文字お越しの性能との兼ね合い
- [ ] 履歴画面の設計
    メインコンテンツを翻訳済みにして、カメラはメインコンテンツ画面下にカメラ起動ボタンを付けて起動させるものでよい
- [ ] カメラの機能強化の調査
  - [ ] ズーム
