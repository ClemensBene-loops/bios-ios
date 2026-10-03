import SwiftUI

// Backfill one past day (Verlauf > tap a day): supplements and medication plan
// of the regimen that was valid on that day (GET /v1/intake/day), with the same
// tick UI as today. Writes go through the existing queues: POST /v1/intake with
// that `date`, POST /v1/medications with `taken_at` on that day; the server
// validates both against the plan version of that day.

/// Loads the day's own regimen; nil lists = not loaded (offline or an older
/// server without the endpoint), the view then falls back to the current plan.
@MainActor
final class IntakeDayModel: ObservableObject {
    let day: String
    @Published private(set) var supplements: [SupplementItem]?
    @Published private(set) var planItems: [MedicationPlanItem]?
    @Published private(set) var loadError: String?
    @Published private(set) var isLoading = false

    nonisolated init(day: String) {
        self.day = day
    }

    func load() async {
        let back = IntakeDayView.daysBack(day) ?? 0
        // Plan counters count the medication list: make it cover this day.
        MedicationStore.shared.widen(to: back + 1)
        await SupplementStore.shared.flush()
        await MedicationStore.shared.flush()
        await MedicationStore.shared.refresh()
        guard let client = APIClient.fromConfig() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let json = try await client.fetchIntakeDay(date: day) else { return }
            let supp = json.obj("supplements")
            let rows = supp?.list("items") ?? []
            supplements = rows.compactMap { SupplementItem(json: $0) }
            var map: [String: Bool] = [:]
            for row in rows {
                if let id = LogQueue.idString(row["id"]) {
                    map[id] = row.flag("taken")
                }
            }
            SupplementStore.shared.mergeDay(day, map)
            planItems = (json.obj("medication_plan")?.list("items") ?? []).compactMap { MedicationPlanItem(json: $0) }
            loadError = nil
        } catch {
            if !ErrorKind.isCancellation(error) {
                loadError = ErrorKind.isOffline(error) ? "Keine Verbindung, zeigt den aktuellen Plan." : error.localizedDescription
            }
        }
    }
}

struct IntakeDayView: View {
    /// The app offers backfill up to this many days back (the server accepts 399).
    static let maxDaysBack = 60

    @EnvironmentObject var supplements: SupplementStore
    @EnvironmentObject var plan: MedicationPlanStore
    @EnvironmentObject var medications: MedicationStore
    @StateObject private var model: IntakeDayModel
    @State private var message: String?
    @State private var planMessage: String?
    @State private var changed = false

    init(day: String) {
        _model = StateObject(wrappedValue: IntakeDayModel(day: day))
    }

    var body: some View {
        let day = model.day
        let items = model.supplements ?? supplements.activeItems(on: day)
        let planItems = model.planItems ?? plan.activeItems(on: day)
        let taken = items.filter { supplements.isTaken($0, on: day) }.count
        let complete = !items.isEmpty && taken == items.count
        let entries = medications.dayEntries(day)
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.title(day))
                        .font(.title3.weight(.bold))
                    Text(Self.subtitle(day))
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .listRowBackground(Color.clear)
            } footer: {
                if let error = model.loadError {
                    Text(error)
                }
            }

            Section {
                if items.isEmpty {
                    Text(model.isLoading ? "Lädt …" : "An diesem Tag keine Präparate im Plan.")
                        .foregroundStyle(BIOSTheme.text2)
                } else {
                    Button {
                        Task { @MainActor in
                            let outcome = await supplements.setAll(on: day, taken: !complete)
                            message = SupplementTodayView.message(outcome, done: !complete)
                            changed = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: complete ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.title3)
                            Text(complete ? "Alle genommen (tippen setzt zurück)" : "Alle genommen eintragen")
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 0)
                            Text("\(taken)/\(items.count)")
                                .font(.headline)
                                .monospacedDigit()
                        }
                        .foregroundStyle(complete ? BIOSTheme.good : BIOSTheme.text1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(complete ? "Alle Supplements genommen" : "Alle Supplements als genommen eintragen")
                    .accessibilityValue("\(taken) von \(items.count)")
                }
                ForEach(items) { item in
                    SupplementTickRow(item: item, day: day) { outcome, done in
                        message = SupplementTodayView.message(outcome, done: done)
                        changed = true
                    }
                }
            } header: {
                Text("Supplements")
            } footer: {
                if let message {
                    Text(message)
                } else if supplements.hasPending {
                    Text("Wartet auf Verbindung, wird nachgereicht.")
                }
            }

            Section {
                if planItems.isEmpty {
                    Text(model.isLoading ? "Lädt …" : "An diesem Tag nichts im Medikamentenplan.")
                        .foregroundStyle(BIOSTheme.text2)
                }
                ForEach(planItems) { item in
                    PlanItemRow(item: item, day: day, time: { plan.defaultTime(for: item, on: day) }) { outcome in
                        planMessage = SupplementTodayView.message(outcome, done: true)
                        changed = true
                    }
                }
            } header: {
                Text("Medikamentenplan")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let planMessage {
                        Text(planMessage)
                    }
                    Text("+ trägt eine Einnahme zur nächsten offenen Planzeit dieses Tages ein, − entfernt die letzte.")
                }
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.name + (entry.dose.map { " · \($0)" } ?? ""))
                                .font(.body)
                            Spacer(minLength: 8)
                            Text(String(entry.takenAt.suffix(5)))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        for index in offsets where index < entries.count {
                            medications.delete(entries[index])
                        }
                        changed = true
                    }
                } header: {
                    Text("Einträge an diesem Tag")
                } footer: {
                    Text("Wischen zum Löschen. Nur Protokoll, keine Dosierungshinweise.")
                }
            }
        }
        .navigationTitle(Self.navigationTitle(day))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
        }
        .refreshable {
            await model.load()
        }
        .onDisappear {
            guard changed else { return }
            // Score (Therapie) and the Routine card read past days too.
            Task { await DashboardStore.shared.refresh(force: true) }
        }
    }

    // MARK: Days

    /// Whole days from `day` back to today; nil for an unreadable day.
    static func daysBack(_ day: String, now: Date = Date()) -> Int? {
        guard let start = MedicationPlanStore.startOfDay(day) else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day
    }

    /// Today and the last `maxDaysBack` days, never the future.
    static func isEditable(_ day: String, now: Date = Date()) -> Bool {
        guard let back = daysBack(day, now: now) else { return false }
        return back >= 0 && back <= maxDaysBack
    }

    /// "Donnerstag, 1. Oktober 2026"
    static func title(_ day: String) -> String {
        guard let date = MedicationPlanStore.startOfDay(day) else { return day }
        return "\(BIOSFormat.longDay(date)) \(Calendar.current.component(.year, from: date))"
    }

    /// "Heute", "Gestern" or "Nachtrag, vor 2 Tagen".
    static func subtitle(_ day: String) -> String {
        switch daysBack(day) ?? 0 {
        case ...0: return "Heute"
        case 1: return "Gestern · Plan dieses Tages"
        case let n: return "Nachtrag · vor \(n) Tagen · Plan dieses Tages"
        }
    }

    static func navigationTitle(_ day: String) -> String {
        switch daysBack(day) ?? 0 {
        case ...0: return "Heute"
        case 1: return "Gestern"
        default:
            guard let date = MedicationPlanStore.startOfDay(day) else { return day }
            return BIOSFormat.dayLabel(date)
        }
    }
}

/// One supplement with its tick for `day` (today view and backfill view).
struct SupplementTickRow: View {
    @EnvironmentObject var store: SupplementStore
    let item: SupplementItem
    let day: String
    let onChange: (EventStore.Outcome, Bool) -> Void

    var body: some View {
        let taken = store.isTaken(item, on: day)
        Button {
            Task { @MainActor in
                let outcome = await store.setTaken(item, on: day, taken: !taken)
                onChange(outcome, !taken)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(taken ? BIOSTheme.good : BIOSTheme.text3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                    let detail = [item.brand, item.doseText.isEmpty ? nil : item.doseText]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    if let note = item.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(BIOSTheme.text1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityValue(taken ? "genommen" : "nicht genommen")
        .accessibilityHint("Doppeltippen zum Umschalten")
    }
}
