# my harness

Private SwiftUI app for a nightly checklist.

## v0 Scope

- SwiftUI / iOS 17+
- Local-first storage with SwiftData
- DDD-ish layered structure:
  - `domain/**/*.domain.swift`
  - `use_case/**/*.use_case.swift`
  - `infra/repository/**/*.repository.swift`
  - `infra/read_store/**/*.read_store.swift`
  - `state/**/*.state.swift`
  - `view/**/*.view.swift`
- Routine item CRUD, delete, and reordering
- Per-item daily repeat settings
- Today view with completion state
- Weekday local notifications with one configurable time
- Home Screen widget extension with interactive checklist toggles

Cloud API/DB integration is intentionally not implemented in v0, but repository ports keep the app ready for a future `my_api` backed implementation.

## Branches

- `develop`: default development branch
- `stage`: TestFlight upload branch
- `prod`: production promotion branch

## TestFlight CI

GitHub Actions uses a self-hosted Apple Silicon Mac runner:

```yaml
runs-on: [self-hosted, macOS, ARM64]
```

Current local runner:

- Directory: `/Users/kou888/apps/actions-runner-my-harness`
- Service: `actions.runner.kou88-my_harness.kou888-mac-my-harness`
- Extra label: `my-harness`

Useful runner commands:

```sh
cd /Users/kou888/apps/actions-runner-my-harness
./svc.sh status
./svc.sh stop
./svc.sh start
```

Workflows:

- `iOS Build`: manual dispatch, pushes to `develop`, and pull requests into `develop`, `stage`, or `prod`
- `TestFlight (Stage)`: manual dispatch, pushes to `stage`, and merged `develop` -> `stage` pull requests

Required repository variables:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`

Required repository secrets:

- `ASC_KEY_P8_BASE64`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`

`TestFlight (Stage)` fetches the latest provisioning profiles from App Store Connect at runtime:

- `my-harness-app-store-push-v2` for `com.kou888.myharness`
- `my-harness-widget-app-store` for `com.kou888.myharness.widget`

Both provisioning profiles must include the App Group entitlement. The app profile must also include Push Notifications:

```text
group.com.kou888.myharness
```

## AIタブ

4つ目の「AI」タブは、`my_api` の `/api/v3/ai` を会話履歴の正本として利用し、Mac上のOS Agentを経由してCodex app-serverを実行します。

- OpenAIはChatGPTサブスクリプションでログインした専用Codex runtimeを使い、OpenAI APIキーは使用しません。
- OpenRouterは実行ホストだけが保持するAPIキーを使います。キーやChatGPT認証情報をiPhoneへ渡しません。
- 相談モードは隔離ディレクトリ・読み取り専用・MCP無効、作業モードは選択済みWorkspaceだけを書き込み対象にします。
- RunイベントはSSEで表示し、`seq`を使って切断後の続きから再開します。バックグラウンド中もMac側の実行は継続します。
- 承認待ち・完了・失敗Pushのdeep linkは `myharness://ai/conversations/{conversationId}` です。
- AI実行には登録済みのMacまたはPCがオンラインである必要があります。オフライン時も保存済み会話は閲覧できます。

永続OS Agent relayを使いながら履歴を保存しないことは保証できないため、一時チャットは安全な非永続経路が実装されるまでUIで明示的に無効化しています。
