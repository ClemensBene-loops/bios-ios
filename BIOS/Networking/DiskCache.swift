import Foundation
import os

/// One cached server response with the time it was fetched ("Stand").
struct CachedJSON: Codable, Sendable {
    let fetchedAt: Date
    let value: JSONValue
}

/// Generic offline cache: one JSON file per endpoint + parameters in
/// Application Support/cache. Raw JSON is cached (not the view models), so a
/// newer app version re-reads old caches with its own lenient parsing.
enum DiskCache {
    private static let log = Logger(subsystem: "at.bene.bios", category: "cache")

    static func directory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let directory = base.appendingPathComponent("cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Key -> safe file name ("series_whoop_rhr_28" -> "series_whoop_rhr_28.json").
    static func fileURL(for key: String) -> URL? {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let safe = String(key.map { allowed.contains($0) ? $0 : "_" }.prefix(120))
        return directory()?.appendingPathComponent(safe + ".json")
    }

    static func load(_ key: String) -> CachedJSON? {
        guard let url = fileURL(for: key),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CachedJSON.self, from: data)
    }

    static func save(_ key: String, value: JSONValue, fetchedAt: Date) {
        guard let url = fileURL(for: key) else { return }
        do {
            let data = try JSONEncoder().encode(CachedJSON(fetchedAt: fetchedAt, value: value))
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("Cache write failed for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
