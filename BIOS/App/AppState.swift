import Foundation
import UserNotifications

/// A push notification as the app saw it, reduced to Sendable values so it
/// can cross from the notification delegate to the main actor.
struct PushInfo: Equatable, Sendable {
    enum Kind: String, Sendable {
        /// Delivered while the app was in the foreground.
        case received
        /// Opened by tapping it (also from a cold start).
        case opened
    }

    let kind: Kind
    let title: String
    let body: String
    /// APNs `thread-id` (e.g. "whoop", "outlook"); empty if none.
    let threadID: String
    /// APNs `category`; empty if none.
    let category: String
    /// `bios.tab` of the payload ("heute", "koerper", "umwelt", "mehr"), if any.
    let biosTab: String?
    /// `bios.detail` of the payload ("infekt", "viren", ...), if any.
    let biosDetail: String?
    /// Custom payload keys (everything except `aps`) as strings; nested
    /// objects are flattened to "bios.tab", "bios.kind", ...
    let userInfo: [String: String]
    let date: Date

    init(notification: UNNotification, kind: Kind) {
        let content = notification.request.content
        var custom: [String: String] = [:]
        for (key, value) in content.userInfo {
            guard let name = key as? String, name != "aps" else { continue }
            if let nested = value as? [String: Any] {
                for (subKey, subValue) in nested {
                    custom["\(name).\(subKey)"] = Self.describe(subValue)
                }
            } else {
                custom[name] = Self.describe(value)
            }
        }
        var tab: String?
        var detail: String?
        if let bios = content.userInfo[AnyHashable("bios")] as? [String: Any] {
            tab = Self.nonEmpty(bios["tab"] as? String)
            detail = Self.nonEmpty(bios["detail"] as? String)
        }
        self.kind = kind
        self.title = content.title
        self.body = content.body
        self.threadID = content.threadIdentifier
        self.category = content.categoryIdentifier
        self.biosTab = tab
        self.biosDetail = detail
        self.userInfo = custom
        self.date = notification.date
    }

    init(kind: Kind, title: String, body: String, threadID: String = "",
         category: String = "", biosTab: String? = nil, biosDetail: String? = nil,
         userInfo: [String: String] = [:], date: Date = Date()) {
        self.kind = kind
        self.title = title
        self.body = body
        self.threadID = threadID
        self.category = category
        self.biosTab = biosTab
        self.biosDetail = biosDetail
        self.userInfo = userInfo
        self.date = date
    }

    private static func describe(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// App-wide observable state: push permission, APNs registration, token
/// upload and the last push. Only touched on the main actor.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Authorization: Equatable {
        case notAsked
        case requesting
        case granted
        case denied
        case failed(String)
    }

    enum Registration: Equatable {
        case pending
        case registered(token: String)
        case failed(String)
    }

    enum Upload: Equatable {
        case waiting
        case notConfigured
        case uploading
        case succeeded(Date)
        case failed(String)
    }

    @Published var authorization: Authorization = .notAsked
    @Published var registration: Registration = .pending
    @Published var upload: Upload = .waiting

    /// Last push received in the foreground or opened by a tap.
    @Published private(set) var lastPush: PushInfo?

    /// Last tapped push, waiting for routing. RootView consumes it (switches
    /// tab, opens the detail, refreshes) and sets it back to nil.
    @Published var pendingOpen: PushInfo?

    init() {}

    func record(_ push: PushInfo) {
        lastPush = push
        if push.kind == .opened {
            pendingOpen = push
        }
    }
}
