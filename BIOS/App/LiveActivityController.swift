import ActivityKit
import Foundation
import os

// BIOS Live Activity, app side (the views live in the BIOSWidgets extension,
// the shared types in Shared/BIOSActivityAttributes.swift). Server contract:
// docs/API_v1.md "Live Activity" in the BIOS repo.
//
// - Tokens: the push-to-start token (iOS 17.2+, kind "start") and the update
//   token of every running activity (kind "update" + activity_id) go to
//   POST /v1/live-activity/token; the server starts the activity at 06:30,
//   updates it hourly and ends it at 23:30 via APNs (topic
//   at.bene.bios.push-type.liveactivity). Toggle off or an ended activity:
//   DELETE /v1/live-activity/token/{token}.
// - Fallback: when the app becomes active during the day and no activity is
//   running, a local one is started with GET /v1/live-activity (the content
//   the next push would send), offline from the cached dashboard and the
//   plan stores. A running activity is refreshed the same way.
// - Night (23:30 to 6:30, same window as the server): only with the
//   "Nachtpause" toggle on (default off) the app ends running activities and
//   starts none. Off: the app ends nothing for the night and may start one
//   locally at any time; the server still sends no updates at night and ends
//   its activity at 23:30.
// No `NSSupportsLiveActivitiesFrequentUpdates`: the server updates at most
// every hour (at the latest every 90 min), well inside the normal APNs budget.

/// Body of `POST /v1/live-activity/token`.
struct LiveActivityTokenBody: Encodable, Sendable {
    /// APNs token, lowercase hex.
    let token: String
    /// "start" (push-to-start) or "update" (one running activity).
    let kind: String
    /// `activity.id` for "update", else nil (sent as null).
    let activityID: String?
    /// "sandbox" or "production" (see `AppConfig.apnsEnvironment`).
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token
        case kind
        case activityID = "activity_id"
        case environment
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token, forKey: .token)
        try container.encode(kind, forKey: .kind)
        try container.encode(activityID, forKey: .activityID)
        try container.encode(environment, forKey: .environment)
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

    /// `DELETE /v1/live-activity/token/{token}` (no error if unknown).
    func deleteLiveActivityToken(_ token: String) async throws {
        let request = makeRequest(path: ["v1", "live-activity", "token", token], method: "DELETE")
        _ = try await send(request)
    }

    /// `GET /v1/live-activity`: `content_state` as the next push would send it.
    func fetchLiveActivityState() async throws -> BIOSActivityState? {
        let json = try await getJSON(path: ["v1", "live-activity"])
        guard let state = json["content_state"], state.objectValue != nil else { return nil }
        let data = try JSONEncoder().encode(state)
        return try JSONDecoder().decode(BIOSActivityState.self, from: data)
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
    /// "Nachtpause" toggle in Mehr (default off): end and don't start at night.
    @Published var nightPauseEnabled: Bool {
        didSet {
            guard nightPauseEnabled != oldValue else { return }
            UserDefaults.standard.set(nightPauseEnabled, forKey: Self.nightPauseKey)
            guard isEnabled else { return }
            Task { await self.appBecameActive() }
        }
    }
    /// Live Activities allowed in iOS settings (per app).
    @Published private(set) var systemEnabled: Bool
    @Published private(set) var isRunning = false
    @Published private(set) var tokenStatus: TokenStatus = .none

    /// Night window in minutes of the day: from 23:30 (server `--end`) to 6:30
    /// (server `--start`).
    static let nightStartMinute = 23 * 60 + 30
    static let morningMinute = 6 * 60 + 30

    private static let log = Logger(subsystem: "at.bene.bios", category: "liveactivity")
    private static let enabledKey = "bios.liveActivity.enabled"
    private static let snoozeKey = "bios.liveActivity.snooze"
    private static let nightPauseKey = "bios.liveActivity.nightPause"

    private var observing = false
    private var observedActivities: Set<String> = []
    private var pushToStartToken: String?
    /// activity id -> update token
    private var activityTokens: [String: String] = [:]
    /// Requests that succeeded ("POST|kind|token", "DELETE|token"), skipped on retry.
    private var done: Set<String> = []

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        nightPauseEnabled = UserDefaults.standard.object(forKey: Self.nightPauseKey) as? Bool ?? false
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
                    await self.syncStartToken()
                }
            }
        }
        refreshRunning()
    }

    /// App became active: end during the night pause, else start (fallback)
    /// or refresh the running activity; retry failed token requests.
    func appBecameActive() async {
        systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        await retryTokens()
        guard isEnabled, !isInNightPause() else {
            await endAll()
            return
        }
        guard systemEnabled else { return }
        let state = await currentState(preferServer: true, fallback: runningActivities.first?.content.state)
        if runningActivities.isEmpty {
            start(with: state)
        } else {
            await update(with: state)
        }
    }

    /// Refreshes the running activities (after an intake or "Später").
    /// `preferServer`: ask GET /v1/live-activity first (the server already
    /// knows a synced intake), else build from the local stores.
    func updateRunning(preferServer: Bool = false) async {
        guard let current = runningActivities.first?.content.state else { return }
        let state = await currentState(preferServer: preferServer, fallback: current)
        await update(with: state)
    }

    // MARK: - Snooze ("Später", keyed by medication name)

    func snooze(_ name: String, minutes: Int) {
        var map = snoozeMap
        map[name.lowercased()] = Date().addingTimeInterval(TimeInterval(minutes * 60)).timeIntervalSince1970
        UserDefaults.standard.set(map, forKey: Self.snoozeKey)
    }

    func clearSnooze(_ name: String) {
        var map = snoozeMap
        map[name.lowercased()] = nil
        UserDefaults.standard.set(map, forKey: Self.snoozeKey)
    }

    private var snoozeMap: [String: Double] {
        let now = Date().timeIntervalSince1970
        let raw = UserDefaults.standard.dictionary(forKey: Self.snoozeKey) as? [String: Double] ?? [:]
        return raw.filter { $0.value > now }
    }

    // MARK: - Start / update / end

    private var runningActivities: [BIOSActivity] {
        BIOSActivity.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private func start(with state: BIOSActivityState) {
        do {
            let activity = try BIOSActivity.request(
                attributes: BIOSActivityAttributes(),
                content: content(state),
                pushType: .token
            )
            Self.log.info("Local Live Activity started \(activity.id, privacy: .public)")
            observe(activity)
        } catch {
            Self.log.error("Live Activity start failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshRunning()
    }

    private func update(with state: BIOSActivityState) async {
        for activity in runningActivities {
            await activity.update(content(state))
        }
    }

    private func endAll() async {
        for activity in BIOSActivity.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            await activityEnded(activity.id)
        }
        refreshRunning()
    }

    private func enabledChanged() async {
        await syncStartToken()
        if isEnabled {
            await appBecameActive()
        } else {
            await endAll()
        }
    }

    private func refreshRunning() {
        isRunning = !runningActivities.isEmpty
    }

    /// Same staleness and relevance as the server's pushes.
    private func content(_ state: BIOSActivityState) -> ActivityContent<BIOSActivityState> {
        let relevance: Double
        switch state.mode {
        case .infection: relevance = 100
        case .temperature: relevance = 90
        case .normal: relevance = 50
        }
        return ActivityContent(state: state, staleDate: Date().addingTimeInterval(2 * 3600), relevanceScore: relevance)
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
                await self.post(kind: "update", token: token, activityID: id)
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
        await delete(token)
    }

    /// Push-to-start token: registered while the toggle is on, removed when off.
    private func syncStartToken() async {
        guard let token = pushToStartToken else { return }
        if isEnabled {
            done.remove("DELETE|\(token)")
            await post(kind: "start", token: token, activityID: nil)
        } else {
            done.remove("POST|start|\(token)")
            await delete(token)
        }
    }

    private func retryTokens() async {
        await syncStartToken()
        for (id, token) in activityTokens {
            await post(kind: "update", token: token, activityID: id)
        }
    }

    private func post(kind: String, token: String, activityID: String?) async {
        let key = "POST|\(kind)|\(token)"
        if done.contains(key) { return }
        guard let client = APIClient.fromConfig() else {
            tokenStatus = .notConfigured
            return
        }
        let body = LiveActivityTokenBody(
            token: token, kind: kind, activityID: activityID, environment: AppConfig.apnsEnvironment
        )
        tokenStatus = .uploading
        do {
            try await client.registerLiveActivityToken(body)
            done.insert(key)
            tokenStatus = .succeeded(Date())
        } catch {
            if ErrorKind.isCancellation(error) { return }
            tokenStatus = .failed(error.localizedDescription)
            Self.log.error("Live Activity token upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func delete(_ token: String) async {
        let key = "DELETE|\(token)"
        if done.contains(key) { return }
        guard let client = APIClient.fromConfig() else { return }
        do {
            try await client.deleteLiveActivityToken(token)
            done.insert(key)
        } catch {
            Self.log.error("Live Activity token delete failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Content

    /// Server state (GET /v1/live-activity) or the local one, with the local
    /// "Später" and the plan item id applied.
    private func currentState(preferServer: Bool, fallback: BIOSActivityState?) async -> BIOSActivityState {
        var state: BIOSActivityState?
        if preferServer, let client = APIClient.fromConfig() {
            do {
                state = try await client.fetchLiveActivityState()
            } catch {
                if !ErrorKind.isCancellation(error) {
                    Self.log.info("GET /v1/live-activity failed, using local data: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        var result = state ?? localState(current: fallback)
        applyLocalOverlay(&result)
        return result
    }

    /// Plan item id for "Genommen" and a pending "Später" time.
    private func applyLocalOverlay(_ state: inout BIOSActivityState) {
        guard var next = state.nextMedication, let name = next.name else { return }
        let today = EventStore.dayString(Date())
        if next.id == nil {
            next.id = MedicationPlanStore.shared.activeItems(on: today)
                .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.serverID
        }
        if let until = snoozeMap[name.lowercased()] {
            next.time = BIOSFormat.time(Date(timeIntervalSince1970: until))
            next.later = true
            next.overdue = false
        }
        state.nextMedication = next
    }

    /// Offline: the same fields from the cached dashboard and the plan stores
    /// (rules as in the contract). Unknown fields keep `current`.
    func localState(current: BIOSActivityState?, now: Date = Date()) -> BIOSActivityState {
        var state = BIOSActivityState()
        let today = EventStore.dayString(now)
        let json = DiskCache.load("dashboard")?.value

        // Gesundheits-Score (dashboard `health`).
        if let health = json?.obj("health") {
            state.healthScore = (health.double("score") ?? health.double("value")).map { Int($0.rounded()) }
            state.healthLevel = health.str("level") ?? health.str("level_text")
            var pillars = [Double?](repeating: nil, count: HealthPillarPalette.pillars.count)
            for pillar in health.list("pillars") {
                guard let key = pillar.str("key") ?? pillar.str("id"),
                      let score = pillar.double("score") ?? pillar.double("value") else { continue }
                if let index = HealthPillarPalette.index(of: key, label: pillar.str("label")) {
                    pillars[index] = score
                }
            }
            state.pillarsMini = pillars.contains { $0 != nil } ? pillars : nil
            // Server list in ring order wins (`health.pillars_mini`).
            let mini = health.list("pillars_mini")
            if mini.count == HealthPillarPalette.pillars.count {
                state.pillarsMini = mini.map { $0.finiteNumber }
            }
        }
        if state.healthScore == nil, let current {
            state.healthScore = current.healthScore
            state.healthLevel = current.healthLevel
            state.pillarsMini = current.pillarsMini
        }

        // Infection: Whoop alarm infekt / infekt_frueh.
        let infection = json?.obj("infection").map { InfectionModel(json: $0) }
        let infectionKinds = ["infekt", "infekt_frueh"]
        var infectionActive = false
        if let infection {
            state.infectionScore = infection.score.map { Int($0.rounded()) }
            state.infectionDay = infection.episodeDay
            let kinds = [infection.kind] + infection.alerts.map(\.kind)
            if let kind = kinds.first(where: { infectionKinds.contains($0.lowercased()) }) {
                state.infectionKind = kind.lowercased()
                infectionActive = true
            }
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
        var temperatureHigh = false
        if let temperature, now.timeIntervalSince(temperature.at) < 24 * 3600 {
            state.temperature = temperature.value
            state.temperatureAt = Self.iso(temperature.at)
            temperatureHigh = temperature.value >= 37.5 && now.timeIntervalSince(temperature.at) < 12 * 3600
        }
        state.temperatureHigh = temperatureHigh

        if temperatureHigh {
            state.mode = .temperature
        } else if infectionActive {
            state.mode = .infection
        } else {
            state.mode = .normal
        }

        // Next intake: first open plan time today (per item the first `taken` times are done).
        let plan = MedicationPlanStore.shared
        let items = plan.activeItems(on: today)
        if items.isEmpty, let current {
            state.nextMedication = current.nextMedication
        } else {
            let clock = BIOSFormat.time(now)
            var best: (time: String, item: MedicationPlanItem)?
            for item in items {
                let times = item.times.sorted()
                let taken = plan.taken(item, on: today)
                guard taken < times.count else { continue }
                let time = times[taken]
                if best.map({ time < $0.time }) ?? true {
                    best = (time, item)
                }
            }
            if let best {
                state.nextMedication = BIOSActivityState.NextMedication(
                    name: best.item.name, time: best.time, overdue: best.time < clock, id: best.item.serverID
                )
            }
        }

        // Supplements today.
        let supplements = SupplementStore.shared.takenCount(on: today)
        if supplements.total > 0 {
            state.supplements = BIOSActivityState.Supplements(taken: supplements.taken, total: supplements.total)
        } else if let current {
            state.supplements = current.supplements
        }

        state.updatedAt = Self.iso(now)
        return state
    }

    // MARK: - Helpers

    /// Night pause toggle on and inside the night window.
    func isInNightPause(_ date: Date = Date()) -> Bool {
        nightPauseEnabled && Self.isNight(date)
    }

    static func isNight(_ date: Date = Date()) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minute >= nightStartMinute || minute < morningMinute
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}

/// App implementation of the Live Activity buttons (Shared/LiveActivityIntents.swift).
enum LiveActivityActions {
    /// "Genommen": one intake of the plan item (by id, else by name) through
    /// the offline-safe store, then the banner shows the next intake.
    @MainActor
    static func taken(medicationID: String?, name: String) async {
        let plan = MedicationPlanStore.shared
        if plan.allItems.isEmpty {
            await plan.refresh()
        }
        let active = plan.activeItems(on: EventStore.dayString(Date()))
        let item = active.first { medicationID != nil && $0.serverID == medicationID }
            ?? active.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard let item else {
            Logger(subsystem: "at.bene.bios", category: "liveactivity")
                .error("Genommen: no plan item for the banner's medication")
            return
        }
        let outcome = await plan.log(item)
        LiveActivityController.shared.clearSnooze(name)
        await LiveActivityController.shared.updateRunning(preferServer: outcome == .synced)
    }

    /// "Später": moves the shown intake by `minutes` (local only).
    @MainActor
    static func later(medicationID: String?, name: String, minutes: Int) async {
        LiveActivityController.shared.snooze(name, minutes: minutes)
        await LiveActivityController.shared.updateRunning()
    }
}
