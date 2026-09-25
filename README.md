# BIOS iOS

Minimal SwiftUI app "BIOS" (iOS 17+) that receives push notifications from the
BIOS server (Whoop check, health outlook) with its own name and icon, and shows
the latest Whoop check and outlook in one screen. Built and signed without a Mac,
like the Loop "Browser Build": GitHub Actions macOS runner + fastlane + App Store
Connect API key + fastlane match, distributed via TestFlight.

The server side (API, APNs channel, cron jobs) lives in the private BIOS repo
(`api/server.py`, `reports/notify.py`, `reports/apns_tokens.py`); see its
`STATUS.md` and `CLAUDE.md`.

| | |
|---|---|
| Display name | BIOS |
| App Store Connect record | BIOS Health |
| Bundle ID | `at.bene.bios` |
| Team ID | `D457V2W8RG` (not a secret, also in `Config/Base.xcconfig`) |
| Minimum iOS | 17.0, iPhone only, portrait |
| GitHub | `ClemensBene-loops/bios-ios` (public, organization on the free plan) |

Status (2026-09-25): build 2 (`1.0 (2)`, from branch `phase2-push`) is installed
via TestFlight, the device token is registered at the server and a forced Whoop
check was sent via APNs. The owner confirmed on 2026-09-25 that the push arrives
on the iPhone with sender "BIOS" and the app icon (end-to-end accepted). ntfy stays
active in parallel on the server for now. Build  expires 90 days after its
upload (around 2026-12-24): upload a new build before then (see TestFlight flow).

This repo is **public**: no secrets, no server URL, no IPA and no personal data
are ever committed or uploaded as workflow artifacts.

## What the app does

- On every launch: asks for notification permission, registers with APNs and
  uploads the device token to the BIOS server (`POST /v1/devices`). Network
  errors, 429 and 5xx are retried with backoff (3 attempts); a failed
  permission, registration or upload is retried when the app becomes active again.
- Shows banners also while the app is in the foreground.
- Registers four notification categories with German group summaries
  ("%u weitere Whoop-Meldungen" etc.); with hidden previews the title stays visible.
- One main view: Whoop check section, "Ausblick" (viruses in wastewater, pollen,
  allergy) and a push status footer (permission, APNs registration, token upload).
  Data comes from `GET /v1/summary` and is cached in Application Support, so the
  view shows the last state offline.
- Tapping a push opens the app, scrolls to and highlights the section of its
  `thread-id` (`whoop` or `outlook`) and refreshes the summary.

## Repository layout

- `project.yml`: XcodeGen spec, the single source of truth for the Xcode project.
  `BIOS.xcodeproj` is generated on the runner (`xcodegen generate`) and not committed.
- `BIOS/App/`: `BIOSApp.swift`, `AppDelegate.swift` (permission, APNs registration,
  categories, token upload), `AppState.swift`, `SummaryStore.swift` (fetch + offline cache).
- `BIOS/Networking/`: `APIClient.swift` (Bearer auth, retry), `APIModels.swift`.
- `BIOS/Models/`, `BIOS/Views/`: summary models, main view and its sections.
- `BIOS/Config/AppConfig.swift`: reads the build-time config from Info.plist.
- `BIOS/Assets.xcassets`: app icon (rendered by `tools/make_icon.py`, preview in `docs/icon-preview.png`).
- `Config/`: `Info.plist`, `BIOS.entitlements` (`aps-environment`), xcconfigs
  (`Base` = team + automatic signing for local builds, `Debug` = `APS_ENVIRONMENT=development`,
  `Release` = `production`, optional git-ignored `Local.xcconfig`).
- `fastlane/`: `Fastfile` (lanes below), `Matchfile`. `Gemfile` for fastlane.
- `.github/workflows/`: workflows 1 to 4.

## Build pipeline (no Mac)

All workflows are **manual only** (`workflow_dispatch`, Actions tab), run only in
`ClemensBene-loops` (never in forks) and use the same org secrets. 2, 3 and 4
first run 1 as a job. 2 and 3 share a concurrency group, so they never run in parallel.

| Workflow | fastlane lane | What it touches at Apple |
|---|---|---|
| 1. Validate Secrets | `validate_secrets` | Nothing. Checks `GH_PAT`, that `Match-Secrets` exists and is private, the API key and that match decrypts; lists bundle ID, capabilities, app record and distribution certificates. |
| 2. Add Identifiers | `identifiers` | Registers the App ID `at.bene.bios` if missing and enables the Push Notifications capability. Idempotent. |
| 3. Create Certificates | `certs` | Creates the App Store provisioning profile for `at.bene.bios` and stores it in `ClemensBene-loops/Match-Secrets`. **Reuses** the distribution certificate shared with Loop; never creates, renews or revokes certificates, no nuke logic. Fails if the App ID or Push is missing. |
| 4. Build BIOS | `build` + `release` | Runner `macos-26`, Xcode 26.5 (falls back to the newest installed). Generates the project, injects the app config, sets build number = latest TestFlight build + 1, signs with the match profile, verifies the IPA has `aps-environment = production`, uploads to TestFlight (does not wait for processing). On failure only the build log is kept (7 days); the IPA is never uploaded as an artifact because it contains `BIOS_API_SECRET`. |

The App Store Connect app record ("BIOS Health") was created once by hand in
App Store Connect; workflow 4 needs it.

Order for a fresh setup: 1, 2, 3, create the app record, 4. For a normal new
build only 4 is needed.

## Secrets

Names only; values live in GitHub (and in the VM `.env` for the server side).

| Secret | Scope | Used for |
|---|---|---|
| `TEAMID` | organization `ClemensBene-loops` (shared with Loop) | Apple Developer Team ID |
| `FASTLANE_KEY_ID` | organization | App Store Connect API key ID |
| `FASTLANE_ISSUER_ID` | organization | App Store Connect API issuer ID |
| `FASTLANE_KEY` | organization | App Store Connect API key (`.p8` content) |
| `GH_PAT` | organization | Access to the private `Match-Secrets` repo |
| `MATCH_PASSWORD` | organization | Decrypts `Match-Secrets` |
| `BIOS_API_BASE_URL` | repository `bios-ios` | Server base URL, `https://<vm-host>/bios` |
| `BIOS_API_SECRET` | repository `bios-ios` | Bearer secret, must equal `BIOS_API_SECRET` in the VM `.env` |

- The org secrets reach this repo because it is public (on the free org plan org
  secrets are only available to public repos). If one shows up empty, check
  Organization > Settings > Secrets and variables > Actions > (secret) > Repository access.
- `BIOS_API_BASE_URL` and `BIOS_API_SECRET` are written into the runner's copy of
  `Config/Info.plist` with `plutil` in workflow 4 (keys `BIOSAPIBaseURL`,
  `BIOSAPISecret`). In git both keys are empty. Without them the app still builds,
  but shows "Server nicht konfiguriert" and uploads no token.
- Rotating the secret: update the VM `.env`, restart `bios-api`, update the repo
  secret, run workflow 4, install the new build.
- The **APNs key** (`.p8`, developer portal > Keys, "Apple Push Notifications
  service") is a different key from `FASTLANE_KEY`. It lives only on the VM
  (`/opt/bios/data/private/`, referenced by `BIOS_APNS_KEY_ID`, `BIOS_APNS_TEAM_ID`,
  `BIOS_APNS_KEY_PATH`), never in GitHub. One key serves sandbox and production
  for all apps of the team. The browser may save the portal download as
  `AuthKey_<KEY_ID>.p8.txt`: rename it to `.p8` before copying it to the VM.

## TestFlight flow

1. Push the code to the branch to build. In the Actions tab open
   "4. Build BIOS" > "Run workflow" and pick that branch in the "Use workflow from"
   selector (feature branches build without merging to `main`; the build number
   is always latest TestFlight + 1).
2. App Store Connect processes the build. "Keine Builds verfügbar" or the status
   "Bereit zur Übermittlung" in the meantime is normal; the first build of the app
   took much longer than later ones. `ITSAppUsesNonExemptEncryption = false` in
   Info.plist skips the export compliance question.
3. TestFlight > internal group **"Ich"** gets the build (internal testing needs no
   beta review). Every tester must be an App Store Connect user of the team.
4. On the iPhone: TestFlight app > BIOS > Install. A new build only shows up
   as "Aktualisieren" (Update) in TestFlight after processing has finished; until
   then TestFlight still offers the previous build.
5. TestFlight builds expire after 90 days (build : around 2026-12-24);
   after that the app no longer launches and no push arrives. Run workflow 4
   again before that. Idea: a scheduled run of workflow 4 (like Loop's monthly
   build) so a fresh build is always in TestFlight.

## Registering a new device

1. The Apple ID on the iPhone must be an App Store Connect user of the team and a
   tester in the internal group "Ich" (App Store Connect > Users and Access, then
   TestFlight > Ich > Testers).
2. Install the TestFlight app, accept the invitation, install BIOS.
3. Open BIOS once and allow notifications. The app registers its APNs token at
   the server (`POST /v1/devices`) on every launch; the push status footer shows
   whether the upload succeeded.
4. Check on the VM: the token appears in `/opt/bios/data/private/apns_tokens.json`
   (`environment: production` for TestFlight builds).
5. Test in `/opt/bios`: `python -m reports.whoop_check --notify --force` sends
   the current Whoop check through all configured channels. `--force` rewrites
   `data/outlook/whoop_check.state.json` (`sent_at`, `channels`): back it up before
   the test and restore it afterwards, otherwise the cron's reminder policy shifts.

No UDID registration or new profile is needed: App Store/TestFlight profiles are
not device-bound. Removing a device: `DELETE /v1/devices/{token}`, or delete the
app; Apple then answers 410 and the server drops the token on a later push.

## Server API contract

Base URL = `BIOS_API_BASE_URL` (Caddy on the VM strips the `/bios` prefix and
proxies to the `bios-api` service). All routes except `/health` require
`Authorization: Bearer <BIOS_API_SECRET>`. JSON only, request bodies at most 4 KB.
Errors: `{"ok": false, "error": "<message>"}` with 400 (bad JSON), 401 (secret),
413 (body too large) or 422 (invalid field).

| Route | Request | Response |
|---|---|---|
| `GET /health` | no auth | `{"ok": true}` |
| `POST /v1/devices` | `{"token": "<64..200 hex>", "environment": "production"\|"sandbox", "bundle_id": "at.bene.bios", "device_name"?: "...", "app_version"?: "1.0 (2)"}` | `{"ok": true}` (upsert) |
| `DELETE /v1/devices/{token}` | none | `{"ok": true, "removed": true\|false}` |
| `GET /v1/summary` | none | `{"whoop_check": {...}\|null, "outlook": {...}\|null, "generated_at": "<UTC ISO>"}` |

- `environment` follows the build: Release/TestFlight is signed with
  `aps-environment = production`, Debug with `development` (sent as `sandbox`).
- `bundle_id` must be `at.bene.bios`, otherwise 422.
- `whoop_check` and `outlook` are the JSON files the VM crons write
  (`data/outlook/whoop_check.json`, `data/outlook/outlook.json`); NaN becomes null.

## Notifications

The server sends `apns-push-type: alert`, `apns-priority: 10`, expiration 24 h,
topic `at.bene.bios` and `apns-collapse-id: <thread>-<tag>` (a reminder replaces
the earlier banner of the same kind). Payload:

```json
{
  "aps": {
    "alert": {"title": "🤒 <verdict>", "body": "<compact German text>"},
    "thread-id": "whoop",
    "category": "WHOOP_ALERT",
    "sound": "default"
  },
  "bios": {"tag": "face_with_thermometer", "kind": "whoop", "priority": "high"}
}
```

- The title emoji is derived from the ntfy tag the reports already use.
- `sound` is only set for high/warn priorities; everything else arrives silently.
- `thread-id` groups the notifications in the notification centre.

| Category | Thread | Sent by |
|---|---|---|
| `WHOOP_ALERT` | `whoop` | `reports.whoop_check --notify`: infection pattern, red recovery streak, sleep debt, reminders |
| `WHOOP_CLEAR` | `whoop` | `reports.whoop_check --notify`: all-clear after an episode |
| `OUTLOOK_ALERT` | `outlook` | `reports.outlook --notify`: changed virus, pollen and allergy alerts |
| `OUTLOOK_WEEKLY` | `outlook` | `reports.outlook --notify --force`: full weekly outlook (Sunday) |

Category identifiers must stay identical in `AppDelegate.swift` and on the server
(`reports/whoop_check.py`, `reports/outlook.py`). The ntfy and SMTP channels keep
running in parallel; one failing channel never blocks the others.

## Troubleshooting

- **TestFlight shows "Keine Builds verfügbar"** after a successful workflow 4:
  processing is still running (the first build took very long). The status
  "Bereit zur Übermittlung" is normal for internal testing. If it stays stuck:
  fill in the TestFlight "Testinformationen", then re-add the build (or yourself
  as tester) in group "Ich".
- **No push arrives:** check in this order: push status footer in the app
  (permission granted, token uploaded), token in `apns_tokens.json` with
  `environment: production`, APNs key and `BIOS_APNS_*` in the VM `.env`,
  `journalctl -u bios-api` and the cron log for `apns` warnings (successful
  deliveries are not logged, only failures). `BadDeviceToken`
  means a token/environment mismatch: the server retries the other environment
  once and corrects the entry.
- **Upload fails with 401/403** ("Server lehnt das Secret ab"): `BIOS_API_SECRET`
  in the repo secret and in the VM `.env` differ; fix it and rebuild (workflow 4).
- **"Server nicht konfiguriert" in the app:** `BIOS_API_BASE_URL` or
  `BIOS_API_SECRET` was empty at build time.
- **Workflow 4 fails at "Verify push entitlement":** the profile lacks the Push
  capability. Run 2, then 3, then 4.
- **Claude Code agents cannot start workflows:** the auto-mode permission
  classifier blocks agents from `gh workflow run` (especially "4. Build BIOS",
  treated as a production deploy), from editing the VM Caddyfile and from merging
  or pushing `main` here. Agents work on feature branches (e.g. `phase2-push`);
  the owner starts workflows, merges to `main` and applies Caddy changes by hand.
- **Certificate expiry or revocation:** the App Store distribution certificate is
  shared with Loop via `Match-Secrets` and expires **2027-08-03**. It is renewed
  on the Loop side (LoopWorkspace "Create Certificates"), never here. Careful: with
  `ENABLE_NUKE_CERTS` set in the Loop repo, Loop's workflow may revoke the shared
  certificate and create a new one. Installed TestFlight builds keep working, but
  the BIOS profile then points to a revoked certificate: run **workflow 3** here
  again (it creates a new profile for the new certificate), then workflow 4. If
  workflow 1 reports an invalid certificate, renew it via Loop first.
- **Apple agreement errors** ("required agreement"): accept the latest Apple
  Developer Program License Agreement at developer.apple.com, then rerun.
