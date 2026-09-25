import SwiftUI

@main
struct BIOSApp: App {
    /// UIKit hooks (push permission, remote notification registration and the
    /// device token upload) live in AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(state: AppState.shared)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appDelegate.refreshAuthorizationIfNeeded()
                    }
                }
        }
    }
}
