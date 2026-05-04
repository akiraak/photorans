# アプリアイコン差し替え

## 目的・背景

`/home/ubuntu/photorans/photorans.png` を新しいアプリアイコンとして iOS ターゲットに反映する。

## 現状

- AppIcon は `ios/Photorans/Resources/Assets.xcassets/AppIcon.appiconset/` に配置
- 構成は **single-size 1024×1024** スタイル (iOS 17+ で標準):
  - `Contents.json`: `idiom: universal` / `platform: ios` / `size: 1024x1024` / `filename: icon-1024.png` の 1 エントリのみ
  - 実体: `icon-1024.png` (1024×1024)
- ビルド設定は `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` (`ios/project.yml:44`) で参照済み

## 差し替え素材の確認

`/home/ubuntu/photorans/photorans.png`:
- サイズ: **1254×1254** (1024 ではない → リサイズ必須)
- フォーマット: PNG, 8-bit/color RGB, sRGB, **アルファ無し** (iOS AppIcon は alpha 不可なので OK)
- 容量: 約 1.12 MiB

## 対応方針

`Contents.json` の構造は変更せず、`icon-1024.png` を **1024×1024 にリサイズしたもので上書き** する。ファイル名・配置場所・appiconset の構造は据え置き。

リサイズには ImageMagick (`convert`) もしくは Python Pillow を使い、以下を担保:
- 出力 1024×1024
- sRGB / RGB (no alpha)
- 元素材が正方形 (1254×1254) なので歪みは出ない

## 影響範囲

- `ios/Photorans/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (上書き)
- `Contents.json` は無変更
- `.swift` ファイルの追加削除は無し → **XcodeGen 再生成は不要** (memory: `feedback_xcodegen_regenerate.md` の対象外)
- ルート直下の `/home/ubuntu/photorans/photorans.png` は差し替え用素材なので、反映後に削除する (リポジトリには残さない)

## テスト方針

- WSL2 では Xcode 起動できないため、ローカルでの実アイコン表示確認は不可
- TestFlight ビルドで Akira さん実機確認:
  - ホーム画面 / Spotlight / 設定アプリのアイコン表示
  - App Store Connect 側でアイコンが正しく取り込まれるか (Apple のプロセシング段階で reject されないこと)

## Phase / Step

- **Step 1**: `photorans.png` を 1024×1024 にリサイズし、`ios/Photorans/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` を上書き
- **Step 2**: ルート直下の `photorans.png` を削除
- **Step 3**: `git status` / `git diff --stat` で差分が想定どおり (icon-1024.png 上書き + photorans.png 削除のみ) であることを確認、コミット
- **Step 4**: TestFlight 実機確認 (タグ push は Akira さん許可取得後)

## 留意事項

- 上書きするとローカルでは元アイコンに戻せない。git 履歴経由で復旧は可能だが、Step 1 着手前に念のため `git status` のクリーンさを確認する
- iOS 17+ は single-size 1024 で OK だが、もし将来 iOS 16 以下対応が必要になれば multi-size appiconset への展開が要る (現 `deploymentTarget.iOS: "17.0"` のため対象外)
