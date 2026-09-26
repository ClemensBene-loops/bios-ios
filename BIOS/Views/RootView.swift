import SwiftUI

/// Root: TabView with Heute, Körper, Umwelt, Mehr (iOS 17 API: `.tabItem` +
/// `.tag`). Every tab has its own NavigationStack; detail screens are pushed
/// by value (`DetailRoute`). A tapped push is routed here (tab + detail).
struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var router: Router
    @ObservedObject var dashboardStore: DashboardStore
    @ObservedObject var seriesStore: SeriesStore
    @ObservedObject var eventStore: EventStore

    var body: some View {
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.heutePath) {
                HeuteView()
                    .withDetailDestinations()
            }
            .tabItem { Label(AppTab.heute.title, systemImage: AppTab.heute.symbol) }
            .tag(AppTab.heute)

            NavigationStack(path: $router.koerperPath) {
                KoerperView()
                    .withDetailDestinations()
            }
            .tabItem { Label(AppTab.koerper.title, systemImage: AppTab.koerper.symbol) }
            .tag(AppTab.koerper)

            NavigationStack(path: $router.umweltPath) {
                UmweltView()
                    .withDetailDestinations()
            }
            .tabItem { Label(AppTab.umwelt.title, systemImage: AppTab.umwelt.symbol) }
            .tag(AppTab.umwelt)

            NavigationStack(path: $router.mehrPath) {
                MehrView()
                    .withDetailDestinations()
            }
            .tabItem { Label(AppTab.mehr.title, systemImage: AppTab.mehr.symbol) }
            .tag(AppTab.mehr)
        }
        .tint(BIOSTheme.accent)
        .environmentObject(state)
        .environmentObject(router)
        .environmentObject(dashboardStore)
        .environmentObject(seriesStore)
        .environmentObject(eventStore)
        .environmentObject(SupplementStore.shared)
        .environmentObject(MedicationStore.shared)
        .environmentObject(MedicationPlanStore.shared)
        .environmentObject(VitalsStore.shared)
        .environment(\.locale, BIOSFormat.locale)
        .overlay(alignment: .bottom) {
            if let toast = eventStore.toast {
                ToastView(text: toast)
                    .padding(.bottom, 96)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: eventStore.toast)
        .task {
            await dashboardStore.refresh()
            await BodyMapStore.shared.refresh()
            await eventStore.flush()
            await eventStore.refresh()
            await SupplementStore.shared.flush()
            await SupplementStore.shared.refresh()
            await MedicationStore.shared.flush()
            await MedicationPlanStore.shared.flush()
            await MedicationPlanStore.shared.refresh()
            await VitalsStore.shared.flush()
        }
        .onAppear {
            consumePendingOpen()
        }
        .onChange(of: state.pendingOpen) { _, _ in
            consumePendingOpen()
        }
    }

    /// Routes a tapped push (AppState.pendingOpen) to its tab/detail, then refreshes.
    private func consumePendingOpen() {
        guard let push = state.pendingOpen else { return }
        state.pendingOpen = nil
        router.open(push)
        Task { @MainActor in
            await dashboardStore.refresh(force: true)
        }
    }
}

extension View {
    /// Registers the detail screens on a NavigationStack root.
    func withDetailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in
            DetailView(route: route)
        }
    }
}

/// Switch over all detail screens.
struct DetailView: View {
    let route: DetailRoute

    var body: some View {
        Group {
            switch route {
            case .infekt: InfektDetailView()
            case .viren: VirenDetailView()
            case .pollen: PollenDetailView()
            case .glukose: GlukoseDetailView()
            case .recovery: RecoveryDetailView()
            case .insulin: InsulinDetailView()
            case .loop: LoopDetailView()
            case .alkohol: AlcoholCalendarView()
            case .blutdruck: BloodPressureDetailView()
            case .gesundheit: HealthDetailView()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
