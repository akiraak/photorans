# TODO

- [ ] 利用トークンと料金を管理画面に表示
- [ ] 横向きの写真を撮りたい / 撮影範囲の WYSIWYG 化 ([plan](docs/plans/landscape-capture.md))
  - [ ] Phase1 撮影範囲 WYSIWYG 化 (`videoGravity = .resizeAspect` + portrait レイアウト再設計)
  - [ ] Phase2 プレビュー回転対応 (`CameraPreviewView` の connection 角度追従)
  - [ ] Phase3 撮影 UI の回転追従 + landscape レイアウト (シャッター位置とアイコン向き)
  - [ ] Phase4 履歴詳細の画像表示をアスペクト比追従に変更
  - [ ] Phase5 EXIF orientation の正常性検証 (必要に応じ修正)
  - [ ] Phase6 仕上げ (リグレッション確認、TODO クローズ)
- [ ] カメラの機能強化の調査