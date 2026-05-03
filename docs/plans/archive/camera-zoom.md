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

### 並行性の不変条件

`CameraSession` は `@unchecked Sendable` で、`device` / `isConfigured` 等の状態は `sessionQueue` 専有とする (既存方針)。MainActor 側 (ViewModel) からは以下のみが許容される:

- `start()` / `stop()` / `capturePhoto(rotationAngle:)` / `focus(at:)` の呼び出し (既存)
- 新規 `setZoomFactor(_:)` / `resetZoomToInitial()` の呼び出し (内部で `sessionQueue.async`)
- `configureIfNeeded` 完了時に CameraSession から MainActor へハンドオフされる **スナップショット値** (`maxZoomFactor` / `isVirtualDevice` / 現在 zoom) の参照

**禁止**: MainActor から `device` プロパティや `isVirtualDevice` フラグを直接読まない (sessionQueue 専有値の競合読みになるため)。HUD 表記変換に必要な `isVirtualDevice` は ViewModel が `@Observable` のミラー値として保持する。

## 影響範囲

| ファイル | 変更内容 |
|---|---|
| `ios/Photorans/Features/Camera/CameraSession.swift` | デバイス選定を `DiscoverySession` 経由に変更。zoom API (`setZoomFactor(_:)` / `resetZoomToInitial()` + 設定完了通知) を追加 |
| `ios/Photorans/Features/Camera/CameraViewModel.swift` | `zoomFactor` / `maxZoomFactor` / `isVirtualDevice` を `@Observable` ミラーとして保持、`onAppear` で `resetZoomToInitial()` 呼び出し、ピンチ用 `updateZoom(scale:state:)` 追加 |
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

「ユーザから見える挙動はほぼ変わらない」状態でデバイス取得経路だけを差し替える。

- `CameraSession.configureIfNeeded()` の `AVCaptureDevice.default(.builtInWideAngleCamera, ...)` を `DiscoverySession` に置換 (`[.builtInTripleCamera, .builtInDualWideCamera, .builtInWideAngleCamera]` の順、`mediaType: .video`, `position: .back`)
- `CameraSession` 内部に `sessionQueue` 専有の状態として保持:
  - `private var isVirtualDevice: Bool = false` (Triple / DualWide なら true)
  - `private var initialZoomFactor: CGFloat = 1.0` (仮想デバイスなら 2.0、Wide 単独なら 1.0)
- `CameraSession.configureIfNeeded()` の最後で、`device.lockForConfiguration` 経由で `device.videoZoomFactor = initialZoomFactor` を適用 (`.continuousAutoFocus` 設定と同じ lock 内でまとめて行う)
- 既存 `configureFocus` ロジックはそのまま維持 (`.near` AF は仮想デバイスでも `isAutoFocusRangeRestrictionSupported` ガードで動作)
- **MainActor 側はまだ何も読まない** (Phase2 でハンドオフ経路を作るまで `isVirtualDevice` は CameraSession 内部に閉じる)
- 検証: ユーザ視点で挙動の変化はほぼ無いはずだが、デバイス classification の変更 (物理 Wide → 仮想 Triple/DualWide) によって以下の差が出る可能性があるので意識する:
  - 起動時の最初のフレーム到達がわずかに遅れる端末がある (constituent 全体の準備)
  - Triple 端末で factor=2.0 = switchover 境界点直前/直後にチラつき
  - 仮想デバイスのスティッチング処理に伴う色味/シャープネスの微差
  Pro / DualWide / Wide 単独 いずれの端末でも明確な回帰がないことを TestFlight で確認
- TestFlight タグ: Phase3 完了後にまとめて 1 回 push する (Phase1 単独では切らない)。Phase4 で起動時間悪化や preview チラつきが出た場合、Phase1 (デバイス変更) と Phase3 (gesture/HUD) を bisect する必要が生じうる点は受け入れる

### Phase2 CameraSession に zoom API 追加 + ViewModel 状態化

UI から呼ぶ口を作る。まだ UI からは呼ばないので可視変化なし。

#### CameraSession に追加

すべて `sessionQueue` 専有の操作。MainActor 側へは callback で snapshot を渡す。

- `struct ZoomSnapshot: Sendable { let isVirtualDevice: Bool; let initialFactor: CGFloat; let minFactor: CGFloat; let maxFactor: CGFloat }`
- `var onConfigured: (@Sendable (ZoomSnapshot) -> Void)?` — `configureIfNeeded()` の末尾で snapshot を組んで MainActor (ViewModel) に通知。1 度だけ呼ばれる
- `func setZoomFactor(_ factor: CGFloat)`:
  ```swift
  sessionQueue.async { [self] in
      guard isConfigured, let device else { return }      // permission denied / 未設定時は no-op
      do {
          try device.lockForConfiguration()
          defer { device.unlockForConfiguration() }
          let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
          device.videoZoomFactor = clamped
      } catch {
          logger.error("setZoomFactor lockForConfiguration 失敗: ...")
      }
  }
  ```
- `func resetZoomToInitial()`:
  ```swift
  sessionQueue.async { [self] in
      guard isConfigured, let device else { return }
      // isVirtualDevice / initialZoomFactor は Phase1 で sessionQueue 専有として保持済み
      // lockForConfiguration → device.videoZoomFactor = initialZoomFactor
  }
  ```
  MainActor から `isVirtualDevice` を読まずに済ませることで、`configureIfNeeded` 完了との順序競合を消す

**意図的に提供しない API**: `currentZoomFactor()` / `maxZoomFactor` / `isVirtualDevice` の MainActor 直接 read。これらは ViewModel が `onConfigured` snapshot で受け取ったあとは ViewModel 側のミラー値を使う (gesture handler が更新する `zoomFactor` がそのまま HUD に流れる)。`sessionQueue.sync` で MainActor を block する経路を作らない。

#### CameraViewModel に追加

- `var zoomFactor: CGFloat = 1.0` (AVFoundation 値そのまま保持。HUD 表示の真実値)
- `var maxZoomFactor: CGFloat = 1.0` (`onConfigured` 受信時に上書き)
- `var isVirtualDevice: Bool = false` (`onConfigured` 受信時に上書き、HUD 表記変換用)
- `private var pinchStartFactor: CGFloat = 1.0`
- `var isPinching: Bool = false` (HUD 不透明度に使う)
- `var displayZoomLabel: String` (computed):
  - 仮想デバイス: `String(format: "%.1fx", zoomFactor / 2)`
  - Wide 単独: `String(format: "%.1fx", zoomFactor)`
- `init` (or `onAppear` 1 回目) で `camera.onConfigured = { [weak self] snapshot in Task { @MainActor in self?.applySnapshot(snapshot) } }` をセット
- `func updateZoom(scale: CGFloat, state: UIGestureRecognizer.State)`:
  - `.began`: `pinchStartFactor = zoomFactor; isPinching = true`
  - `.changed`: `let target = pinchStartFactor * scale; let clamped = min(max(target, 1.0), maxZoomFactor); zoomFactor = clamped; camera.setZoomFactor(clamped)`
  - `.ended` / `.cancelled` / `.failed`: `isPinching = false`
  - 注意: `state` の型は SwiftUI の `GestureState` (property wrapper) ではなく **UIKit の `UIGestureRecognizer.State` (enum)**
- `onAppear` の最後で `camera.resetZoomToInitial()` を呼び、`zoomFactor` も `isVirtualDevice ? 2.0 : 1.0` で MainActor 側ミラーをリセット (`onConfigured` snapshot の `initialFactor` を使う形でも可)

検証: ユニットテスト or プレビュー確認のみ。UI からの呼び出しは Phase3 で配線するので、Phase2 単独では実機反映なし

### Phase3 ピンチジェスチャ + 倍率 HUD

ユーザにズーム機能を露出する。

- `CameraPreviewView`:
  - `var onPinch: (@MainActor (_ scale: CGFloat, _ state: UIGestureRecognizer.State) -> Void)?` を追加
  - `makeUIView` で `UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))` を `addGestureRecognizer`
  - `Coordinator.handlePinch` で `recognizer.scale` と `recognizer.state` を `onPinch` に渡す。`.ended` / `.cancelled` / `.failed` で `recognizer.scale = 1` リセット
  - 既存 `UITapGestureRecognizer` (1 本指) と `UIPinchGestureRecognizer` (2 本指) は finger count で UIKit が排他判定するため `requireToFail` 等の追加設定は不要
- `CameraView`:
  - `CameraPreviewView` の呼び出しに `onPinch: { scale, state in viewModel.updateZoom(scale: scale, state: state) }` を追加
  - `previewSection` 内 `ZStack` に倍率 HUD を overlay。修飾子順序に注意 (`maxHeight: .infinity` の **前** に `padding(.top, 16)`):
    ```swift
    Capsule()
        .fill(.black.opacity(0.5))
        .overlay(Text(viewModel.displayZoomLabel).font(.caption).foregroundStyle(.white))
        .frame(width: 56, height: 28)        // Capsule のサイズは固定で良い (1.0x ~ 5.0x で文字幅変化なし)
        .opacity(viewModel.isPinching ? 1.0 : 0.6)
        .animation(.easeOut(duration: 0.2), value: viewModel.isPinching)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    ```
  - HUD の不透明度: ピンチ中 1.0 / それ以外 0.6 (linger 無し。research プランの「ピンチ終了後 1.5s linger」は MVP では落とす — 必要なら後追い)
- 検証: 実機で 1) ピンチで滑らかにズーム、2) HUD が現在倍率を正しく表示、3) 既存タップ AF が壊れない、4) 撮影中ピンチが clear に直列化されること
- TestFlight タグ push: Phase1〜3 まとめて。タグメッセージは「カメラズーム実装 (ピンチ + 仮想デバイス自動切替)」相当

### Phase4 リリース後ベリフィケーション (TestFlight 1 ラウンド)

実装後、Akira さんの実機で以下を確認:

- **起動時の preview 到達時間** が現状から悪化しないこと (体感 OK で十分。stopwatch は不要)
- **switchover 挙動 (上方向)**: Triple 端末で 1x → 5x までピンチでスイープし、preview に明確な黒フレーム / 数秒級フリーズが出ないこと
- **switchover 挙動 (下方向)**: 仮想デバイス端末 (Triple / DualWide) で 1x → 0.5x までピンチアウトし、UltraWide への切替が滑らかに行われること。`videoZoomFactor=2` 境界をまたぐ瞬間の挙動を上方向と同じ基準で確認
- **OCR 精度比較**: 同一被写体 (テキスト密集の看板等) を 0.5x / 1x / 2x / 3x / 5x で撮影 → `/translate` 結果の `originalText` を比較し、ズーム上昇で文字認識が改善 (悪化していない) ことを確認。撮影位置・照明・手ブレを揃えるため三脚 or 固定面に置いて行う
- **既存機能の回帰**: タップ AF / 撮影 / 履歴保存 / 翻訳結果遷移 が壊れていないこと
- **portrait lock**: 端末を横にしても UI / preview が縦固定のままであること
- **撮影画像の世界向き**: 撮影 JPEG が世界向きで保存されること (history detail で確認)
- **権限 denied 経路**: 設定アプリでカメラ権限を一旦オフにしてから起動 → 「カメラへのアクセスが許可されていません」表示が出ることと、`setZoomFactor` / `resetZoomToInitial` の no-op ガードが効いて crash しないこと

確認結果が NG なら: 該当 Phase まで戻して修正 → 再 TestFlight。NG が `.near` AF と Telephoto の干渉だった場合は、switchover threshold を超えたら自動的に `.near` を解除する分岐を追加する (現状は未実装)。

OK なら: 親 TODO「カメラズーム実装」を `DONE.md` に移送、本ファイルを `docs/plans/archive/` に移動。

## テスト方針

- Phase1, Phase2 単独では UI 変化なしのため自動テストは書かない (CameraSession の構成は実機 AVFoundation 依存で unit test しにくい既存方針に合わせる)
- Phase3 完了時点で TestFlight 1 ラウンドを Phase4 として消費。CLAUDE.md「実機確認ルート」に従いタグ push は Akira さん確認の上で行う
- 回帰の温度: 過去 `landscape-capture` で 8 秒ブラックアウトを踏んだ前例がある。Phase4 ベリフィケーションでは「preview 起動時間 / switchover 時のフリーズ」の 2 点を最優先で見る

## 非ゴール / 既知の制約

- **アクセシビリティ**: ピンチ専用 = VoiceOver / Switch Control ユーザは zoom を使えない。MVP ではこの制約を受け入れる。research Phase2 結論で「プリセットボタンは実機 dogfooding でフィードバックが出てから検討」としており、その検討時にアクセシビリティも併せて扱う
- **背景/前景遷移時の zoom リセット**: `onAppear` reset は CameraView の出入りでのみ発火する。アプリを background → foreground 復帰したケースでは `videoZoomFactor` は device プロパティとして保持されたままになる (session の stop/start でデバイス状態は維持される)。これは現状仕様として許容
