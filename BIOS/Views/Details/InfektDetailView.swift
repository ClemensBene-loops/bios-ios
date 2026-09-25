import SwiftUI

/// Detail "Infekt-Check": status, alerts, chips, Whoop charts with baseline
/// band and pattern days, glucose/insulin context table, last 7 days.
struct InfektDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let infection = dashboardStore.dashboard?.infection
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                InfektSummaryCard(infection: infection)
                RangePicker(days: $days)
                MetricChartCard(kind: .rhr, days: days)
                MetricChartCard(kind: .hrv, days: days)
                MetricChartCard(kind: .skinTemp, days: days)
                MetricChartCard(kind: .respRate, days: days)
                ContextSignalsCard(infection: infection)
                if let infection, !infection.days.isEmpty {
                    LastDaysCard(days: infection.days)
                }
                NoteText(text: noteText(infection?.baseline))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }

    private func noteText(_ baseline: InfectionBaseline?) -> String {
        var values: [String] = []
        if let rhr = baseline?.rhr { values.append("Ruhepuls \(BIOSFormat.number(rhr))") }
        if let hrv = baseline?.hrv { values.append("HRV \(BIOSFormat.number(hrv)) ms") }
        if let skin = baseline?.skinTemp { values.append("Haut \(BIOSFormat.number(skin, digits: 1)) °C") }
        if let resp = baseline?.respRate { values.append("Atmung \(BIOSFormat.number(resp, digits: 1))") }
        let days = baseline?.days ?? 28
        let head = "Baseline \(days) Tage (endet 3 Tage vor heute)"
        let list = values.isEmpty ? "." : ": " + values.joined(separator: ", ") + "."
        return head + list + " Muster: Ruhepuls hoch und HRV tief an 2 von 3 Tagen, Haut, Atmung und SpO2 stützen."
    }
}

struct InfektSummaryCard: View {
    let infection: InfectionModel?

    var body: some View {
        let status = infection?.status ?? .unknown
        let zone = infection?.recoveryZone ?? .none
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RecoveryRing(value: infection?.recovery, color: zone.color, lineWidth: 8)
                        .frame(width: 76, height: 76)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(BIOSFormat.number(infection?.recovery))
                            .font(.title3.bold())
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    .frame(width: 60)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: status.symbol)
                            .foregroundStyle(status.tint)
                        Text(infection?.headline ?? "Noch keine Daten")
                    }
                    .font(.title3.bold())
                    Text(checkedText(zone: zone))
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            .accessibilityElement(children: .combine)

            Text(alertText)
                .font(.subheadline)
                .foregroundStyle(infection?.alerts.isEmpty == false ? BIOSTheme.text1 : BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if let note = infection?.confounderNote {
                ContextLine(symbol: "wineglass", title: note, detail: nil, style: .neutral)
            }

            if let chips = infection?.chips, !chips.isEmpty {
                FlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(chips) { chip in
                        ChipView(chip: chip, status: status)
                    }
                }
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func checkedText(zone: BIOSZone) -> String {
        var text = "Recovery \(zone.word)"
        if let checked = infection?.checkedAt {
            text += " · geprüft \(BIOSFormat.relative(checked))"
        }
        return text
    }

    private var alertText: String {
        guard let infection else { return "Der Infekt-Check wird vom Server geladen." }
        if !infection.alerts.isEmpty {
            return infection.alerts.map(\.text).joined(separator: " ")
        }
        return infection.subline ?? "Keine Auffälligkeit gegenüber deiner Baseline."
    }
}

/// "Glukose und Insulin" (rule A: context only, never an alarm on its own).
struct ContextSignalsCard: View {
    let infection: InfectionModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Glukose und Insulin")
                    .font(.headline)
                Spacer()
                Text("Kontext")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }

            let glucose = infection?.glucose
            let insulin = infection?.insulin
            if glucose == nil && insulin == nil {
                NotEvaluableBox(title: "Keine Angaben", text: "Der Server liefert noch keine Glukose- und Insulinsignale.")
            } else {
                if let glucose, !glucose.evaluable {
                    NotEvaluableBox(
                        title: "Glukose nicht bewertbar",
                        text: (glucose.reason ?? "Zu wenige Werte") + (insulin?.evaluable == true ? ". Insulin wird weiter bewertet." : ".")
                    )
                }
                if let insulin, !insulin.evaluable {
                    NotEvaluableBox(title: "Insulin nicht bewertbar", text: insulin.reason)
                }
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        GridHeaderText(text: "Abweichung").gridColumnAlignment(.trailing)
                        GridHeaderText(text: "Status").gridColumnAlignment(.trailing)
                    }
                    if let glucose, glucose.evaluable {
                        signalRow("Nacht-Ø heute (0 bis 6 Uhr)", value: glucose.nightDelta.map { BIOSFormat.signed($0) + " mg/dL" }, up: glucose.up)
                        signalRow("Tages-Ø gestern", value: glucose.dayDelta.map { BIOSFormat.signed($0) + " mg/dL" }, up: glucose.up)
                        signalRow("Zeit über 180 gestern", value: glucose.tarDelta.map { BIOSFormat.signed($0) + " Pkt." }, up: glucose.up)
                    }
                    if let insulin, insulin.evaluable {
                        signalRow("Insulin/10 g KH", value: insulin.per10gDeltaPct.map { BIOSFormat.signed($0) + " %" }, up: insulin.up)
                        signalRow("Gesamtinsulin gestern", value: insulin.tddDeltaPct.map { BIOSFormat.signed($0) + " %" }, up: insulin.up)
                    }
                }
                .font(.footnote)
                .monospacedDigit()
            }

            Text("Zählt nie allein als Alarm. Erhöht heißt: z ≥ 1,5 gegenüber deiner Baseline. Loop gleicht aus, darum steigt oft nur der Insulinbedarf.")
                .font(.caption)
                .foregroundStyle(BIOSTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func signalRow(_ label: String, value: String?, up: Bool) -> some View {
        GridRow {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
            Text(value ?? "n. v.")
                .gridColumnAlignment(.trailing)
            HStack(spacing: 3) {
                if up {
                    Image(systemName: "arrow.up")
                        .font(.caption2.weight(.bold))
                }
                Text(up ? "erhöht" : "normal")
            }
            .foregroundStyle(up ? BIOSTheme.badText : BIOSTheme.text2)
            .fontWeight(up ? .semibold : .regular)
            .gridColumnAlignment(.trailing)
        }
    }
}

/// "Letzte 7 Tage": Ruhepuls / HRV / Recovery with pattern markers.
struct LastDaysCard: View {
    let days: [InfectionDay]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Letzte 7 Tage")
                    .font(.headline)
                Spacer()
                Text("Ruhepuls / HRV / Recovery")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    GridHeaderText(text: "Tag")
                    GridHeaderText(text: "RP").gridColumnAlignment(.trailing)
                    GridHeaderText(text: "HRV").gridColumnAlignment(.trailing)
                    GridHeaderText(text: "Rec.").gridColumnAlignment(.trailing)
                    Text("")
                }
                ForEach(Array(days.suffix(7).reversed())) { day in
                    GridRow {
                        Text(BIOSDate.day(day.date).map { BIOSFormat.dayLabel($0) } ?? day.date)
                        Text(BIOSFormat.number(day.rhr))
                            .foregroundStyle(day.flagged ? BIOSTheme.badText : BIOSTheme.text1)
                        Text(BIOSFormat.number(day.hrv))
                            .foregroundStyle(day.flagged ? BIOSTheme.badText : BIOSTheme.text1)
                        Text(day.recovery.map { BIOSFormat.number($0) + " %" } ?? "n. v.")
                        if day.flagged {
                            Label("Muster", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.badText)
                        } else {
                            Text("")
                        }
                    }
                }
            }
            .font(.footnote)
            .monospacedDigit()
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }
}

/// Small grey column header inside a Grid.
struct GridHeaderText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(BIOSTheme.text3)
    }
}
