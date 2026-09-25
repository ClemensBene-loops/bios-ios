import SwiftUI

/// "Whoop-Check": verdict, alerts, values of the evaluated day, last days.
struct WhoopCheckSection: View {
    let check: WhoopCheck?
    let isHighlighted: Bool

    var body: some View {
        Section {
            SectionStatusRow(
                status: check?.status ?? .unknown,
                title: check?.headline ?? "Noch keine Daten",
                subtitle: subtitle
            )
            .id(SectionID.whoop)
            .listRowBackground(HighlightBackground(isOn: isHighlighted))

            if let check {
                ForEach(check.alerts) { alert in
                    AlertRow(alert: alert)
                }
                if let latest = check.latest {
                    metricRows(latest, check: check)
                }
                ForEach(Array(check.errors.enumerated()), id: \.offset) { entry in
                    ErrorRow(text: entry.element)
                }
                if check.days.count > 1 {
                    DisclosureGroup("Letzte Tage") {
                        ForEach(Array(check.days.suffix(5).reversed())) { day in
                            WhoopDayRow(day: day)
                        }
                        if let baseline = baselineText(check) {
                            Text(baseline)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let text = check.text, !text.isEmpty {
                    FullTextDisclosure(text: text)
                }
            }
        } header: {
            Text("Whoop-Check")
        }
    }

    private var subtitle: String {
        guard let check else { return "Wird vom Server geladen" }
        guard let day = check.day else { return "" }
        return "Werte vom \(BIOSFormat.day(day))"
    }

    @ViewBuilder
    private func metricRows(_ day: WhoopDay, check: WhoopCheck) -> some View {
        if let rhr = day.rhr {
            LabeledContent("Ruhepuls", value: withDelta(
                "\(BIOSFormat.number(rhr)) bpm",
                delta: check.baselineMedian["whoop_rhr"].map { BIOSFormat.signed(rhr - $0) }
            ))
        }
        if let hrv = day.hrv {
            LabeledContent("HRV", value: withDelta(
                "\(BIOSFormat.number(hrv)) ms",
                delta: percentDelta(hrv, median: check.baselineMedian["whoop_hrv"])
            ))
        }
        if let recovery = day.recovery {
            LabeledContent("Recovery", value: "\(BIOSFormat.number(recovery)) %")
        }
        if let sleep = day.sleepHours {
            LabeledContent("Schlaf", value: "\(BIOSFormat.number(sleep, digits: 1)) h")
        }
        if let temp = day.skinTemp, let median = check.baselineMedian["whoop_skin_temp"] {
            LabeledContent("Hauttemperatur", value: "\(BIOSFormat.signed(temp - median, digits: 1)) °C")
        }
        if let resp = day.respRate {
            LabeledContent("Atemfrequenz", value: withDelta(
                "\(BIOSFormat.number(resp, digits: 1)) /min",
                delta: check.baselineMedian["whoop_resp_rate"].map { BIOSFormat.signed(resp - $0, digits: 1) }
            ))
        }
    }

    private func withDelta(_ value: String, delta: String?) -> String {
        guard let delta else { return value }
        return "\(value) (\(delta))"
    }

    private func percentDelta(_ value: Double, median: Double?) -> String? {
        guard let median, median > 0 else { return nil }
        return "\(BIOSFormat.signed((value / median - 1) * 100)) %"
    }

    private func baselineText(_ check: WhoopCheck) -> String? {
        guard let rhr = check.baselineMedian["whoop_rhr"],
              let hrv = check.baselineMedian["whoop_hrv"] else {
            return nil
        }
        let days = check.baselineDays.map { " (\($0) Tage)" } ?? ""
        return "Baseline\(days): Ruhepuls \(BIOSFormat.number(rhr)), HRV \(BIOSFormat.number(hrv)) ms. Klammern = Abweichung davon, ! = Infektmuster."
    }
}

/// One day in "Letzte Tage": date, Ruhepuls / HRV, marker if flagged.
struct WhoopDayRow: View {
    let day: WhoopDay

    var body: some View {
        HStack(spacing: 8) {
            Text(BIOSFormat.day(day.date))
            Spacer(minLength: 8)
            Text(values)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if day.flagged {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.red)
                    .accessibilityLabel("Infektmuster")
            }
        }
        .font(.subheadline)
    }

    private var values: String {
        let rhr = day.rhr.map { BIOSFormat.number($0) } ?? "–"
        let hrv = day.hrv.map { BIOSFormat.number($0) } ?? "–"
        return "Puls \(rhr) · HRV \(hrv)"
    }
}
