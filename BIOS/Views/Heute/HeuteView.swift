import SwiftUI

/// Tab "Heute": offline banner, hero (Infekt-Check), outlook card, six tiles,
/// "Stand" line. Pull to refresh reloads the dashboard and loaded series.
struct HeuteView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @EnvironmentObject var seriesStore: SeriesStore
    @EnvironmentObject var router: Router
    @EnvironmentObject var eventStore: EventStore
    @EnvironmentObject var supplementStore: SupplementStore
    @EnvironmentObject var medicationStore: MedicationStore
    @State private var quickLog: QuickLogTarget?

    private let columns = [
        GridItem(.flexible(), spacing: 12, alignment: .top),
        GridItem(.flexible(), spacing: 12, alignment: .top),
    ]

    var body: some View {
        let dashboard = dashboardStore.dashboard
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BIOSFormat.longDay(Date()).uppercased())
                            .font(.footnote.weight(.semibold))
                            .tracking(0.5)
                            .foregroundStyle(BIOSTheme.text2)
                        Text("Dein Tag im Überblick")
                            .font(.title3)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    Spacer(minLength: 8)
                    // Brand mark (design A): the app icon in miniature.
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(BIOSBrand.green)
                        BIOSMarkImage(tile: 48)
                    }
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)

                StoreStatusBanner()
                WhoopRefreshStatusLine()

                if let health = dashboard?.health {
                    // Design A: Gesundheits-Score, compact Infekt-Check, Routine.
                    HealthScoreCard(health: health)
                    if let bodymap = dashboard?.bodymap {
                        BodyMapTodayCard(summary: bodymap)
                    }
                    InfektCheckCompactCard(infection: dashboard?.infection, vitals: dashboard?.vitals)
                    RoutineCard { target in
                        quickLog = target
                    }
                } else {
                    // Server without `health`: the Build 5 layout.
                    HeroCard(infection: dashboard?.infection, glucoseTile: dashboard?.glucose)
                    if let bodymap = dashboard?.bodymap {
                        BodyMapTodayCard(summary: bodymap)
                    }
                    QuickStatusCard { target in
                        quickLog = target
                    }
                }

                OutlookCard(outlook: dashboard?.outlook) {
                    router.show(.umwelt)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    VirusTile(region: dashboard?.virusesWien)
                    PollenTile(pollen: dashboard?.pollen, outlookAt: dashboard?.outlook?.generatedAt)
                    GlucoseTile(glucose: dashboard?.glucose)
                    RecoveryTile(recovery: dashboard?.recovery)
                    InsulinTile(insulin: dashboard?.insulin)
                    LoopTile(loop: dashboard?.loop)
                    if let pressure = dashboard?.bloodPressure {
                        BloodPressureTile(pressure: pressure)
                    }
                }

                Text("Beobachtung, keine Diagnose")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                StandLine()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .navigationTitle("Heute")
        .refreshable {
            // Requests a fresh Whoop pull first, then reloads dashboard, series
            // and body map; polls in the background while the pull is queued.
            await WhoopRefreshStore.shared.pullToRefresh(owner: "heute")
        }
        .onDisappear {
            WhoopRefreshStore.shared.cancel(owner: "heute")
        }
        .sheet(item: $quickLog) { target in
            QuickLogSheet(start: target)
                .environmentObject(eventStore)
                .environmentObject(supplementStore)
                .environmentObject(medicationStore)
                .environmentObject(MedicationPlanStore.shared)
                .environmentObject(VitalsStore.shared)
                .environmentObject(dashboardStore)
                .environmentObject(seriesStore)
                .environment(\.locale, BIOSFormat.locale)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    quickLog = .menu
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Schnell eintragen")
                .accessibilityHint("Alkohol, Supplements oder Medikamente")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if dashboardStore.isOffline {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(BIOSTheme.text2)
                        .accessibilityLabel("Offline")
                }
            }
        }
    }
}

/// Offline / error banner shown above cached data (Heute, Umwelt).
struct StoreStatusBanner: View {
    @EnvironmentObject var dashboardStore: DashboardStore

    var body: some View {
        if dashboardStore.showsStaleData {
            OfflineBanner(
                isOffline: dashboardStore.isOffline,
                error: dashboardStore.lastError,
                stand: dashboardStore.dashboard?.generatedAt ?? dashboardStore.fetchedAt
            )
        } else if dashboardStore.dashboard == nil, let error = dashboardStore.lastError {
            NotEvaluableBox(title: "Keine Daten", text: error)
        }
        if dashboardStore.isSample {
            NotEvaluableBox(title: "Beispieldaten", text: "Server nicht konfiguriert, alle Werte sind erfunden.")
        }
        if dashboardStore.dashboard?.isNewerSchema == true {
            NotEvaluableBox(title: "Neue Server-Version", text: "Einige Felder zeigt erst ein App-Update an.")
        }
    }
}

/// Small status of the Whoop pull after pull-to-refresh ("Whoop wird abgerufen …",
/// "Whoop aktualisiert 12:42", "Whoop zuletzt 12:42, nächster Abruf ab 12:52").
/// Shows nothing without a recent status (offline, errors, older server).
struct WhoopRefreshStatusLine: View {
    @ObservedObject private var store = WhoopRefreshStore.shared

    var body: some View {
        if let text = store.statusText() {
            HStack(spacing: 6) {
                if store.isWaiting {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                }
                Text(text)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text2)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// "Ausblick" card: 1 to 2 lines, tap switches to Umwelt.
struct OutlookCard: View {
    let outlook: OutlookCardModel?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "leaf")
                    .font(.body)
                    .foregroundStyle(BIOSTheme.pollen)
                    .frame(width: 34, height: 34)
                    .background(BIOSTheme.pollen.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: title)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text1)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text3)
                    .frame(maxHeight: .infinity)
            }
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ausblick: \(text)")
        .accessibilityHint("Öffnet den Tab Umwelt")
    }

    private var title: String {
        if let at = outlook?.generatedAt {
            return "Ausblick · \(BIOSFormat.time(at))"
        }
        return "Ausblick"
    }

    private var text: String {
        guard let outlook else { return "Noch kein Ausblick geladen." }
        if outlook.lines.isEmpty { return "Nichts Besonderes." }
        return outlook.lines.prefix(2).joined(separator: " ")
    }
}

/// "Stand 13:31 · Glukose und Loop stündlich", tap refreshes.
struct StandLine: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @EnvironmentObject var seriesStore: SeriesStore

    var body: some View {
        VStack(spacing: 4) {
            Button {
                Task {
                    await dashboardStore.refresh(force: true)
                    await seriesStore.refreshLoaded()
                }
            } label: {
                HStack(spacing: 6) {
                    if dashboardStore.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(text)
                        .monospacedDigit()
                }
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Aktualisiert die Daten")
            Text("Nach unten ziehen oder tippen zum Aktualisieren")
                .font(.caption2)
                .foregroundStyle(BIOSTheme.text3)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
    }

    private var text: String {
        let stand = dashboardStore.dashboard?.generatedAt ?? dashboardStore.fetchedAt
        guard let stand else {
            return dashboardStore.isLoading ? "Wird geladen ..." : "Noch nicht geladen"
        }
        let when = Calendar.current.isDateInToday(stand) ? BIOSFormat.time(stand) : BIOSFormat.relative(stand)
        let base = "Stand \(when)"
        if dashboardStore.showsStaleData {
            return base + (dashboardStore.isOffline ? " · offline" : " · nicht aktualisiert")
        }
        if let success = dashboardStore.lastSuccess, Date().timeIntervalSince(success) < 90 {
            return base + " · gerade aktualisiert"
        }
        return base + " · Glukose und Loop stündlich"
    }
}
