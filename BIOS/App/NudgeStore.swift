import Foundation
import os
import UIKit

/// Loads `GET /v1/nudge` for Mehr > "Bewegungs-Stupser" and writes the settings
/// (`PATCH /v1/nudge/settings`). The last good answer is kept on disk (DiskCache
/// key "nudge"), like the dashboard. A server without the endpoint (HTTP 404) is
/// not an error: the section says "Server kennt Stupser noch nicht".
@MainActor
final class NudgeStore: ObservableObject {
    static let shared = NudgeStore()

    @Published private(set) var model: NudgeModel?
    /// Settings shown in the UI; set at once on a change, reverted if the server rejects it.
    @Published private(set) var settings: NudgeSettings = .standard
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?
    /// Message of the last failed settings change; nil after a successful one.
    @Published private(set) var saveError: String?
    @Published private(set) var isOffline = false
    /// The server answered 404 (older server without nudges).
    @Published private(set) var isUnavailable = false

    private static let log = Logger(subsystem: "at.bene.bios", category: "nudge")
    static let cacheKey = "nudge"
    private var lastAttempt: Date?
    private let minimumInterval: TimeInterval = 20

    init(loadCache: Bool = true) {
        if loadCache, let cached = DiskCache.load(Self.cacheKey) {
            let model = NudgeModel(json: cached.value)
            self.model = model
            settings = model.settings
            fetchedAt = cached.fetchedAt
        }
    }

    /// Cached data is shown although the last refresh failed.
    var showsStaleData: Bool {
        model != nil && lastError != nil
    }

    /// Fetches the nudge state. `force` ignores the short throttle.
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return
        }
        isLoading = true
        lastAttempt = Date()
        do {
            let json = try await client.fetchNudge()
            let now = Date()
            let fetched = NudgeModel(json: json)
            model = fetched
            if !isSaving {
                settings = fetched.settings
            }
            fetchedAt = now
            lastError = nil
            isOffline = false
            isUnavailable = false
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: now)
        } catch {
            if !ErrorKind.isCancellation(error) {
                if let apiError = error as? APIError, apiError == .http(404) {
                    isUnavailable = true
                    isOffline = false
                    lastError = "Server kennt Stupser noch nicht"
                } else {
                    isOffline = ErrorKind.isOffline(error)
                    lastError = isOffline ? "Keine Verbindung" : error.localizedDescription
                }
                Self.log.error("Nudge refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }

    // MARK: - Settings

    func setEnabled(_ enabled: Bool) async {
        var next = settings
        next.enabled = enabled
        await save(["enabled": .bool(enabled)], optimistic: next)
    }

    func setTone(_ tone: String) async {
        var next = settings
        next.tone = tone
        await save(["tone": .string(tone)], optimistic: next)
    }

    /// Sends both ends of the window, so the server always checks the full pair.
    func setHours(start: String, end: String) async {
        var next = settings
        next.start = start
        next.end = end
        await save(["hours": .object(["start": .string(start), "end": .string(end)])], optimistic: next)
    }

    func setMaxPerDay(_ value: Int) async {
        var next = settings
        next.maxPerDay = value
        await save(["max_per_day": .number(Double(value))], optimistic: next)
    }

    /// Safety margin (`guard`: "streng", "mittel", "locker").
    func setSafety(_ value: String) async {
        var next = settings
        next.safety = value
        await save(["guard": .string(value)], optimistic: next)
    }

    private func save(_ patch: [String: JSONValue], optimistic: NudgeSettings) async {
        guard optimistic != settings, !isSaving else { return }
        guard let client = APIClient.fromConfig() else {
            saveError = APIError.notConfigured.errorDescription
            return
        }
        let previous = settings
        settings = optimistic
        isSaving = true
        saveError = nil
        do {
            let result = try await client.patchNudgeSettings(.object(patch))
            if result.isSuccess {
                if let saved = result.json?.obj("settings") {
                    settings = NudgeSettings(json: saved)
                }
            } else if result.status == 404 {
                settings = previous
                isUnavailable = true
                saveError = "Server kennt Stupser noch nicht"
            } else {
                settings = previous
                saveError = result.errorText
            }
        } catch {
            settings = previous
            if !ErrorKind.isCancellation(error) {
                saveError = ErrorKind.isOffline(error)
                    ? "Keine Verbindung, nicht gespeichert"
                    : "Nicht gespeichert: " + error.localizedDescription
                Self.log.error("Nudge settings failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isSaving = false
        // Today's budget depends on max_per_day: reload the whole state.
        await refresh(force: true)
    }
}

// MARK: - Notification buttons

/// Buttons of the `MOVE_NUDGE` notification (identifiers registered in AppDelegate).
enum NudgeAction: String, Codable, Sendable {
    case done
    case snooze
    case offToday = "off_today"

    static let categoryID = "MOVE_NUDGE"
    static let doneID = "NUDGE_DONE"
    static let snoozeID = "NUDGE_SNOOZE"
    static let offTodayID = "NUDGE_OFF_TODAY"

    /// Action from a `UNNotificationResponse.actionIdentifier`, nil for a tap or dismiss.
    init?(actionIdentifier: String) {
        switch actionIdentifier {
        case Self.doneID: self = .done
        case Self.snoozeID: self = .snooze
        case Self.offTodayID: self = .offToday
        default: return nil
        }
    }
}

/// Sends the answer of a notification button to `POST /v1/nudge/action`.
/// Runs inside a UIKit background task, so it finishes from the lock screen or
/// the Apple Watch without opening the app. 404/422 (unknown or old nudge) are
/// accepted as done; offline or 5xx answers go into a small queue in
/// UserDefaults that is retried when the app becomes active (entries older
/// than 12 h are dropped: "Später" and "Heute nicht" only matter today).
enum NudgeActionQueue {
    struct Item: Codable, Equatable {
        let id: String
        let action: NudgeAction
        let at: Date
    }

    private static let log = Logger(subsystem: "at.bene.bios", category: "nudge")
    private static let defaultsKey = "nudge_action_queue"
    private static let maxAge: TimeInterval = 12 * 60 * 60

    /// Notification button pressed: send now, queue on failure, then `completion`.
    @MainActor
    static func handle(id: String, action: NudgeAction, completion: @escaping @Sendable () -> Void) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            log.error("Nudge action without nudge_id ignored")
            completion()
            return
        }
        let background = BackgroundTaskToken.begin(name: "nudge-action")
        Task { @MainActor in
            let sent = await send(Item(id: trimmed, action: action, at: Date()))
            if !sent {
                enqueue(Item(id: trimmed, action: action, at: Date()))
            }
            completion()
            background.end()
        }
    }

    /// Retries queued answers (app became active).
    @MainActor
    static func flush() async {
        let queued = load()
        guard !queued.isEmpty else { return }
        let now = Date()
        var rest: [Item] = []
        for item in queued where now.timeIntervalSince(item.at) < maxAge {
            if !(await send(item)) {
                rest.append(item)
            }
        }
        store(rest)
        if rest.count < queued.count, NudgeStore.shared.model != nil {
            await NudgeStore.shared.refresh(force: true)
        }
    }

    /// true = the server took it (or knows it no more: 404/422), false = retry later.
    @MainActor
    private static func send(_ item: Item) async -> Bool {
        guard let client = APIClient.fromConfig() else {
            log.info("Server not configured, nudge action dropped")
            return true
        }
        do {
            let result = try await client.postNudgeAction(id: item.id, action: item.action.rawValue)
            if result.isSuccess {
                log.info("Nudge action \(item.action.rawValue, privacy: .public) sent")
                return true
            }
            log.error("Nudge action \(item.action.rawValue, privacy: .public) answered HTTP \(result.status)")
            // 404 unknown id, 422 invalid: retrying cannot help.
            return result.status != 401 && result.status != 403
        } catch {
            log.error("Nudge action failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static func enqueue(_ item: Item) {
        var items = load().filter { !($0.id == item.id && $0.action == item.action) }
        items.append(item)
        store(Array(items.suffix(20)))
    }

    private static func load() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    private static func store(_ items: [Item]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// A UIKit background task that is ended exactly once (by the work or by expiry).
@MainActor
final class BackgroundTaskToken {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    static func begin(name: String) -> BackgroundTaskToken {
        let token = BackgroundTaskToken()
        token.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak token] in
            MainActor.assumeIsolated {
                token?.end()
            }
        }
        return token
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
