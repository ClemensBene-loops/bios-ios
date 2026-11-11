import Foundation
import os

/// One observable entry per request key: a chart card observes only its own
/// slot, so loading one series does not re-render every chart on the page
/// (that made long pages like Körper stutter while scrolling).
@MainActor
final class SeriesSlot: ObservableObject {
    @Published var entry: SeriesStore.Entry?
}

/// Loads `/v1/series` per (metric, days, source) with an in-memory table and
/// the disk cache, so charts show the last state offline. The store itself
/// publishes nothing; views read through `slot(_:)` (see SeriesReader).
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

    private var slots: [String: SeriesSlot] = [:]

    private var requests: [String: Request] = [:]
    private static let log = Logger(subsystem: "at.bene.bios", category: "series")
    /// A series younger than this is not refetched automatically.
    private let maxAge: TimeInterval = 5 * 60

    init() {}

    func entry(_ request: Request) -> Entry? {
        slots[request.key]?.entry
    }

    /// The observable slot of a request (created on first use).
    func slot(_ request: Request) -> SeriesSlot {
        if let slot = slots[request.key] { return slot }
        let slot = SeriesSlot()
        slots[request.key] = slot
        return slot
    }

    private func store(_ entry: Entry, _ request: Request) {
        slot(request).entry = entry
    }

    func load(_ request: Request, force: Bool = false) async {
        let key = request.key
        requests[key] = request
        var entry = self.entry(request) ?? Entry()
        if entry.isLoading { return }
        var fromDisk = false
        if entry.model == nil, let cached = DiskCache.load(key) {
            entry.model = SeriesModel(json: cached.value)
            entry.fetchedAt = cached.fetchedAt
            fromDisk = true
        }
        if !force, entry.model != nil, entry.error == nil, let fetched = entry.fetchedAt,
           Date().timeIntervalSince(fetched) < maxAge {
            // Fresh already: publish only what changed (a card re-appearing in a
            // lazy stack must not re-render for nothing).
            if fromDisk { store(entry, request) }
            return
        }
        guard let client = APIClient.fromConfig() else {
            #if DEBUG
            if entry.model == nil, let json = SampleData.series(metric: request.metric, days: request.days) {
                entry.model = SeriesModel(json: json)
                entry.fetchedAt = Date()
                store(entry, request)
                return
            }
            #endif
            entry.error = APIError.notConfigured.errorDescription
            store(entry, request)
            return
        }
        entry.isLoading = true
        store(entry, request)
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
        store(entry, request)
    }

    /// Reloads the shown series of some metrics (after an entry in the app).
    func reload(metrics: Set<String>) async {
        for request in requests.values where metrics.contains(request.metric) {
            await load(request, force: true)
        }
    }

    /// Pull-to-refresh: reloads every series that was shown in this session.
    func refreshLoaded() async {
        for request in requests.values {
            await load(request, force: true)
        }
    }
}
