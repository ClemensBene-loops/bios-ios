# BIOS iOS

Minimal SwiftUI app (iOS 17+, bundle ID `at.bene.bios`) that will receive push
notifications from the BIOS server. Built without a Mac, like the Loop
"Browser Build": GitHub Actions macOS runner + fastlane + App Store Connect API
key + fastlane match. Full documentation follows in Phase 4.

## Layout

- `project.yml`: XcodeGen spec. `BIOS.xcodeproj` is generated on the runner and not committed.
- `BIOS/`: Swift sources and asset catalog (app icon). `App/AppDelegate.swift` asks for push
  permission, registers with APNs and uploads the device token on every launch via
  `Networking/APIClient.swift` (`POST {BIOSAPIBaseURL}/v1/devices`, `Authorization: Bearer <BIOSAPISecret>`,
  `environment` = `sandbox` for Debug, `production` for Release/TestFlight from `APS_ENVIRONMENT`).
  The main view (`Views/ContentView.swift`) shows the Whoop check and outlook from
  `GET /v1/summary` (cached in Application Support for offline use); a push tap scrolls to
  the section of its `thread-id`. Notification categories: `WHOOP_ALERT`, `WHOOP_CLEAR`,
  `OUTLOOK_ALERT`, `OUTLOOK_WEEKLY`.
- `Config/`: Info.plist, entitlements (Push), xcconfigs (team, `APS_ENVIRONMENT`).
- `fastlane/`: lanes `validate_secrets`, `identifiers`, `certs`, `build`, `release`.
- `tools/make_icon.py`: renders the app icon (Pillow + numpy), preview in `docs/icon-preview.png`.

## Workflows (Actions tab, manual only)

1. Validate Secrets: read-only check of secrets, API key and Match-Secrets.
2. Add Identifiers: registers `at.bene.bios` with Push Notifications.
3. Create Certificates: adds the App Store profile to Match-Secrets, reusing the existing distribution certificate (shared with Loop, never renewed or revoked here).
4. Build BIOS: builds, signs and uploads to TestFlight.

Secrets are the organization secrets of `ClemensBene-loops` (`TEAMID`, `FASTLANE_KEY_ID`,
`FASTLANE_ISSUER_ID`, `FASTLANE_KEY`, `GH_PAT`, `MATCH_PASSWORD`), plus optional
`BIOS_API_BASE_URL` and `BIOS_API_SECRET` for the app config. No secret values in this repo.
