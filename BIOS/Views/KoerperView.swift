import SwiftUI

/// Shared 7/28 days selection (Körper and the detail screens use the same value).
enum RangeSetting {
    static let key = "bios.rangeDays"
}

/// Tab "Körper": Whoop, glucose and insulin charts with baseline bands.
struct KoerperView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @EnvironmentObject var seriesStore: SeriesStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let glucose = dashboardStore.dashboard?.glucose
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RangePicker(days: $days)

                SectionHeader(title: "Whoop", route: .recovery)
                MetricChartCard(kind: .recovery, days: days, compact: true)
                MetricChartCard(kind: .rhr, days: days, compact: true)
                MetricChartCard(kind: .hrv, days: days, compact: true)
                MetricChartCard(kind: .sleep, days: days, compact: true)

                SectionHeader(title: "Glukose", route: .glukose)
                if let glucose, !glucose.evaluable {
                    NotEvaluableBox(
                        title: "Glukose heute nicht bewertbar",
                        text: (glucose.reason ?? "Zu wenige Werte") + ". Die Tageswerte bis gestern sind vollständig."
                    )
                }
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
            await dashboardStore.refresh(force: true)
            await seriesStore.refreshLoaded()
        }
    }
}
