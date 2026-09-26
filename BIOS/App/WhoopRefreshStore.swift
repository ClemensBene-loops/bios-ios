import Foundation
import os

/// Pull-to-refresh with a fresh Whoop pull (Heute, Körper).
///
/// `pullToRefresh` first asks the server for a Whoop pull (`POST /v1/refresh`,
/// rate-limited to one pull per 10 min, run by a minute cron), then reloads
/// dashboard, series and body map as before. While the pull is queued or
/// pending, a background task polls `GET /v1/refresh` every 8 s (at most 90 s)
/// until `last_pull` changes, then reloads everything once more with force.
/// Leaving the screen cancels the polling. Offline, errors or an older server
/// (404) fall back to the normal reload without any message.
@MainActor
final class WhoopRefreshStore: ObservableObject {
    static let shared = WhoopRefreshStore()

    enum Phase: Equatable {
        /// Pull requested, waiting for the server.
        case waiting
        /// A new pull arrived (time of `last_pull`).
        case updated(Date?)
        /// Last pull younger than the interval: nothing requested.
        case recent(last: Date?, next: Date?)
        /// Polling ended without a new pull.
        case unchanged(last: Date?)
    }

    @Published private(set) var phase: Phase?
    /// When `phase` was set; the status line hides old states.
    @Published private(set) var phaseAt: Date?

    private static let log = Logger(subsystem: "at.bene.bios", category: "whoop-refresh")
    private let pollInterval: UInt64 = 8
    private let pollLimit: TimeInterval = 90
    /// A status older than this is not shown any more.
    static let statusLifetime: TimeInterval = 10 * 60

    private var pollTask: Task<Void, Never>?
    private var pollOwner: String?

    init() {}

    /// Status text for the small line under the header, nil = show nothing.
    func statusText(now: Date = Date()) -> String? {
        guard let phase, let at = phaseAt, now.timeIntervalSince(at) < Self.statusLifetime else { return nil }
        switch phase {
        case .waiting:
            return "Whoop wird abgerufen …"
        case .updated(let last):
            return last.map { "Whoop aktualisiert \(Self.clock($0))" } ?? "Whoop aktualisiert"
        case .recent(let last, let next):
            var parts: [String] = []
            if let last { parts.append("Whoop zuletzt \(Self.clock(last))") }
            if let next, next > now { parts.append("nächster Abruf ab \(Self.clock(next))") }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        case .unchanged(let last):
            return last.map { "Whoop zuletzt \(Self.clock($0))" }
        }
    }

    var isWaiting: Bool { phase == .waiting }

    /// The refreshable action of Heute and Körper. `owner` names the screen,
    /// so only that screen's disappearance cancels the polling.
    func pullToRefresh(owner: String) async {
        let state = await requestPull()
        await WhoopRefreshStore.reloadAll()
        guard let state else { return }
        if state.isWaiting {
            startPolling(from: state, owner: owner)
        } else {
            cancelPolling()
            if state.reason == "recent" {
                setPhase(.recent(last: state.lastPull, next: state.nextAllowedAt))
            }
        }
    }

    /// Stops polling if `owner` started it (screen left).
    func cancel(owner: String) {
        guard pollOwner == owner else { return }
        cancelPolling()
        if phase == .waiting {
            phase = nil
            phaseAt = nil
        }
    }

    /// Dashboard, loaded series and body map, all forced.
    static func reloadAll() async {
        await DashboardStore.shared.refresh(force: true)
        await SeriesStore.shared.refreshLoaded()
        await BodyMapStore.shared.refresh(force: true)
    }

    // MARK: - Internals

    private func requestPull() async -> WhoopRefreshState? {
        guard let client = APIClient.fromConfig() else { return nil }
        do {
            return try await client.requestWhoopRefresh()
        } catch {
            if !ErrorKind.isCancellation(error) {
                Self.log.info("Whoop refresh request failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
    }

    private func startPolling(from start: WhoopRefreshState, owner: String) {
        cancelPolling()
        pollOwner = owner
        setPhase(.waiting)
        let interval = pollInterval
        let deadline = Date().addingTimeInterval(pollLimit)
        pollTask = Task { [weak self] in
            var latest = start
            while Date() < deadline {
                do {
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                } catch {
                    return
                }
                if Task.isCancelled { return }
                guard let client = APIClient.fromConfig() else { break }
                guard let state = try? await client.fetchWhoopRefreshState() else {
                    if Task.isCancelled { return }
                    continue
                }
                if Task.isCancelled { return }
                if state.lastPull != nil || latest.lastPull == nil { latest = state }
                if start.hasNewerPull(state) {
                    await WhoopRefreshStore.reloadAll()
                    guard let self, !Task.isCancelled else { return }
                    self.finishPolling(.updated(state.lastPull))
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.finishPolling(.unchanged(last: latest.lastPull))
        }
    }

    private func finishPolling(_ phase: Phase) {
        pollTask = nil
        pollOwner = nil
        setPhase(phase)
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
        pollOwner = nil
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        phaseAt = Date()
    }

    private static func clock(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? BIOSFormat.time(date) : BIOSFormat.relative(date)
    }
}
