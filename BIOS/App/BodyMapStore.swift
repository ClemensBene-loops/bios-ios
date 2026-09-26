import Foundation
import os

/// Loads `GET /v1/bodymap` and keeps the last good response on disk
/// (DiskCache key "bodymap"), like the dashboard: the Körper tab shows the last
/// state offline with its "Stand". A server without the endpoint (HTTP 404)
/// is not an error: the map says "noch nicht verfügbar".
@MainActor
final class BodyMapStore: ObservableObject {
    static let shared = BodyMapStore()

    @Published private(set) var model: BodyMapModel?
    /// When `model` was fetched from the server (or loaded from the cache).
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?
    @Published private(set) var isOffline = false
    /// The server answered 404: endpoint not deployed (older server).
    @Published private(set) var isUnavailable = false

    private static let cacheKey = "bodymap"
    private static let log = Logger(subsystem: "at.bene.bios", category: "bodymap")
    private var lastAttempt: Date?
    /// Automatic refreshes (appear, becoming active) are skipped within this interval.
    private let minimumInterval: TimeInterval = 20

    init(loadCache: Bool = true) {
        if loadCache, let cached = DiskCache.load(Self.cacheKey) {
            model = BodyMapModel(json: cached.value)
            fetchedAt = cached.fetchedAt
        }
    }

    /// Whether data is shown that is not fresh from the server.
    var showsStaleData: Bool {
        model != nil && lastError != nil
    }

    /// Fetches the map. `force` ignores the short throttle (pull-to-refresh).
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
            let json = try await client.fetchBodymap()
            let now = Date()
            model = BodyMapModel(json: json)
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
                    lastError = BodyMapStyle.unavailableTitle
                } else {
                    isOffline = ErrorKind.isOffline(error)
                    lastError = isOffline ? "Keine Verbindung" : error.localizedDescription
                }
                Self.log.error("Body map refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }
}
