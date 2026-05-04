# カメラ画面の閉じるボタン

photorans の `CameraView` (fullScreenCover で提示) に明示的な「閉じる」導線を追加する実装プラン。

ステータス: **着手前** / 起票日: 2026-05-03

## 目的・背景

- 現状 `CameraView` は撮影成功時の `onCaptured` でしか dismiss せず、撮影をやめたい場合の導線が無い
- `fullScreenCover` 提示なので edge swipe での dismiss も効かない (sheet と違い modal を引き下げられない)
- 純正カメラ風の UX に寄せる方針 (portrait lock 等) と整合する形で、明示的な X ボタンを置く

## 採用方針

| 項目 | 仕様 |
|---|---|
| アイコン | SF Symbol `xmark` (`.semibold` / 18pt 程度)。視認性のため zoomHUD と同様の半透明黒丸背景に重ねる |
| 配置 | preview セクション左上、safe area + 12〜16pt 程度のパディング (純正カメラの戻る系 UI に近い位置) |
| サイズ | ヒット領域 44pt 角を確保 (Apple HIG 準拠) |
| 動作 | タップで `onClose` クロージャを呼び、親 (`HomeFAB`) で `isShowingCamera = false` |
| 撮影中の挙動 | `isCapturing` でも閉じる操作は許可する (ユーザが中断したい意図を尊重)。進行中の撮影は AVFoundation 側で完了するが、`onDisappear` で `viewModel.onDisappear()` が呼ばれ session は止まる。Item 保存は capture delegate が完走するため、撮影直後に閉じても保存は走る点に注意 |
| アクセシビリティ | `accessibilityLabel("閉じる")` を付与 |
| 権限拒否時 | `permissionDeniedOverlay` 表示中も閉じられる必要があるため、ボタンは ZStack の最前面 (overlay より後ろではなく前) に配置 |

## 影響範囲

| ファイル | 変更内容 |
|---|---|
| `ios/Photorans/Features/Camera/CameraView.swift` | `onClose: @MainActor () -> Void = {}` プロパティ追加、preview 上に閉じるボタン overlay を配置 |
| `ios/Photorans/Features/Home/HomeFAB.swift` | `CameraView(...)` 呼び出しに `onClose: { isShowingCamera = false }` を追加 |

**変更しない**:
- `CameraViewModel` (閉じる操作はビュー層の責務、VM 状態に持たせる必要なし)
- `CameraSession` / `CameraPreviewView` (撮影パイプラインに無関係)
- `Info.plist` portrait lock / preview rotation 設定

## Step 分解

### Step 1: `CameraView` に閉じるボタン UI と `onClose` を追加

- `onClose: @MainActor () -> Void = {}` を `onCaptured` と並列でプロパティ追加
- `previewSection` ZStack に閉じるボタンを追加 (zoomHUD と同列) し、`alignment: .topLeading` で配置
- ボタン本体: `Button { onClose() } label: { Image(systemName: "xmark") ... }`
- スタイルは zoomHUD と同様 `Capsule().fill(.black.opacity(0.5))` か、円形 `Circle().fill(.black.opacity(0.5))` で 36〜40pt 角
- `.accessibilityLabel("閉じる")` 付与
- `#Preview` は引数を増やすので default 引数で済む (変更不要)

### Step 2: `HomeFAB` から `onClose` を配線

- `CameraView(targetGroup:..., onCaptured:..., onClose: { isShowingCamera = false })` に変更

### Step 3: XcodeGen 再生成 (新規ファイルは無いので実質不要)

- 既存ファイル編集のみなので `project.yml` / `pbxproj` の再生成は不要 (memory: XcodeGen 再生成必須は .swift 追加削除時のみ)。Step として明示するだけで実作業はスキップ可能

### Step 4: 実機確認の段取り

- Akira さんに動作確認用 TestFlight 配信が要るか確認
- 必要なら commit → tag push (patch インクリメント) を Akira さんの許可取得後に実施
- TestFlight に届いたら Akira さんが iPhone で:
  - 撮影前に X タップ → Home に戻る
  - 撮影中に X タップ → Home に戻る (Item 保存は走って良い)
  - 権限拒否ダイアログ表示中も X タップで閉じられる

## テスト方針

- ユニット/UI テストは現状 CameraView 系を持たない (CameraView は AVFoundation 依存で WSL2 でビルド検証不可)
- 検証は TestFlight 実機での目視のみ。Step 4 のシナリオを Akira さんが実機チェック
- WSL2 では Swift API 単体の syntax 確認のみ可能 (memory: Swift API は推測で書かない → SF Symbol 名と SwiftUI Button のシグネチャは公式ドキュメントで裏取り済み相当のものを使用)
