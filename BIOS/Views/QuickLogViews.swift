import SwiftUI

/// Where the "+" sheet opens.
enum QuickLogTarget: String, Identifiable {
    case menu
    case alcohol
    case supplements
    case medications
    case temperature
    case bloodPressure

    var id: String { rawValue }
}

/// Sheet behind the "+" button on Heute (and the status rows).
struct QuickLogSheet: View {
    let start: QuickLogTarget
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch start {
                case .menu: QuickLogMenu()
                case .alcohol: AlcoholQuickView()
                case .supplements: SupplementTodayView()
                case .medications: MedicationLogView()
                case .temperature: TemperatureLogView()
                case .bloodPressure: BloodPressureLogView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents(start == .menu ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
    }
}

struct QuickLogMenu: View {
    @EnvironmentObject var events: EventStore
    @EnvironmentObject var supplements: SupplementStore
    @EnvironmentObject var medications: MedicationStore
    @EnvironmentObject var plan: MedicationPlanStore
    @EnvironmentObject var vitals: VitalsStore

    var body: some View {
        let today = EventStore.dayString(Date())
        let count = supplements.takenCount(on: today)
        let planProgress = plan.progress(on: today)
        List {
            NavigationLink {
                AlcoholQuickView()
            } label: {
                QuickLogMenuRow(
                    symbol: "wineglass",
                    color: BIOSTheme.context,
                    title: "Alkohol",
                    subtitle: events.isMarked(today) ? "heute eingetragen" : "heute kein Eintrag"
                )
            }
            NavigationLink {
                SupplementTodayView()
            } label: {
                QuickLogMenuRow(
                    symbol: "pills",
                    color: BIOSTheme.good,
                    title: "Supplements",
                    subtitle: count.total == 0 ? "keine Präparate" : "heute \(count.taken) von \(count.total)"
                )
            }
            NavigationLink {
                MedicationLogView()
            } label: {
                QuickLogMenuRow(
                    symbol: "cross.case",
                    color: BIOSTheme.insulin,
                    title: "Medikamente",
                    subtitle: planProgress.total > 0
                        ? "Plan heute \(planProgress.taken) von \(planProgress.total)"
                        : (medications.count(on: today) == 0 ? "heute kein Eintrag" : "heute \(medications.count(on: today)) Einträge")
                )
            }
            NavigationLink {
                TemperatureLogView()
            } label: {
                QuickLogMenuRow(
                    symbol: "thermometer",
                    color: BIOSTheme.skin,
                    title: "Temperatur",
                    subtitle: vitals.latest(VitalReading.temperature).map { reading in
                        "zuletzt \(reading.valueText), \(reading.date.map { BIOSFormat.relative($0) } ?? reading.measuredAt)"
                    } ?? "noch kein Eintrag"
                )
            }
            NavigationLink {
                BloodPressureLogView()
            } label: {
                QuickLogMenuRow(
                    symbol: "heart.text.square",
                    color: BIOSTheme.rhr,
                    title: "Blutdruck",
                    subtitle: vitals.latest(VitalReading.bloodPressure).map { reading in
                        "zuletzt \(reading.valueText), \(reading.date.map { BIOSFormat.relative($0) } ?? reading.measuredAt)"
                    } ?? "Sys, Dia, Puls"
                )
            }
        }
        .navigationTitle("Eintragen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct QuickLogMenuRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Alkohol

struct AlcoholQuickView: View {
    @EnvironmentObject var events: EventStore

    var body: some View {
        let now = Date()
        let today = EventStore.dayString(now)
        let yesterday = EventStore.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        List {
            Section {
                AlcoholDayButton(title: "Heute", day: today)
                    .listRowBackground(Color.clear)
                AlcoholDayButton(title: "Gestern", day: yesterday)
                    .listRowBackground(Color.clear)
            } footer: {
                Text(events.hasPending ? "Wartet auf Verbindung, wird nachgereicht." : "Kontext für den Infekt-Check. Siri: \"Alkohol in BIOS\".")
            }
            Section {
                NavigationLink {
                    AlcoholCalendarView()
                        .navigationTitle("Alkohol-Tage")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("Kalender, rückwirkend markieren", systemImage: "calendar")
                }
            }
        }
        .navigationTitle("Alkohol")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Supplements

struct SupplementTodayView: View {
    @EnvironmentObject var store: SupplementStore
    @State private var dayOffset = 0
    @State private var message: String?

    var body: some View {
        let day = SupplementTodayView.day(offset: dayOffset)
        let items = store.activeItems(on: day)
        let complete = store.isComplete(on: day)
        let count = store.takenCount(on: day)
        List {
            Section {
                Picker("Tag", selection: $dayOffset) {
                    Text("Heute").tag(0)
                    Text("Gestern").tag(-1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Button {
                    Task { @MainActor in
                        let outcome = await store.setAll(on: day, taken: !complete)
                        message = SupplementTodayView.message(outcome, done: !complete)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: complete ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(complete ? "Alle genommen" : "Alle genommen eintragen")
                                .font(.headline)
                            Text(complete ? "Tippen setzt zurück" : "\(count.taken) von \(count.total) eingetragen")
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(complete ? BIOSTheme.good : BIOSTheme.text1)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(complete ? BIOSTheme.good.opacity(0.16) : BIOSTheme.card2)
                    )
                }
                .buttonStyle(CardButtonStyle())
                .listRowBackground(Color.clear)
                .accessibilityLabel(complete ? "Alle Supplements genommen" : "Alle Supplements als genommen eintragen")
                .accessibilityValue("\(count.taken) von \(count.total)")
            } footer: {
                if let message {
                    Text(message)
                } else if store.hasPending {
                    Text("Wartet auf Verbindung, wird nachgereicht.")
                }
            }

            Section {
                if items.isEmpty {
                    Text(store.allItems.isEmpty ? "Noch keine Präparate. Unter Bearbeiten anlegen." : "Keine aktiven Präparate an diesem Tag.")
                        .foregroundStyle(BIOSTheme.text2)
                }
                ForEach(items) { item in
                    let taken = store.isTaken(item, on: day)
                    Button {
                        Task { @MainActor in
                            let outcome = await store.setTaken(item, on: day, taken: !taken)
                            message = SupplementTodayView.message(outcome, done: !taken)
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
            } header: {
                Text("Präparate")
            }

            Section {
                NavigationLink {
                    SupplementHistoryView()
                } label: {
                    Label("Verlauf", systemImage: "calendar")
                }
                NavigationLink {
                    SupplementEditView()
                } label: {
                    Label("Präparate bearbeiten", systemImage: "pencil")
                }
            }
        }
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.flush()
            await store.refresh()
        }
        .refreshable {
            await store.flush()
            await store.refresh()
        }
    }

    static func day(offset: Int) -> String {
        EventStore.dayString(Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date())
    }

    static func message(_ outcome: EventStore.Outcome, done: Bool) -> String {
        switch outcome {
        case .synced: return done ? "Eingetragen." : "Zurückgesetzt."
        case .queued: return "Gespeichert, wird nachgereicht (keine Verbindung)."
        case .failed(let text): return "Nicht gespeichert: \(text)"
        }
    }
}

/// Last 6 months: filled check = all taken, ring = partly, nothing = none.
struct SupplementHistoryView: View {
    @EnvironmentObject var store: SupplementStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StatItem(label: "Serie", value: "\(streak)", unit: "Tage")
                    StatItem(label: "letzte 30 Tage", value: "\(completeDays(30))", unit: "komplett")
                }
                .biosCard()
                ForEach(AlcoholCalendarView.months(count: 6), id: \.self) { month in
                    IntakeMonthGrid(month: month)
                }
                LegendView(items: [
                    LegendItem(color: BIOSTheme.good, text: "alle genommen", mark: .dot),
                    LegendItem(color: BIOSTheme.mid, text: "teilweise", mark: .box, opacity: 0.6),
                ])
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .biosPageBackground()
        .navigationTitle("Verlauf")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh(days: 190)
        }
    }

    private var streak: Int {
        if let streak = store.dashboardIntake?.streakDays { return streak }
        var count = 0
        for offset in 0..<400 {
            let day = SupplementTodayView.day(offset: -offset)
            if store.isComplete(on: day) {
                count += 1
            } else if offset > 0 {
                break
            }
        }
        return count
    }

    private func completeDays(_ days: Int) -> Int {
        (0..<days).filter { store.isComplete(on: SupplementTodayView.day(offset: -$0)) }.count
    }
}

struct IntakeMonthGrid: View {
    @EnvironmentObject var store: SupplementStore
    let month: Date

    var body: some View {
        let cells = MonthGrid.cells(for: month)
        let today = EventStore.dayString(Date())
        VStack(alignment: .leading, spacing: 8) {
            Text("\(BIOSFormat.monthsLong[max(0, min(11, Calendar.current.component(.month, from: month) - 1))]) \(Calendar.current.component(.year, from: month))")
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { name in
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(BIOSTheme.text3)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(cells) { cell in
                    if let date = cell.date {
                        let day = EventStore.dayString(date)
                        let complete = store.isComplete(on: day)
                        let partial = !complete && store.hasAnyIntake(on: day)
                        VStack(spacing: 2) {
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(day > today ? BIOSTheme.text3.opacity(0.5) : BIOSTheme.text1)
                            Image(systemName: complete ? "checkmark.circle.fill" : (partial ? "circle.lefthalf.filled" : "circle"))
                                .font(.caption2)
                                .foregroundStyle(complete ? BIOSTheme.good : (partial ? BIOSTheme.mid : BIOSTheme.text3.opacity(0.3)))
                        }
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(Calendar.current.component(.day, from: date)).")
                        .accessibilityValue(complete ? "alle genommen" : (partial ? "teilweise" : "nichts eingetragen"))
                    } else {
                        Color.clear.frame(height: 36).accessibilityHidden(true)
                    }
                }
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }
}

/// Add, change and remove items; saved with PUT (the server keeps history).
struct SupplementEditView: View {
    @EnvironmentObject var store: SupplementStore
    @Environment(\.dismiss) var dismiss
    @State private var draft: [SupplementItem] = []
    @State private var loaded = false
    @State private var saving = false

    var body: some View {
        List {
            Section {
                ForEach($draft) { $item in
                    NavigationLink {
                        SupplementItemForm(item: $item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "Ohne Namen" : item.name)
                                .font(.body.weight(.semibold))
                            let detail = [item.brand, item.doseText.isEmpty ? nil : item.doseText].compactMap { $0 }.joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(detail)
                                    .font(.footnote)
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                            if !item.isActive(on: EventStore.dayString(Date())) {
                                Text("nicht aktiv")
                                    .font(.caption)
                                    .foregroundStyle(BIOSTheme.text3)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    draft.remove(atOffsets: offsets)
                }
                Button {
                    var item = SupplementItem(name: "")
                    item.activeFrom = EventStore.dayString(Date())
                    draft.append(item)
                } label: {
                    Label("Präparat hinzufügen", systemImage: "plus.circle")
                }
            } footer: {
                Text("Wischen zum Entfernen. Änderungen gelten ab heute, der Server behält den Verlauf.")
            }
        }
        .navigationTitle("Präparate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Speichert ..." : "Sichern") {
                    saving = true
                    let cleaned = draft.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    Task { @MainActor in
                        await store.saveItems(cleaned)
                        saving = false
                        dismiss()
                    }
                }
                .disabled(saving)
            }
        }
        .onAppear {
            if !loaded {
                draft = store.allItems
                loaded = true
            }
        }
    }
}

struct SupplementItemForm: View {
    @Binding var item: SupplementItem
    @State private var amountText = ""
    @State private var perDayText = ""
    @State private var prepared = false

    init(item: Binding<SupplementItem>) {
        self._item = item
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $item.name)
                TextField("Marke", text: optional($item.brand))
            }
            Section {
                TextField("Menge", text: $amountText)
                    .keyboardType(.decimalPad)
                TextField("Einheit (mg, IE, Kapsel)", text: optional($item.unit))
                TextField("Pro Tag (1 bis 10)", text: $perDayText)
                    .keyboardType(.numberPad)
            } header: {
                Text("Dosis")
            }
            Section {
                Toggle("Aktiv ab", isOn: hasDate($item.activeFrom))
                if item.activeFrom != nil {
                    DatePicker("ab", selection: dateBinding($item.activeFrom), displayedComponents: .date)
                }
                Toggle("Enddatum", isOn: hasDate($item.activeTo))
                if item.activeTo != nil {
                    DatePicker("bis", selection: dateBinding($item.activeTo), displayedComponents: .date)
                }
            } header: {
                Text("Zeitraum")
            }
            Section {
                TextField("Notiz", text: optional($item.note), axis: .vertical)
            }
        }
        .navigationTitle(item.name.isEmpty ? "Neues Präparat" : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !prepared else { return }
            amountText = item.amount.map { SupplementItemForm.text($0) } ?? ""
            perDayText = item.perDay.map { SupplementItemForm.text($0) } ?? ""
            prepared = true
        }
        .onChange(of: amountText) { _, value in
            item.amount = SupplementItemForm.number(value)
        }
        .onChange(of: perDayText) { _, value in
            item.perDay = SupplementItemForm.number(value)
        }
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding<String>(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    private func hasDate(_ binding: Binding<String?>) -> Binding<Bool> {
        Binding<Bool>(
            get: { binding.wrappedValue != nil },
            set: { binding.wrappedValue = $0 ? EventStore.dayString(Date()) : nil }
        )
    }

    private func dateBinding(_ binding: Binding<String?>) -> Binding<Date> {
        Binding<Date>(
            get: { BIOSDate.day(binding.wrappedValue) ?? Date() },
            set: { binding.wrappedValue = EventStore.dayString($0) }
        )
    }

    static func text(_ value: Double) -> String {
        BIOSFormat.number(value, digits: value.rounded() == value ? 0 : 2)
    }

    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}

// MARK: - Medikamente

struct MedicationLogView: View {
    @EnvironmentObject var store: MedicationStore
    @EnvironmentObject var plan: MedicationPlanStore
    @State private var name = ""
    @State private var dose = ""
    @State private var note = ""
    @State private var takenAt = Date()
    @State private var message: String?

    var body: some View {
        let recent = Array(store.entries.prefix(50))
        let today = EventStore.dayString(Date())
        let planItems = plan.activeItems(on: today)
        List {
            Section {
                if planItems.isEmpty {
                    Text(plan.allItems.isEmpty ? "Noch kein Plan. Unter Plan bearbeiten anlegen." : "Heute nichts geplant.")
                        .foregroundStyle(BIOSTheme.text2)
                }
                ForEach(planItems) { item in
                    PlanItemRow(item: item, day: today) { outcome in
                        message = SupplementTodayView.message(outcome, done: true)
                    }
                }
                NavigationLink {
                    MedicationPlanEditView()
                } label: {
                    Label("Plan bearbeiten", systemImage: "pencil")
                }
            } header: {
                Text("Plan heute")
            } footer: {
                Text("Tippen trägt eine Einnahme jetzt ein. Siri: \"<Name> in BIOS\".")
            }

            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                if !store.recentNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.recentNames, id: \.self) { suggestion in
                                Button(suggestion) {
                                    name = suggestion
                                }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                            }
                        }
                    }
                }
                TextField("Dosis (optional)", text: $dose)
                DatePicker("Zeit", selection: $takenAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("Notiz (optional)", text: $note)
                Button {
                    let entryName = name.trimmingCharacters(in: .whitespaces)
                    let entryDose = dose.trimmingCharacters(in: .whitespaces)
                    let entryNote = note.trimmingCharacters(in: .whitespaces)
                    let at = takenAt
                    Task { @MainActor in
                        let outcome = await store.add(
                            name: entryName,
                            dose: entryDose.isEmpty ? nil : entryDose,
                            note: entryNote.isEmpty ? nil : entryNote,
                            at: at
                        )
                        message = SupplementTodayView.message(outcome, done: true)
                        name = ""
                        dose = ""
                        note = ""
                        takenAt = Date()
                    }
                } label: {
                    Label("Eintragen", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Freier Eintrag")
            } footer: {
                if let message {
                    Text(message)
                } else if store.hasPending {
                    Text("Wartet auf Verbindung, wird nachgereicht.")
                }
            }

            Section {
                if recent.isEmpty {
                    Text("Noch keine Einträge")
                        .foregroundStyle(BIOSTheme.text2)
                }
                ForEach(recent) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name + (entry.dose.map { " · \($0)" } ?? ""))
                                .font(.body.weight(.semibold))
                            if let note = entry.note {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(BIOSTheme.text3)
                            }
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(entry.date.map { BIOSFormat.relative($0) } ?? entry.takenAt)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text2)
                            if store.isPending(entry) {
                                Label("wartet", systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(BIOSTheme.text3)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    for index in offsets where index < recent.count {
                        store.delete(recent[index])
                    }
                }
            } header: {
                Text("Letzte Einträge")
            } footer: {
                Text("Wischen zum Löschen. Nur Protokoll, keine Dosierungshinweise.")
            }
        }
        .navigationTitle("Medikamente")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.flush()
            await store.refresh()
            await plan.flush()
            await plan.refresh()
        }
    }
}

// MARK: - Heute: slim status card

/// Replaces the big alcohol card: alcohol today/yesterday toggles,
/// supplements x/y, medications today; rows open the quick-log sheet.
struct QuickStatusCard: View {
    @EnvironmentObject var events: EventStore
    @EnvironmentObject var supplements: SupplementStore
    @EnvironmentObject var medications: MedicationStore
    @EnvironmentObject var plan: MedicationPlanStore
    let open: (QuickLogTarget) -> Void

    var body: some View {
        let now = Date()
        let today = EventStore.dayString(now)
        let yesterday = EventStore.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label("Alkohol", systemImage: "wineglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.context)
                Spacer(minLength: 4)
                SlimToggle(title: "Heute", on: events.isMarked(today)) { events.toggle(today) }
                SlimToggle(title: "Gestern", on: events.isMarked(yesterday)) { events.toggle(yesterday) }
                NavigationLink(value: DetailRoute.alkohol) {
                    Image(systemName: "calendar")
                        .foregroundStyle(BIOSTheme.accent)
                }
                .accessibilityLabel("Alkohol-Kalender")
            }
            .padding(.vertical, 8)

            Divider().overlay(BIOSTheme.separator)

            Button {
                open(.supplements)
            } label: {
                statusRow(
                    symbol: "pills",
                    color: BIOSTheme.good,
                    title: "Supplements",
                    value: supplementText(today),
                    done: supplementDone(today)
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(BIOSTheme.separator)

            Button {
                open(.medications)
            } label: {
                statusRow(
                    symbol: "cross.case",
                    color: BIOSTheme.insulin,
                    title: "Medikamente",
                    value: medicationText(today),
                    done: false
                )
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(BIOSTheme.text1)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func statusRow(symbol: String, color: Color, title: String, value: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BIOSTheme.good)
            }
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text2)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BIOSTheme.text3)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)\(done ? ", vollständig" : "")")
    }

    private func supplementText(_ today: String) -> String {
        let count = supplements.takenCount(on: today)
        if count.total > 0 { return "heute \(count.taken)/\(count.total)" }
        if let intake = supplements.dashboardIntake, let taken = intake.taken, let total = intake.total, total > 0 {
            return "heute \(taken)/\(total)"
        }
        return "eintragen"
    }

    private func supplementDone(_ today: String) -> Bool {
        if supplements.takenCount(on: today).total > 0 { return supplements.isComplete(on: today) }
        return supplements.dashboardIntake?.complete ?? false
    }

    private func medicationText(_ today: String) -> String {
        let progress = plan.progress(on: today)
        if progress.total > 0 {
            return "heute \(progress.taken)/\(progress.total)"
        }
        let local = medications.count(on: today)
        let count = Swift.max(local, supplements.dashboardIntake?.medicationsToday ?? 0)
        return count == 0 ? "heute keine" : "heute \(count)"
    }
}

/// Small capsule toggle: symbol + word carry the state.
struct SlimToggle: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(on ? BIOSTheme.contextText : BIOSTheme.text2)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(on ? BIOSTheme.context.opacity(0.22) : BIOSTheme.card2))
            .overlay(Capsule().strokeBorder(on ? BIOSTheme.context.opacity(0.5) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Alkohol \(title)")
        .accessibilityValue(on ? "eingetragen" : "kein Eintrag")
    }
}
