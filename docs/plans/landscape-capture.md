# 横向きの写真を撮りたい / 撮影範囲の WYSIWYG 化

iOS ネイティブクライアント (`ios/Photorans/`) で、(1) 端末を横向き (landscape) に持って撮影したときに、プレビュー・撮影画像・履歴表示のすべてが破綻なく成立すること、(2) プレビューに見えている範囲と実際に保存・OCR される範囲を一致させる (WYSIWYG)、の 2 つを同時に達成する。

ステータス: **未着手** / 起票日: 2026-05-01

## 目的・背景

### 課題 1: 横向き撮影の UI / 画像 / 表示が破綻

AVFoundation 側のキャプチャ経路 (`CameraSession.capturePhoto(rotationAngle:)` + `CameraViewModel.currentRotationAngle()`) は landscape の `videoRotationAngle` (0° / 180°) まで含めてマッピング済み。`Info.plist` も `UISupportedInterfaceOrientations` に `LandscapeLeft` / `LandscapeRight` を含めてある。にもかかわらず、実機で横向きに構えて撮影すると以下が破綻している (想定):

1. **プレビューが回転しない** — `CameraPreviewView` 側で `AVCaptureVideoPreviewLayer.connection.videoRotationAngle` を端末向きに追従させていない
2. **撮影 UI がポートレート前提のレイアウト** — `CameraView.bottomControls` が「常に画面下中央にシャッター」を仮定しており、横持ちで右手親指の自然な位置に来ない
3. **履歴詳細の画像表示が縦長固定** — `HistoryDetailView.photo` が `aspectRatio(3.0 / 4.0, contentMode: .fit)` を強制しているため、4:3 横長画像が中央クロップされる
4. **ImageCompressor の resize 不要パスでの EXIF orientation 取り扱いが不明確**

### 課題 2: プレビュー枠より実際の撮影範囲が広い

別 TODO 項目「撮影画面に表示される範囲よりも実際に撮影された画像の方が広い」の根本原因は `CameraPreviewView.makeUIView` で `videoGravity = .resizeAspectFill` を指定していること。具体的には:

- `session.sessionPreset = .photo` でキャプチャされる画像は **4:3 アスペクト** (例: 4032×3024)
- iPhone の画面は **9:19.5 ~ 縦長** (例: iPhone15 Pro で 1179×2556)
- `.resizeAspectFill` は「プレビュー枠を画像で埋める」モードなので、portrait (画面 9:19.5 ≒ W/H 0.46、画像 3:4 ≒ W/H 0.75) では画像が「画面より相対的に横広」→ **画面の高さで fill (画面高 = scaled 画像高) し、scaled 画像の左右が画面幅を超えてはみ出す → 左右端が見えない**
  - 例: iPhone15 Pro 1179×2556 / 画像 3024×4032 → scale = 2556/4032 ≈ 0.634 → scaled 1917×2556 → 横方向に (1917−1179)/2 ≈ 369px ずつ画面外
- 一方 `AVCapturePhotoOutput` は元の 4:3 全域をそのまま保存するため、「枠の外にあったテキスト」もサーバに送られて OCR される
- 結果: ユーザーが「枠内に被写体を収めたつもり」でも、枠外の余分な文字 / 別の被写体が混ざって翻訳精度が下がる

横向きでも同じ問題が裏返しで起きる: 横持ち時はキャプチャ画像 (4:3 横長) を画面 (19.5:9 横長) に `.resizeAspectFill` するため、今度は **画面幅で fill して上下がはみ出して見えない**。

### 統合する理由

両者は「カメラ画面の UI レイアウト」を共通の起点として触る。WYSIWYG 化で `videoGravity` を `.resizeAspect` に変えるとプレビューと画面の間に余白 (黒帯) が生じ、その余白の使い方 (シャッター配置) が portrait / landscape の両方で問題になる。先に WYSIWYG を決めてから回転対応の UI を組むのが自然なので、1 つのプランで連続して扱う。

OCR + 翻訳アプリの性質上、「ユーザーが枠内にテキストを収めれば正しく翻訳される」予測可能性は最重要。WYSIWYG は単なる見た目の問題ではなく、アプリの中核的な UX 要件。

## 対応方針

### 判断 A: カメラ画面のみ自由回転 vs アプリ全体を自由回転

- (A1) `RootView` の `TabView` ごと自由回転: 履歴も横で見やすくなるが、リスト UI を横向きで詰めて見せる設計が別途要る
- (A2) `CameraView` だけ自由回転、他のタブは Portrait 固定: 修正範囲が小さい

→ **(A2) を第一候補**。履歴詳細の画像アスペクト比対応 (課題 1 の 3.) は別軸として本プランに含めるが、履歴タブ自体の自由回転は対象外。

### 判断 B: シャッターボタン位置の追従方式

- (B1) UI は portrait 固定で、撮影画像のみ正しい向きで保存: 横持ち時にシャッターが押しにくい
- (B2) UI ごと SwiftUI に回転を委ねる (interface orientation を全許可): SafeArea が回って bottomControls が「現実世界の下」ではなく「画面下」に来るため、横持ちで端末のショートエッジ側にシャッターが来てしまい押しにくい
- (B3) UI は portrait 固定だが、シャッター / サムネを `.rotationEffect` で端末向きに合わせて回転 (アイコン向きだけ追従、配置は portrait の画面下中央): iOS 純正カメラと同じ挙動

→ **(B3) を第一候補**。プレビューは `previewLayer.connection?.videoRotationAngle` を端末向きで都度更新するので「世界の上」が常に画面上に映る。

#### B3 補足: 端末向き → 回転角の決め方 (capture / アイコン共通)

`UIDevice.current.orientation` をそのまま `currentRotationAngle()` (90 / 0 / 180 / 270) に変換すると OCR アプリで以下が破綻する:

1. **`.faceUp` / `.faceDown` / `.unknown` の fallback**
   - 机上のテキストを真上から撮るときに常に発火する代表シナリオ。現状の `currentRotationAngle()` (`CameraViewModel.swift:129-137`) は portrait (90°) に fallback しているため、横持ちで端末を伏せて撮ると保存画像が縦向きになる
   - 対策: 直近に観測した *有効向き* (`portrait` / `landscapeLeft` / `landscapeRight`) を保持し、無効向きが来ても更新しない (= 直前値を維持)
2. **`.portraitUpsideDown` のアイコン**
   - iPhone は `UISupportedInterfaceOrientations` で除外済みだが、`UIDevice` センサー側は通知してくる。現状 270° を返しているので、そのまま `.rotationEffect` に渡すと**シャッターアイコンが上下逆向き**で固定される瞬間が出る
   - iOS 純正カメラ準拠なら upside-down は無視。アイコン用にも capture 用にも portrait と同じ 90° に寄せる (iPhone で逆さ撮影する人はほぼいないため capture 側もまとめて良い)

実装方針: ViewModel に **`@Observable var lastValidRotationAngle: CGFloat = 90`** を 1 つ持ち、orientation observer で `portrait` → 90 / `landscapeLeft` → 0 / `landscapeRight` → 180 のいずれかが届いたときだけ更新。`portraitUpsideDown` / `faceUp` / `faceDown` / `unknown` は何もせず直前値を維持する。capture (`CameraSession.capturePhoto(rotationAngle:)`) もアイコン回転 (`.rotationEffect(.degrees(...))`) も同じプロパティを参照する。

#### 確定: 2026-05-02 (Phase3 検証で B3' に変更)

実機検証の結果、当初の (B3) 案 (UI portrait 固定 + アイコンだけ `.rotationEffect`) は preview connection を端末向きに追従させると preview frame が縦長のまま中身だけ横倒し映像になり UX 不良、また (B2) を一時試したが UI ごと auto-rotation する場合に **横持ち / 縦持ち切替で 8 秒程度のブラックアウト** (UI 回転 + AVCaptureSession 反映待ち) が発生し photorans の用途に不適と判明。

**最終判断: (B3') = iOS 純正カメラを portrait lock で使った時と同じ動作で確定**:

- UI / preview は **常に portrait 固定** (`Info.plist` の `UISupportedInterfaceOrientations` は portrait のみ)
- preview connection (`AVCaptureVideoPreviewLayer.connection.videoRotationAngle`) も **常に 90° 固定** (sensor portrait 向き)
- 横持ち時、preview の中身は「縦長 frame に縦長映像」のまま (世界向きではない)。ユーザーは縦に保たれた preview を見ながら横持ちで構える
- **撮影画像 (JPEG) だけが世界向きで保存される** — `CameraSession.capturePhoto(rotationAngle:)` に `lastValidRotationAngle` を渡し、capture connection の `videoRotationAngle` で世界向きに焼き込む
- shutter / overlay は portrait 配置のまま、`.rotationEffect` も適用しない (UI 固定なので意味なし)
- `lastValidRotationAngle` の orientation observer は **capture 用に必須** なので残す

この方針はメモリ `feedback_camera_ui_portrait_only.md` にも保存。横長 preview 要望が再発した場合はこの履歴を確認の上、再度 Akira さんに確認すること。

### 判断 C: ImageCompressor の orientation 安全化

`AVCapturePhotoOutput.capturePhoto` で `connection.videoRotationAngle` を設定すれば JPEG はピクセル単位で回転済み (EXIF Orientation = 1) で出る、というのが Apple の挙動。実機検証で「resize 不要パス (元 JPEG が 2048px 以下) を通っても向きが崩れない」ことを確認できれば追加対応不要。崩れるなら `UIImage` を経由して `draw(in:)` で焼き直すか、`CGImageSource` で EXIF を読んで明示的に正規化する。

### 判断 D: HistoryDetailView の画像表示

固定 `aspectRatio(3.0/4.0)` をやめ、画像本来のアスペクト比に従わせる:

```swift
Image(uiImage: image)
    .resizable()
    .scaledToFit()
    .frame(maxWidth: .infinity)
```

ScrollView 内なので高さが伸びても問題ない。プレースホルダ (画像が見つからない時) は仮値の aspect で OK。

### 判断 E: 撮影範囲を WYSIWYG にする方式 (課題 2 への対応)

- (E1) **`videoGravity = .resizeAspect`** に変更し、プレビュー枠 = 撮影画像の見える範囲を一致させる。プレビューと画面の間に余白 (黒帯) が出るが、その領域はシャッター / サムネ / 翻訳中オーバレイの配置スペースとしてむしろ好都合
- (E2) プレビュー枠は画面いっぱい (`.resizeAspectFill`) のままで、撮影後にプレビューに見えていた範囲だけをクロップして保存: 撮影画像のピクセル数が減る (OCR 不利)。クロップ計算は座標系変換が必要で実装も重い
- (E3) プレビュー枠は画面いっぱい、矩形オーバーレイで「OCR 対象範囲」を示し、撮影画像はフルサイズで保存・送信: 枠と実画像が違うのでユーザーが戸惑う

→ **(E1) を第一候補**。OCR の精度予測可能性 = ユーザーが見ている = サーバが見える、が最重要。余白を活かしてシャッターをプレビュー外に置く iOS 純正カメラ (写真モード) と同じ構成が組める。

### 判断 F: WYSIWYG 化に伴うレイアウト

`.resizeAspect` 採用時のレイアウト方針:

- **Portrait** (画面 9:19.5、画像 3:4): プレビューは画面幅 = 画像幅で上下方向にフィット。画像 3:4 を画面幅で表示すると、画面高の 4/3 × (画面幅 / 画面高) ≒ 約 60% を占める。プレビューを画面上部 (SafeArea 上端) に貼って、下半分の余白に bottomControls を配置すると iOS 純正カメラに近い見え方になる
- **Landscape** (画面 19.5:9、画像 4:3): プレビューは画面高 = 画像高で左右方向にフィット。画像 4:3 が画面の中央に寄り、左右に余白。シャッターは画面右側 (端末を横持ちで右下) の余白に配置するのが iOS 純正カメラ準拠

実装としては GeometryReader で画面アスペクトを取り、preview frame と controls frame を分けて配置する。

> **2026-05-02 確定 (判断 B 参照)**: B3' (UI portrait 固定 + 撮影画像のみ世界向き) を採用したため、**landscape レイアウト分岐は実装しない**。Portrait 側のレイアウト (preview を画面幅 × 4/3 で上、shutter を下半分中央) のみ採用。

## 影響範囲

- `ios/Photorans/Features/Camera/CameraPreviewView.swift` — `videoGravity` を `.resizeAspect` に変更、`previewLayer.connection.videoRotationAngle` を端末向きで更新する仕組みを追加
- `ios/Photorans/Features/Camera/CameraView.swift` — preview と bottomControls の配置を分離 (GeometryReader で portrait / landscape のレイアウトを切り替え)、シャッターに `.rotationEffect` を適用。直前撮影サムネ (`thumbnailView`) はユーザー判断で削除する
- `ios/Photorans/Features/Camera/CameraViewModel.swift` — 既存の orientation observer を `@Observable var lastValidRotationAngle: CGFloat` として外部公開。`portrait` / `landscapeLeft` / `landscapeRight` のみを 90 / 0 / 180 に変換して書き込み、`portraitUpsideDown` / `faceUp` / `faceDown` / `unknown` は無視 (直前値維持)。capture 用とアイコン回転用でこの値を共用。`lastThumbnail` プロパティはサムネ撤去に伴い削除
- `ios/Photorans/Features/Camera/CameraSession.swift` — 変更なし (キャプチャ経路は完成済み) の見込み
- `ios/Photorans/Features/History/HistoryDetailView.swift` — 画像のアスペクト比固定を解除
- `ios/Photorans/Features/Camera/ImageCompressor.swift` — 検証次第で orientation 正規化を追加
- `ios/Photorans/Info.plist` — 変更なし (既に Landscape 許可済み)
- `ios/Photorans/RootView.swift` — (A2) なら変更なし

リスク:

- `.rotationEffect` 方式は **タップ判定の境界** に注意 (SwiftUI のヒットテスト矩形は回転前のまま残るが、ボタンサイズが大きければ実用上問題ない)
- `.resizeAspect` への変更でプレビューの見た目が大きく変わる → 既存ユーザー (TestFlight ベータ) に違和感が出る可能性。MVP 段階なので変更コストとして受容
- iPad 対応は本プラン範囲外
- 撮影中に回転が起きたタイミングのレースコンディション (連続タップ + 回転)
- AF レチクル (`FocusReticleView`) のタップ座標は preview view 内の point なので、`.resizeAspect` への切替で preview frame が小さくなった後も座標系は preview view ローカルで完結する → そのままで OK

## テスト方針

実機 (Akira さんの iPhone) で:

1. **WYSIWYG 検証**: portrait で起動 → 文字を画面に映る範囲ぴったりに収めて撮影 → `/admin` および履歴詳細で「画面に見えていた範囲がそのまま保存されている」「枠外の文字が写り込んでいない」ことを確認
2. **portrait リグレッション**: 縦写真撮影 → 履歴詳細で縦長表示
3. **landscape プレビュー**: 起動後に landscape left に回す → プレビューが回り、シャッター / サムネが回転して右手親指で押せる位置に見える
4. **landscape 撮影**: landscape で撮影 → 履歴一覧サムネが横長で表示
5. **landscape 履歴詳細**: 履歴詳細で landscape 撮影画像を開く → 画像本来のアスペクト比 (4:3 横長) で枠に収まる
6. **landscape right**: 端末を逆向きに横にしても 3〜5 が成立
7. **撮影中の回転**: 回転途中で撮ってクラッシュしない、シャッター連打耐性
8. **server `/admin` 確認**: 縦・横の画像が EXIF Orientation を尊重して正しく表示されること (server 側変更は不要のはず、確認のみ)

ユニットテストは `ImageCompressor` の orientation 正規化を追加した場合のみ書く。SwiftUI 側はビジュアル確認に頼る。

## Phase / Step

- **Phase1 撮影範囲 WYSIWYG 化 (portrait のみで完成)** — `videoGravity = .resizeAspect` に切替えて、プレビューと bottomControls の配置を再設計
  - Step1-1 `CameraPreviewView.makeUIView` で `videoGravity` を `.resizeAspect` に変更
  - Step1-2 `CameraView` を GeometryReader でレイアウト構成に変更し、画面上部に preview を貼って下部余白に bottomControls を配置 (portrait 想定)
  - Step1-3 実機で「枠に映っている範囲 = 撮影される範囲」を確認、`/admin` で撮影画像の構図がプレビューと一致
- **Phase2 プレビュー回転対応** — `CameraViewModel.lastValidRotationAngle` を導入し capture 用の角度ソースを共通化する (preview connection の追従は B3' 確定で撤回、Step2-2 は実装後に Phase3 で revert された)
  - Step2-1 `CameraViewModel` に `lastValidRotationAngle: CGFloat` を `@Observable` の var として導入。orientation observer のクロージャから `portrait` / `landscapeLeft` / `landscapeRight` のみを 90 / 0 / 180 に変換して書き込む (それ以外の向きは無視 = 直前値維持)。`capturePhoto` 内の `currentRotationAngle()` 呼び出しも同プロパティ参照に切替
  - ~~Step2-2~~ (Phase3 で revert): `CameraPreviewView` の preview connection は B3' 確定で **常に 90° 固定**。`lastValidRotationAngle` は capture 用にだけ参照する
  - Step2-3 実機で `lastValidRotationAngle` が landscape で更新されることを debug overlay で確認 (preview 回転は実装しないため目視確認は Phase3 で代替)
- **Phase3 UI を portrait に確定 + 撮影画像のみ世界向き** — B3' (純正カメラ portrait lock 準拠)。判断 B の確定セクション参照
  - Step3-1 `Info.plist` の `UISupportedInterfaceOrientations` を portrait のみに限定 (auto-rotation を停止)
  - Step3-2 `CameraView` を portrait 1 本のレイアウトに維持 (B2 として一時導入した GeometryReader の portrait/landscape 切替は撤回)
  - Step3-3 `CameraPreviewView` の `rotationAngle` 引数を撤去し、preview connection の `videoRotationAngle` を 90° 固定に。capture connection は `CameraSession.capturePhoto(rotationAngle:)` 経由で `lastValidRotationAngle` を渡し続け、撮影画像だけ世界向きで保存
  - Step3-4 実機で portrait UI 固定で持ち替えても回転待ちが起きないこと、横持ち撮影画像がサーバ `/admin` で横長保存されていることを確認
- **Phase4 履歴詳細の画像表示をアスペクト比追従に変更** — `HistoryDetailView.photo` の固定 aspect を撤去
  - Step4-1 `Image` を `.scaledToFit()` + `.frame(maxWidth: .infinity)` に置換
  - Step4-2 プレースホルダは 3:4 (portrait) を維持 — 画像がない時の仮表示はデフォルト用途 (縦) に合わせる
  - ~~Step4-3~~ 履歴一覧サムネ (`HistoryRowView.thumbnail`) の実機確認は本プラン対象外として別 TODO に分離
- **Phase5 EXIF orientation の正常性検証 (必要に応じ修正)** — landscape 撮影 JPEG が `/admin` / 端末両方で正しい向きで表示されること
  - Step5-1 実機で landscape 撮影 → server `/admin/:id/image` で確認
  - Step5-2 もし向きが崩れていれば `ImageCompressor` 内で orientation 正規化を追加
- **Phase6 仕上げ** — リグレッション確認、TODO クローズ
  - Step6-1 portrait 撮影が以前と同等以上 (WYSIWYG 化分は前進)
  - Step6-2 撮影中の回転 / 高速タップでクラッシュしない
  - Step6-3 TODO.md → DONE.md (両 TODO 項目を統合してクローズ)、本プランを `docs/plans/archive/` に移動

判断履歴:
- Phase1 着手時: (A2) + (B3) + (E1) を第一候補として開始
- Phase3 検証 (2026-05-02): B3 → B2 → **B3'** に確定 (詳細は判断 B の「確定」セクション参照)。これに合わせて判断 F の landscape レイアウト方針は不採用
