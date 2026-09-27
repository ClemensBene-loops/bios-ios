import Foundation
import os

/// Loads `GET /v1/bodymap` (one store per layer and demo flag) and keeps the
/// last good response on disk, like the dashboard: the Körper tab shows the
/// last state offline with its "Stand". A server without the endpoint (HTTP
/// 404), or without the requested layer (answers another `layer`), is not an
/// error: the map says "noch nicht verfügbar".
///
/// `shared` is the systems layer (DiskCache key "bodymap", as before), used by
/// the Heute card. Other layers: `BodyMapStore.store(layer:demo:)`, cache key
/// "bodymap_<layer>" plus "_demo", so example data never replaces real data.
@MainActor
final class BodyMapStore: ObservableObject {
    static let shared = BodyMapStore()

    /// Stores of the other layers, created on first use.
    private static var others: [String: BodyMapStore] = [:]

    /// Store of `layer` (systems without demo = `shared`). Demo only for
    /// layers other than systems.
    static func store(layer: String, demo: Bool) -> BodyMapStore {
        let isSystems = layer == BodyMapLayerOption.systemsID
        if isSystems {
            return shared
        }
        let key = cacheKey(layer: layer, demo: demo)
        if let store = others[key] {
            return store
        }
        let store = BodyMapStore(layer: layer, demo: demo)
        others[key] = store
        return store
    }

    /// Pull-to-refresh: the systems map and every other layer loaded so far.
    static func refreshAll(force: Bool) async {
        await shared.refresh(force: force)
        for store in others.values {
            await store.refresh(force: force)
        }
    }

    static func cacheKey(layer: String, demo: Bool) -> String {
        if layer == BodyMapLayerOption.systemsID && !demo {
            return "bodymap"
        }
        return "bodymap_" + layer + (demo ? "_demo" : "")
    }

    let layer: String
    let demo: Bool

    @Published private(set) var model: BodyMapModel?
    /// When `model` was fetched from the server (or loaded from the cache).
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?
    @Published private(set) var isOffline = false
    /// The server answered 404, or does not know this layer yet (older server).
    @Published private(set) var isUnavailable = false

    private static let log = Logger(subsystem: "at.bene.bios", category: "bodymap")
    private let cacheKey: String
    private var lastAttempt: Date?
    /// Automatic refreshes (appear, becoming active) are skipped within this interval.
    private let minimumInterval: TimeInterval = 20

    init(layer: String = BodyMapLayerOption.systemsID, demo: Bool = false, loadCache: Bool = true) {
        self.layer = layer
        self.demo = demo
        cacheKey = Self.cacheKey(layer: layer, demo: demo)
        if loadCache, let cached = DiskCache.load(cacheKey) {
            model = BodyMapModel(json: cached.value)
            fetchedAt = cached.fetchedAt
        }
    }

    var isSystems: Bool {
        layer == BodyMapLayerOption.systemsID
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
            let json = try await client.fetchBodymap(layer: isSystems ? nil : layer, demo: demo)
            let now = Date()
            let fetched = BodyMapModel(json: json)
            if !isSystems && fetched.layer != layer {
                // An older server ignores `layer` and answers the systems map.
                isUnavailable = true
                isOffline = false
                lastError = BodyMapStyle.unavailableTitle
                model = nil
            } else {
                model = fetched
                fetchedAt = now
                lastError = nil
                isOffline = false
                isUnavailable = false
                DiskCache.save(cacheKey, value: json, fetchedAt: now)
            }
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
                Self.log.error("Body map refresh failed (\(self.layer, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }
}
