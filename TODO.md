# TODO

- [ ] TestFlight での実行 [plan](docs/plans/testflight.md)
  - [x] Phase4-1 production プロファイルと API URL 切替
  - [x] Phase4-2 App Store Connect アプリレコード作成
  - [ ] Phase4-3 production ビルド
    - [ ] VisionCamera Release WMO クラッシュ回避 [plan](docs/plans/testflight-vision-camera-release-fix.md)
      - [ ] Step1 config plugin 作成
      - [ ] Step2 production ビルド再実行
  - [ ] Phase4-4 TestFlight 提出
  - [ ] Phase4-5 実機 TestFlight 動作確認
- [ ] カメラを横にして撮影したらサーバに投げる画像やクライアントでの表示も横にする（撮影直後 / 表示時 / 送信時の各層で EXIF orientation を一貫させる）
- [ ] 利用トークンと料金を管理画面に表示
- [ ] カメラのフォーカスが合わない（まず `device.minimumFocusDistance` から逆算した自動 zoom で近接被写体の合焦を改善する。それでも不足なら iOS のみ Native カメラ Module 化のスパイクを別途検討）