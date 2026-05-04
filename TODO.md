# TODO

- [ ] 未分類にアイテムがいくつか存在するのに、グループに一度入った後に画面トップの未分類ボタンから移動するとアイテムが何もないというバグの修正 [plan](docs/plans/unclassified-segment-empty-bug.md)
  - [ ] Phase 1 Step 1.1: `RootView` に Picker + `ZStack + opacity` 骨組み (selectedSegment State 追加)
  - [ ] Phase 1 Step 1.2: `HomeView` から Picker 描画と selectedSegment State を削除
  - [ ] Phase 1 Step 1.3: `RootView` グループモード branch に NavigationStack + HomeView(scope:.root) を配線
  - [ ] Phase 1 Step 1.4: `RootView` 未分類モード branch に UnclassifiedListView を配線
  - [ ] Phase 1 Step 1.5: `SegmentScope.defaultSegment` 削除
  - [ ] Phase 1 Step 1.6: `HomeQueries` 改修 (`directItems` の `.group` 分岐削除 + `directContents(group:)` 追加)
  - [ ] Phase 1 Step 1.7: `UnclassifiedListView` を scope 非依存化 + `HomeFAB(scope:.root)` overlay 追加
  - [ ] Phase 1 Step 1.8: `GroupListView` を Group X で「子 Group + 子 Item」混在表示に改修
  - [ ] Phase 1 Step 1.9: `SegmentQueryTests` の更新 + 混在表示テスト追加
  - [ ] Phase 1 Step 1.10: ドキュメントコメント整合
  - [ ] Phase 2 Step 2.1: ローカル / シミュレータ確認
  - [ ] Phase 2 Step 2.2: タグ push → Bitrise → TestFlight
  - [ ] Phase 2 Step 2.3: 実機確認 (Picker 固定アニメ / モード状態保持 / 混在表示 / 撮影保存先)
  - [ ] Phase 2 Step 2.4: NG ならプラン書き直し
  - [ ] Phase 2 Step 2.5: DONE 移送 + plan archive
- [ ] 翻訳中アニメーションの変更
- [ ] OCRモデルと翻訳モデルを切り替え可能に
  - [ ] 管理画面でモデル別の料金比較ができるように
  - [ ] 管理画面で１アイテムごとの平均料金を表示
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] カメラを横にしたときに倍率表示の文字を横に回転する
- [ ] グループの中に入った場合の空だった時の表示を「翻訳作成するかグループを作成するか」のテキストに変える
      グループのルート: 今までと同じ
      グループ内のグループ（English > Store）: 「翻訳作成するかグループを作成するか」
- [ ] グループをフォルダという名称に変更
- [ ] プライバシーの観点からサーバ側で画像、OCRテキスト、翻訳テキストを保持しない
      - 最適なAIモデルを選択するために画像ファイルサイズ、OCRテキスト文字数、翻訳テキスト文字数を保持する
- [ ] 管理画面の改善
