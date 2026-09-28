import SwiftUI

/// Mehr > "Bewegungs-Stupser": switch (default off, server profile), tone with
/// an example, time window, maximum per day, today's budget, last check, and
/// a second section with the last nudges and their effect plus the weekly text.
/// Every change is a `PATCH /v1/nudge/settings`; the server is the truth.
struct NudgeSection: View {
    @ObservedObject private var store = NudgeStore.shared
    @State private var showAll = false

    var body: some View {
        Section {
            if store.isUnavailable {
                calmRow("Server kennt Stupser noch nicht",
                        detail: "Kommt mit dem nächsten Server-Update, dann hier einschalten.",
                        symbol: "circle.dashed")
            } else if store.model == nil {
                if store.isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Wird geladen ...")
                            .foregroundStyle(BIOSTheme.text2)
                    }
                } else {
                    calmRow("Noch nicht geladen", detail: store.lastError, symbol: "circle.dashed")
                }
            } else {
                controls
            }
        } header: {
            Text("Bewegungs-Stupser")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if store.showsStaleData, let fetched = store.fetchedAt {
                    Text((store.isOffline ? "Offline" : "Nicht aktualisiert") + ", Stand \(BIOSFormat.relative(fetched)).")
                }
                Text("Mitteilungen mit Knöpfen erscheinen automatisch auch auf der Apple Watch, dort gehen Erledigt, Später und Heute nicht direkt am Handgelenk.")
            }
        }
        .task {
            await store.refresh()
        }

        if let model = store.model, !store.isUnavailable,
           !model.nudges.isEmpty || model.week?.displayText != nil {
            historySection(model)
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private var controls: some View {
        let settings = store.settings
        let options = store.model?.options ?? NudgeOptions(json: nil)

        Toggle(isOn: Binding(
            get: { store.settings.enabled },
            set: { value in Task { await store.setEnabled(value) } }
        )) {
            Label("Stupser", systemImage: "figure.walk")
        }
        .disabled(store.isSaving)

        Text("Ein leiser Hinweis ohne Ton, kurz aufzustehen, wenn die Glukose nach dem Essen steil steigt oder das Insulin zäh wirkt, höchstens \(settings.maxPerDay) am Tag.")
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text2)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 8) {
            Picker("Ton", selection: Binding(
                get: { store.settings.tone },
                set: { value in Task { await store.setTone(value) } }
            )) {
                ForEach(options.tones, id: \.self) { tone in
                    Text(NudgeModel.toneTitle(tone)).tag(tone)
                }
            }
            .pickerStyle(.segmented)
            .disabled(store.isSaving)
            Text("Beispiel: \"\(NudgeModel.example(tone: settings.tone))\"")
                .font(.footnote)
                .italic()
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)

        let times = NudgeClock.options(lower: options.hoursLower, upper: options.hoursUpper,
                                       including: [settings.start, settings.end])
        Picker(selection: Binding(
            get: { store.settings.start },
            set: { value in Task { await store.setHours(start: value, end: store.settings.end) } }
        )) {
            ForEach(times.filter { $0 < settings.end || $0 == settings.start }, id: \.self) { time in
                Text(time).monospacedDigit().tag(time)
            }
        } label: {
            Label("Von", systemImage: "sunrise")
        }
        .disabled(store.isSaving)

        Picker(selection: Binding(
            get: { store.settings.end },
            set: { value in Task { await store.setHours(start: store.settings.start, end: value) } }
        )) {
            ForEach(times.filter { $0 > settings.start || $0 == settings.end }, id: \.self) { time in
                Text(time).monospacedDigit().tag(time)
            }
        } label: {
            Label("Bis", systemImage: "sunset")
        }
        .disabled(store.isSaving)

        Stepper(value: Binding(
            get: { store.settings.maxPerDay },
            set: { value in Task { await store.setMaxPerDay(value) } }
        ), in: options.maxRange) {
            Label("Höchstens \(settings.maxPerDay) pro Tag", systemImage: "number")
        }
        .disabled(store.isSaving)

        if let error = store.saveError {
            calmRow("Nicht gespeichert", detail: error, symbol: "exclamationmark.circle", tint: BIOSTheme.mid)
        }

        StatusRow(title: "Heute", status: todayStatus)
        if settings.enabled, let check = store.model?.lastCheck, let reason = check.reason {
            StatusRow(title: "Letzte Prüfung", status: StatusDisplay(
                text: (check.at.map { BIOSFormat.time($0) + ": " } ?? "") + reason,
                symbol: check.send ? "figure.walk" : "checkmark.circle",
                tint: BIOSTheme.text2
            ))
        }
    }

    private var todayStatus: StatusDisplay {
        let settings = store.settings
        guard settings.enabled else {
            return StatusDisplay(text: "Aus, es kommen keine Stupser", symbol: "pause.circle", tint: BIOSTheme.text3)
        }
        guard let today = store.model?.today else {
            return StatusDisplay(text: "Noch keine Angaben", symbol: "circle.dashed", tint: BIOSTheme.text3)
        }
        if today.offToday {
            return StatusDisplay(text: "\"Heute nicht\" gewählt, morgen geht es weiter", symbol: "moon", tint: BIOSTheme.text2)
        }
        let maximum = today.maxPerDay ?? settings.maxPerDay
        let remaining = today.remaining ?? max(0, maximum - today.sent)
        var text = "\(today.sent) von \(maximum) gesendet, noch \(remaining)"
        if let last = today.lastSentAt {
            text += ", zuletzt \(BIOSFormat.time(last))"
        }
        if let cooldown = today.cooldownUntil, cooldown > Date() {
            text += ". Pause bis \(BIOSFormat.time(cooldown))"
        }
        return StatusDisplay(text: text, symbol: "figure.walk", tint: BIOSTheme.good)
    }

    // MARK: - History

    private func historySection(_ model: NudgeModel) -> some View {
        let visible = showAll ? model.nudges : Array(model.nudges.prefix(3))
        return Section {
            if let week = model.week?.displayText {
                Label {
                    Text(week)
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .foregroundStyle(BIOSTheme.glucose)
                }
            }
            ForEach(visible) { entry in
                NudgeEntryRow(entry: entry)
            }
            if model.nudges.count > 3 {
                Button(showAll ? "Weniger zeigen" : "Alle \(model.nudges.count) zeigen") {
                    showAll.toggle()
                }
            }
        } header: {
            Text("Stupser und Wirkung")
        } footer: {
            Text("Δ = Glukose 30 und 60 min nach dem Stupser minus Wert beim Stupser. Beschreibend, ohne Vergleichsgruppe: nach dem Essen sinkt die Kurve oft auch von selbst.")
        }
    }

    private func calmRow(_ title: String, detail: String?, symbol: String, tint: Color = BIOSTheme.text3) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One sent nudge: kind and time, title, glucose with Δ30/Δ60, the answer.
struct NudgeEntryRow: View {
    let entry: NudgeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.displayLabel + (entry.followupOf != nil ? " (Nachfass)" : ""))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let sent = entry.sentAt {
                    Text(BIOSFormat.relative(sent))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text3)
                }
            }
            if let title = entry.title {
                Text(title)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "drop")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.glucose)
                Text(entry.effectText)
                    .font(.footnote)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Antwort: \(entry.actionText)" + (entry.actionAt.map { ", \(BIOSFormat.time($0))" } ?? ""))
                .font(.caption)
                .foregroundStyle(BIOSTheme.text3)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
