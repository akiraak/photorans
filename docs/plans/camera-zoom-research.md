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

(Phase1 で確定値に更新済み。下の「Phase1 調査結果 → B」を参照)

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

## Phase1 調査結果 (2026-05-02)

ステータス: **完了**。Phase2 へ進む前提知識を確定。

### A. AVFoundation ズーム API 仕様

| 項目 | 確定内容 |
|---|---|
| `videoZoomFactor` の値域 | `1.0` 〜 `device.activeFormat.videoMaxZoomFactor`。下限を切るとセンサー全画素 (= 仮想デバイスでは最広 lens の FOV)、上に行くほど中央 crop |
| 設定方法 | `device.lockForConfiguration()` を取ってから代入。`commit/begin Configuration` (session 側) は不要。lock を取らずに代入すると `NSGenericException` |
| `ramp(toVideoZoomFactor:withRate:)` | スムーズ遷移。倍率が `pow(2, rate * time)` で時間に対して指数的に変化 (画面上は線形に見える)。`rate=1` → 1 秒ごとに 2 倍。`cancelVideoZoomRamp()` で中断可能。同じく lock 取得が前提 |
| Threading | `lockForConfiguration` 自体はどのキューからでも呼べるが、session 構成と整合させるため `CameraSession.sessionQueue` 上で呼ぶのが安全。AVFoundation 側のキャプチャ処理は session 内部キューに乗るのでブロッキングしない |
| `minAvailableVideoZoomFactor` / `maxAvailableVideoZoomFactor` | iOS 11+ で利用可。マルチカム時のサーマル制約等で動的に縮むので、UI 上限はこちらを参照すべき |

### B. 端末別の利用可能デバイス (確定)

「光学比」は AVFoundation の `videoZoomFactor` 上での値ではなく、Apple 純正カメラ UI 表示準拠の `0.5x / 1x / 5x` 表記。

| 端末 | 推奨 DeviceType | constituent / 焦点 | 純正 UI の光学切替点 |
|---|---|---|---|
| iPhone 16 Pro / 16 Pro Max | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(120mm) | 0.5x / 1x / 5x |
| iPhone 15 Pro Max | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(120mm) | 0.5x / 1x / 5x |
| iPhone 15 Pro | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(77mm) | 0.5x / 1x / 3x |
| iPhone 14 Pro / 14 Pro Max | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(77mm) | 0.5x / 1x / 3x |
| iPhone 13 Pro / 13 Pro Max | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(77mm) | 0.5x / 1x / 3x |
| iPhone 11 Pro / 11 Pro Max | `.builtInTripleCamera` | UltraWide + Wide + Telephoto(52mm) | 0.5x / 1x / 2x |
| iPhone 16 / 16 Plus | `.builtInDualWideCamera` | UltraWide + Wide(48MP) | 0.5x / 1x (2x はセンサー crop) |
| iPhone 15 / 15 Plus | `.builtInDualWideCamera` | UltraWide + Wide(48MP) | 0.5x / 1x (2x はセンサー crop) |
| iPhone 14 / 14 Plus | `.builtInDualWideCamera` | UltraWide + Wide | 0.5x / 1x |
| iPhone 13 / 13 mini | `.builtInDualWideCamera` | UltraWide + Wide | 0.5x / 1x |
| iPhone 12 / 12 mini | `.builtInDualWideCamera` | UltraWide + Wide | 0.5x / 1x |
| iPhone 11 (無印) | `.builtInDualWideCamera` | UltraWide + Wide | 0.5x / 1x |
| iPhone SE (2nd / 3rd gen) | `.builtInWideAngleCamera` | Wide 単独 | 1x のみ |

注:
- `.builtInDualCamera` (Wide + Telephoto) は iPhone 7 Plus / 8 Plus / X / XS 系統で使われた仮想デバイス。**iPhone 11 以降には存在しない**ため、現行端末に対しては選択肢外
- iPhone 14 Pro 以降の Pro 系は名目 48MP の wide を持つが、AVFoundation 上で 2x を *光学* として露出する経路は **存在しない**。純正カメラの 2x はアプリ側のセンサー crop で実装されている (= digital zoom と等価)
- iPhone 16 / 15 (無印) も同様で、48MP wide からの 2x crop は AVFoundation 側で `videoZoomFactor=2.0` を設定するのと違いはほぼ無い

### `virtualDeviceSwitchOverVideoZoomFactors` の意味

仮想デバイスの `videoZoomFactor` は **constituent の最広 lens (UltraWide) の FOV を 1.0** とする。Apple のカメラ UI 表記と 2 倍ずれる:

| 仮想デバイス | switchOverVideoZoomFactors (= AVFoundation 値) | 純正 UI 表記 |
|---|---|---|
| iPhone 14 Pro `.builtInTripleCamera` | `[2, 6]` | 0.5x → 1x → 3x |
| iPhone 16 Pro `.builtInTripleCamera` | `[2, 10]` (推定) | 0.5x → 1x → 5x |
| iPhone 11 / 12 / 13 / 14 / 15 / 16 (無印) `.builtInDualWideCamera` | `[2]` | 0.5x → 1x |

**UX 上の含意**: ユーザに `1x / 2x / 3x` を見せたい場合は、UI 表示時に AVFoundation `videoZoomFactor` を 0.5 倍してから整形する (`0.5x = factor 1.0`, `1x = factor 2.0`, `3x = factor 6.0`)。Phase2 のプリセット案で確定する。

### C. フォールバック戦略 (確定)

`AVCaptureDevice.DiscoverySession` を `sessionQueue` 上で 1 回叩き、優先度順に最初に取れたものを採用する:

```swift
let session = AVCaptureDevice.DiscoverySession(
    deviceTypes: [
        .builtInTripleCamera,
        .builtInDualWideCamera,
        .builtInDualCamera,        // iPhone 11 以降では返らないが念のため
        .builtInWideAngleCamera
    ],
    mediaType: .video,
    position: .back
)
guard let device = session.devices.first else { return /* CameraError.noDevice */ }
```

注意点:
- `deviceTypes` 配列の順序は `discoverySession.devices` の順序に反映される。**仮想デバイスを単体デバイスより先に並べる**
- `AVCaptureDevice.default(.builtInWideAngleCamera, ...)` は wide 単体しか返さないので、現状の `CameraSession.swift:125` のコードは「Triple / DualWide があっても拾わない」状態。Phase4 で実装する場合は DiscoverySession に切り替えるのが必須
- `.builtInLiDARDepthCamera` は depth 取得を有効化したいときのみ。photorans では使わない (LiDAR は Triple と排他的に選べる Pro 系の選択肢でしかなく、写真撮影だけなら Triple のほうが上位互換)

### D. 既存 `CameraSession.swift` への影響予測

| 既存挙動 | DiscoverySession に変えた場合の確認事項 |
|---|---|
| `configureFocus`: `.continuousAutoFocus` + `.near` | UltraWide / Telephoto は最短撮影距離が wide と異なる。`isAutoFocusRangeRestrictionSupported` を見て条件付き適用する現状コードで問題ないが、Telephoto 使用中は実質 `.near` が無効になる可能性あり (Phase3 で実機検証 or ドキュメント確認が必要) |
| `videoRotationAngle = 90` 固定 | TripleCamera でも単一 connection なので、現行ロジック (capture connection に対して都度 set) のままで OK |
| Session 再構成 (input 差し替え) のブラックアウト ~8 秒 | **仮想デバイスを最初から入力に使えば光学切替は input 差し替えなし**で AVFoundation 内部で完結する。Phase3 F で詳細検証だが、API 仕様上は switchover で input は変わらない |

### Phase1 結論

1. **API 仕様は十分明確**で、追加の実機検証なしに Phase2 (UX 設計) に進める
2. **フォールバック戦略は確定**: Triple → DualWide → WideAngle 単独 (`.builtInDualCamera` は現行端末に存在しないので実質スキップ可)
3. **`videoZoomFactor` の基準が UltraWide` 起点 (1.0)** という事実は UX 設計に直接効くので Phase2 で必ず加味する
4. **既存 `CameraSession.swift:125` の `AVCaptureDevice.default(.builtInWideAngleCamera, ...)` は変更が必要**。実装に進む場合は DiscoverySession への置き換えが Phase4 の最初の Step
5. **OCR 視点の懸念 (digital zoom が 2048px キャップで意味を失う / Telephoto と `.near` AF の整合)** は Phase3 の主要論点として残し、Phase2 では UX 形だけ決める

## Phase2 調査結果 (2026-05-02)

ステータス: **完了**。推奨 UX を 1 案 (ピンチのみ + 仮想デバイス自動切替) に確定。

### リファレンスアプリの挙動 (ドキュメント観察)

| アプリ | ズーム UI | 所感 |
|---|---|---|
| iOS 純正カメラ | ピンチ + プリセット wheel (0.5x / 1x / 2x / 3x or 5x) | 動画も含む万能 UI。プリセットは長押しで連続スライダーに変形 |
| Google Lens (Android / iOS web) | ピンチのみ。倍率 HUD は薄いラベル | OCR / object 認識に特化。プリセットは出さない |
| Microsoft Lens (Document モード) | ピンチのみ | プリセットなし。Document モードでは枠検出が主役 |
| DeepL カメラ | ピンチのみ | OCR + 翻訳という photorans に最も近いユースケース |

**示唆**: OCR / 翻訳系アプリではプリセットボタンを持たないのが多数派。プリセットは「動画記録中も瞬時に光学を切り替えたい」純正カメラ要件に応えるための UI で、静止画 OCR では過剰になりがち。

### 各 UX 案の評価

#### 案1. ピンチジェスチャのみ

| 観点 | 評価 |
|---|---|
| ユースケース適合 | ◎ 「もう少しだけ寄りたい」を無段階で吸収 |
| 光学切替の活用 | ○ `virtualDeviceSwitchOverVideoZoomFactors` 越えで AVFoundation が自動的に物理レンズを切り替える。ユーザは「1.0x → 5.0x」と滑らかに動かすだけで Telephoto が裏で走る |
| 端末差吸収 | ◎ Triple / DualWide / Wide 単独すべて同じコード。仮想デバイスの `maxAvailableVideoZoomFactor` を上限にクランプするだけ |
| 既存 tap-to-focus との競合 | △→○ `UIPinchGestureRecognizer` (2 本指) と既存 `UITapGestureRecognizer` (1 本指) は finger count / motion が排他なので衝突しない。同じ `PreviewUIView` に並べて add 可 |
| portrait lock 下 | ◎ ピンチは方向に依存しないので影響なし |
| 発見性 | △ ジェスチャ単独は気づきにくい。「現在倍率」を小さく overlay (`1.0x`) するだけで十分緩和できる |
| 実装コスト | 小 (gesture 1 個 + ViewModel に zoom factor + `device.lockForConfiguration` 経由の setter) |

#### 案2. プリセットボタンのみ

| 観点 | 評価 |
|---|---|
| ユースケース適合 | △ 「あと 10% 寄りたい」が表現できない。OCR では微調整需要が高い |
| 光学切替の活用 | ◎ ボタン = 光学切替点に直接マップできる |
| 端末差吸収 | ✕ Triple は 0.5/1/3(or 5)、DualWide は 0.5/1、SE は 1 のみ → 端末ごとにボタン構成が変わる条件分岐が必要 |
| ラベル表記の混乱 | ✕ 同じ「2x」でも Pro は digital zoom、無印 (48MP) もセンサー crop だが「光学」ではない。ユーザに誤認させる懸念 |
| 発見性 | ◎ 明示ボタン |
| 実装コスト | 中 (端末別ロジック + 動的ボタン生成 + ハイライト管理) |

#### 案3. 併用 (純正カメラ式)

| 観点 | 評価 |
|---|---|
| ユースケース適合 | ◎ |
| 実装コスト | 大 (案1 + 案2 + 両者同期) |
| MVP 妥当性 | ✕ photorans は撮影 → 翻訳の 1 アクション最適化が主軸。複雑な UI コンポーネントを最初から積むのは過剰 |

#### 案4. 何も追加しない (現状維持)

| 観点 | 評価 |
|---|---|
| ユースケース適合 | ✕ Pro 系の Telephoto を使えないのは「遠めの看板を撮りたい」要件に直接刺さる |
| 期待値 | ✕ 「カメラ画面でピンチが効かない」のは現代ユーザの暗黙の期待を裏切る |
| 後退判断の根拠 | OCR 視点では digital zoom が 2048px キャップでほぼ意味を失う点が論拠になりうるが、Pro の光学 zoom は別物なので "全否定" は正当化しにくい |

### gesture 配置の確認 (`CameraPreviewView.swift`)

- 現状: `PreviewUIView` (UIView) に `UITapGestureRecognizer` を 1 本貼っている (`CameraPreviewView.swift:30`)
- 案1 採用時の追加: 同じ view に `UIPinchGestureRecognizer` を `addGestureRecognizer` するだけ。Apple 既定でタップとピンチは排他的に判定されるため `requireToFail` 等の細工は不要
- ピンチの delta を `recognizer.scale` で取り、`startFactor * scale` を `device.videoZoomFactor` に書き戻す。`recognizer.scale = 1` リセットは pinch end 時に行う
- gesture 内で View 状態 (倍率 HUD 表示) を更新するため `Coordinator` に zoom 用 closure を 1 本追加
- ピンチ中は `device.ramp(...)` ではなく即値代入 (`videoZoomFactor =`) のほうが追従感が出る。プリセットボタンを将来足す場合のみ `ramp` を使う

### 倍率 HUD (発見性補完)

- preview の上端中央 or 下端 (controls section との境界付近) に `Capsule` 1 個 + `Text("1.0x")`
- 通常時はうっすら表示、ピンチ中は不透明、ピンチ終了後 1.5 秒で薄く戻す
- 表記ルール: AVFoundation `videoZoomFactor` を **純正カメラ表記に変換してから** 表示する (Phase1 で確定: 仮想デバイス上で `factor / 2` が UI 表記)。Triple 端末で `factor=2.0 → "1.0x"`、`factor=10.0 → "5.0x"`。Wide 単独端末は `factor=1.0 → "1.0x"` でそのまま
- SE のような Wide 単独端末では `maxAvailableVideoZoomFactor` が小さい (典型的に 5〜10) ため上限に注意。実装時に明確にクランプする

### 撮影セッション間の倍率の永続化

- 推奨: **CameraView を抜けるたびに 1.0x にリセット**。次回起動はゼロから
- 理由: photorans のメインフローは「撮って即翻訳結果へ遷移」なので、戻ってきたユーザは別被写体を撮る公算が高い。前回倍率を保持すると意図しない高倍率で開いて慌てる UX
- 実装的にも `viewModel.onAppear` で `device.videoZoomFactor = 1.0` を流すだけで済む

### Phase2 結論

1. **採用 UX = ピンチジェスチャのみ + 倍率 HUD**。プリセットボタンは MVP では出さない
2. 仮想デバイス (`.builtInTripleCamera` / `.builtInDualWideCamera`) を入力に使い、光学切替は `virtualDeviceSwitchOverVideoZoomFactors` 任せ。ピンチ中の switchover でブラックアウトが出るかは Phase3 (項目 F) で検証
3. 既存 tap-to-focus との共存は `UIPinchGestureRecognizer` を `PreviewUIView` に並列で add するだけで成立。`CameraPreviewView` の Coordinator に zoom closure を 1 本足す形になる
4. 倍率上限は `device.maxAvailableVideoZoomFactor` クランプ。HUD 表示は仮想デバイスの場合に限り「`factor / 2`」を純正 UI 風に表記する
5. 撮影セッション間で倍率は持ち越さない (戻る → 1.0x にリセット)
6. プリセットボタンは「ピンチでは届かない使い勝手 (例: ワンタップで Telephoto に飛びたい)」というフィードバックが実機 dogfooding で出てから検討する。Phase4 で実装する場合の dependency にはしない

## 完了の定義 (DoD)

- 「ズームを実装するか / しないか」が結論として明文化されている
- 実装する場合の方針 (digital のみ / 仮想デバイス / UX パターン / フォールバック戦略) が決まっている
- 既存設定 (`.near` AF / portrait lock / 圧縮) を崩さないことが論理的に確認されている
- 実装する場合は実装プランファイルが起票され、TODO に追加されている
- 親 TODO がクローズされ DONE.md に記載、本プランは archive に移動済み
