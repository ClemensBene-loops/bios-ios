import Foundation
import os

/// Loads `/v1/series` per (metric, days, source) with an in-memory table and
/// the disk cache, so charts show the last state offline.
@MainActor
final class SeriesStore: ObservableObject {
    static let shared = SeriesStore()

    struct Request: Hashable {
        let metric: String
        let days: Int
        let source: String?

        var key: String {
            "series_\(metric)_\(days)" + (source.map { "_\($0)" } ?? "")
        }
    }

    struct Entry {
        var model: SeriesModel?
        var fetchedAt: Date?
        var isLoading = false
        var error: String?
    }

    @Published private(set) var entries: [String: Entry] = [:]

    private var requests: [String: Request] = [:]
    private static let log = Logger(subsystem: "at.bene.bios", category: "series")
    /// A series younger than this is not refetched automatically.
    private let maxAge: TimeInterval = 5 * 60

    init() {}

    func entry(_ request: Request) -> Entry? {
        entries[request.key]
    }

    func load(_ request: Request, force: Bool = false) async {
        let key = request.key
        requests[key] = request
        var entry = entries[key] ?? Entry()
        if entry.isLoading { return }
        if entry.model == nil, let cached = DiskCache.load(key) {
            entry.model = SeriesModel(json: cached.value)
            entry.fetchedAt = cached.fetchedAt
        }
        if !force, entry.model != nil, entry.error == nil, let fetched = entry.fetchedAt,
           Date().timeIntervalSince(fetched) < maxAge {
            entries[key] = entry
            return
        }
        guard let client = APIClient.fromConfig() else {
            #if DEBUG
            if entry.model == nil, let json = SampleData.series(metric: request.metric, days: request.days) {
                entry.model = SeriesModel(json: json)
                entry.fetchedAt = Date()
                entries[key] = entry
                return
            }
            #endif
            entry.error = APIError.notConfigured.errorDescription
            entries[key] = entry
            return
        }
        entry.isLoading = true
        entries[key] = entry
        do {
            let json = try await client.fetchSeries(metric: request.metric, days: request.days, source: request.source)
            let now = Date()
            entry.model = SeriesModel(json: json)
            entry.fetchedAt = now
            entry.error = nil
            DiskCache.save(key, value: json, fetchedAt: now)
        } catch {
            if !ErrorKind.isCancellation(error) {
                entry.error = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                Self.log.error("Series \(key, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        entry.isLoading = false
        entries[key] = entry
    }

    /// Pull-to-refresh: reloads every series that was shown in this session.
    func refreshLoaded() async {
        for request in requests.values {
            await load(request, force: true)
        }
    }
}
