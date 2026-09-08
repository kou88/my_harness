# 家電リモコンウィジェット

2026-09-08。iOS 17以降のApp Intentによる対話型ウィジェット。ライト・エアコンともアプリを開かず操作する。

## 使い方

1. 更新後にMyHarnessを一度開く。既存のログインを共有Keychainへ移行する。ログインしていない場合は既存のログイン画面を利用する。
2. ホーム画面からmy harnessのウィジェットを追加する。「家電リモコン」は中サイズで両機器、「ライト」「エアコン」は個別の小サイズ。
3. エアコンを含むウィジェットは長押し→編集で運転モードを選ぶ。「前回設定」は前回の設定で運転。その他はモード・温度・風量の指定が必要。未設定時は運転ボタンを無効化するが停止は使える。
4. 設定の変更だけでは送信しない。運転・停止・点灯・消灯ボタンで送信する。
5. 背景のタップ、またはアプリの設定→家電リモコンから接続確認・使い方を開ける。

通信エラーや権限不足はウィジェットに表示する。赤外線操作のため、成功表示は「信号を送信しました」と送信時刻であり電源状態を表さない。再送はユーザーの明示操作のみ。通信中の同一機器連打は抑制する。

## ロック画面

「ライト」「エアコン」は`accessoryRectangular`にも対応する。ロック画面を長押し→カスタマイズ→ロック画面→時計下のウィジェット枠→my harnessから追加する。横長2枠を並べて配置でき、それぞれにオン・オフの明示ボタンを表示する。「家電リモコン」の一体型はホーム画面専用。

エアコンの設定はロック画面のカスタマイズ中に配置したウィジェットをタップして選ぶ。ホーム画面の設定とは独立しており、未設定の運転は無効・停止は有効。設定変更だけでは送信しない。送信中・失敗・送信時刻を単色のコンパクト表示にし、実際の電源状態を推測したトグルは置かない。

通常のロック画面ウィジェットのボタンは端末認証後に実行される。MyHarnessの起動は不要。ロック未解除のまま操作できる専用Control Widgetはこの実装には含まない。
https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities

## 認証

既存App Group `group.com.kou888.myharness`をKeychain access groupとして使用する。認証情報はUserDefaultsやファイルへ保存しない。端末の初回ロック解除後に読めるThisDeviceOnly項目とする。共有するのは既存Cognitoセッションで、SwitchBotのtoken/secretはサーバーのみ。

既存ログイン保護のため、アプリ専用Keychainから共有Keychainへの一度限りの移行を行う。保存に成功してから旧項目を削除する。ログアウトは両方を削除してウィジェットを更新する。移行処理は既存利用者が旧形式の配布版から更新し終わるまで残し、終了時には`CognitoAuthSession.loadToken`内の旧Keychain読み取り部分を削除する。dual writeはしない。

ウィジェットのプロセス内でCognito更新を行い、アプリを開く必要はない。更新中のログアウト/アカウント変更を検出した場合はセッションを復活させず、操作を中止する。Cognito外部応答/旧保存形式で欠けうるrefresh/id token、およびウィジェットで未選択の設定値に限りOptionalを使用する。エアコン設定の暗黙補完はしない。

AppleのApp GroupはKeychain共有も許可するため、新たなKeychain entitlementや配布profileの追加は不要。
https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps

## 検証

MyHarness schemeのSimulator build、既存のSwift tests、チャット回帰テストを実行する。`swift test --filter HomeControlSessionTests`でログイン更新・失効・更新中のログアウト・更新不要時の通信なしを検証する。Simulatorの実ウィジェットでレイアウト、未設定運転の無効化、設定画面、認証、背景タップのdeep linkを確認する。APIは別repoの`docs/home-control.md`を正本とする。実機の点灯/運転状態の確認は赤外線受信側で行う。

ロック画面追加時のローカル確認（2026-09-08）: iPhone 17 Pro Simulator（`AD933F96-24D3-4D6C-A728-8FA3E1DEBD2C`）向けbuild成功、共有セッションの5テスト成功。App Groupを使うため、起動確認用buildには`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`を指定し、更新版アプリの起動を確認した。Simulatorの設定に壁紙編集項目がなく、Widget scheme実行でもホーム画面が表示されたため、ロック画面用`#Preview`を用意した。Canvasの確認中にMacがロックされ、横長表示・ロック画面での設定操作・認証後の実機操作は未確認。
