import SwiftUI
import UIKit

/// Loads `GET /v1/therapy` (Loop settings, delivered basal, basal assistant),
/// cached on disk for offline display.
@MainActor
final class TherapyStore: ObservableObject {
    static let shared = TherapyStore()

    @Published private(set) var model: TherapyModel?
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private static let cacheKey = "therapy"

    init() {
        if let cached = DiskCache.load(Self.cacheKey) {
            model = TherapyModel(json: cached.value)
            fetchedAt = cached.fetchedAt
        }
    }

    func refresh() async {
        if isLoading { return }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let json = try await client.getJSON(path: ["v1", "therapy"])
            let now = Date()
            model = TherapyModel(json: json)
            fetchedAt = now
            lastError = nil
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: now)
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }
}

/// "Loop-Einstellungen": the settings like Loop's settings screen, delivered
/// basal per hour, the basal assistant (status, per hour proposal) and a text
/// to share. Display only: no editing, nothing is sent to Loop.
struct TherapyView: View {
    @ObservedObject private var store = TherapyStore.shared

    var body: some View {
        let model = store.model
        List {
            if let model, !model.isEmpty {
                if let active = model.activeOverride {
                    Section {
                        Label("Aktiv: \(active.bannerText)", systemImage: "dial.medium")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BIOSTheme.contextText)
                            .listRowBackground(BIOSTheme.context.opacity(0.18))
                    } footer: {
                        Text("Laufender Override in Loop, Stand des letzten Profilabrufs.")
                    }
                }
                if let suggestions = model.suggestions {
                    Section {
                        SuggestionStatusCard(suggestions: suggestions)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                basalSection(model)
                scheduleSection(title: "KH-Verhältnis", entries: model.carbRatio, unit: "g/IE", digits: 1)
                scheduleSection(title: "Insulinempfindlichkeit", entries: model.sensitivity, unit: "mg/dL/IE", digits: 0)
                targetSection(model.targets)
                limitsSection(model)
                overridesSection(model.overrides)
                shareSection(model)
            } else {
                Section {
                    if store.isLoading {
                        ProgressView()
                    } else {
                        Text(store.lastError ?? "Der Server liefert noch keine Loop-Einstellungen.")
                            .foregroundStyle(BIOSTheme.text2)
                    }
                }
            }
            Section {
                Text("Nur Beobachtung, Anpassungen mit Arzt besprechen und in Loop selbst eintragen.")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                if model?.profileSource == "db" {
                    Text("Nightscout nicht erreichbar: nur das gespeicherte Basalprofil, ohne KH-Verhältnis, Empfindlichkeit, Ziele und Limits.")
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.midText)
                }
                ForEach(model?.errors ?? [], id: \.self) { error in
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                }
                if let fetched = store.fetchedAt {
                    Text(standText(model, fetched: fetched))
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .biosPageBackground()
        .navigationTitle("Loop-Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    private func standText(_ model: TherapyModel?, fetched: Date) -> String {
        var parts = ["Stand \(BIOSFormat.relative(fetched))"]
        if let name = model?.profileName { parts.append("Profil \(name)") }
        if let updated = model?.updatedAt { parts.append("Profil geändert \(BIOSFormat.relative(updated))") }
        return parts.joined(separator: " · ")
    }

    // MARK: Basal

    @ViewBuilder
    private func basalSection(_ model: TherapyModel) -> some View {
        if !model.basal.isEmpty || model.hasHourly {
            Section {
                if model.hasHourly {
                    BasalHourHeader(showProposal: model.suggestions != nil)
                    ForEach(0..<24, id: \.self) { hour in
                        BasalHourRow(hour: hour, model: model)
                    }
                } else {
                    ForEach(model.basal) { entry in
                        ScheduleRow(time: entry.timeText, value: "\(BIOSFormat.number(entry.value, digits: 2)) IE/Std")
                    }
                }
            } header: {
                Text("Basalrate")
            } footer: {
                Text(basalFooter(model))
            }
        }
    }

    private func basalFooter(_ model: TherapyModel) -> String {
        var lines: [String] = []
        if let total = model.basalTotal {
            var line = "Summe \(BIOSFormat.number(total, digits: 2)) IE/Tag"
            if let delivered = model.deliveredTotal {
                line += " · abgegeben Ø \(BIOSFormat.number(delivered, digits: 2)) IE"
                if let days = model.deliveredDays { line += " (\(days) Tage)" }
            }
            lines.append(line)
        }
        if let suggestions = model.suggestions, let old = suggestions.totalOld, let new = suggestions.totalNew {
            var line = "Vorschlag: \(BIOSFormat.number(old, digits: 2)) → \(BIOSFormat.number(new, digits: 2)) IE/Tag"
            if let pct = suggestions.totalChangePct, abs(pct) >= 0.05 {
                line += " (\(BIOSFormat.signed(pct, digits: 1)) %)"
            }
            lines.append(line)
        }
        if let note = model.note {
            lines.append(note)
        }
        lines.append("Abgegeben Ø: was Loop in dieser Stunde im Mittel tatsächlich abgegeben hat (Temp-Basals eingerechnet).")
        return lines.joined(separator: "\n")
    }

    // MARK: Other schedules

    @ViewBuilder
    private func scheduleSection(title: String, entries: [TherapyScheduleEntry], unit: String, digits: Int) -> some View {
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { entry in
                    ScheduleRow(time: entry.timeText, value: "\(BIOSFormat.number(entry.value, digits: digits)) \(unit)")
                }
            }
        }
    }

    @ViewBuilder
    private func targetSection(_ entries: [TherapyScheduleEntry]) -> some View {
        if !entries.isEmpty {
            Section("Zielbereich") {
                ForEach(entries) { entry in
                    ScheduleRow(time: entry.timeText, value: TherapyText.target(entry))
                }
            }
        }
    }

    @ViewBuilder
    private func limitsSection(_ model: TherapyModel) -> some View {
        if model.maxBasal != nil || model.maxBolus != nil {
            Section("Abgabelimits") {
                if let maxBasal = model.maxBasal {
                    LabeledContent("Max. Basalrate", value: "\(BIOSFormat.number(maxBasal, digits: 2)) IE/Std")
                }
                if let maxBolus = model.maxBolus {
                    LabeledContent("Max. Bolus", value: "\(BIOSFormat.number(maxBolus, digits: 1)) IE")
                }
            }
        }
    }

    @ViewBuilder
    private func overridesSection(_ overrides: [TherapyOverride]) -> some View {
        if !overrides.isEmpty {
            Section("Override-Vorlagen") {
                ForEach(overrides) { preset in
                    VStack(alignment: .leading, spacing: 2) {
                        Text([preset.symbol, preset.name].compactMap { $0 }.joined(separator: " "))
                            .font(.body.weight(.semibold))
                        if !preset.detailText.isEmpty {
                            Text(preset.detailText)
                                .font(.footnote)
                                .foregroundStyle(BIOSTheme.text2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Share

    @ViewBuilder
    private func shareSection(_ model: TherapyModel) -> some View {
        Section {
            if let suggestions = model.suggestions, !suggestions.blocks.isEmpty || !suggestions.hours.isEmpty {
                let proposal = TherapyText.proposal(model, suggestions)
                ShareLink(item: proposal) {
                    Label("Vorschlag Basalrate teilen", systemImage: "square.and.arrow.up")
                }
                CopyButton(title: "Vorschlag kopieren", text: proposal)
            }
            let settings = TherapyText.settings(model)
            ShareLink(item: settings) {
                Label("Einstellungen als Text teilen", systemImage: "doc.plaintext")
            }
            CopyButton(title: "Einstellungen kopieren", text: settings)
        } header: {
            Text("Übertragen")
        } footer: {
            Text("Text zum Abtippen in Loop oder für den Arzttermin. BIOS ändert nichts in Loop.")
        }
    }
}

// MARK: - Assistant status

struct SuggestionStatusCard: View {
    let suggestions: TherapySuggestions
    @State private var showExcluded = false

    /// Recommended (green), no change needed (neutral), not recommended (amber).
    private var style: (tint: Color, symbol: String, title: String) {
        if suggestions.recommended {
            return (BIOSTheme.good, "checkmark.seal.fill", "Zur Übernahme empfohlen")
        }
        if suggestions.noChangeNeeded {
            return (BIOSTheme.text2, "checkmark.circle", suggestions.statusText)
        }
        return (BIOSTheme.mid, "exclamationmark.triangle.fill", "Nicht zur Übernahme empfohlen")
    }

    var body: some View {
        let style = self.style
        let tint = style.tint
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: style.symbol)
                    .foregroundStyle(suggestions.noChangeNeeded ? BIOSTheme.good.opacity(0.8) : tint)
                Text(style.title)
                    .font(.headline)
            }
            if suggestions.statusText != style.title {
                Text(suggestions.statusText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(suggestions.reasons.enumerated()), id: \.offset) { entry in
                Label(entry.element, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if let window = suggestions.windowText {
                    Text("Fenster \(window)")
                }
                if let clean = suggestions.cleanText {
                    Button {
                        showExcluded.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(clean)
                            if !suggestions.excluded.isEmpty {
                                Image(systemName: showExcluded ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(BIOSTheme.accent)
                    .disabled(suggestions.excluded.isEmpty)
                    .accessibilityHint("Zeigt die ausgeschlossenen Tage")
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(BIOSTheme.text3)
            if showExcluded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestions.excluded) { day in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(BIOSFormat.relativeDay(day.date))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Text(day.reasons.isEmpty ? "ausgeschlossen" : day.reasons.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
            if let disclaimer = suggestions.disclaimer {
                Text(disclaimer)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(suggestions.noChangeNeeded ? BIOSTheme.card2 : tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(suggestions.noChangeNeeded ? BIOSTheme.separator : tint.opacity(0.45), lineWidth: 1)
        )
    }
}

// MARK: - Rows

struct BasalHourHeader: View {
    let showProposal: Bool

    var body: some View {
        HStack {
            Text("Zeit").frame(width: 48, alignment: .leading)
            Spacer(minLength: 4)
            Text("Profil").frame(width: 58, alignment: .trailing)
            Text("abgegeben Ø").frame(width: 92, alignment: .trailing)
            if showProposal {
                Text("Vorschlag").frame(width: 80, alignment: .trailing)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(BIOSTheme.text3)
        .accessibilityHidden(true)
    }
}

struct BasalHourRow: View {
    let hour: Int
    let model: TherapyModel

    var body: some View {
        let suggestion = model.suggestions?.hour(hour)
        let scheduled = suggestion?.scheduled ?? model.scheduled(hour: hour)
        let delivered = model.delivered(hour: hour)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(BIOSFormat.twoDigits(hour)):00")
                    .frame(width: 48, alignment: .leading)
                Spacer(minLength: 4)
                Text(BIOSFormat.number(scheduled, digits: 2))
                    .frame(width: 58, alignment: .trailing)
                HStack(spacing: 3) {
                    if let indicator = TherapyText.difference(delivered?.mean, scheduled) {
                        Image(systemName: indicator.symbol)
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                    Text(BIOSFormat.number(delivered?.mean, digits: 2))
                        .foregroundStyle(BIOSTheme.text2)
                }
                .frame(width: 92, alignment: .trailing)
                if model.suggestions != nil {
                    proposalView(suggestion)
                        .frame(width: 80, alignment: .trailing)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            if let suggestion, suggestion.isLowConsistency || suggestion.note != nil {
                Text([suggestion.isLowConsistency ? "wenig konsistent" : nil, suggestion.note].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(BIOSTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(scheduled: scheduled, delivered: delivered, suggestion: suggestion))
    }

    @ViewBuilder
    private func proposalView(_ suggestion: TherapySuggestions.Hour?) -> some View {
        if let suggestion, let proposed = suggestion.proposed {
            HStack(spacing: 2) {
                if suggestion.hypo {
                    Image(systemName: "arrow.down.to.line")
                        .font(.caption2)
                        .foregroundStyle(BIOSTheme.badText)
                        .accessibilityLabel("Unterzucker in dieser Stunde")
                }
                if suggestion.hasChange {
                    Image(systemName: proposed > (suggestion.scheduled ?? proposed) ? "arrow.up" : "arrow.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BIOSTheme.strongTrend)
                }
                Text(BIOSFormat.number(proposed, digits: 2))
                    .fontWeight(suggestion.hasChange ? .semibold : .regular)
                    .foregroundStyle(suggestion.hasChange ? BIOSTheme.strongTrend : BIOSTheme.text3)
            }
        } else {
            Text("n. v.")
                .foregroundStyle(BIOSTheme.text3)
        }
    }

    private func accessibilityText(scheduled: Double?, delivered: DeliveredHour?,
                                   suggestion: TherapySuggestions.Hour?) -> String {
        var parts = ["\(hour) Uhr", "Profil \(BIOSFormat.number(scheduled, digits: 2)) IE pro Stunde"]
        if let delivered {
            parts.append("abgegeben im Mittel \(BIOSFormat.number(delivered.mean, digits: 2))")
        }
        if let suggestion, let proposed = suggestion.proposed {
            parts.append(suggestion.hasChange ? "Vorschlag \(BIOSFormat.number(proposed, digits: 2))" : "Vorschlag unverändert")
            if suggestion.hypo { parts.append("Unterzucker in dieser Stunde") }
            if suggestion.isLowConsistency { parts.append("wenig konsistent") }
        }
        return parts.joined(separator: ", ")
    }
}

struct ScheduleRow: View {
    let time: String
    let value: String

    var body: some View {
        HStack {
            Text(time)
                .monospacedDigit()
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CopyButton: View {
    let title: String
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
        } label: {
            Label(copied ? "Kopiert" : title, systemImage: copied ? "checkmark" : "doc.on.doc")
        }
    }
}

// MARK: - Texts

enum TherapyText {
    /// Delivered vs scheduled: arrow only from 10 % difference, else "≈".
    static func difference(_ delivered: Double?, _ scheduled: Double?) -> (symbol: String, pct: Double)? {
        guard let delivered, let scheduled, scheduled > 0 else { return nil }
        let pct = (delivered - scheduled) / scheduled * 100
        if abs(pct) < 10 { return ("equal", pct) }
        return (pct > 0 ? "arrow.up.right" : "arrow.down.right", pct)
    }

    static func target(_ entry: TherapyScheduleEntry) -> String {
        if let low = entry.low, let high = entry.high {
            return low == high ? "\(BIOSFormat.number(low)) mg/dL" : "\(BIOSFormat.number(low)) bis \(BIOSFormat.number(high)) mg/dL"
        }
        return "\(BIOSFormat.number(entry.value ?? entry.low ?? entry.high)) mg/dL"
    }

    private static func today() -> String {
        let now = Date()
        return "\(BIOSFormat.shortDate(now))\(Calendar.current.component(.year, from: now))"
    }

    /// Proposed blocks in Loop format, always with status and disclaimer.
    static func proposal(_ model: TherapyModel, _ suggestions: TherapySuggestions) -> String {
        var lines = ["Vorschlag Basalrate (BIOS, \(today()))"]
        if suggestions.recommended {
            lines.append("Status: zur Übernahme empfohlen")
        } else if suggestions.noChangeNeeded {
            lines.append("Status: \(suggestions.statusText) (Profil unverändert lassen)")
        } else {
            lines.append("!!! NICHT ZUR ÜBERNAHME EMPFOHLEN !!!")
            lines.append(suggestions.statusText)
        }
        for reason in suggestions.reasons { lines.append("- \(reason)") }
        if let window = suggestions.windowText {
            lines.append("Fenster \(window)" + (suggestions.cleanText.map { ", \($0)" } ?? ""))
        }
        lines.append("")
        var blocks = suggestions.blocks
        if blocks.isEmpty {
            // No blocks from the server: join equal proposed hours.
            var last: Double?
            for hour in suggestions.hours {
                guard let proposed = hour.proposed else { continue }
                if proposed != last {
                    blocks.append(TherapyScheduleEntry(id: blocks.count, minute: hour.hour * 60, value: proposed))
                    last = proposed
                }
            }
        }
        for block in blocks {
            lines.append("\(block.timeText) \(BIOSFormat.number(block.value, digits: 2)) IE/Std")
        }
        if let old = suggestions.totalOld, let new = suggestions.totalNew {
            lines.append("Summe \(BIOSFormat.number(old, digits: 2)) → \(BIOSFormat.number(new, digits: 2)) IE/Tag"
                + (suggestions.totalChangePct.map { " (\(BIOSFormat.signed($0, digits: 1)) %)" } ?? ""))
        } else if let total = TherapyScheduleEntry.dailyTotal(blocks) {
            lines.append("Summe \(BIOSFormat.number(total, digits: 2)) IE/Tag")
        }
        lines.append("")
        lines.append(suggestions.disclaimer ?? "Nur Beobachtung, Anpassungen mit Arzt besprechen und in Loop selbst eintragen.")
        return lines.joined(separator: "\n")
    }

    /// Current settings as plain text (Loop units).
    static func settings(_ model: TherapyModel) -> String {
        var lines = ["Loop-Einstellungen (BIOS, \(today()))"]
        func section(_ title: String, _ rows: [String]) {
            guard !rows.isEmpty else { return }
            lines.append("")
            lines.append(title)
            lines.append(contentsOf: rows)
        }
        section("Basalrate", model.basal.map { "\($0.timeText) \(BIOSFormat.number($0.value, digits: 2)) IE/Std" }
            + (model.basalTotal.map { ["Summe \(BIOSFormat.number($0, digits: 2)) IE/Tag"] } ?? []))
        section("KH-Verhältnis", model.carbRatio.map { "\($0.timeText) \(BIOSFormat.number($0.value, digits: 1)) g/IE" })
        section("Insulinempfindlichkeit", model.sensitivity.map { "\($0.timeText) \(BIOSFormat.number($0.value)) mg/dL/IE" })
        section("Zielbereich", model.targets.map { "\($0.timeText) \(target($0))" })
        var limits: [String] = []
        if let maxBasal = model.maxBasal { limits.append("Max. Basalrate \(BIOSFormat.number(maxBasal, digits: 2)) IE/Std") }
        if let maxBolus = model.maxBolus { limits.append("Max. Bolus \(BIOSFormat.number(maxBolus, digits: 1)) IE") }
        section("Abgabelimits", limits)
        if let active = model.activeOverride {
            section("Aktiver Override", [active.bannerText])
        }
        section("Override-Vorlagen", model.overrides.map { preset in
            ([preset.symbol, preset.name].compactMap { $0 }.joined(separator: " "))
                + (preset.detailText.isEmpty ? "" : ": \(preset.detailText)")
        })
        lines.append("")
        lines.append("Nur Beobachtung, Anpassungen mit Arzt besprechen und in Loop selbst eintragen.")
        return lines.joined(separator: "\n")
    }
}
