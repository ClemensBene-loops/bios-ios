import SwiftUI

@main
struct BIOSApp: App {
    /// UIKit hooks (remote notification registration and the device token
    /// callback in Phase 2) live in AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
