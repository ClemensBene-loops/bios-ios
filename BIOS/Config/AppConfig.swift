import Foundation

/// Build-time configuration read from Info.plist.
///
/// `BIOSAPIBaseURL` and `BIOSAPISecret` are empty in git and filled by the
/// build workflow from the GitHub secrets `BIOS_API_BASE_URL` and
/// `BIOS_API_SECRET`. Both may be missing; callers must handle `nil`.
enum AppConfig {
    static var apiBaseURL: URL? {
        infoString("BIOSAPIBaseURL").flatMap { URL(string: $0) }
    }

    static var apiSecret: String? {
        infoString("BIOSAPISecret")
    }

    static var isServerConfigured: Bool {
        apiBaseURL != nil && apiSecret != nil
    }

    static var version: String {
        infoString("CFBundleShortVersionString") ?? "?"
    }

    static var build: String {
        infoString("CFBundleVersion") ?? "?"
    }

    /// Non-empty, trimmed Info.plist string, or nil.
    private static func infoString(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
