# 家電リモコンウィジェット

2026-09-08。iOS 17以降のApp Intentによる対話型ウィジェット。ライト・エアコンともアプリを開かず操作する。

## 使い方

1. 更新後にMyHarnessを一度開く。既存のログインを共有Keychainへ移行する。ログインしていない場合は既存のログイン画面を利用する。
2. ホーム画面からmy harnessのウィジェットを追加する。「家電リモコン」は中サイズで両機器、「ライト」「エアコン」は個別の小サイズ。
3. エアコンを含むウィジェットは長押し→編集で運転モードを選ぶ。「前回設定」は前回の設定で運転。その他はモード・温度・風量の指定が必要。未設定時は運転ボタンを無効化するが停止は使える。
4. 設定の変更だけでは送信しない。運転・停止・点灯・消灯ボタンで送信する。
5. 背景のタップ、またはアプリの設定→家電リモコンから接続確認・使い方を開ける。

通信エラーや権限不足はウィジェットに表示する。赤外線操作のため、成功表示は「信号を送信しました」と送信時刻であり電源状態を表さない。再送はユーザーの明示操作のみ。通信中の同一機器連打は抑制する。

## 認証

既存App Group `group.com.kou888.myharness`をKeychain access groupとして使用する。認証情報はUserDefaultsやファイルへ保存しない。端末の初回ロック解除後に読めるThisDeviceOnly項目とする。共有するのは既存Cognitoセッションで、SwitchBotのtoken/secretはサーバーのみ。

既存ログイン保護のため、アプリ専用Keychainから共有Keychainへの一度限りの移行を行う。保存に成功してから旧項目を削除する。ログアウトは両方を削除してウィジェットを更新する。移行処理は既存利用者が旧形式の配布版から更新し終わるまで残し、終了時には`CognitoAuthSession.loadToken`内の旧Keychain読み取り部分を削除する。dual writeはしない。

ウィジェットのプロセス内でCognito更新を行い、アプリを開く必要はない。更新中のログアウト/アカウント変更を検出した場合はセッションを復活させず、操作を中止する。Cognito外部応答/旧保存形式で欠けうるrefresh/id token、およびウィジェットで未選択の設定値に限りOptionalを使用する。エアコン設定の暗黙補完はしない。

AppleのApp GroupはKeychain共有も許可するため、新たなKeychain entitlementや配布profileの追加は不要。
https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps

## 検証

MyHarness schemeのSimulator build、既存のSwift tests、チャット回帰テストを実行する。`swift test --filter HomeControlSessionTests`でログイン更新・失効・更新中のログアウト・更新不要時の通信なしを検証する。Simulatorの実ウィジェットでレイアウト、未設定運転の無効化、設定画面、認証、背景タップのdeep linkを確認する。APIは別repoの`docs/home-control.md`を正本とする。実機の点灯/運転状態の確認は赤外線受信側で行う。
