# TODO

- [ ] ナビバーを削除しパンくずリンクで階層を表示する [plan](docs/plans/breadcrumb-navigation.md)
  - [x] Phase 0: BreadcrumbView 単独 (chain + popCount + 描画 を 1 ファイル統合 / a11y / 単体テスト)
  - [x] Phase 1: 検索 UI (.searchable) を削除 (Step 1.0 で再導入 TODO 起票 → 1.1〜1.5 で削除)
  - [x] Phase 2: NavigationStack を path 化 + ナビバー削除 + カスタム戻る (Step 2.5 の edge swipe 早期検証はスキップ → Phase 6 にまとめる)
  - [x] Phase 3: GroupDetailView にパンくず統合 + 未分類時の非表示制御
  - [x] Phase 4: 左側省略レイアウト (Root に近い側を ...) + Dynamic Type / RTL 検証
  - [ ] Phase 5: 動作確認 + テスト + VoiceOver 確認
  - [ ] Phase 6: TestFlight (実機リグレッション + edge swipe / VoiceOver / Dynamic Type 確認)
- [ ] 検索 UI を再導入する (パンくず実装で一旦削除した分。仕様: Item は scope 無視で全 `.completed` 横断 / Group は scope 配下子孫の名前 contains。`SegmentQueryTests` 末尾の仕様コメントブロックを参照)
- [ ] グループで項目を選択すると次の画面で未分類が選択されてしまうのを直す
- [ ] カメラ画面に閉じるボタンを入れる
- [ ] カメラを横にしたときに倍率表示の文字を横に回転する

- [ ] 管理画面の改善
