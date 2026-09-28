import SwiftUI

// Quick log part 2: medication plan (rows, edit screen), temperature and
// blood pressure entries (POST /v1/vitals). Display and protocol only: no
// dosing or therapy hints.

// MARK: - Medication plan

/// One plan item of the selected day: counter with − (removes the latest
/// intake of that day) and + (logs one at the given time), warning above per_day.
struct PlanItemRow: View {
    @EnvironmentObject var plan: MedicationPlanStore
    @EnvironmentObject var medications: MedicationStore
    let item: MedicationPlanItem
    /// Selected day "YYYY-MM-DD" (today or yesterday).
    let day: String
    /// Time of a new intake (now, plan time or the chosen time).
    let time: () -> Date
    let onChange: (EventStore.Outcome) -> Void

    @State private var busy = false

    var body: some View {
        let taken = plan.taken(item, on: day)
        let target = item.target
        let over = taken > target
        let done = taken == target
        let canRemove = item.serverID.map { medications.latest(planItemID: $0, on: day) != nil } ?? false
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                if !item.doseText.isEmpty {
                    Text(item.doseText)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
                Text(item.scheduleText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
                if over {
                    Label("\(taken - target) mehr als geplant", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BIOSTheme.midText)
                }
            }
            Spacer(minLength: 6)
            Button {
                change(add: false)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(canRemove ? BIOSTheme.text2 : BIOSTheme.text3.opacity(0.5))
            .disabled(!canRemove || busy)
            .accessibilityLabel("Eine Einnahme entfernen")

            Text("\(taken)/\(target)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(over ? BIOSTheme.midText : (done ? BIOSTheme.good : BIOSTheme.text1))
                .frame(minWidth: 40)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    Capsule().fill(over ? BIOSTheme.mid.opacity(0.16) : Color.clear)
                )

            Button {
                change(add: true)
            } label: {
                Image(systemName: over || done ? "plus.circle" : "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(item.serverID == nil ? BIOSTheme.text3 : BIOSTheme.accent)
            .disabled(item.serverID == nil || busy)
            .accessibilityLabel("Eine Einnahme eintragen")
        }
        .foregroundStyle(BIOSTheme.text1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
        .accessibilityValue("\(EventStore.dayLabel(day)) \(taken) von \(target)" + (over ? ", mehr als geplant" : ""))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(add: true)
            case .decrement: change(add: false)
            @unknown default: break
            }
        }
    }

    /// + logs one intake at `time()`, − removes the latest one of the day.
    /// Both update the counter at once (optimistic) and then reload the list
    /// and the dashboard, so the counter matches the list below.
    private func change(add: Bool) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            let outcome: EventStore.Outcome?
            if add {
                outcome = await plan.log(item, at: time())
            } else {
                outcome = await plan.unlog(item, on: day)
            }
            if let outcome {
                onChange(outcome)
                await medications.reloadAfterChange()
            }
        }
    }
}

/// Add, change and remove plan items; saved with PUT (the server keeps history).
struct MedicationPlanEditView: View {
    @EnvironmentObject var plan: MedicationPlanStore
    @Environment(\.dismiss) var dismiss
    @State private var draft: [MedicationPlanItem] = []
    @State private var loaded = false
    @State private var saving = false

    var body: some View {
        List {
            Section {
                ForEach($draft) { $item in
                    NavigationLink {
                        MedicationPlanItemForm(item: $item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name.isEmpty ? "Ohne Namen" : item.name)
                                .font(.body.weight(.semibold))
                            if !item.doseText.isEmpty {
                                Text(item.doseText)
                                    .font(.footnote)
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                            Text(item.scheduleText)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text3)
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
                    var item = MedicationPlanItem(name: "")
                    item.activeFrom = EventStore.dayString(Date())
                    draft.append(item)
                } label: {
                    Label("Medikament hinzufügen", systemImage: "plus.circle")
                }
            } footer: {
                Text("Wischen zum Entfernen. Änderungen gelten ab heute, der Server behält den Verlauf. Der Plan liegt nur am Server.")
            }
        }
        .navigationTitle("Medikamentenplan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saving ? "Speichert ..." : "Sichern") {
                    saving = true
                    let cleaned = draft.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                    Task { @MainActor in
                        await plan.saveItems(cleaned)
                        saving = false
                        dismiss()
                    }
                }
                .disabled(saving)
            }
        }
        .onAppear {
            if !loaded {
                draft = plan.allItems
                loaded = true
            }
        }
    }
}

struct MedicationPlanItemForm: View {
    @Binding var item: MedicationPlanItem

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $item.name)
                TextField("Form (Tablette, Inhalator)", text: FormBindings.optional($item.form))
            }
            Section {
                TextField("Dosis (z. B. 1 oder 2)", text: FormBindings.optional($item.dose))
                TextField("Einheit (Tablette, Hübe, mg)", text: FormBindings.optional($item.unit))
                Stepper(value: perDay, in: 1...12) {
                    Text("Ziel pro Tag: \(item.target)x")
                        .monospacedDigit()
                }
            } header: {
                Text("Dosis")
            } footer: {
                Text("Ohne eigenes Ziel zählt die Anzahl der Zeiten.")
            }
            Section {
                ForEach(item.times.indices, id: \.self) { index in
                    DatePicker("Zeit \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                }
                .onDelete { offsets in
                    item.times.remove(atOffsets: offsets)
                }
                Button {
                    item.times.append(item.times.isEmpty ? "08:00" : "20:00")
                } label: {
                    Label("Zeit hinzufügen", systemImage: "plus.circle")
                }
            } header: {
                Text("Zeiten")
            }
            Section {
                Toggle("Aktiv ab", isOn: FormBindings.hasDate($item.activeFrom))
                if item.activeFrom != nil {
                    DatePicker("ab", selection: FormBindings.dateBinding($item.activeFrom), displayedComponents: .date)
                }
                Toggle("Enddatum", isOn: FormBindings.hasDate($item.activeTo))
                if item.activeTo != nil {
                    DatePicker("bis", selection: FormBindings.dateBinding($item.activeTo), displayedComponents: .date)
                }
            } header: {
                Text("Zeitraum")
            }
            Section {
                TextField("Notiz", text: FormBindings.optional($item.note), axis: .vertical)
            }
        }
        .navigationTitle(item.name.isEmpty ? "Neues Medikament" : item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var perDay: Binding<Int> {
        Binding<Int>(
            get: { item.target },
            set: { item.perDay = $0 }
        )
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding<Date>(
            get: {
                guard index < item.times.count else { return Date() }
                return FormBindings.date(fromTime: item.times[index])
            },
            set: { value in
                guard index < item.times.count else { return }
                item.times[index] = FormBindings.time(from: value)
            }
        )
    }
}

/// Bindings shared by the edit forms.
enum FormBindings {
    static func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding<String>(
            get: { binding.wrappedValue ?? "" },
            set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }

    static func hasDate(_ binding: Binding<String?>) -> Binding<Bool> {
        Binding<Bool>(
            get: { binding.wrappedValue != nil },
            set: { binding.wrappedValue = $0 ? EventStore.dayString(Date()) : nil }
        )
    }

    static func dateBinding(_ binding: Binding<String?>) -> Binding<Date> {
        Binding<Date>(
            get: { BIOSDate.day(binding.wrappedValue) ?? Date() },
            set: { binding.wrappedValue = EventStore.dayString($0) }
        )
    }

    /// "08:30" -> today 08:30.
    static func date(fromTime text: String) -> Date {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: parts.first ?? 8, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()
        ) ?? Date()
    }

    static func time(from date: Date) -> String {
        BIOSFormat.time(date)
    }
}

// MARK: - Temperature

struct TemperatureLogView: View {
    @EnvironmentObject var store: VitalsStore
    /// Tenths of a degree (365 = 36,5 °C).
    @State private var tenths = 365
    @State private var measuredAt = Date()
    @State private var method = "infrarot"
    @State private var message: String?
    @State private var prepared = false
    @State private var saving = false

    var body: some View {
        let recent = store.recent(VitalReading.temperature)
        List {
            Section {
                Picker("Temperatur", selection: $tenths) {
                    ForEach(350...425, id: \.self) { value in
                        Text("\(BIOSFormat.number(Double(value) / 10, digits: 1)) °C")
                            .monospacedDigit()
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 150)
                DatePicker("Zeit", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Picker("Methode", selection: $method) {
                    ForEach(VitalsStore.methods, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Button {
                    save()
                } label: {
                    Label(saving ? "Speichert ..." : "Speichern", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .disabled(saving)
            } header: {
                Text("Neu")
            } footer: {
                if let message {
                    Text(message)
                } else if store.hasPending {
                    Text("Wartet auf Verbindung, wird nachgereicht.")
                } else {
                    Text("Kontext zum Infekt-Check (ab 37,5 °C als Hinweis), ändert keinen Alarm. Siri: \"Temperatur in BIOS\".")
                }
            }

            VitalsRecentSection(title: "Letzte Messungen", readings: recent)
        }
        .navigationTitle("Temperatur")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !prepared else { return }
            method = store.lastMethod
            prepared = true
        }
        .task {
            await store.flush()
            await store.refresh()
        }
    }

    private func save() {
        saving = true
        let value = Double(tenths) / 10
        let at = measuredAt
        let chosen = method
        Task { @MainActor in
            let outcome = await store.addTemperature(value, method: chosen, at: at)
            message = VitalsRecentSection.message(outcome, text: "\(BIOSFormat.number(value, digits: 1)) °C")
            measuredAt = Date()
            saving = false
        }
    }
}

// MARK: - Blood pressure

struct BloodPressureLogView: View {
    @EnvironmentObject var store: VitalsStore
    @State private var sysText = ""
    @State private var diaText = ""
    @State private var pulseText = ""
    @State private var measuredAt = Date()
    @State private var message: String?
    @State private var saving = false

    var body: some View {
        let recent = store.recent(VitalReading.bloodPressure)
        let check = validation
        List {
            Section {
                LabeledContent("Systolisch") {
                    TextField("120", text: $sysText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                LabeledContent("Diastolisch") {
                    TextField("80", text: $diaText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                LabeledContent("Puls (optional)") {
                    TextField("70", text: $pulseText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                DatePicker("Zeit", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Button {
                    save()
                } label: {
                    Label(saving ? "Speichert ..." : "Speichern", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .disabled(saving || check.values == nil)
            } header: {
                Text("Neu, mmHg")
            } footer: {
                if let problem = check.problem {
                    Text(problem)
                } else if let message {
                    Text(message)
                } else if store.hasPending {
                    Text("Wartet auf Verbindung, wird nachgereicht.")
                } else {
                    Text("Wie zu Hause: morgens und abends je 3 Messungen im Abstand von 1 bis 2 Minuten, gezählt wird das Mittel aus Messung 2 und 3.")
                }
            }

            VitalsRecentSection(title: "Letzte Messungen aus der App", readings: recent)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Blutdruck")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.flush()
            await store.refresh()
        }
    }

    /// Parsed values within the server ranges (sys 60 to 260, dia 30 to 160 and
    /// below sys, pulse 25 to 250), or the problem as text.
    private var validation: (values: (sys: Int, dia: Int, pulse: Int?)?, problem: String?) {
        let sys = Int(sysText.trimmingCharacters(in: .whitespaces))
        let dia = Int(diaText.trimmingCharacters(in: .whitespaces))
        let pulseRaw = pulseText.trimmingCharacters(in: .whitespaces)
        let pulse = Int(pulseRaw)
        guard let sys, let dia else { return (nil, nil) }
        if !(60...260).contains(sys) { return (nil, "Systolisch zwischen 60 und 260.") }
        if !(30...160).contains(dia) { return (nil, "Diastolisch zwischen 30 und 160.") }
        if dia >= sys { return (nil, "Diastolisch muss unter systolisch liegen.") }
        if !pulseRaw.isEmpty {
            guard let pulse, (25...250).contains(pulse) else { return (nil, "Puls zwischen 25 und 250 oder leer lassen.") }
        }
        return ((sys, dia, pulse), nil)
    }

    private func save() {
        guard let values = validation.values else { return }
        saving = true
        let at = measuredAt
        Task { @MainActor in
            let outcome = await store.addBloodPressure(sys: values.sys, dia: values.dia, pulse: values.pulse, at: at)
            message = VitalsRecentSection.message(outcome, text: "\(values.sys)/\(values.dia)")
            sysText = ""
            diaText = ""
            pulseText = ""
            measuredAt = Date()
            saving = false
        }
    }
}

/// Recent app readings with swipe to delete.
struct VitalsRecentSection: View {
    @EnvironmentObject var store: VitalsStore
    let title: String
    let readings: [VitalReading]

    var body: some View {
        Section {
            if readings.isEmpty {
                Text("Noch keine Einträge")
                    .foregroundStyle(BIOSTheme.text2)
            }
            ForEach(readings) { reading in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.valueText)
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        if let method = reading.method {
                            Text(method)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(reading.date.map { BIOSFormat.relative($0) } ?? reading.measuredAt)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text2)
                        if store.isPending(reading) {
                            Label("wartet", systemImage: "clock")
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                for index in offsets where index < readings.count {
                    store.delete(readings[index])
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Wischen zum Löschen.")
        }
    }

    static func message(_ outcome: EventStore.Outcome, text: String) -> String {
        switch outcome {
        case .synced: return "\(text) gespeichert."
        case .queued: return "\(text) gespeichert, wird nachgereicht (keine Verbindung)."
        case .failed(let error): return "Nicht gespeichert: \(error)"
        }
    }
}
