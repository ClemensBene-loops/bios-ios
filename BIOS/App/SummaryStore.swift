import Foundation

/// Loads `/v1/summary` and keeps the last good response on disk
/// (Application Support/summary.json), so the app shows the latest state
/// offline with its "Stand".
@MainActor
final class SummaryStore: ObservableObject {
    static let shared = SummaryStore()

    @Published private(set) var summary: SummaryResponse?
    /// When `summary` was fetched from the server.
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?

    private var lastAttempt: Date?
    /// Automatic refreshes (appear, becoming active) are skipped within this interval.
    private let minimumInterval: TimeInterval = 20

    init(loadCache: Bool = true) {
        if loadCache {
            self.loadCache()
        }
    }

    /// Fetches the summary. `force` ignores the short throttle (pull-to-refresh, push tap).
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        guard let client = APIClient.fromConfig() else {
            lastError = "Server nicht konfiguriert"
            return
        }
        isLoading = true
        lastAttempt = Date()
        do {
            let result = try await client.fetchSummary()
            summary = result
            fetchedAt = Date()
            lastError = nil
            saveCache()
        } catch {
            if !Self.isCancellation(error) {
                lastError = error.localizedDescription
                Log.push.error("Summary refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    // MARK: - Disk cache

    private struct CachedSummary: Codable {
        let fetchedAt: Date
        let summary: SummaryResponse
    }

    private static func cacheURL() -> URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return directory.appendingPathComponent("summary.json")
    }

    private func loadCache() {
        guard let url = Self.cacheURL(),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedSummary.self, from: data) else {
            return
        }
        summary = cached.summary
        fetchedAt = cached.fetchedAt
    }

    private func saveCache() {
        guard let url = Self.cacheURL(), let summary, let fetchedAt else { return }
        do {
            let data = try JSONEncoder().encode(CachedSummary(fetchedAt: fetchedAt, summary: summary))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Log.push.error("Summary cache write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
