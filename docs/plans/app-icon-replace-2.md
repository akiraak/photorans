# アプリアイコン再差し替え

## 目的・背景

`v0.1.20` で `photorans.png` を素材としたアプリアイコンを TestFlight 配布したが、Akira さん判断で再差し替え要請。新素材 `/home/ubuntu/photorans/photorans-icon.png` で `icon-1024.png` を再度上書きする。

旧プラン (`docs/plans/archive/app-icon-replace.md`) と同じ手順を踏むので方針はそのまま流用。

## 差し替え素材の確認

`/home/ubuntu/photorans/photorans-icon.png`:
- サイズ: **1254×1254** (1024 ではない → リサイズ必須)
- フォーマット: PNG, 8-bit/color RGB, **アルファ無し** (iOS AppIcon は alpha 不可なので OK)
- 容量: 約 1.16 MiB

## 対応方針

`Contents.json` の構造は変更せず、`icon-1024.png` を 1024×1024 にリサイズしたもので上書き。Pillow で:

- 出力 1024×1024 / sRGB / RGB (no alpha)
- 元素材が正方形なので歪みなし

## 影響範囲

- `ios/Photorans/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (上書き)
- `Contents.json` は無変更
- `.swift` 追加削除無し → **XcodeGen 再生成は不要**
- ルート直下 `/home/ubuntu/photorans/photorans-icon.png` は反映後に削除

## Step 分解

- **Step 1**: `photorans-icon.png` を 1024×1024 にリサイズし `icon-1024.png` を上書き
- **Step 2**: ルート直下の `photorans-icon.png` を削除
- **Step 3**: 差分確認 (`git status` / `git diff --stat`) しコミット
- **Step 4**: TestFlight 実機確認 (タグ push は Akira さん許可後)

## テスト方針

- WSL2 ではアイコン表示確認不可
- TestFlight ビルドで Akira さん実機確認 (ホーム画面 / Spotlight / 設定アプリ / App Store Connect 取り込み)
