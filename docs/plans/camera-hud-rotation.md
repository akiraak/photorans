# カメラ倍率 HUD の文字を端末向きに合わせて回転する

iOS ネイティブクライアント (`ios/Photorans/Features/Camera/`) で、CameraView の倍率 HUD (`zoomHUD` の "1.0x" 等の文字) を、端末を横向きに構えたときに読みやすい向きに回転させる。UI は portrait 固定のまま、HUD のテキストだけ `.rotationEffect` で世界向きに合わせる、iOS 純正カメラと同じ挙動。

ステータス: **未着手** / 起票日: 2026-05-04

## 目的・背景

photorans のカメラ画面は `feedback_camera_ui_portrait_only.md` / `landscape-capture.md` で確定したとおり **UI / preview とも portrait 固定**。端末を横にしても画面レイアウトは縦のまま、撮影画像だけ `lastValidRotationAngle` を使って世界向きで保存する。

この方針自体は維持しつつ、現状は HUD の倍率文字 ("1.0x" など) も縦固定で、端末を横にして文字を撮ろうとするとユーザー視点で 90° 倒れて読みにくい。iOS 純正カメラ (portrait lock 状態) は、フラッシュ / セルフタイマー / 倍率バッジなどのアイコン・テキストだけを端末向きに合わせて `.rotationEffect` で回し、配置は portrait のままにしている。同じ振る舞いを倍率 HUD に対して入れたい。

スコープは TODO の文言どおり **倍率 HUD の文字** に限定する。シャッターボタン・閉じるボタンなど他の UI 要素の回転対応は本プランでは扱わない (純正カメラもシャッターは回さない / 閉じるボタンはアイコンが上下対称で回す必要が薄いため)。後続タスクとしてフォーカスレチクル等を扱うかは別途検討。

## 対応方針

### 判断 A: 回転角の源

`CameraViewModel.lastValidRotationAngle` (capture 用、`portrait=90` / `landscapeLeft=0` / `landscapeRight=180`、`portraitUpsideDown` / `faceUp` / `faceDown` / `unknown` は直前値維持) を再利用する。capture と HUD で同じ「直近の有効な世界向き」を使うので、机に伏せたとき (`.faceUp`) などでも HUD が暴れない。専用の observer を新設しない。

### 判断 B: capture 角度 → HUD 回転角の対応

capture 側の値は `AVCaptureConnection.videoRotationAngle` 用 (= sensor → world 回転)。HUD の `.rotationEffect` は SwiftUI ビュー (= 画面ローカル → 世界向き) なので、別の符号系として写像し直す。期待値 (純正カメラ準拠):

| 端末向き | `lastValidRotationAngle` | `.rotationEffect(.degrees(...))` | 文字の見え方 |
| --- | --- | --- | --- |
| portrait | 90 | 0 | 画面と同じ向きで上向き |
| landscapeLeft (端末上端が左、ホーム/Dynamic Island が右) | 0 | 90 | 横持ちで上向き |
| landscapeRight (端末上端が右) | 180 | -90 (= 270) | 逆横持ちで上向き |

実装は `CameraView` 内で:

```swift
private var zoomHUDRotation: Angle {
    switch viewModel.lastValidRotationAngle {
    case 0: return .degrees(90)     // landscapeLeft
    case 180: return .degrees(-90)  // landscapeRight
    default: return .degrees(0)     // portrait + 直前値維持
    }
}
```

`Text` に `.rotationEffect(zoomHUDRotation)` を適用し、`.animation(.easeInOut(duration: 0.2), value: viewModel.lastValidRotationAngle)` で滑らかに切り替える。Capsule (背景) は文字よりわずかに大きい縦横比のはずなので、回転で文字がはみ出さないかを実機で確認する (はみ出す場合は Capsule もまとめて回転させるか、Capsule を正方形寄りに広げる)。

### 判断 C: ViewModel 公開範囲

`lastValidRotationAngle` は `landscape-capture.md` Phase2 で `@Observable var` 化済みなので、CameraView から直接読むだけで SwiftUI 再描画が走る。新規 API は追加しない。

### 判断 D: 純正カメラとの振る舞い差異

純正カメラは UI portrait lock 状態でも `.portraitUpsideDown` を含めた 4 向きで文字を回す挙動だが、photorans は `landscape-capture.md` 判断 B3' どおり `portraitUpsideDown` を無視する (capture 側もアイコン側もまとめて 90° に寄せる)。HUD 側だけ独自に upside-down 対応を入れると capture と乖離するので、本プランも upside-down は portrait 扱いで揃える。

## 影響範囲

- `ios/Photorans/Features/Camera/CameraView.swift` — `zoomHUD` の `Text` に `.rotationEffect` と `.animation` を追加。回転角を導く小さな computed property (`zoomHUDRotation`) を追加
- `ios/Photorans/Features/Camera/CameraViewModel.swift` — 変更なし (`lastValidRotationAngle` は既存)
- 他のファイル — 変更なし

リスク:

- 回転で文字が Capsule (`width: 56, height: 28`) からはみ出す可能性。"1.0x" など 4 文字程度なら 28pt 高さ内に収まる想定だが、`.font(.caption)` の実測幅次第。実機確認で要調整 (Capsule もまとめて回転させる方針に倒す場合は Capsule + Text 全体を `ZStack` で組み、外側に `.rotationEffect` を当てる)
- `.rotationEffect` は SwiftUI ヒットテスト矩形を変えないが、HUD はタップ対象ではない (`.opacity` で表示制御するだけ) のでヒット判定問題は発生しない
- ピンチ中の回転 (端末を回しながらピンチ): `isPinching` と `lastValidRotationAngle` は独立に observable なので、両方への反応で `.animation` が二重発火する可能性あり。違和感が出たら `.animation` の `value:` を分けて指定する

## テスト方針

実機 (Akira さんの iPhone) で:

1. **portrait 起動**: HUD 文字が縦向き (画面と同じ向き) で表示される
2. **landscapeLeft (端末上端が左)**: HUD 文字が 90° 回転してユーザー視点で上向きになる
3. **landscapeRight (端末上端が右)**: HUD 文字が -90° 回転してユーザー視点で上向きになる
4. **portraitUpsideDown / faceUp / faceDown**: 直前の有効向きの回転状態を維持 (= portrait で構えていれば縦のまま)
5. **回転アニメーション**: 端末を回したときに HUD 文字が 0.2 秒程度で滑らかに次の向きへ補間する (急にスナップしない)
6. **ピンチ中の回転**: ピンチで HUD が強調 (opacity 1.0) になっている最中に端末を回しても、文字の回転と opacity の遷移が両方滑らかに動く
7. **capture リグレッション**: 横持ちで撮影した画像が `landscape-capture.md` 完了時と同じく世界向きで保存される (HUD 回転対応は capture 経路に影響しないが念のため確認)
8. **HUD 余白確認**: Capsule からはみ出していないか、文字がクリップされていないか目視

ユニットテストは追加しない (SwiftUI ビジュアルのみの変更)。

## Phase / Step

- **Phase1 HUD 文字回転実装**
  - Step1-1 `CameraView.zoomHUD` の `Text` に `.rotationEffect(zoomHUDRotation)` と `.animation(.easeInOut(duration: 0.2), value: viewModel.lastValidRotationAngle)` を追加
  - Step1-2 `zoomHUDRotation` computed property を CameraView に追加 (判断 B のマッピング)
  - Step1-3 ローカルでビルド ⇒ 警告/エラーが無いこと、type-check 通過を確認 (WSL2 では Xcode 直接ビルド不可なので push 前にコードレビューのみ)
- **Phase2 実機確認**
  - Step2-1 タグ push (Akira さんに事前確認) → Bitrise → TestFlight
  - Step2-2 テスト方針 1〜8 を実機で確認し、HUD 余白問題があれば Capsule + Text を一体回転に変更して再 push
- **Phase3 仕上げ**
  - Step3-1 TODO.md → DONE.md に移送、本プランを `docs/plans/archive/` に移動

判断履歴:
- 起票時 (2026-05-04): 判断 A (既存 `lastValidRotationAngle` 再利用) + 判断 B (capture 角度 → HUD 角度の写像) + 判断 D (upside-down は portrait に寄せる) で開始
