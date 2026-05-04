# TODO

- [ ] アイテムとグループの一覧に画像を表示する [plan](docs/plans/list-thumbnails.md)
  - [x] Step 1: `ThumbnailCache` (NSCache wrapper) を実装
  - [x] Step 2: `ItemThumbnailView` を実装 (path + size → 画像 / プレースホルダ)
  - [x] Step 3: `ItemRowView` に左 56pt サムネを統合 (3 ステータス共通)
  - [x] Step 4: `HomeQueries.representativeItem(of:)` を追加 + `SegmentQueryTests` に追記
  - [x] Step 5: `GroupListView` の leading icon を サムネ / `folder.fill` に分岐
  - [x] Step 6: XcodeGen 再生成 (新規 .swift 2 ファイルあり)
  - [ ] Step 7: TestFlight 実機確認 (タグ push は Akira さん許可後)
- [ ] 翻訳中アニメーションの変更
- [ ] OCRモデルと翻訳モデルを切り替え可能に
  - [ ] 管理画面でモデル別の料金比較ができるように
  - [ ] 管理画面で１アイテムごとの平均料金を表示
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] カメラを横にしたときに倍率表示の文字を横に回転する
- [ ] グループの中に入った場合の空だった時の表示を「翻訳作成するかグループを作成するか」のテキストに変える
      グループのルート: 今までと同じ
      グループ内のグループ（English > Store）: 「翻訳作成するかグループを作成するか」

- [ ] プライバシーの観点からサーバ側で画像、OCRテキスト、翻訳テキストを保持しない
      - 最適なAIモデルを選択するために画像ファイルサイズ、OCRテキスト文字数、翻訳テキスト文字数を保持する
- [ ] 管理画面の改善
