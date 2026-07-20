# Push通知設定のAPI契約

## 現状

iOSは次のサーバー設定を取得・更新し、通知表示のため端末内にもキャッシュする。

- Push通知全体
- Missionの実行完了・失敗
- 新しいRecommendationSet

Push通知全体を無効化した場合は、登録済みPush Deviceを削除し、iOSのRemote Notification登録も解除する。
種類別設定はフォアグラウンド表示と通知タップへ適用する。

サーバー正本は、認証付きの `GET /api/v2/notification-preferences` と `PUT /api/v2/notification-preferences` で取得・更新する。

## APIに必要な契約

種類別設定を全配送経路へ適用するには、認証済みユーザー向けに次のRead/Write契約が必要になる。

```json
{
  "pushEnabled": true,
  "missionEventsEnabled": true,
  "recommendationsEnabled": true
}
```

保存時はユーザー単位で上書きし、Notification Outboxへ積む前にイベント種別と照合する。

- `*_mission_completed` / `*_mission_failed` / `execution_completed` / `execution_failed` は `missionEventsEnabled`
- `venture_recommendations_ready` は `recommendationsEnabled`
- `pushEnabled` がfalseなら全イベントを保存・配送しない

APNs payloadには、iOS側でも同じ分類を検証できるよう `eventType` を含める。既存の `entityType`、`entityId`、`route` は維持する。

レスポンスは上記3項目を `data` に格納する。設定APIの命名が確定時に変わった場合は、iOSのAPI Clientだけを同時に調整する。
