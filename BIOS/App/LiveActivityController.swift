import ActivityKit
import Foundation
import os

// BIOS Live Activity, app side (the views live in the BIOSWidgets extension,
// the shared types in Shared/BIOSActivityAttributes.swift).
//
// - Tokens: the push-to-start token (iOS 17.2+) and the update token of every
//   running activity go to POST /v1/live-activity/token, so the server can
//   start the activity in the morning, update it (content-state) and end it
//   at night via APNs (topic at.bene.bios.push-type.liveactivity).
// - Fallback: when the app becomes active during the day and no activity is
//   running, a local one is started from the cached dashboard and the plan
//   stores; a running one is refreshed with the same local data.
// - Night (22 to 6 h): the app ends running activities and starts none.
// - Toggle "Live Activity" in Mehr (default on): off ends everything and tells
//   the server (enabled = false) to stop push-to-start.
// No `NSSupportsLiveActivitiesFrequentUpdates`: the content changes a few
// times a day (intake, score, temperature), well inside the normal APNs budget.

/// Body of `POST /v1/live-activity/token`.
struct LiveActivityTokenBody: Encodable, Sendable {
    /// "push_to_start" (starts new activities) or "update" (one running activity).
    let kind: String
    /// APNs token, lowercase hex.
    let token: String
    /// ActivityKit id of the activity (only for "update").
    let activityID: String?
    /// "sandbox" or "production" (see `AppConfig.apnsEnvironment`).
    let environment: String
    let bundleID: String
    /// `attributes-type` for push-to-start payloads.
    let attributesType: String
    /// false = the user switched the Live Activity off (no push-to-start).
    let enabled: Bool
    /// true = this activity has ended, its update token is void.
    let ended: Bool
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case kind
        case token
        case activityID = "activity_id"
        case environment
        case bundleID = "bundle_id"
        case attributesType = "attributes_type"
        case enabled
        case ended
        case appVersion = "app_version"
    }
}

extension APIClient {
    /// `POST /v1/live-activity/token`: registers a Live Activity push token.
    func registerLiveActivityToken(_ body: LiveActivityTokenBody) async throws {
        var request = makeRequest(path: ["v1", "live-activity", "token"], method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        _ = try await send(request)
    }
}

@MainActor
final class LiveActivityController: ObservableObject {
    static let shared = LiveActivityController()

    typealias BIOSActivity = Activity<BIOSActivityAttributes>

    /// Upload state of the tokens, for Mehr.
    enum TokenStatus: Equatable {
        case none
        case notConfigured
        case uploading
        case succeeded(Date)
        case failed(String)
    }

    /// User toggle in Mehr (default on).
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            Task { await self.enabledChanged() }
        }
    }
    /// Live Activities allowed in iOS settings (per app).
    @Published private(set) var systemEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var tokenStatus: TokenStatus = .none

    /// Evening hour from which activities end, morning hour from which they may start.
    static let nightStartHour = 22
    static let morningHour = 6

    private static let log = Logger(subsystem: "at.bene.bios", category: "liveactivity")
    private static let enabledKey = "bios.liveActivity.enabled"
    private static let snoozeKey = "bios.liveActivity.snooze"
    private static let attributesType = "BIOSActivityAttributes"

    private var observing = false
    private var observedActivities: Set<String> = []
    private var pushToStartToken: String?
    /// activity id -> update token
    private var activityTokens: [String: String] = [:]
    /// Uploads that succeeded ("kind|token|enabled|ended"), skipped on retry.
    private var uploaded: Set<String> = []

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Lifecycle

    /// Called once at launch (AppDelegate): observes push-to-start tokens,
    /// activities started by the server and the iOS permission.
    func startObserving() {
        guard !observing else { return }
        observing = true
        for activity in BIOSActivity.activities {
            observe(activity)
        }
        Task { @MainActor in
            for await activity in BIOSActivity.activityUpdates {
                self.observe(activity)
            }
        }
        Task { @MainActor in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                self.systemEnabled = enabled
            }
        }
        if #available(iOS 17.2, *) {
            Task { @MainActor in
                for await data in BIOSActivity.pushToStartTokenUpdates {
                    let token = Self.hex(data)
                    self.pushToStartToken = token
                    Self.log.info("Push-to-start token \(String(token.prefix(8)), privacy: .public)...")
                    await self.upload(kind: "push_to_start", token: token, activityID: nil)
                }
            }
        }
        refreshRunning()
    }

    /// App became active: end at night, else start (fallback) or refresh the
    /// running activity with local data; retry failed token uploads.
    func appBecameActive() async {
        systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        await retryUploads()
        guard isEnabled, !Self.isNight() else {
            await endAll()
            return
        }
        guard systemEnabled else { return }
        if runningActivities.isEmpty {
            start()
        } else {
            await updateRunning()
        }
    }

    /// Refreshes the running activities from the local stores (after an intake).
    func updateRunning() async {
        for activity in runningActivities {
            let state = localState(current: activity.content.state)
            await activity.update(ActivityContent(state: state, staleDate: Self.staleDate()))
        }
    }

    // MARK: - Snooze ("Später")

    func snooze(_ medicationID: String, minutes: Int) {
        var map = snoozeMap
        map[medicationID] = Date().addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: Self.snoozeKey)
    }

    func clearSnooze(_ medicationID: String) {
        var map = snoozeMap
        map[medicationID] = nil
        UserDefaults.standard.set(map, forKey: Self.snoozeKey)
    }

    private var snoozeMap: [String: Double] {
        let now = Date().timeIntervalSince1970
        let raw = UserDefaults.standard.dictionary(forKey: Self.snoozeKey) as? [String: Double] ?? [:]
        return raw.filter { $0.value > now }
    }

    // MARK: - Start / end

    private var runningActivities: [BIOSActivity] {
        BIOSActivity.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private func start() {
        let state = localState(current: nil)
        do {
            let activity = try BIOSActivity.request(
                attributes: BIOSActivityAttributes(),
                content: ActivityContent(state: state, staleDate: Self.staleDate()),
                pushType: .token
            )
            Self.log.info("Local Live Activity started \(activity.id, privacy: .public)")
            observe(activity)
        } catch {
            Self.log.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshRunning()
    }

    private func endAll() async {
        for activity in BIOSActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            await activityEnded(activity.id)
        }
        refreshRunning()
    }

    private func enabledChanged() async {
        if let token = pushToStartToken {
            await upload(kind: "push_to_start", token: token, activityID: nil)
        }
        if isEnabled {
            await appBecameActive()
        } else {
            await endAll()
        }
    }

    private func refreshRunning() {
        isRunning = !runningActivities.isEmpty
    }

    // MARK: - Tokens

    private func observe(_ activity: BIOSActivity) {
        let id = activity.id
        guard !observedActivities.contains(id) else { return }
        observedActivities.insert(id)
        Task { @MainActor in
            for await data in activity.pushTokenUpdates {
                let token = Self.hex(data)
                self.activityTokens[id] = token
                Self.log.info("Activity token \(String(token.prefix(8)), privacy: .public)... for \(id, privacy: .public)")
                await self.upload(kind: "update", token: token, activityID: id)
            }
        }
        Task { @MainActor in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await self.activityEnded(id)
                }
                self.refreshRunning()
            }
        }
        refreshRunning()
    }

    private func activityEnded(_ id: String) async {
        guard let token = activityTokens.removeValue(forKey: id) else { return }
        await upload(kind: "update", token: token, activityID: id, ended: true)
    }

    private func retryUploads() async {
        if let token = pushToStartToken {
            await upload(kind: "push_to_start", token: token, activityID: nil)
        }
        for (id, token) in activityTokens {
            await upload(kind: "update", token: token, activityID: id)
        }
    }

    private func upload(kind: String, token: String, activityID: String?, ended: Bool = false) async {
        let key = [kind, token, String(isEnabled), String(ended)].joined(separator: "|")
        if uploaded.contains(key) { return }
        guard let client = APIClient.fromConfig() else {
            tokenStatus = .notConfigured
            return
        }
        let body = LiveActivityTokenBody(
            kind: kind,
            token: token,
            activityID: activityID,
            environment: AppConfig.apnsEnvironment,
            bundleID: AppConfig.bundleID,
            attributesType: Self.attributesType,
            enabled: isEnabled,
            ended: ended,
            appVersion: AppConfig.versionString
        )
        tokenStatus = .uploading
        do {
            try await client.registerLiveActivityToken(body)
            uploaded.insert(key)
            tokenStatus = .succeeded(Date())
        } catch {
            if ErrorKind.isCancellation(error) { return }
            tokenStatus = .failed(error.localizedDescription)
            Self.log.error("Live Activity token upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Local content

    /// State from the cached dashboard and the plan stores. Fields the local
    /// data does not know keep the value of `current` (e.g. pushed by the server).
    func localState(current: BIOSActivityState?, now: Date = Date()) -> BIOSActivityState {
        var state = BIOSActivityState()
        let today = EventStore.dayString(now)
        let json = DiskCache.load("dashboard")?.value

        // Gesundheits-Score (dashboard `health`, optional).
        if let health = json?.obj("health") {
            state.healthScore = (health.double("score") ?? health.double("value")).map { Int($0.rounded()) }
            state.healthLevel = health.str("level") ?? health.str("level_text")
            var pillars: [String: Double] = [:]
            for pillar in health.list("pillars") {
                guard let key = pillar.str("key") ?? pillar.str("id"),
                      let score = pillar.double("score") ?? pillar.double("value") else { continue }
                pillars[BIOSActivityColors.pillarKey(key, label: pillar.str("label"))] = score
            }
            state.pillars = pillars.isEmpty ? nil : pillars
        }
        if state.healthScore == nil, let current {
            state.healthScore = current.healthScore
            state.healthLevel = current.healthLevel
            state.pillars = current.pillars
        }

        // Infection episode.
        let infection = json?.obj("infection").map { InfectionModel(json: $0) }
        let infectionActive = infection.map { $0.kind.lowercased().hasPrefix("infekt") && $0.status != .ok } ?? false
        if let infection {
            state.infectionScore = infection.score.map { Int($0.rounded()) }
            state.infectionDay = infection.episodeDay
        }

        // Temperature: newest of the local log and the dashboard `vitals`.
        var temperature: (value: Double, at: Date)?
        if let reading = VitalsStore.shared.latest(VitalReading.temperature), let value = reading.value,
           let at = BIOSDate.parse(reading.measuredAt.count == 16 ? reading.measuredAt + ":00" : reading.measuredAt) {
            temperature = (value, at)
        }
        if let last = json?.obj("vitals")?.obj("temperature_last"), let value = last.double("value"),
           let raw = last.str("measured_at"),
           let at = BIOSDate.parse(raw.count == 16 ? raw + ":00" : raw),
           at > (temperature?.at ?? .distantPast) {
            temperature = (value, at)
        }
        let temperatureActive: Bool
        if let temperature, now.timeIntervalSince(temperature.at) < 12 * 3600, temperature.value >= 37.5 {
            temperatureActive = true
            state.temperature = temperature.value
            state.temperatureTime = BIOSFormat.time(temperature.at)
            state.temperatureLabel = temperature.value >= 38.0 ? "Fieber" : "Erhöht"
        } else {
            temperatureActive = false
        }

        if infectionActive {
            state.mode = .infection
            state.status = infection?.status == .warn ? "warn" : "info"
        } else if temperatureActive {
            state.mode = .temperature
            state.status = "info"
        } else {
            state.mode = .normal
            state.status = "ok"
        }

        // Next intake of the medication plan (first time not yet covered).
        let plan = MedicationPlanStore.shared
        let items = plan.activeItems(on: today).filter { $0.serverID != nil }
        if items.isEmpty, let current {
            state.nextMedication = current.nextMedication
            state.nextMedicationID = current.nextMedicationID
            state.nextTime = current.nextTime
            state.nextLabel = current.nextLabel
        } else {
            let snoozed = snoozeMap
            var best: (time: String, item: MedicationPlanItem, later: Bool)?
            for item in items {
                let times = item.times.sorted()
                let taken = plan.taken(item, on: today)
                guard taken < times.count, let id = item.serverID else { continue }
                var time = times[taken]
                var later = false
                if let until = snoozed[id] {
                    time = BIOSFormat.time(Date(timeIntervalSince1970: until))
                    later = true
                }
                if best == nil || time < best!.time {
                    best = (time, item, later)
                }
            }
            if let best {
                state.nextMedication = best.item.name
                state.nextMedicationID = best.item.serverID
                state.nextTime = best.time
                state.nextLabel = best.later ? "Später" : nil
            }
        }

        // Supplements today.
        let supplements = SupplementStore.shared.takenCount(on: today)
        if supplements.total > 0 {
            state.supplementsTaken = supplements.taken
            state.supplementsTotal = supplements.total
        } else if let current {
            state.supplementsTaken = current.supplementsTaken
            state.supplementsTotal = current.supplementsTotal
        }

        state.updatedAt = now.timeIntervalSince1970
        return state
    }

    // MARK: - Helpers

    static func isNight(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= nightStartHour || hour < morningHour
    }

    /// Content is stale from 22:00 (the app or the server ends it then).
    static func staleDate(_ now: Date = Date()) -> Date? {
        Calendar.current.date(bySettingHour: nightStartHour, minute: 0, second: 0, of: now)
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// App implementation of the Live Activity buttons (Shared/LiveActivityIntents.swift).
enum LiveActivityActions {
    @MainActor
    static func taken(medicationID: String, name: String) async {
        _ = await LogIntentRunner.medication(id: medicationID, name: name)
        LiveActivityController.shared.clearSnooze(medicationID)
        await LiveActivityController.shared.updateRunning()
    }

    @MainActor
    static func later(medicationID: String, minutes: Int) async {
        LiveActivityController.shared.snooze(medicationID, minutes: minutes)
        await LiveActivityController.shared.updateRunning()
    }
}
