import SwiftUI

@main
struct BIOSApp: App {
    /// UIKit hooks (push permission, notification categories, remote
    /// notification registration and the device token upload) live in AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(state: AppState.shared, store: SummaryStore.shared)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        appDelegate.refreshAuthorizationIfNeeded()
                        Task { @MainActor in
                            await SummaryStore.shared.refresh()
                        }
                    }
                }
        }
    }
}
