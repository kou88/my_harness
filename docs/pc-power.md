# PC管理（2026-09-16）

AI画面右上の設定→PC管理で、PC/AI/自宅中継機の状態、起動、通常停止、作業完了後の停止、停止予約取消、操作履歴を表示する。GPUの実行枠・コンテキストへも移動できる。画面表示中は5秒ごとに更新し、foreground復帰時も再取得する。

起動の確認期限は5分、停止予約は60分。停止処理開始後は取り消せない。接続不明を電源OFFとは表示しない。通知はmyharness://ai/pcs/{hostId}で対象PCを開く。

検証: iPhone17 Pro/iOS26.4（UDID AD933F96-24D3-4D6C-A728-8FA3E1DEBD2C）で本体build/run、稼働状態表示、模擬作業中の停止予約、取消、サーバー反映を確認。通知routing12テストとチャットstate回帰テスト成功。

Simulatorの本体確認はCODE_SIGNING_ALLOWED=YES、CODE_SIGN_IDENTITY=-で行う。署名なしbuildは通るがApp Groupが使えず起動で失敗するため、build成功とUI確認を区別する。
