# TODO

- [ ] アプリアイコンの再差し替え。差し替え画像:/home/ubuntu/photorans/photorans-icon.png [plan](docs/plans/app-icon-replace-2.md)
  - [x] Step 1: `photorans-icon.png` を 1024×1024 にリサイズし `icon-1024.png` を上書き
  - [x] Step 2: ルート直下の `photorans-icon.png` を削除
  - [x] Step 3: 差分確認しコミット
  - [ ] Step 4: TestFlight 実機確認 (タグ push は Akira さん許可後)
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] カメラ画面に閉じるボタンを入れる [plan](docs/plans/camera-close-button.md)
  - [x] Step 1: `CameraView` に閉じるボタン UI と `onClose` を追加
  - [x] Step 2: `HomeFAB` から `onClose` を配線
  - [x] Step 3: XcodeGen 再生成 (新規ファイル無しのためスキップ判断)
  - [ ] Step 4: TestFlight 実機確認 (タグ push は Akira さん許可取得後)
- [ ] カメラを横にしたときに倍率表示の文字を横に回転する
- [ ] グループの中に入った場合の空だった時の表示を「翻訳作成するかグループを作成するか」のテキストに変える
      グループのルート: 今までと同じ
      グループ内のグループ（English > Store）: 「翻訳作成するかグループを作成するか」

- [ ] 管理画面の改善
