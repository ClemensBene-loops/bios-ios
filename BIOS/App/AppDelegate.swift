import os
import UIKit
import UserNotifications

/// UIKit entry points that SwiftUI does not expose directly: push permission,
/// remote notification registration and the device token upload.
///
/// Flow on every launch (tokens can change, the upload is cheap):
/// request authorization -> `registerForRemoteNotifications()` ->
/// `didRegisterForRemoteNotificationsWithDeviceToken` -> `POST /v1/devices`.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Strong reference: `UNUserNotificationCenter.delegate` is weak.
    private let notificationDelegate = NotificationDelegate()
    private var uploadTask: Task<Void, Never>?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Must be set before launch finishes so a tap that cold-starts the app
        // is still delivered to the delegate.
        UNUserNotificationCenter.current().delegate = notificationDelegate
        registerNotificationCategories()
        requestAuthorizationAndRegister()
        // Early, so a Live Activity started by push (iOS 17.2+) delivers its
        // update token even when the system launches the app in the background.
        LiveActivityController.shared.startObserving()
        return true
    }

    /// Categories the server sets as `aps.category` (incl. `LAB_REVIEW`). No custom actions except
    /// `MOVE_NUDGE` (below): a tap opens the app. With hidden previews the title (emoji + verdict) stays
    /// visible; grouped notifications get a German summary line.
    private func registerNotificationCategories() {
        let definitions: [(id: String, summary: String)] = [
            ("WHOOP_ALERT", "%u weitere Whoop-Meldungen"),
            ("WHOOP_CLEAR", "%u weitere Whoop-Meldungen"),
            ("OUTLOOK_ALERT", "%u weitere Ausblick-Meldungen"),
            ("OUTLOOK_WEEKLY", "%u weitere Ausblick-Meldungen"),
            // Heartbeat warnings/Entwarnung and the test push (thread "system", tab Mehr)
            ("SYSTEM_ALERT", "%u weitere System-Meldungen"),
            // Labor: extracted values wait for the review (thread "labs", opens Labor > Zu prüfen)
            ("LAB_REVIEW", "%u weitere Befunde"),
        ]
        var categories = Set<UNNotificationCategory>()
        for definition in definitions {
            categories.insert(UNNotificationCategory(
                identifier: definition.id,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "BIOS-Meldung",
                categorySummaryFormat: definition.summary,
                options: [.hiddenPreviewsShowTitle]
            ))
        }
        categories.insert(Self.moveNudgeCategory())
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    /// Bewegungs-Stupser (thread "move"): three buttons without `.foreground`,
    /// so they work from the lock screen and on the Apple Watch without opening
    /// the app; each one posts `/v1/nudge/action` (NotificationDelegate).
    /// A tap on the notification itself opens Heute (`bios.tab`).
    private static func moveNudgeCategory() -> UNNotificationCategory {
        let actions = [
            UNNotificationAction(identifier: NudgeAction.doneID, title: "Erledigt", options: [],
                                 icon: UNNotificationActionIcon(systemImageName: "checkmark")),
            UNNotificationAction(identifier: NudgeAction.snoozeID, title: "Später", options: [],
                                 icon: UNNotificationActionIcon(systemImageName: "clock")),
            UNNotificationAction(identifier: NudgeAction.offTodayID, title: "Heute nicht", options: [],
                                 icon: UNNotificationActionIcon(systemImageName: "moon")),
        ]
        return UNNotificationCategory(
            identifier: NudgeAction.categoryID,
            actions: actions,
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Bewegungs-Stupser",
            categorySummaryFormat: "%u weitere Stupser",
            options: [.hiddenPreviewsShowTitle]
        )
    }

    /// Called when the app becomes active: picks up a permission the user
    /// granted in Settings after an earlier denial, and retries a failed
    /// APNs registration or token upload (e.g. launched while offline).
    func refreshAuthorizationIfNeeded() {
        var retry = false
        switch AppState.shared.authorization {
        case .denied, .failed:
            retry = true
        default:
            break
        }
        switch AppState.shared.registration {
        case .failed:
            retry = true
        default:
            break
        }
        switch AppState.shared.upload {
        case .failed:
            retry = true
        default:
            break
        }
        if retry {
            requestAuthorizationAndRegister()
        }
    }

    private func requestAuthorizationAndRegister() {
        AppState.shared.authorization = .requesting
        Task { @MainActor in
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    AppState.shared.authorization = .granted
                    UIApplication.shared.registerForRemoteNotifications()
                } else {
                    AppState.shared.authorization = .denied
                    BIOSLog.push.info("Push permission denied")
                }
            } catch {
                AppState.shared.authorization = .failed(error.localizedDescription)
                BIOSLog.push.error("Push authorization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Remote notification registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        BIOSLog.push.info("APNs token \(String(token.prefix(8)), privacy: .public)... (\(AppConfig.apnsEnvironment, privacy: .public))")
        AppState.shared.registration = .registered(token: token)
        uploadToken(token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        BIOSLog.push.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
        AppState.shared.registration = .failed(error.localizedDescription)
    }

    // MARK: - Token upload

    private func uploadToken(_ token: String) {
        guard let client = APIClient.fromConfig() else {
            BIOSLog.push.info("Server not configured, token not uploaded")
            AppState.shared.upload = .notConfigured
            return
        }
        let registration = DeviceRegistration(
            token: token,
            environment: AppConfig.apnsEnvironment,
            bundleID: AppConfig.bundleID,
            deviceName: Self.deviceName(),
            appVersion: AppConfig.versionString
        )

        uploadTask?.cancel()
        AppState.shared.upload = .uploading
        uploadTask = Task { @MainActor in
            do {
                try await client.registerDevice(registration)
                if Task.isCancelled { return }
                AppState.shared.upload = .succeeded(Date())
                BIOSLog.push.info("Token uploaded")
            } catch {
                if Task.isCancelled { return }
                AppState.shared.upload = .failed(error.localizedDescription)
                BIOSLog.push.error("Token upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// "iPhone (iPhone17,1), iOS 26.0". Since iOS 16 `UIDevice.name` is the
    /// generic model name, so the hardware identifier is added.
    private static func deviceName() -> String {
        let device = UIDevice.current
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return "\(device.name) (\(machine)), \(device.systemName) \(device.systemVersion)"
    }
}

/// Handles notifications while the app runs and taps on notifications.
///
/// Deliberately not main-actor isolated: the system may call these methods on
/// a background queue. Completion handlers are called synchronously, state
/// updates hop to the main actor with Sendable values only.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Push arrives while the app is open: show it anyway.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let push = PushInfo(notification: notification, kind: .received)
        Task { @MainActor in
            AppState.shared.record(push)
        }
        completionHandler([.banner, .list, .sound])
    }

    /// User tapped a push (or one of its actions).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Stupser buttons run in the background: answer the server, do not open a tab.
        if let action = NudgeAction(actionIdentifier: response.actionIdentifier) {
            let bios = response.notification.request.content.userInfo[AnyHashable("bios")] as? [String: Any]
            let nudgeID = (bios?["nudge_id"] as? String) ?? ""
            let done = CompletionBox(completionHandler)
            Task { @MainActor in
                NudgeActionQueue.handle(id: nudgeID, action: action) {
                    done.call()
                }
            }
            return
        }
        if response.actionIdentifier != UNNotificationDismissActionIdentifier {
            let push = PushInfo(notification: response.notification, kind: .opened)
            Task { @MainActor in
                AppState.shared.record(push)
            }
        }
        completionHandler()
    }
}

/// Carries a notification completion handler into a Task and calls it once.
/// UserNotifications accepts the call from any thread.
final class CompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        lock.lock()
        let pending = handler
        handler = nil
        lock.unlock()
        pending?()
    }
}

enum BIOSLog {
    static let push = Logger(subsystem: "at.bene.bios", category: "push")
}
