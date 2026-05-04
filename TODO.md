# TODO

- [ ] 翻訳中アニメーションの変更
- [ ] グループの中に入った場合の空だった時の表示を「翻訳作成するかグループを作成するか」のテキストに変える [plan](docs/plans/group-empty-state.md)
      グループのルート: 今までと同じ
      グループ内のグループ（English > Store）: 「翻訳作成するかグループを作成するか」
  - [x] Phase1 文言分岐実装
    - [x] Step1-1 `GroupListView.emptyView` を `rootEmptyView` にリネーム (中身据え置き)
    - [x] Step1-2 `groupEmptyView` を新規追加 (新文言 + `tray` アイコン)
    - [x] Step1-3 `rootBody` / `groupBody(group:)` の参照を新名に書き換え
    - [x] Step1-4 コードレビュー (WSL2 ではビルド不可)
  - [ ] Phase2 実機確認 (タグ push → Bitrise → TestFlight、Akira さん事前確認)
  - [ ] Phase3 仕上げ (TODO → DONE 移送、plan を archive へ)
- [ ] グループをフォルダという名称に変更
- [ ] 日->英, 英->日の両方向の翻訳対応
- [ ] OCRモデルと翻訳モデルを切り替え可能に
  - [ ] 管理画面でモデル別の料金比較ができるように
  - [ ] 管理画面で１アイテムごとの平均料金を表示
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] プライバシーの観点からサーバ側で画像、OCRテキスト、翻訳テキストを保持しない
      - 最適なAIモデルを選択するために画像ファイルサイズ、OCRテキスト文字数、翻訳テキスト文字数を保持する
- [ ] 管理画面の改善
