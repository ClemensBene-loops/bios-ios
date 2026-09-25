import UIKit

/// UIKit entry points that SwiftUI does not expose directly.
///
/// Phase 2 adds here: `UNUserNotificationCenter` authorization,
/// `application.registerForRemoteNotifications()` and the
/// `didRegisterForRemoteNotificationsWithDeviceToken` callback that uploads
/// the token to the BIOS server (see `AppConfig`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
