# カメラズーム実装

photorans カメラ画面にピンチズーム + 仮想デバイス自動切替 (光学ズーム) を追加する実装プラン。

ステータス: **着手前** / 起票日: 2026-05-02

調査プラン (本実装の根拠) は `docs/plans/archive/camera-zoom-research.md` を参照。

## 目的・背景

- 看板・本・遠めのテキストなど被写体に近づけない状況で OCR 撮影を成立させる
- iPhone Pro 系の Telephoto を活用すれば 2048px キャップ (`ImageCompressor`) 後でも文字エッジが鮮明 ⇒ OCR にネット positive
- DualWide / Wide 単独端末でも digital zoom はフレーミング向上 (被写体あたりの実画素数増加) で OCR にプラス
- 「カメラ画面でピンチが効かない」現状は現代ユーザの暗黙の期待を裏切るので、UX 上も入れる価値が高い

## 採用方針 (research プラン Phase4 結論より)

| 項目 | 仕様 |
|---|---|
| デバイス選定 | `AVCaptureDevice.DiscoverySession` で Triple → DualWide → Wide 単独 の優先順位検索 |
| ズーム操作 | ピンチジェスチャのみ (プリセットボタン/ボタン UI は出さない) |
| 倍率上限 | `device.maxAvailableVideoZoomFactor` でクランプ |
| 起動時の初期倍率 | 仮想デバイスは AVFoundation `videoZoomFactor=2.0` (= 純正 1.0x = Wide FOV) / Wide 単独は `1.0` |
| 倍率の永続化 | しない。`onAppear` で毎回初期倍率にリセット |
| HUD 表示 | preview 上に `Capsule + Text("1.0x")`。仮想デバイスは `factor / 2` で純正 UI 風に整形 |
| 撮影中ズーム変更 | `sessionQueue.async` + `device.lockForConfiguration` で直列化 |

## 影響範囲

| ファイル | 変更内容 |
|---|---|
| `ios/Photorans/Features/Camera/CameraSession.swift` | デバイス選定を `DiscoverySession` 経由に変更。zoom API (`setZoomFactor` / `currentZoomFactor` / `maxZoomFactor` / `isVirtualDevice`) を追加 |
| `ios/Photorans/Features/Camera/CameraViewModel.swift` | `zoomFactor` 状態追加、`onAppear` で初期倍率セット、ピンチ用 `updateZoom(scale:state:)` 追加 |
| `ios/Photorans/Features/Camera/CameraPreviewView.swift` | `UIPinchGestureRecognizer` を追加。`Coordinator` に zoom closure を 1 本追加 |
| `ios/Photorans/Features/Camera/CameraView.swift` | `CameraPreviewView` 呼び出しに onPinch closure を渡す。preview overlay に倍率 HUD を追加 |

**変更しない (research プラン「既存コードの前提」より)**:
- `configureFocus` の `.continuousAutoFocus` + `.near` + `.continuousAutoExposure`
- `Info.plist` の portrait lock + preview connection `videoRotationAngle = 90`
- `capturePhoto(rotationAngle:)` の世界向き焼き込み
- `ImageCompressor.compressForUpload` の長辺 ≤ 2048px / base64 ≤ 5 MiB
- session 再構成 (input 差し替え) は **やらない**。仮想デバイスを最初から入力に入れて switchover に任せる

## Phase 分解

### Phase1 デバイス選定を DiscoverySession に切替 + 初期倍率セット

「ユーザから見える挙動は変わらない」状態でデバイス取得経路だけを差し替える。

- `CameraSession.configureIfNeeded()` の `AVCaptureDevice.default(.builtInWideAngleCamera, ...)` を `DiscoverySession` に置換 (`[.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]` の順、`mediaType: .video`, `position: .back`)
- `CameraSession` に `private(set) var isVirtualDevice: Bool` を追加 (Triple / DualWide なら true)
- `CameraSession.configureIfNeeded()` の最後で、仮想デバイスなら `device.videoZoomFactor = 2.0`、Wide 単独なら `1.0` を `lockForConfiguration` 経由で適用
- 既存 `configureFocus` ロジックはそのまま維持 (`.near` AF は仮想デバイスでも `isAutoFocusRangeRestrictionSupported` ガードで動作)
- 検証: ユーザ視点で挙動変化なし (preview は依然として「純正 1.0x = Wide FOV」相当に見える)。Pro / DualWide / Wide 単独 いずれの端末でも回帰しないことを TestFlight で確認
- TestFlight タグ: Phase3 完了後にまとめて 1 回 push する (Phase1 単独では切らない)

### Phase2 CameraSession に zoom API 追加 + ViewModel 状態化

UI から呼ぶ口を作る。まだ UI からは呼ばないので可視変化なし。

- `CameraSession` に追加:
  - `var maxZoomFactor: CGFloat { device?.maxAvailableVideoZoomFactor ?? 1.0 }` (MainActor 側 read 用)
  - `var minZoomFactor: CGFloat { device?.minAvailableVideoZoomFactor ?? 1.0 }`
  - `func setZoomFactor(_ factor: CGFloat)`: `sessionQueue.async` 内で `lockForConfiguration` を取り、`max(min(factor, maxAvailableVideoZoomFactor), minAvailableVideoZoomFactor)` でクランプして `device.videoZoomFactor` に代入
  - `func currentZoomFactor() -> CGFloat`: 現在値を取り出す (UI HUD 用; `sessionQueue.sync` で device から読む or 別の publish 機構)
- `CameraViewModel` に追加:
  - `var zoomFactor: CGFloat` (AVFoundation 値そのまま保持)
  - `var displayZoomLabel: String` (computed: 仮想デバイスなら `String(format: "%.1fx", zoomFactor / 2)`、Wide 単独なら `String(format: "%.1fx", zoomFactor)`)
  - `func updateZoom(scale: CGFloat, state: GestureState)`: ピンチの scale を受けて `startFactor * scale` をクランプして `camera.setZoomFactor` を呼び、`zoomFactor` も更新
  - `onAppear` の最後で初期 `zoomFactor` を `camera.isVirtualDevice ? 2.0 : 1.0` にセット (Phase1 で既に設定済みだが、再 onAppear 時のリセット保証)
- 検証: ユニットテスト or プレビュー確認のみ。UI からの呼び出しは Phase3 で配線するので、Phase2 単独では実機反映なし

### Phase3 ピンチジェスチャ + 倍率 HUD

ユーザにズーム機能を露出する。

- `CameraPreviewView`:
  - `var onPinch: (@MainActor (_ scale: CGFloat, _ state: UIGestureRecognizer.State) -> Void)?` を追加
  - `makeUIView` で `UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))` を `addGestureRecognizer`
  - `Coordinator.handlePinch` で `recognizer.scale` と `recognizer.state` を `onPinch` に渡す。`.ended` / `.cancelled` / `.failed` で `recognizer.scale = 1` リセット
- `CameraView`:
  - `CameraPreviewView` の呼び出しに `onPinch: { scale, state in viewModel.updateZoom(scale: scale, state: state) }` を追加
  - `previewSection` 内 `ZStack` に倍率 HUD を overlay (`Capsule().fill(.black.opacity(0.5))` + `Text(viewModel.displayZoomLabel).font(.caption).foregroundStyle(.white)` を `padding(.horizontal, 12).padding(.vertical, 6)` で囲み、上端中央に `.frame(maxHeight: .infinity, alignment: .top).padding(.top, 16)`)
  - HUD の不透明度: ピンチ中 1.0 / それ以外 0.6 (アニメーションは withAnimation で 0.2s)
- `CameraViewModel`:
  - `isPinching: Bool` 状態を追加 (HUD 不透明度に使う)
  - `updateZoom` の state ハンドリングで `.began` → `startFactor = zoomFactor; isPinching = true`、`.changed` → 値更新、`.ended/cancelled/failed` → `isPinching = false`
- 検証: 実機で 1) ピンチで滑らかにズーム、2) HUD が現在倍率を正しく表示、3) 既存タップ AF が壊れない、4) 撮影中ピンチが clear に直列化されること
- TestFlight タグ push: Phase1〜3 まとめて。タグメッセージは「カメラズーム実装 (ピンチ + 仮想デバイス自動切替)」相当

### Phase4 リリース後ベリフィケーション (TestFlight 1 ラウンド)

実装後、Akira さんの実機で以下を確認:

- **起動時の preview 到達時間** が現状から悪化しないこと (体感 OK で十分。stopwatch は不要)
- **switchover 挙動**: Triple 端末で 1x → 5x までピンチでスイープし、preview に明確な黒フレーム / 数秒級フリーズが出ないこと
- **OCR 精度比較**: 同一被写体 (テキスト密集の看板等) を 1x / 2x / 3x / 5x で撮影 → `/translate` 結果の `originalText` を比較し、ズーム上昇で文字認識が改善 (悪化していない) ことを確認
- **既存機能の回帰**: タップ AF / 撮影 / 履歴保存 / 翻訳結果遷移 が壊れていないこと
- **portrait lock**: 端末を横にしても UI / preview が縦固定のままであること
- **撮影画像の世界向き**: 撮影 JPEG が世界向きで保存されること (history detail で確認)

確認結果が NG なら: 該当 Phase まで戻して修正 → 再 TestFlight。NG が `.near` AF と Telephoto の干渉だった場合は、switchover threshold を超えたら自動的に `.near` を解除する分岐を追加する (現状は未実装)。

OK なら: 親 TODO「カメラズーム実装」を `DONE.md` に移送、本ファイルを `docs/plans/archive/` に移動。

## テスト方針

- Phase1, Phase2 単独では UI 変化なしのため自動テストは書かない (CameraSession の構成は実機 AVFoundation 依存で unit test しにくい既存方針に合わせる)
- Phase3 完了時点で TestFlight 1 ラウンドを Phase4 として消費。CLAUDE.md「実機確認ルート」に従いタグ push は Akira さん確認の上で行う
- 回帰の温度: 過去 `landscape-capture` で 8 秒ブラックアウトを踏んだ前例がある。Phase4 ベリフィケーションでは「preview 起動時間 / switchover 時のフリーズ」の 2 点を最優先で見る
