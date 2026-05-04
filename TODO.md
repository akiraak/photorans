# TODO

- [ ] グループをフォルダという名称に変更 [plan](docs/plans/group-to-folder-rename.md)
      スコープ: ユーザーに見える日本語文字列のみ (`Text` / `Label` / `navigationTitle` / `Section` / `accessibilityLabel` 等 20 か所)
      Swift 識別子 (`ItemGroup` / `Features/Group/` 配下のクラス・ファイル名 / `Item.group` 等) と SwiftData 永続化は据え置き (別 TODO で起票検討)
  - [ ] Phase1 文字列差し替え
    - [ ] Step1-1 `HomeView.swift` 3 か所 (Picker label / 削除 Label / メニュー accessibilityLabel)
    - [ ] Step1-2 `HomeFAB.swift` 1 か所 (Group 作成 FAB の accessibilityLabel)
    - [ ] Step1-3 `GroupCreateSheet.swift` 2 か所 (TextField placeholder / navigationTitle)
    - [ ] Step1-4 `GroupRenameSheet.swift` 2 か所 (TextField placeholder / navigationTitle)
    - [ ] Step1-5 `GroupDetailView.swift` 3 か所 (削除確認 alert 文言 3 種)
    - [ ] Step1-6 `GroupListView.swift` 5 か所 (Root/Group 空状態文言 + 行サブタイトル、`グループ化` → `フォルダで整理` 書き換え含む)
    - [ ] Step1-7 `MoveToGroupSheet.swift` 2 か所 (Section ヘッダ / navigationTitle)
    - [ ] Step1-8 `ItemDetailView.swift` 2 か所 (移動メニュー Label / metadata label)
    - [ ] Step1-9 `rg 'グループ' ios/Photorans --type swift` で抜け漏れ確認 (コメント / 識別子説明以外がヒットしないこと)
    - [ ] Step1-10 コードレビュー (WSL2 ではビルド不可)
  - [ ] Phase2 実機確認 (タグ push → Bitrise → TestFlight、Akira さん事前確認)
  - [ ] Phase3 仕上げ (TODO → DONE 移送、plan を archive へ)
- [ ] 翻訳中アニメーションの変更
- [ ] 日->英, 英->日の両方向の翻訳対応
- [ ] OCRモデルと翻訳モデルを切り替え可能に
  - [ ] 管理画面でモデル別の料金比較ができるように
  - [ ] 管理画面で１アイテムごとの平均料金を表示
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] プライバシーの観点からサーバ側で画像、OCRテキスト、翻訳テキストを保持しない
      - 最適なAIモデルを選択するために画像ファイルサイズ、OCRテキスト文字数、翻訳テキスト文字数を保持する
- [ ] 管理画面の改善
