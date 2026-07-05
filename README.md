# my harness

Private SwiftUI app for a nightly checklist plus one-line logs.

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
- Item types: `check` and `checkLog`
- Today view with completion state and inline one-line logs
- Weekday local notifications with one configurable time
- Weekly plain-text export to clipboard
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

Required repository variables:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`

Required repository secrets:

- `ASC_KEY_P8_BASE64`
- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `BUILD_PROVISION_PROFILE_BASE64` for `com.kou888.myharness`
- `BUILD_WIDGET_PROVISION_PROFILE_BASE64` for `com.kou888.myharness.widget`

Both provisioning profiles must include the App Group entitlement:

```text
group.com.kou888.myharness
```
