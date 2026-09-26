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
            // Cold start: the brand splash (Brand.swift) sits on top of the
            // TabView for about 1.7 s; RootView is built at once underneath,
            // so its data loading runs in parallel and is never delayed.
            SplashContainer {
                RootView(
                    state: AppState.shared,
                    router: Router.shared,
                    dashboardStore: DashboardStore.shared,
                    seriesStore: SeriesStore.shared,
                    eventStore: EventStore.shared
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    appDelegate.refreshAuthorizationIfNeeded()
                    Task { @MainActor in
                        await DashboardStore.shared.refresh()
                        // Offline queue of alcohol marks: retry on every foreground.
                        await EventStore.shared.flush()
                        await SupplementStore.shared.flush()
                        await MedicationStore.shared.flush()
                        await MedicationPlanStore.shared.flush()
                        await VitalsStore.shared.flush()
                        // Live Activity: start (fallback), refresh or end at night.
                        await LiveActivityController.shared.appBecameActive()
                    }
                } else if newPhase == .background {
                    // Intakes logged in the app show up on the lock screen at once.
                    Task { @MainActor in
                        await LiveActivityController.shared.updateRunning()
                    }
                }
            }
        }
    }
}
