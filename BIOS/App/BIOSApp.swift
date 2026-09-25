import SwiftUI

@main
struct BIOSApp: App {
    /// UIKit hooks (push permission, notification categories, remote
    /// notification registration and the device token upload) live in AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // Dark mode is fixed app-wide by UIUserInterfaceStyle = Dark in
            // Info.plist (applies from launch, also to system sheets).
            RootView(
                state: AppState.shared,
                router: Router.shared,
                dashboardStore: DashboardStore.shared,
                seriesStore: SeriesStore.shared
            )
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    appDelegate.refreshAuthorizationIfNeeded()
                    Task { @MainActor in
                        await DashboardStore.shared.refresh()
                    }
                }
            }
        }
    }
}
