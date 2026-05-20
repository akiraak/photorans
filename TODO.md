# TODO

- [ ] 管理画面の改善 - OCRモデルと翻訳モデルを切り替え可能に ([plan](docs/plans/admin-model-switching.md))
  - 要件:
    - 左ペインに見出し、右ペインにコンテンツにする
    - OCRと翻訳のモデルを変更可能に
    - モデル別の料金比較ができるように
    - １アイテムごとの平均料金を表示
    - OCR料金平均と翻訳料金平均
    - その他必要とあるものを表示
  - [ ] Phase1: `pricing.ts` のモデル候補拡張 (Opus / Haiku 追加, `supportsVision`)
  - [ ] Phase2: history スキーマを OCR/翻訳別 usage に拡張 (10 列追加, ALTER TABLE 冪等)
  - [ ] Phase3: `settings` テーブル + `getSetting` / `setSetting` 実装
  - [ ] Phase4: `/translate` を OCR / 翻訳の 2 段呼び出しに分割 (レスポンス JSON 互換維持)
  - [ ] Phase5: 管理画面を 2 ペイン構造に再設計 (`renderAdminLayout`)
  - [ ] Phase6: モデル設定 UI (`/admin/settings` GET/POST)
  - [ ] Phase7: サマリ + モデル別比較セクション (1件あたり平均, OCR/翻訳別平均)
  - [ ] Phase8: 一覧 / 詳細ページの料金表示を OCR/翻訳別に
  - [ ] Phase9: 疎通確認 (legacy 行混在 + 新規 `/translate` 投入)

- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] プライバシーの観点からサーバ側で画像、OCRテキスト、翻訳テキストを保持しない
      - 最適なAIモデルを選択するために画像ファイルサイズ、OCRテキスト文字数、翻訳テキスト文字数を保持する
- [ ] 管理画面の改善

- [ ] アプリの接続先を変更する。XXXXXXXXXXXXは変更する
      https://photorans.chobi.me/XXXXXXXXXXXX/
      https://photorans.chobi.me/XXXXXXXXXXXX/admin