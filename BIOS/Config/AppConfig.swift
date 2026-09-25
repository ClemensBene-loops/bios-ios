import Foundation

/// Build-time configuration read from Info.plist.
///
/// `BIOSAPIBaseURL` and `BIOSAPISecret` are empty in git and filled by the
/// build workflow from the GitHub secrets `BIOS_API_BASE_URL` and
/// `BIOS_API_SECRET`. Both may be missing; callers must handle `nil`.
///
/// `BIOSAPSEnvironment` is `$(APS_ENVIRONMENT)` from the xcconfigs, i.e. the
/// same value that goes into the `aps-environment` entitlement
/// (`development` for Debug, `production` for Release/TestFlight).
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

    /// "1.0 (7)", sent to the server as `app_version`.
    static var versionString: String {
        "\(version) (\(build))"
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "at.bene.bios"
    }

    /// Raw `aps-environment` value this build was signed with
    /// ("development" or "production"). Falls back on the build configuration
    /// if the Info.plist key is missing or was not expanded.
    static var apsEnvironment: String {
        if let value = infoString("BIOSAPSEnvironment"), !value.hasPrefix("$(") {
            return value
        }
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    /// APNs host the server must use for this build's device token:
    /// "sandbox" (development) or "production" (TestFlight, App Store).
    static var apnsEnvironment: String {
        apsEnvironment == "development" ? "sandbox" : "production"
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
