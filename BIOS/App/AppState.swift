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
    /// Custom top-level payload keys (everything except `aps`), stringified.
    let userInfo: [String: String]
    let date: Date

    init(notification: UNNotification, kind: Kind) {
        let content = notification.request.content
        var custom: [String: String] = [:]
        for (key, value) in content.userInfo {
            guard let name = key as? String, name != "aps" else { continue }
            custom[name] = String(describing: value)
        }
        self.kind = kind
        self.title = content.title
        self.body = content.body
        self.threadID = content.threadIdentifier
        self.category = content.categoryIdentifier
        self.userInfo = custom
        self.date = notification.date
    }

    init(kind: Kind, title: String, body: String, threadID: String = "",
         category: String = "", userInfo: [String: String] = [:], date: Date = Date()) {
        self.kind = kind
        self.title = title
        self.body = body
        self.threadID = threadID
        self.category = category
        self.userInfo = userInfo
        self.date = date
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

    /// Last tapped push, kept for routing (Phase 3 opens the matching view by
    /// `threadID`, then sets this back to nil).
    @Published var pendingOpen: PushInfo?

    init() {}

    func record(_ push: PushInfo) {
        lastPush = push
        if push.kind == .opened {
            pendingOpen = push
        }
    }

    /// Sample state for SwiftUI previews.
    static func preview() -> AppState {
        let state = AppState()
        state.authorization = .granted
        state.registration = .registered(token: "a1b2c3d4e5f60718293a4b5c6d7e8f90")
        state.upload = .succeeded(Date())
        state.record(PushInfo(
            kind: .received,
            title: "Infekt-Muster",
            body: "HRV -18 %, Ruhepuls +6",
            threadID: "whoop"
        ))
        return state
    }
}
