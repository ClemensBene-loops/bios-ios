import Foundation
import os

/// One change of a day mark that still has to reach the server.
struct PendingEvent: Codable, Equatable, Sendable {
    let id: UUID
    let date: String
    let kind: String
    /// true = mark (POST), false = remove (DELETE).
    let add: Bool
    let queuedAt: Date
}

/// Context events (kind "alcohol") per day: server state from `/v1/events`,
/// optimistic local changes and an offline queue that is retried on the next
/// launch / foreground. Used by the Heute card, the calendar and the App Intent.
@MainActor
final class EventStore: ObservableObject {
    static let shared = EventStore()
    static let alcohol = "alcohol"

    enum Outcome: Equatable {
        /// Reached the server.
        case synced
        /// Saved locally, sent later (offline, server error).
        case queued
        /// Rejected (invalid day); the local change was undone.
        case failed(String)
    }

    /// Marked days ("YYYY-MM-DD") as the server knows them.
    @Published private(set) var confirmed: Set<String> = []
    /// Local changes not yet confirmed, oldest first.
    @Published private(set) var pending: [PendingEvent] = []
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    /// Short confirmation shown at the bottom of the screen.
    @Published private(set) var toast: String?

    private static let cacheKey = "events"
    private static let log = Logger(subsystem: "at.bene.bios", category: "events")
    private var toastTask: Task<Void, Never>?

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        if let cached = DiskCache.load(Self.cacheKey) {
            confirmed = Self.alcoholDays(cached.value)
            fetchedAt = cached.fetchedAt
        }
        pending = Self.loadPending()
    }

    // MARK: - State

    func isMarked(_ day: String) -> Bool {
        if let last = pending.last(where: { $0.date == day }) {
            return last.add
        }
        return confirmed.contains(day)
    }

    func isPending(_ day: String) -> Bool {
        pending.contains { $0.date == day }
    }

    var hasPending: Bool {
        !pending.isEmpty
    }

    /// Marked days (confirmed + pending) within the last `days` days.
    func markedCount(lastDays days: Int, now: Date = Date()) -> Int {
        let calendar = Calendar.current
        var count = 0
        for offset in 0..<max(1, days) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            if isMarked(Self.dayString(date)) { count += 1 }
        }
        return count
    }

    // MARK: - Changes

    /// Tap on a day: flips the mark optimistically and syncs in the background.
    func toggle(_ day: String) {
        let target = !isMarked(day)
        Task { @MainActor in
            let outcome = await self.set(day, marked: target)
            self.showToast(EventStore.message(for: outcome, day: day, marked: target))
        }
    }

    /// Sets the mark of `day` and tries to sync right away. Always queued first,
    /// so nothing is lost when the app is offline or the request fails.
    @discardableResult
    func set(_ day: String, marked: Bool) async -> Outcome {
        guard day <= Self.dayString(Date()) else {
            return .failed("Nur heute oder frühere Tage")
        }
        pending.removeAll { $0.date == day && $0.kind == Self.alcohol }
        // Always queue (POST and DELETE are idempotent), so an in-flight
        // request for the same day can never win over the newest tap.
        pending.append(PendingEvent(id: UUID(), date: day, kind: Self.alcohol, add: marked, queuedAt: Date()))
        savePending()
        return await flush()
    }

    /// Sends the queue in order. Stops at the first connection problem.
    @discardableResult
    func flush() async -> Outcome {
        if isSyncing { return .queued }
        guard !pending.isEmpty else { return .synced }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return .queued
        }
        isSyncing = true
        defer { isSyncing = false }
        while let event = pending.first {
            do {
                if event.add {
                    try await client.postEvent(date: event.date, kind: event.kind)
                    confirmed.insert(event.date)
                } else {
                    try await client.deleteEvent(date: event.date, kind: event.kind)
                    confirmed.remove(event.date)
                }
                pending.removeAll { $0.id == event.id }
                savePending()
                saveConfirmed()
            } catch {
                if Self.keepInQueue(error) {
                    lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                    Self.log.info("Event queued: \(error.localizedDescription, privacy: .public)")
                    return .queued
                }
                // Rejected by the server (400/422): drop it, the UI falls back to the server state.
                pending.removeAll { $0.id == event.id }
                savePending()
                lastError = error.localizedDescription
                Self.log.error("Event rejected: \(error.localizedDescription, privacy: .public)")
                return .failed(error.localizedDescription)
            }
        }
        lastError = nil
        return .synced
    }

    /// Loads the marked days of the last `days` days (calendar: 12 months).
    func refresh(days: Int = 400) async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            let json = try await client.fetchEvents(days: days)
            let now = Date()
            confirmed = Self.alcoholDays(json)
            fetchedAt = now
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: now)
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }

    /// Dashboard `events` block (read fresh by the server on every request):
    /// authoritative for the last 14 days including today. Pending local
    /// changes still win in `isMarked`.
    func seed(from events: DashboardEventsModel?) {
        guard let events else { return }
        let calendar = Calendar.current
        let now = Date()
        let today = Self.dayString(now)
        let yesterday = Self.dayString(calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        var updated = confirmed
        for offset in 0..<14 {
            if let date = calendar.date(byAdding: .day, value: -offset, to: now) {
                updated.remove(Self.dayString(date))
            }
        }
        for day in events.alcoholRecent {
            updated.insert(day)
        }
        confirmed = updated
        if let marked = events.todayMarked {
            if marked { confirmed.insert(today) } else { confirmed.remove(today) }
        }
        if let marked = events.yesterdayMarked {
            if marked { confirmed.insert(yesterday) } else { confirmed.remove(yesterday) }
        }
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled {
                self.toast = nil
            }
        }
    }

    // MARK: - Helpers

    /// Local calendar day "YYYY-MM-DD".
    nonisolated static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// "heute", "gestern" or "Mi 23.09.".
    nonisolated static func dayLabel(_ day: String) -> String {
        BIOSFormat.relativeDay(day)
    }

    nonisolated static func message(for outcome: Outcome, day: String, marked: Bool) -> String {
        let label = dayLabel(day)
        switch outcome {
        case .synced:
            return marked ? "Alkohol für \(label) eingetragen" : "Alkohol für \(label) entfernt"
        case .queued:
            return "Gespeichert, wird nachgereicht (keine Verbindung)"
        case .failed(let message):
            return "Nicht gespeichert: \(message)"
        }
    }

    /// Connection problems, server errors and auth/config problems stay queued;
    /// only a rejected request (400/422) is dropped.
    private static func keepInQueue(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .http(let status):
                return !(status == 400 || status == 422)
            case .invalidResponse, .notConfigured:
                return true
            }
        }
        return true
    }

    private static func alcoholDays(_ json: JSONValue) -> Set<String> {
        var days = Set<String>()
        for event in json.list("events") {
            guard (event.str("kind") ?? alcohol) == alcohol, let date = event.str("date") else { continue }
            days.insert(String(date.prefix(10)))
        }
        return days
    }

    private func saveConfirmed() {
        let events: [JSONValue] = confirmed.sorted().map { day in
            .object(["date": .string(day), "kind": .string(Self.alcohol)])
        }
        DiskCache.save(Self.cacheKey, value: .object(["events": .array(events)]), fetchedAt: fetchedAt ?? Date())
    }

    private static func pendingURL() -> URL? {
        DiskCache.directory()?.appendingPathComponent("events_pending.json")
    }

    private static func loadPending() -> [PendingEvent] {
        guard let url = pendingURL(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PendingEvent].self, from: data)) ?? []
    }

    private func savePending() {
        guard let url = Self.pendingURL() else { return }
        do {
            let data = try JSONEncoder().encode(pending)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("Pending events write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
