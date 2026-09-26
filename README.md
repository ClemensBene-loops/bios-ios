# BIOS iOS

SwiftUI app "BIOS" (iOS 17+) for the private BIOS health pipeline: a dark dashboard
with an infection check, glucose, insulin, recovery, blood pressure, viruses in
wastewater and pollen, plus native push notifications with the app's own name and
icon. The app stays "dumb": the server computes every tile, text and series, the
app only renders and caches them. Built and signed without a Mac, like the Loop
"Browser Build": GitHub Actions macOS runner + fastlane + App Store Connect API key
+ fastlane match, distributed via TestFlight.

The server side (API, APNs channel, cron jobs, analysis) lives in the private BIOS
repo (`api/server.py`, `api/dashboard.py`, `api/series.py`, `api/intake.py`,
`reports/notify.py`); see its `STATUS.md`, `CLAUDE.md` and the API contract
`docs/API_v1.md`.

| | |
|---|---|
| Display name | BIOS |
| App Store Connect record | BIOS Health |
| Bundle ID | `at.bene.bios`, widget extension `at.bene.bios.widgets` (Live Activity) |
| Team ID | `D457V2W8RG` (not a secret, also in `Config/Base.xcconfig`) |
| Minimum iOS | 17.0, iPhone only, portrait |
| Version | `MARKETING_VERSION` 2.0 (`project.yml`), build number = latest TestFlight build + 1 |
| GitHub | `ClemensBene-loops/bios-ios` (public, organization on the free plan) |

Status (2026-09-26): v2 lives on branch `v2-dashboard` (TestFlight builds `2.0 (3)`
and later: charts, infection score, blood pressure, quick log, Gesundheits-Score,
Live Activity, Körperkarte). `main` still holds v1 (build `1.0 (2)`, PR #1) until
`v2-dashboard` is merged.

This repo is **public**: no secrets, no server URL, no IPA and no personal health
data are ever committed or uploaded as workflow artifacts. Sample data in the code
is invented.

## What the app does

Four tabs (`TabView`), dark mode first, SF Symbols, colors always paired with a
symbol or text, Dynamic Type and VoiceOver labels, no third-party dependencies
(Swift Charts is Apple's).

- **Heute**: Gesundheits-Score card (see below), Körperkarte card, compact
  Infekt-Check (score, status pill, 7-day sparkline, temperature) and "Deine
  Routine". A server without the `health` block gets the build 5 layout: hero card
  with the infection score ring (0 to 100, server levels niedrig/mittel/hoch),
  status line ("Alles im Rahmen", "Frühzeichen", "Infektmuster Tag 3") and
  deviation chips of the day, plus the Körperkarte card and the quick status row.
  Below, in both layouts: outlook card and a tile grid (viruses Wien,
  pollen, glucose, recovery/sleep, insulin, Loop, blood pressure when there are
  readings). A tap on a tile opens its detail view with charts. "Stand" line at
  the bottom.
- **Körper**: Körperkarte on top (see below), then Whoop, glucose and insulin in
  detail, charts with the personal baseline band, 7/28 day switch shared with the
  detail screens.
- **Umwelt**: viruses in wastewater (Wien, Germany) with fine trend arrows, pollen
  forecast for the next 4 days, allergy block, season hints.
- **Mehr**: push status (permission, APNs registration, token upload, last push),
  "Test-Push senden", data freshness per source, server hints, alcohol calendar,
  version and push environment.
- **Charts** (Swift Charts): scrubbing with a dashed rule and the value, header
  numbers follow the selected range (mean over 7/28 days, "gestern" small), episode
  days as red dots, context days (glucose/insulin up) as indigo diamonds.
- **Offline**: `/v1/dashboard`, `/v1/bodymap` and every loaded series are cached as
  raw JSON in Application Support (`DiskCache`); offline the app shows the last
  state with a "wifi.slash" hint. Pull to refresh reloads the dashboard, the body
  map and the loaded series.
- **Push registration** (unchanged from v1): on every launch the app asks for
  permission, registers with APNs and uploads the token (`POST /v1/devices`) with
  retry and backoff; banners also show in the foreground.

### Gesundheits-Score

Dashboard block `health` (server `analysis/health_score.py`, contract in
`docs/API_v1.md` of the BIOS repo, section "Gesundheits-Score"). Six pillars with
server weights: Schlaf 20, Erholung 20, Stoffwechsel 20, Kreislauf 10, Abwehr 15,
Routine 15; missing pillars are renormalized, the total is `null` below half the
weight. The app renders only what the server sends: score, level word
(`sehr gut` >= 80, `gut` >= 65, `mittel` >= 50, `niedrig`), headline and subline,
`delta_week` as a pill ("+4 zur Vorwoche"), and per pillar score, trend and a
German reason (Kreislauf names its parts: resting HR level, training minutes,
blood pressure). Observation only; the score never hides a warning.

- **Heute card** (`HealthScoreCard`): ring 138 pt / line 11 pt with number and
  level word, delta pill, freshness line, pillar grid (3 columns). Tap opens the
  detail.
- **Detail** (`HealthDetailView`, route `gesundheit`): ring 130 pt / line 10 pt,
  pillar list with bars, trends and reasons, "keine Daten" for a missing pillar.
- **Live Activity**: the same ring on the lock screen (56 / 4.5) and in the
  Dynamic Island (44 / 3.5) from `pillars_mini`.

**Ring geometry.** One geometry for every ring, in `Shared/HealthRing.swift`
(compiled into app and widget extension, no copies per view): six equal arcs in
the server pillar order (`ORDER`: Schlaf, Erholung, Stoffwechsel, Kreislauf,
Abwehr, Routine), start at 12 o'clock, clockwise. `r` is the center line of the
stroke (`(size − lineWidth) / 2`), a fixed visible gap of 3 pt becomes the angle
`g = 3 pt / r`, and the round-cap overhang `c = (lineWidth / 2) / r` is taken off
both ends so every cap ends inside its own arc:

```
span     = 360° / 6
a0       = i · span + g/2 + c
a1       = (i + 1) · span − g/2 − c
fill_end = a0 + (a1 − a0) · score / 100
```

If `a1 <= a0` (small radius, thick line) the arc uses a butt cap over
`i · span + g/2 ... (i + 1) · span − g/2`. Every arc has a dim background track
from `a0` to `a1` and a fill proportional to the pillar score inside its own arc;
value 0 shows the track only, a missing pillar a grey dashed track. Checked
numerically for all four sizes in the design mockup: the smallest distance
between two drawn arcs including caps is 2.97 pt, so no two arcs touch (build 6
overlapped at the top between Routine and Schlaf).

### Körperkarte (body map)

A 2D outline figure (dark, thin cream line, front and back view) whose regions
light up by the current state; first cut without lab values. Data from
`GET /v1/bodymap` (server `analysis/bodymap.py`, `api/bodymap.py`), the Heute
card from the dashboard block `bodymap`. Observation, no diagnosis: no new alarm
rule, nothing is pushed.

- **Views**: `BodyMapSection` on top of the Körper tab (figure with a soft glow
  per status, symbol badge per region, Vorne/Hinten toggle, legend, "Stand"), the
  region list below the figure (sorted auffällig, beobachten, ok, keine Daten; the
  accessible alternative to the figure), `BodyMapRegionSheet` on tap (status with
  reason, values with delta or the server text, buttons to the existing detail
  screens, Dynamic Type), and `BodyMapTodayCard` on Heute under the
  Gesundheits-Score (mini figure, "n beobachten · n auffällig", top reason; tap
  opens the Körper tab). VoiceOver label per region, e.g. "Lunge, beobachten:
  Atemfrequenz erhöht".
- **Regions**: `kopf_schlaf`, `abwehr`, `lunge`, `herz`, `leber`, `stoffwechsel`,
  `niere`, `muskeln`, `knochen` (`niere`, `knochen` on the back). `leber`, `niere`
  and `knochen` are neutral ("noch keine Daten", until lab values or DEXA exist).
- **States**: `ok`, `beobachten`, `auffaellig`, `keine_daten`, always shown with
  symbol and word (`checkmark.circle`, `eye`, `exclamationmark.triangle`,
  `minus.circle`), never by color alone; keine Daten is grey and dashed.
  Thresholds, labels and reasons come from the server.
- **Tolerant decoding** (`BIOS/Models/BodyMapModels.swift`): an unknown or missing
  status becomes `keine_daten`, missing fields get defaults, duplicate region ids
  are dropped, unknown detail links are dropped, invalid or missing shapes and
  anchors fall back to the bundled layout. HTTP 404 (older server without the
  endpoint) shows "Körperkarte noch nicht verfügbar" instead of an error; offline
  the last cached map is shown (`BodyMapStore`, DiskCache key `bodymap`).
- **Layout**: normalized coordinates 0 to 1 in a box width:height = 0.5 (x from
  the viewer's left, the front view shows the left body side on the right). The
  constants in `BIOS/Views/BodyMap/BodyMapShapes.swift` (`BodyMapLayout`,
  `version = 1`) are identical to `docs/fixtures/bodymap_layout.json` in the BIOS
  repo (`analysis.bodymap.LAYOUT`, checked by its tests). The outline is drawn in
  the app (open polylines smoothed with uniform Catmull-Rom), region ellipses and
  badge anchors come from the server with the bundled layout as fallback. No image
  assets.
- **One place for changes**: colors, opacities, sizes and texts in
  `BIOS/Views/BodyMap/BodyMapStyle.swift`, geometry in `BodyMapShapes.swift`.

### Quick log ("+" on Heute)

The "+" button in the Heute toolbar opens a sheet with three entries:

- **Alkohol**: toggles for today and yesterday, a 12-month calendar to mark days
  retroactively (`POST/DELETE /v1/events`, kind `alcohol`). The server uses the marks
  to dampen the infection score on the following days.
- **Supplements**: tick single items or all at once for today, history calendar,
  edit the regimen (`GET/PUT /v1/supplements`, `POST/GET /v1/intake`). The regimen is
  stored only on the server; changes apply from today and the server keeps the history.
- **Medikamente**: plan rows as counters for Heute or Gestern ("+" logs one intake
  with `plan_item_id`, now for today, the next open plan time for yesterday, or an
  own time; "−" removes the latest intake of that item on that day with
  `DELETE /v1/medications/{id}`; a warning above `per_day`), plus free entries with
  time and optional dose (`POST/GET/DELETE /v1/medications`). The list below shows
  the selected day. After every add or delete the app reloads the list and the
  dashboard, so counter, list and Routine card agree. Log only, never dosing advice.

All three queue writes on disk when offline and send them later; the dashboard's
`events` and `intake` blocks reconcile the local state on every refresh.

### Siri and Shortcuts

App Intents in the main target (`BIOS/App/AlcoholIntents.swift`, no extension, no
entitlement). Phrases (German):

| Intent | Phrases |
|---|---|
| Alkohol eintragen (today, optional day parameter) | "Alkohol in BIOS", "BIOS heute Alkohol", "Alkohol in BIOS eintragen" |
| Alkohol gestern eintragen | "Gestern Alkohol in BIOS", "BIOS gestern Alkohol" |
| Supplements genommen (all active items today) | "Supplements genommen in BIOS", "BIOS Supplements genommen" |

Siri answers with a short German confirmation; without network the entry is queued
and sent when the app is online again.

### Deep links from a push

Every push carries `bios.tab` (`heute`, `umwelt`, `mehr`) and optionally
`bios.detail` (`infekt`, `viren`, `pollen`; reserved `blutdruck`). `Router.target`
resolves in this order: `bios.tab` (+ detail), `bios.detail` alone (its home tab),
the APNs `thread-id` (`whoop` -> Heute + Infekt-Check, `outlook` -> Umwelt,
`system` -> Mehr), the category prefix, else Heute. So older pushes without
`bios.tab` still land in the right place, and unknown values fall back instead of
failing. There is no URL scheme; deep links come only from pushes.

### Live Activity (lock screen, Dynamic Island)

Widget extension `BIOSWidgets` (`at.bene.bios.widgets`, iOS 17). Lock screen banner:
left the Gesundheits-Score ring (six pillar colors), right the current information
per mode (`normal`: next intake; `infection`: "Infekt · Tag n" + Infekt-Score;
`temperature`: value, time, "Erhöht"), bottom the supplements. Dynamic Island:
minimal = "b" mark with a status dot (the usual state next to Loop), compact =
mark + score, expanded with "Genommen" / "Später" (`LiveActivityIntent`, runs in
the app, logs the intake through the offline queue).

**Health ring.** The lock screen (56/4.5) and island (44/3.5) rings use the shared
geometry in `Shared/HealthRing.swift`, the same as the Heute hero (138/11) and the
score detail (130/10); see "Gesundheits-Score" above.

**Flow over a day.**

| When | Who | What |
| --- | --- | --- |
| App opens, nothing running | app | local start with `GET /v1/live-activity` (offline: cached dashboard + plan stores) |
| 06:30 | server cron `--start` | push-to-start (iOS 17.2+) to the `start` token |
| every hour at :22 | server cron | `update` push to every registered `update` token |
| 23:30 | server cron `--end` | `end` push, banner disappears |
| 23:30 to 06:30 | server | no updates (the banner keeps its last state) |

- **Nachtpause** (Mehr > Live Activity, default off): on = the app ends the banner
  from 23:30 to 06:30 and starts none; off = the app ends nothing at night and may
  start one locally at any time. The server side is the same either way.
- **8-hour limit:** iOS ends a Live Activity after at most 8 hours (then up to
  4 hours on the lock screen as ended). A push-started activity from 06:30 ends
  around 14:30; updates to its token go nowhere afterwards. Opening the app in the
  afternoon starts a new local one (and registers its new `update` token).
- **"Später"** is local only: the app moves the intake by 30 min in its own banner
  (UserDefaults, keyed by name); the server does not know it, so the next hourly
  push shows the plan time again until the snooze is re-applied when the app
  updates the banner.
- **Tokens:** `kind: start` = push-to-start token (one per device, sent while the
  toggle is on and iOS allows Live Activities, deleted when either is switched
  off); `kind: update` + `activity_id` = one per running activity (deleted when it
  ends). Both via `POST /v1/live-activity/token`, removal via
  `DELETE /v1/live-activity/token/{token}`.

**APNs contract.** `apns-push-type: liveactivity`, topic
`at.bene.bios.push-type.liveactivity`, push-to-start with
`attributes-type: BIOSActivityAttributes` and `attributes: {}`. Content-state keys
(`Shared/BIOSActivityAttributes.swift`, all optional and decoded leniently, no
`Date` fields because ActivityKit would read them as seconds since 2001):

| Key | Swift type | Meaning |
| --- | --- | --- |
| `health_score` | `Int?` | Gesundheits-Score 0 to 100 |
| `health_level` | `String?` | level word (fallback from the score: 80 / 65 / 50) |
| `pillars_mini` | `[Double?]?` | six pillar scores in ring order, null = no data |
| `mode` | `String` | `normal`, `infection`, `temperature` (unknown = normal) |
| `infection_score`, `infection_day` | `Int?` | Infekt-Score, day of the episode |
| `infection_kind` | `String?` | `infekt` or `infekt_frueh` |
| `temperature` | `Double?` | °C (>= 37.5 within 12 h) |
| `temperature_at` | `String?` | ISO time of the measurement |
| `temperature_high` | `Bool?` | at least 37.5 °C |
| `next_medication` | object? | `name`, `time` ("HH:MM"), `overdue`, `id` (plan item id) |
| `supplements` | object? | `taken`, `total` |
| `updated_at` | `String?` | ISO time of the data |

No decoding test target in this repo (a test target would touch the scheme that
workflow 4 archives); the BIOS repo checks the server's content state against these
keys in its contract test.

**Troubleshooting.**
- Banner never appears: Mehr > Live Activity shows the iOS permission ("In
  Einstellungen erlauben" opens the app settings), whether one is running and the
  token upload. Live Activities must be allowed for BIOS in iOS settings.
- No 06:30 start: push-to-start needs iOS 17.2+, the `start` token on the server
  (upload status in Mehr) and the app opened at least once since install/update.
  The server log shows the APNs answer per token (8 characters).
- Banner stuck on an old state in the afternoon: the 8-hour limit ended the
  push-started activity; open the app to start a local one.
- Banner gone at night: the server ended it at 23:30 (normal), or Nachtpause is on.
- Server side without sending anything: `python -m reports.live_activity --preview
  [--event start|end]` in the BIOS repo prints the payloads and their size.

## Repository layout

- `project.yml`: XcodeGen spec, the single source of truth for the Xcode project.
  `BIOS.xcodeproj` is generated on the runner (`xcodegen generate`) and not committed.
- `BIOS/App/`: `BIOSApp.swift`, `AppDelegate.swift` (permission, APNs registration,
  categories, token upload), `AppState.swift`, `Router.swift` (tabs, detail routes,
  push deep links), stores `DashboardStore`, `SeriesStore`, `EventStore`, `LogStores`
  (supplements, medications, offline queues), `BodyMapStore` (body map + cache),
  `AlcoholIntents.swift` (App Intents).
- `BIOS/Networking/`: `APIClient.swift` (+ `APIClient+Logs.swift`; Bearer auth, retry),
  `APIModels.swift`, `DiskCache.swift` (offline cache), `JSONValue+Access.swift`.
- `BIOS/Models/`: dashboard, series, score and blood pressure models (lenient
  decoding: fields optional, missing tiles are fine), `Formatting.swift` (German
  number and date formats), `SampleData.swift` (invented, `#if DEBUG`).
- `BIOS/Views/`: `RootView` (TabView), `Heute/` (hero, tiles), `KoerperView`,
  `UmweltView`, `MehrView`, `Details/`, `Charts/`, `BodyMap/` (`BodyMapShapes`
  layout and paths, `BodyMapStyle` colors and texts, `BodyMapView`), `QuickLogViews`,
  `AlcoholViews`, `BloodPressureViews`, `Theme`, `Components`.
- `BIOS/Config/AppConfig.swift`: reads the build-time config from Info.plist.
- `BIOSWidgets/`: widget extension (Live Activity views, `Info.plist`).
- `Shared/`: compiled into the app and the extension: `BIOSActivityAttributes`
  (content state, brand colors), `HealthRing` (pillar order and colors, ring
  geometry, ring view), Live Activity intents, `BrandAssets.xcassets`
  (mark `BIOSMark`).
- `BIOS/Assets.xcassets`: "Seed" app icon and `LaunchBackground` color (splash mark `BIOSMark` in `Shared/BrandAssets.xcassets`) (prepared from `docs/brand/bios-seed.png` by `tools/make_icon.py`, preview in `docs/icon-preview.png`; wordmark SVGs in `docs/brand`, drawn in code in `BIOS/Views/Brand.swift`).
- `Config/`: `Info.plist`, `BIOS.entitlements` (`aps-environment`), xcconfigs
  (`Base` = team + automatic signing for local builds, `Debug` = `APS_ENVIRONMENT=development`,
  `Release` = `production`, optional git-ignored `Local.xcconfig`).
- `fastlane/`: `Fastfile` (lanes below), `Matchfile`. `Gemfile` for fastlane.
- `.github/workflows/`: workflows 0 to 4.

## Build pipeline (no Mac)

Workflows 1 to 4 run only in `ClemensBene-loops` (never in forks) and use the same
org secrets. 2, 3 and 4 first run 1 as a job. 2 and 3 share a concurrency group, so
they never run in parallel.

| Workflow | Trigger | fastlane lane | What it touches at Apple |
|---|---|---|---|
| 0. Compile Check | every push to a branch other than `main` (not for `**.md`, `docs/**`, `tools/**`), or manual | none | Nothing. `xcodegen generate`, then `xcodebuild build` Release and Debug for the iOS Simulator without signing. No secrets; only the build log on failure (7 days). Errors and warnings land in the job summary. |
| 1. Validate Secrets | manual | `validate_secrets` | Nothing. Checks `GH_PAT`, that `Match-Secrets` exists and is private, the API key and that match decrypts; lists bundle ID, capabilities, app record and distribution certificates. |
| 2. Add Identifiers | manual | `identifiers` | Registers the App ID `at.bene.bios` if missing and enables the Push Notifications capability; registers `at.bene.bios.widgets` (no capability). Idempotent. |
| 3. Create Certificates | manual | `certs` | Creates the missing App Store provisioning profiles for `at.bene.bios` and `at.bene.bios.widgets` and stores them in `ClemensBene-loops/Match-Secrets`. **Reuses** the distribution certificate shared with Loop; never creates, renews or revokes certificates, no nuke logic. Fails if the App ID or Push is missing. |
| 4. Build BIOS | manual (any branch) and monthly schedule | `build` + `release` | Runner `macos-26`, Xcode 26.5 (falls back to the newest installed). Generates the project, injects the app config, sets build number = latest TestFlight build + 1, signs app and extension with their match profiles, verifies the IPA has `aps-environment = production` and an embedded, signed `BIOSWidgets.appex`, uploads to TestFlight (does not wait for processing). On failure only the build log is kept (7 days); the IPA is never uploaded as an artifact because it contains `BIOS_API_SECRET`. |

The App Store Connect app record ("BIOS Health") was created once by hand in
App Store Connect; workflow 4 needs it.

Order for a fresh setup: 1, 2, 3, create the app record, 4. For a normal new
build only 4 is needed.

### Compile check (Swift feedback without a Mac)

Swift is only compiled on the runner, there are no local previews. Every push to a
feature branch starts "0. Compile Check" automatically; iterate until it is green,
then start one build with workflow 4. Keep Swift conservative (iOS 17 APIs only,
Swift 5, optionals for every server field) and self-review before a build, so a
build rarely fails. Read results with `gh run list` and `gh run view --log-failed`.

### Monthly build and keepalive

TestFlight builds expire 90 days after upload; after that the app no longer
launches and no push arrives. Workflow 4 therefore also runs on schedule
`0 4 1 * *` (1st of the month, 04:00 UTC):

- Scheduled runs always build the default branch `main`, and the schedule only takes
  effect once the workflow file is on `main` (it arrives with the `v2-dashboard` merge).
- GitHub disables schedules in public repos after 60 days without repository
  activity. The workflow's `keepalive` job re-enables the workflow on every scheduled
  run (`gh api --method PUT .../actions/workflows/4_build_testflight.yml/enable`, as
  in Loop). If it was disabled anyway (Actions tab shows "This scheduled workflow is
  disabled"): Actions > "4. Build BIOS" > "Enable workflow", or
  `gh workflow enable 4_build_testflight.yml -R ClemensBene-loops/bios-ios`.
- On the iPhone: TestFlight > BIOS > "Automatische Updates" on, then new builds
  install by themselves.
- The distribution certificate is shared with Loop: if Loop renews it, run
  workflow 3 here again before the next build (see Troubleshooting).

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
  `BIOSAPISecret`). In git both keys are empty (also in the compile check). Without
  them the app still builds, but shows "Server nicht konfiguriert" and uploads no token.
- Rotating the secret: update the VM `.env`, restart `bios-api`, update the repo
  secret, run workflow 4, install the new build.
- The **APNs key** (`.p8`, developer portal > Keys, "Apple Push Notifications
  service") is a different key from `FASTLANE_KEY`. It lives only on the VM
  (referenced by `BIOS_APNS_KEY_ID`, `BIOS_APNS_TEAM_ID`, `BIOS_APNS_KEY_PATH`),
  never in GitHub. One key serves sandbox and production for all apps of the team.
  The browser may save the portal download as `AuthKey_<KEY_ID>.p8.txt`: rename it
  to `.p8` before copying it to the VM.

## TestFlight flow

1. Push the code to the branch to build and wait for a green "0. Compile Check".
   In the Actions tab open "4. Build BIOS" > "Run workflow" and pick that branch in
   the "Use workflow from" selector (feature branches build without merging to
   `main`; the build number is always latest TestFlight + 1).
2. App Store Connect processes the build (5 to 30+ minutes). "Keine Builds verfügbar"
   or the status "Bereit zur Übermittlung" in the meantime is normal.
   `ITSAppUsesNonExemptEncryption = false` in Info.plist skips the export compliance question.
3. TestFlight > internal group **"Ich"** gets the build (internal testing needs no
   beta review). Every tester must be an App Store Connect user of the team.
4. On the iPhone: TestFlight app > BIOS > Install. A new build only shows up
   as "Aktualisieren" (Update) in TestFlight after processing has finished; until
   then TestFlight still offers the previous build.
5. Builds expire after 90 days; the monthly scheduled build (see above) keeps a fresh
   one in TestFlight once it is on `main`.

## Registering a new device

1. The Apple ID on the iPhone must be an App Store Connect user of the team and a
   tester in the internal group "Ich" (App Store Connect > Users and Access, then
   TestFlight > Ich > Testers).
2. Install the TestFlight app, accept the invitation, install BIOS.
3. Open BIOS once and allow notifications. The app registers its APNs token at
   the server (`POST /v1/devices`) on every launch; Mehr > Mitteilungen shows
   whether the upload succeeded and how many devices the server knows.
4. Mehr > "Test-Push senden" (see below) confirms delivery end to end.

No UDID registration or new profile is needed: App Store/TestFlight profiles are
not device-bound. Removing a device: `DELETE /v1/devices/{token}`, or delete the
app; Apple then answers 410 and the server drops the token on a later push.

## Server API contract

The full contract (fields, types, errors, examples) is `docs/API_v1.md` in the
private BIOS repo, with invented example responses in `docs/fixtures/` there. This
README only lists what the app uses. Base URL = `BIOS_API_BASE_URL` (injected at
build time, never committed). All routes except `/health` require
`Authorization: Bearer <BIOS_API_SECRET>`. JSON only, request bodies at most 4 KB,
numbers are never NaN. Errors: `{"ok": false, "error": "<message>"}` with 400 (bad
JSON), 401 (secret), 404, 413 (body too large), 422 (invalid field), 429 (rate
limit) or 503.

| Route | Used for |
|---|---|
| `GET /health` | no auth, `{"ok": true}` |
| `POST /v1/devices`, `DELETE /v1/devices/{token}` | APNs token upload (unchanged from v1) |
| `GET /v1/summary` | v1 screen (build 2), kept unchanged on the server |
| `GET /v1/dashboard` | everything on Heute, Umwelt and Mehr: `health` (Gesundheits-Score), `infection` (hero, score, chips), `bodymap` (Heute card), `vitals`, `outlook`, `tiles`, `environment`, `freshness`, `push`, `events`, `intake`, `schema_version` |
| `GET /v1/bodymap` | Körperkarte: `regions[]` (`id`, `label`, `view`, `status`, `reason`, `neutral`, `anchor`, `shapes[]`, `metrics[]`, `links[]`), `statuses[]` legend, `summary`, `layout_version`, `aspect`; contract in `docs/API_v1.md` (BIOS repo), section "Körperkarte", example `docs/fixtures/bodymap.json` |
| `GET /v1/series?metric=...&days=...[&source=...]` | chart data: points, baseline band, reference lines, `flags`, `context_flags` |
| `POST/DELETE/GET /v1/events` | alcohol marks per day |
| `GET/PUT /v1/supplements`, `POST/GET /v1/intake` | supplement regimen and daily ticks |
| `POST/GET /v1/medications`, `DELETE /v1/medications/{id}` | medication log |
| `POST /v1/test-push` | test push to this device |
| `POST /v1/live-activity/token`, `DELETE /v1/live-activity/token/{token}`, `GET /v1/live-activity` | Live Activity push tokens (`start`, `update`) and the current content state |

Rules the app relies on:

- New fields may appear at any time without a `schema_version` bump; the app
  decodes leniently (optionals, unknown keys ignored, a missing tile shows
  "keine Daten"). `schema_version` only rises on incompatible changes.
- A tile with `evaluable: false` carries a ready German `reason`; the app shows it
  instead of numbers.
- The server delivers finished German texts (`headline`, `subline`, `display`,
  `reason`, ...) and color keys (`status`, `zone`, `level_rank`), never colors.
- Device `environment` follows the build: Release/TestFlight is signed with
  `aps-environment = production`, Debug with `development` (sent as `sandbox`).
  `bundle_id` must be `at.bene.bios`.

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
  "bios": {"tag": "face_with_thermometer", "kind": "whoop", "priority": "high",
           "tab": "heute", "detail": "infekt"}
}
```

- The title emoji is derived from the ntfy tag the reports already use.
- `sound` is only set for high/warn priorities; everything else arrives silently.
- `thread-id` groups the notifications in the notification centre.
- `bios.tab`/`bios.detail` drive the deep link (see above).

| Category | Thread | Opens | Sent by |
|---|---|---|---|
| `WHOOP_ALERT` | `whoop` | Heute > Infekt-Check | `reports.whoop_check --notify`: infection pattern, red recovery streak, sleep debt, reminders |
| `WHOOP_CLEAR` | `whoop` | Heute | `reports.whoop_check --notify`: all-clear after an episode |
| `OUTLOOK_ALERT` | `outlook` | Umwelt (> Viren or Pollen) | `reports.outlook --notify`: changed virus, pollen and allergy alerts |
| `OUTLOOK_WEEKLY` | `outlook` | Umwelt | `reports.outlook --notify --force`: full weekly outlook (Sunday) |
| `SYSTEM_ALERT` | `system` | Mehr | `reports.heartbeat` (pipeline warning and all-clear), test push |

Category identifiers must stay identical in `AppDelegate.swift` and on the server.
The ntfy and SMTP channels keep running in parallel on the server; one failing
channel never blocks the others.

### Test push

Mehr > "Test-Push senden" calls `POST /v1/test-push` with this device's token. The
server sends a short silent alert "BIOS Test-Push" via APNs only to this token
(thread `system`, tab Mehr), at most once per token per 60 s (429 otherwise; the app
does not retry automatically). No cron state is touched and ntfy/SMTP get nothing,
so this replaces backing up and restoring the server state files for manual tests.
The row shows whether Apple accepted the push, or the error; the server logs the
delivery.

## Troubleshooting

- **Compile check red:** open the run, the job summary lists errors and warnings;
  the full log is attached as `compile-check-log` for 7 days. Fix on the branch and
  push again (a newer push cancels the running check).
- **TestFlight shows "Keine Builds verfügbar"** after a successful workflow 4:
  processing is still running. The status "Bereit zur Übermittlung" is normal for
  internal testing. If it stays stuck: fill in the TestFlight "Testinformationen",
  then re-add the build (or yourself as tester) in group "Ich".
- **No push arrives:** first try Mehr > "Test-Push senden". Then check in this
  order: push status in Mehr (permission granted, token uploaded, device count > 0),
  token on the server with `environment: production`, APNs key and `BIOS_APNS_*` in
  the VM `.env`, then the logs: every accepted delivery is logged at INFO
  (`apns 1a2b3c4d...: 200 delivered`, tokens shortened to 8 characters) in
  `journalctl -u bios-api` (test push) and in the cron logs (reports).
  `BadDeviceToken` means a token/environment mismatch: the server retries the other
  environment once and corrects the entry.
- **A push opens the wrong tab:** check `bios.tab`/`bios.detail` in the payload;
  without them the app routes by `thread-id` and category (see Deep links).
- **Dashboard shows old data or "offline":** the server caches `/v1/dashboard` for
  60 s and series for 10 min, and the ingest runs hourly, so values are "Stand hh:mm",
  not real time. Mehr > Datenfrische shows the age per source.
- **Upload fails with 401/403** ("Server lehnt das Secret ab"): `BIOS_API_SECRET`
  in the repo secret and in the VM `.env` differ; fix it and rebuild (workflow 4).
- **"Server nicht konfiguriert" in the app:** `BIOS_API_BASE_URL` or
  `BIOS_API_SECRET` was empty at build time.
- **Workflow 4 fails at "Verify push entitlement":** the profile lacks the Push
  capability. Run 2, then 3, then 4.
- **Scheduled build did not run:** the schedule is only active on `main`, and GitHub
  may have disabled it (see Monthly build and keepalive).
- **Claude Code agents cannot start workflows:** the auto-mode permission
  classifier blocks agents from `gh workflow run` (especially "4. Build BIOS",
  treated as a production deploy), from editing the VM Caddyfile and from merging
  or pushing `main` here. Agents work on feature branches (e.g. `v2-dashboard`) and
  may read runs (`gh run list`, `gh run view --log-failed`); the owner starts
  workflow 4, merges to `main` and applies Caddy changes by hand.
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
