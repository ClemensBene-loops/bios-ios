import Foundation
import os

/// Loads `/v1/dashboard` and keeps the last good response on disk
/// (DiskCache key "dashboard"), so every tab shows the last state offline
/// with its "Stand".
@MainActor
final class DashboardStore: ObservableObject {
    static let shared = DashboardStore()

    @Published private(set) var dashboard: DashboardModel?
    /// When `dashboard` was fetched from the server (or loaded from the cache).
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?
    /// The last refresh failed because there is no connection.
    @Published private(set) var isOffline = false
    /// Set after a successful refresh, for "gerade aktualisiert".
    @Published private(set) var lastSuccess: Date?
    /// Built-in example data is shown (Debug builds without server config only).
    @Published private(set) var isSample = false

    private static let cacheKey = "dashboard"
    private static let log = Logger(subsystem: "at.bene.bios", category: "dashboard")
    private var lastAttempt: Date?
    /// Automatic refreshes (appear, becoming active) are skipped within this interval.
    private let minimumInterval: TimeInterval = 20

    init(loadCache: Bool = true) {
        if loadCache, let cached = DiskCache.load(Self.cacheKey) {
            dashboard = DashboardModel(json: cached.value)
            fetchedAt = cached.fetchedAt
        }
    }

    /// Whether data is shown that is not fresh from the server.
    var showsStaleData: Bool {
        dashboard != nil && lastError != nil
    }

    /// Fetches the dashboard. `force` ignores the short throttle (pull-to-refresh, push tap).
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            #if DEBUG
            loadSample()
            #endif
            return
        }
        isLoading = true
        lastAttempt = Date()
        do {
            let json = try await client.fetchDashboard()
            let now = Date()
            dashboard = DashboardModel(json: json)
            fetchedAt = now
            lastSuccess = now
            lastError = nil
            isOffline = false
            isSample = false
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: now)
        } catch {
            if !ErrorKind.isCancellation(error) {
                isOffline = ErrorKind.isOffline(error)
                lastError = isOffline ? "Keine Verbindung" : error.localizedDescription
                Self.log.error("Dashboard refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }

    #if DEBUG
    /// Invented example values (SampleData) for simulator runs without a server.
    private func loadSample() {
        guard dashboard == nil || isSample else { return }
        if let json = SampleData.dashboard() {
            dashboard = DashboardModel(json: json)
            fetchedAt = Date()
            isSample = true
        }
    }
    #endif
}
