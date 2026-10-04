# 記事URLとiOSアプリ連携・TestFlight診断（2026-10-05）

## 現在の実装

- Webの記事URLは `https://kou88.dev/articles/{UUID}`。iOSに既存の `myharness://articles/{UUID}` があるため、iOSのWeb記事内に「アプリで開く」を置く。未導入端末では元のWeb記事を維持し、自動リダイレクトしない。
- iOSは両URLを厳密に検証して同じ記事IDへ進む。HTTPSは `kou88.dev` のみ、`/articles/{UUID}` のみ受け付ける。ログインが必要なときはログイン後に記事を再取得する。記事APIの本人認証・所有者分離は既存のまま。
- `onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` でUniversal Linkを受ける。ただし、現時点のアプリにAssociated Domains entitlementがないため、HTTPSの自動遷移はまだ有効にならない。

## HTTPSの自動遷移に必要な設定（未実施）

1. Apple Developerの既存App ID `com.kou888.myharness` にAssociated Domains capabilityを追加する。Push NotificationsとApp Groupは維持する。
2. App Store配布用プロファイルを上記capabilityを含む形で更新し、CIが新しいプロファイルを取得できるようにする。署名・権限設定の変更なので事前承認が必要。
3. 既存プロファイルからApplication Identifier Prefixを確認し、Webの `/.well-known/apple-app-site-association` にそのprefixとbundle IDを指定する。対象パスは `/articles/*` に限定する。HTTPSでリダイレクトなし、JSONとして配信する。
4. iOSに再配布し、インストール直後と更新後のAASA取得を確認する。AppleのCDNによる反映には時間差がある。Safariで同一ドメイン内のリンクを押した場合はWebに留まるため、Webの「アプリで開く」導線も維持する。

## TestFlight HTTP 403

- stageの配布ジョブは、署名処理の前のApp Store Connect `GET /v1/apps` で `HTTP 403` を受ける。直近成功ジョブと現行ジョブのKey ID・Issuer IDは一致した。キー本文やJWTは記録・表示していない。
- 原因はまだ確定していない。キーの有効状態・ロール、個人キーなら作成者のアプリ権限、Apple側の契約・アクセス状態をApp Store Connectの「ユーザとアクセス」→「統合」→「App Store Connect API」で読み取り確認する。キーや権限の変更は事前承認が必要。
- CIのエラーログはHTTPコードしか出なかったため、AppleのJSONエラーの`code`だけを文字種制限して記録する。本文、JWT、ヘッダー、秘密鍵は表示しない。
