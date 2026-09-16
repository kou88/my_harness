# PC管理（2026-09-16）

AI画面右上の設定→PC管理で、PC/AI/自宅中継機の状態、起動、通常停止、作業完了後の停止、停止予約取消、操作履歴を表示する。GPUの実行枠・コンテキストへも移動できる。画面表示中は5秒ごとに更新し、foreground復帰時も再取得する。

起動の確認期限は5分、停止予約は60分。停止処理開始後は取り消せない。接続不明を電源OFFとは表示しない。通知はmyharness://ai/pcs/{hostId}で対象PCを開く。

検証: iPhone17 Pro/iOS26.4（UDID AD933F96-24D3-4D6C-A728-8FA3E1DEBD2C）で本体build/run、稼働状態表示、模擬作業中の停止予約、取消、サーバー反映を確認。通知routing12テストとチャットstate回帰テスト成功。

Simulatorの本体確認はCODE_SIGNING_ALLOWED=YES、CODE_SIGN_IDENTITY=-で行う。署名なしbuildは通るがApp Groupが使えず起動で失敗するため、build成功とUI確認を区別する。

## 共有設定の接続表示（2026-09-16）

共有画面の `model.online` は電源ではなくOS Agentのクラウド接続を示す。モデル一覧APIは `agent_hosts.status` と75秒以内の `last_seen_at` で判定する。AI停止でAgent接続まで切れる既存経路があり、「PCを起動してください」という案内は不正確だった。

共有画面ではPC管理APIの状態とモデル一覧を別々に読み、PC／OS Agent／AIを分けて表示する。表示開始・foreground復帰・5秒ごと・pull-to-refreshで取得し直す。取得失敗は未取得／確認不能として示し、古いオンライン情報で共有設定を保存させない。PC管理画面へ直接移動できる。API契約は変更せず、旧Agentにも適用できる。

確認: iOS Release Simulator build、AI domain 33テスト、chat state回帰。隔離Simulator hostで「PC稼働・Agent未接続・AI停止」→Agent復旧の5秒更新、状態取得失敗時の表示を確認。`scripts/prepare-ai-sharing-ui-regression.rb` は本番の共有画面とstateを、メモリ内transportでbuildする。実PC・クラウド・GPUにはアクセスしない。テスト対象外の遷移先だけをstubにしている。

Agent側修正は別repo。PC-02を起動しない依頼のため、Agentの実機配置と稼働中PCとのE2Eは未実施。AIのPCIe安全停止は別問題であり、この表示修正で解除しない。
