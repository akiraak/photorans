# カメラズーム機能の調査

photorans カメラ画面にズーム機能を追加するかどうか / どう実装するかを判断するための調査プラン。実装は別 TODO で起票する想定。

ステータス: **着手前** / 開始予定: 2026-05-02 〜

## 目的・背景

- `TODO.md` 「カメラの機能強化の調査 / ズーム」より
- ユースケース: 看板・本・遠めのテキストなど、被写体に物理的に近づけない状況で撮影したい。現状は `.builtInWideAngleCamera` 単独 + `videoZoomFactor=1.0` 固定なので近寄るしかない
- 純正カメラアプリ相当 (0.5x / 1x / 2x / 3x のプリセット + ピンチ) が当たり前のリファレンスになるため、実装しない場合も「なぜしないか」を説明できる根拠を残したい
- OCR / 翻訳が主用途なので「ズームすると OCR 精度がどう変わるか」を検証軸の中心に置く必要がある (digital zoom はアップスケール、optical zoom (telephoto) は実画素)

## 調査スコープ

- **対象**: 背面カメラのみ。撮影ズーム (静止画) のみ
- **対象外**:
  - フロントカメラ (現状未使用)
  - 動画ズーム (アプリで動画は撮らない)
  - 実装そのもの (調査結果を踏まえて別 TODO で起票)

## 既存コードの前提 (変更してはいけない不変項目)

調査は以下を **崩さない** 前提で進める。崩す案が必要になった場合は明記してトレードオフを評価する。

- `CameraSession.configureFocus`: OCR 用に `.continuousAutoFocus` + `.near` (`isAutoFocusRangeRestrictionSupported` のみ) + `.continuousAutoExposure`
- `Info.plist UISupportedInterfaceOrientations` portrait のみ + preview connection `videoRotationAngle = 90` 固定 (memory `feedback_camera_ui_portrait_only.md`、DONE.md `landscape-capture` 参照)
- 撮影 JPEG は `CameraSession.capturePhoto(rotationAngle:)` で世界向きに焼き込み
- `ImageCompressor.compressForUpload` で長辺 ≤ 2048px に縮小、base64 ≤ 5 MiB を保証 (memory `reference_anthropic_vision_5mb.md`)
- 過去の試行で **session 再構成 (`beginConfiguration` 〜 `commitConfiguration` で input 差し替え) は約 8 秒のブラックアウトを引き起こす** ことが判明済み (`landscape-capture.md` Phase3 B2)。デバイス切替案を出す場合はこのコストを必ず見積もる

## 調査項目

### A. iOS AVFoundation のズーム API

- `AVCaptureDevice.videoZoomFactor` (1.0 〜 `activeFormat.videoMaxZoomFactor`)
- `device.ramp(toVideoZoomFactor:withRate:)` / `cancelVideoZoomRamp()` の挙動
- 仮想マルチカム (`.builtInDualCamera` / `.builtInDualWideCamera` / `.builtInTripleCamera`) と `virtualDeviceSwitchOverVideoZoomFactors` による光学切替
- `.builtInUltraWideCamera` / `.builtInTelephotoCamera` を直接指定する場合との違い
- `videoZoomFactor` を `lockForConfiguration` で設定するときのスレッド (`sessionQueue` 上で実行する必要があるか)

### B. 端末別の利用可能デバイス

| 端末 | 仮想デバイスの最有力 | 提供される光学比 |
|---|---|---|
| iPhone 16 Pro / 15 Pro / 14 Pro 等 | `.builtInTripleCamera` | 0.5x / 1x / 5x または 3x |
| iPhone 16 / 15 / 14 / 13 (無印) | `.builtInDualWideCamera` | 0.5x / 1x |
| iPhone 12 / 11 / SE 等 | フォールバック | 1x のみ |

- Apple 公式ドキュメントで現行ラインアップを再確認 (上表は要検証)
- `AVCaptureDevice.DiscoverySession` で実機で取れるデバイスを列挙する手順
- フォールバック戦略: Triple → DualWide → Dual → WideAngle 単独

### C. UX パターン比較

調査するパターンと、それぞれの photorans ユースケースへの適合度:

1. **ピンチジェスチャのみ** (SwiftUI `MagnificationGesture` ベース)
   - 標準的、無段階。OCR 用途で「もう少しだけ寄りたい」に対応しやすい
   - portrait lock 下でも動作。CameraPreviewView 上に gesture を載せる位置を確認する必要あり (現状 tap-to-focus と競合しないか)
2. **プリセットボタンのみ** (0.5x / 1x / 2x / 3x の丸ボタン)
   - 純正カメラ準拠。光学切替点に紐付けやすい (Triple なら 0.5/1/3 など)
3. **両方併用** (純正カメラ式)
   - UI 面積を取る。MVP では過剰の可能性
4. **何も追加しない (現状維持)**
   - 「近寄れば良い」「OCR 精度的に digital zoom はむしろ不利」と判断する場合

### D. OCR 精度への影響

- **Digital zoom**: センサーから crop して拡大した画素を撮影 → `ImageCompressor` で結局 ≤ 2048px に縮小 → トータルで「中央 crop + 同じ解像度」と等価。情報量は減らないが、撮像段でアップスケール補間が入る分 OCR には不利な可能性。実機で 1x / 2x / 5x 撮影した同一被写体を `/translate` に投げて originalText の差分を見る
- **Optical zoom (telephoto)**: 望遠センサーは別物理素子なので 2048px に縮めても文字エッジが鮮明。OCR には有利だが、`.near` AF が telephoto レンズで動作するかは要検証 (telephoto は最短撮影距離が長い)
- **2048px キャップとの相互作用**: 高倍率にしても最終的には Anthropic に送るのは 2048px のため、digital zoom 範囲では「ズームせず後段で crop」と等価。UI 上は意味があっても OCR スコアに差が出ないかもしれない

### E. 既存設定との互換性確認

- `videoZoomFactor` 変更で `.near` AF restriction が解除されないか
- 仮想デバイス → 単一デバイス切替で `configureFocus` を再適用する必要があるか
- `videoRotationAngle = 90` 固定が telephoto / ultra-wide でも維持されるか
- 撮影中 (`capturePhoto` 待ち) にズーム変更が来た場合の競合制御

### F. session 再構成コストの実測

- B2 で確認された「input 差し替えで約 8 秒ブラックアウト」が、**仮想デバイス内の光学切替 (input 差し替えなし)** にも当てはまるかが最大の論点
- 仮想デバイス (`.builtInTripleCamera`) を最初から使えば、`videoZoomFactor` を switchover threshold 越えに設定するだけで AVFoundation が裏で物理レンズを切り替える ⇒ 原則ブラックアウトなしのはず
- ただし初回 session 立ち上げで仮想デバイスが間に合わない端末では諦めて wide 単独にフォールバック
- 計測案: `AVCaptureSession.sessionPreset = .photo` + `.builtInTripleCamera` で起動した場合のフレーム到達までの時間、zoom factor を 1 → 5 に切り替えた瞬間のフレーム drop / 黒フレーム継続時間を debug ログで計る (Phase4 で実装プラン化するときの指標)

## 成果物

調査の出力として以下を作成する。実装はしない。

- 本ファイルに各 Phase の結論を追記 (どの方針を採るか + その理由)
- 実装プラン草案を `docs/plans/camera-zoom.md` (新規) として起票し、`TODO.md` に「カメラズーム実装」を追加
- もし「やらない」結論になったら、その判断と背景を memory `feedback_camera_zoom_research.md` に保存して TODO を閉じる

## テスト方針

調査主体のため大きなテストは無い。Phase4 で実機計測が要る場合のみ TestFlight 経路 (CLAUDE.md「実機確認ルート」) で v0.1.X を切る。Phase1-3 はドキュメント調査のみで完結する想定。

## Phase 分解

### Phase1 AVFoundation ズーム API + 端末別利用可能デバイスの整理

- Apple Developer Documentation で `videoZoomFactor` / `ramp` / `DeviceType` の現行仕様を確認
- iPhone 11 〜 16 系で利用可能な仮想デバイス + 光学比を表にする (本ファイル「B. 端末別の利用可能デバイス」の表を確定値に更新)
- フォールバック戦略の論理を決定 (`AVCaptureDevice.DiscoverySession` の使い方含む)
- 出力: 本ファイルに Phase1 結論セクションを追記

### Phase2 UX パターン比較

- ピンチ / プリセットボタン / 併用 / 何もしない、の各案について photorans ユースケースとの相性を評価
- iOS 純正カメラ + 主要 OCR アプリ (Google Lens / Microsoft Lens / DeepL カメラ) の挙動を観察してリファレンス化
- portrait lock 下での gesture 配置 (現状 tap-to-focus との競合可否) を CameraView.swift で確認
- 出力: 推奨 UX を 1 案に絞り、本ファイルに Phase2 結論セクションを追記

### Phase3 OCR 精度 / 既存設定との相互作用の評価

- D「OCR 精度への影響」の検証方針を確定 (実機検証が必要かドキュメント考察で済むか)
- E「既存設定との互換性確認」を `CameraSession.swift` を読みながら整理し、必要な変更点を列挙
- F「session 再構成コスト」について、仮想デバイス起動を初期 `configureIfNeeded()` 段階で行えば差し替え無しで済むことの妥当性を確認
- 必要なら Phase3 内で実機 1 回計測を行うかどうかを判断 (TestFlight 1 ラウンド消費)
- 出力: 本ファイルに Phase3 結論セクションを追記

### Phase4 推奨方針 + 実装プラン草案

- Phase1-3 の結論を統合し「やる / やらない / 限定実装」を判断
- やる場合: `docs/plans/camera-zoom.md` を新規作成し、Phase 分解 + 影響範囲 + テスト方針を書き起こす。`TODO.md` に「カメラズーム実装」を追加
- やらない場合: 本ファイルに判断理由を残し、memory に「ズームは見送り、その理由」を保存
- 親 TODO「カメラの機能強化の調査」を `DONE.md` へ移送し、本ファイルを `docs/plans/archive/` へ移動

## 完了の定義 (DoD)

- 「ズームを実装するか / しないか」が結論として明文化されている
- 実装する場合の方針 (digital のみ / 仮想デバイス / UX パターン / フォールバック戦略) が決まっている
- 既存設定 (`.near` AF / portrait lock / 圧縮) を崩さないことが論理的に確認されている
- 実装する場合は実装プランファイルが起票され、TODO に追加されている
- 親 TODO がクローズされ DONE.md に記載、本プランは archive に移動済み
