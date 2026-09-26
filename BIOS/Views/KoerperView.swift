import SwiftUI

/// Shared 7/28 days selection (Körper and the detail screens use the same value).
enum RangeSetting {
    static let key = "bios.rangeDays"
}

/// Tab "Körper": Körperkarte on top (BodyMapSection, own store), then Whoop,
/// glucose and insulin charts with baseline bands.
///
/// Scrolling: a LazyVStack builds the chart cards only near the screen; every
/// card observes only its own series slot (SeriesStore) and the charts skip
/// re-rendering for unchanged data. The page itself observes no store, so a
/// dashboard refresh does not rebuild the stack.
struct KoerperView: View {
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                BodyMapSection()

                RangePicker(days: $days)

                SectionHeader(title: "Whoop", route: .recovery)
                MetricChartCard(kind: .recovery, days: days, compact: true)
                MetricChartCard(kind: .rhr, days: days, compact: true)
                MetricChartCard(kind: .hrv, days: days, compact: true)
                SleepChartCard(days: days, compact: true)

                BodyTemperatureSection(days: days)

                SectionHeader(title: "Glukose", route: .glukose)
                GlucoseNotEvaluableNote()
                MetricChartCard(kind: .glucoseDaily, days: days, compact: true)
                MetricChartCard(kind: .tir, days: days, compact: true)

                SectionHeader(title: "Insulin", route: .insulin)
                MetricChartCard(kind: .tdd, days: days, compact: true)
                MetricChartCard(kind: .per10g, days: days, compact: true)

                NoteText(text: "Band: deine persönliche Baseline, Median der 28 Tage bis 3 Tage vor heute, ±1,5 robuste σ. Glukose und Insulin sind ganze Tage bis gestern.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .navigationTitle("Körper")
        .refreshable {
            await DashboardStore.shared.refresh(force: true)
            await BodyMapStore.shared.refresh(force: true)
            await SeriesStore.shared.refreshLoaded()
        }
    }
}

/// "Glukose heute nicht bewertbar" box; observes the dashboard on its own.
private struct GlucoseNotEvaluableNote: View {
    @EnvironmentObject var dashboardStore: DashboardStore

    var body: some View {
        if let glucose = dashboardStore.dashboard?.glucose, !glucose.evaluable {
            NotEvaluableBox(
                title: "Glukose heute nicht bewertbar",
                text: (glucose.reason ?? "Zu wenige Werte") + ". Die Tageswerte bis gestern sind vollständig."
            )
        }
    }
}

/// Körpertemperatur (readings entered in the app, `body_temp`): only shown
/// when there is at least one reading in the selected range.
struct BodyTemperatureSection: View {
    let days: Int

    var body: some View {
        SeriesReader(request: SeriesStore.Request(metric: MetricKind.bodyTemp.metric, days: days, source: nil)) { entry in
            if let model = entry?.model, model.hasValues {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Temperatur")
                    MetricChartCard(kind: .bodyTemp, days: days, compact: true)
                }
            }
        }
    }
}
