import AppIntents
import Foundation

// Siri / Shortcuts. App Intents in the main app target need no extension,
// entitlement or Info.plist key; the phrases are registered by `BIOSShortcuts`
// at build time (App Intents metadata extraction). Apple requires the app name
// in every phrase and allows at most 10 App Shortcuts per app (9 used here).
// Supplements and medications are entities from the cached server lists; after
// a list loads, `BIOSShortcuts.updateAppShortcutParameters()` lets Siri learn
// the names (no names in code: the lists live only on the server).

// MARK: - Alcohol

/// Marks a day with alcohol (default today). Runs without opening the app.
struct LogAlcoholIntent: AppIntent {
    static let title: LocalizedStringResource = "Alkohol eintragen"

    @Parameter(title: "Tag")
    var date: Date?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await LogIntentRunner.markAlcohol(date ?? Date())
        return .result(dialog: "\(text)")
    }
}

/// Marks yesterday with alcohol (own intent, so Siri needs no follow-up question).
struct LogAlcoholYesterdayIntent: AppIntent {
    static let title: LocalizedStringResource = "Alkohol gestern eintragen"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let text = await LogIntentRunner.markAlcohol(yesterday)
        return .result(dialog: "\(text)")
    }
}

// MARK: - Supplements

struct SupplementEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Supplement"
    static var defaultQuery = SupplementQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Active supplements of today from the cached list (GET /v1/supplements).
struct SupplementQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [SupplementEntity.ID]) async throws -> [SupplementEntity] {
        await LogIntentRunner.supplementEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SupplementEntity] {
        await LogIntentRunner.supplementEntities()
    }

    func entities(matching string: String) async throws -> [SupplementEntity] {
        let needle = string.lowercased()
        return await LogIntentRunner.supplementEntities().filter { $0.name.lowercased().contains(needle) }
    }
}

/// Marks every active supplement as taken today.
struct SupplementsTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Supplements genommen"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await LogIntentRunner.allSupplements(taken: true)
        return .result(dialog: "\(text)")
    }
}

/// Removes every supplement tick of today ("Alle Supplements austragen").
/// Asks first ("3 Häkchen von heute entfernen?"), then says what it did.
struct SupplementsResetIntent: AppIntent {
    static let title: LocalizedStringResource = "Alle Supplements austragen"
    static let description = IntentDescription("Entfernt alle Supplement-Häkchen von heute.")

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = await LogIntentRunner.supplementTicksToday()
        if count == 0 {
            return .result(dialog: "Heute ist in BIOS kein Supplement abgehakt.")
        }
        let question: IntentDialog = count == 1
            ? "1 Häkchen von heute entfernen?"
            : "\(count) Häkchen von heute entfernen?"
        try await requestConfirmation(result: .result(dialog: question), confirmationActionName: .go)
        let text = await LogIntentRunner.clearSupplements(count: count)
        return .result(dialog: "\(text)")
    }
}

/// Marks one supplement as taken today.
struct SupplementTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Supplement genommen"

    @Parameter(title: "Supplement")
    var supplement: SupplementEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await LogIntentRunner.supplement(id: supplement.id, name: supplement.name, taken: true)
        return .result(dialog: "\(text)")
    }
}

/// Un-marks one supplement of today.
struct SupplementResetIntent: AppIntent {
    static let title: LocalizedStringResource = "Supplement zurücksetzen"

    @Parameter(title: "Supplement")
    var supplement: SupplementEntity

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await LogIntentRunner.supplement(id: supplement.id, name: supplement.name, taken: false)
        return .result(dialog: "\(text)")
    }
}

// MARK: - Medications (plan)

struct MedicationEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Medikament"
    static var defaultQuery = MedicationQuery()

    let id: String
    let name: String
    /// Synonyms from the server (`aliases`): Siri accepts each of them for the
    /// entity parameter, so "Asthma-Spray genommen in BIOS" finds the inhaler.
    var aliases: [String] = []

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: nil,
            image: nil,
            synonyms: aliases.map { alias -> LocalizedStringResource in "\(alias)" }
        )
    }

    /// True when `text` names this item: name or a synonym, ignoring case,
    /// accents, hyphens and spaces ("Asthmaspray" = "Asthma-Spray").
    func matches(_ text: String) -> Bool {
        let needle = Self.fold(text)
        guard !needle.isEmpty else { return false }
        return ([name] + aliases).contains { candidate in
            let folded = Self.fold(candidate)
            guard !folded.isEmpty else { return false }
            // "Inhalator" finds "Asthma-Inhalator"; a spoken sentence around a
            // name ("mein Inhalator") still matches when the name has >= 4 letters.
            return folded == needle || folded.contains(needle) || (folded.count >= 4 && needle.contains(folded))
        }
    }

    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .filter { $0.isLetter || $0.isNumber }
    }
}

/// Active items of the medication plan (GET /v1/medication-plan, cached for
/// offline use), matched by name and synonyms.
struct MedicationQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [MedicationEntity.ID]) async throws -> [MedicationEntity] {
        await LogIntentRunner.medicationEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [MedicationEntity] {
        await LogIntentRunner.medicationEntities()
    }

    func entities(matching string: String) async throws -> [MedicationEntity] {
        await LogIntentRunner.medicationEntities().filter { $0.matches(string) }
    }
}

/// "<Medikament> genommen in BIOS": logs one intake now with the plan dose,
/// no follow-up questions, exactly like "+" in the app (with plan_item_id;
/// more than planned is logged too and said). Answer: "Eingetragen: X, heute 2 von 3."
struct MedicationTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Medikament jetzt genommen"
    static let description = IntentDescription("Trägt eine Einnahme aus dem Medikamentenplan jetzt ein, mit der Dosis aus dem Plan.")

    @Parameter(title: "Medikament")
    var medication: MedicationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$medication) jetzt genommen")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await LogIntentRunner.medicationNow(id: medication.id, name: medication.name)
        return .result(dialog: "\(text)")
    }
}

/// Logs one intake of a plan item. Siri asks "Wie viel?" (answer "normal" keeps
/// the plan dose) and "Wann?" ("jetzt", "um 8 Uhr", "vor einer Stunde").
struct LogMedicationIntent: AppIntent {
    static let title: LocalizedStringResource = "Medikament genommen"

    @Parameter(title: "Medikament")
    var medication: MedicationEntity

    @Parameter(title: "Menge", description: "Leer oder \"normal\" = Dosis aus dem Plan",
               requestValueDialog: IntentDialog("Wie viel? Sag „normal“ für die Dosis aus dem Plan."))
    var amount: String?

    @Parameter(title: "Zeit", description: "Leer = jetzt",
               requestValueDialog: IntentDialog("Wann? Zum Beispiel jetzt, um 8 Uhr oder vor einer Stunde."))
    var time: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$medication) \(\.$amount) um \(\.$time) eintragen")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var answer = amount
        if answer == nil {
            answer = try? await $amount.requestValue(
                IntentDialog("Wie viel? Sag „normal“ für die Dosis aus dem Plan.")
            )
        }
        var when = time
        if when == nil {
            when = try? await $time.requestValue(
                IntentDialog("Wann? Zum Beispiel jetzt, um 8 Uhr oder vor einer Stunde.")
            )
        }
        let text = await LogIntentRunner.medication(
            id: medication.id,
            name: medication.name,
            amount: SpokenInput.isDefaultAnswer(answer) ? nil : answer,
            at: LogIntentRunner.pastTime(when ?? Date())
        )
        return .result(dialog: "\(text)")
    }
}

// MARK: - Temperature

/// Body temperature now. The value is text: Siri does not turn a German
/// decimal comma ("36,6") into a Double and would ask again and again.
struct LogTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Temperatur eintragen"

    @Parameter(title: "Temperatur in °C", description: "z. B. 36,6",
               requestValueDialog: IntentDialog("Wie viel Grad? Zum Beispiel 36,6."))
    var value: String

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let celsius = SpokenInput.temperature(value) else {
            throw $value.needsValueError(
                IntentDialog("Das habe ich nicht als Temperatur verstanden. Bitte einen Wert zwischen 34 und 43 Grad, zum Beispiel 36,6.")
            )
        }
        let text = await LogIntentRunner.temperature(celsius)
        return .result(dialog: "\(text)")
    }
}

// MARK: - Runner (shared stores, offline safe)

enum LogIntentRunner {
    @MainActor
    static func supplementEntities() async -> [SupplementEntity] {
        let store = SupplementStore.shared
        if store.allItems.isEmpty {
            await store.refresh()
        }
        let today = EventStore.dayString(Date())
        return store.activeItems(on: today).compactMap { item in
            item.serverID.map { SupplementEntity(id: $0, name: item.name) }
        }
    }

    @MainActor
    static func medicationEntities() async -> [MedicationEntity] {
        let store = MedicationPlanStore.shared
        if store.allItems.isEmpty {
            await store.refresh()
        }
        let today = EventStore.dayString(Date())
        return store.activeItems(on: today).compactMap { item in
            item.serverID.map { MedicationEntity(id: $0, name: item.name, aliases: item.aliases ?? []) }
        }
    }

    @MainActor
    static func allSupplements(taken: Bool) async -> String {
        let outcome = await SupplementStore.shared.setAll(on: EventStore.dayString(Date()), taken: taken)
        switch outcome {
        case .synced:
            return taken ? "Alle Supplements für heute in BIOS eingetragen." : "Supplements für heute zurückgesetzt."
        case .queued:
            return "Keine Verbindung. BIOS trägt das nach, sobald die App wieder online ist."
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    @MainActor
    static func supplement(id: String, name: String, taken: Bool) async -> String {
        let store = SupplementStore.shared
        let day = EventStore.dayString(Date())
        var item = store.allItems.first(where: { $0.serverID == id }) ?? SupplementItem(name: name)
        item.serverID = id
        let outcome = await store.setTaken(item, on: day, taken: taken)
        switch outcome {
        case .synced:
            let count = store.takenCount(on: day)
            let progress = count.total > 0 ? " Heute \(count.taken) von \(count.total)." : ""
            return (taken ? "\(name) eingetragen." : "\(name) zurückgesetzt.") + progress
        case .queued:
            return "Keine Verbindung. BIOS trägt \(name) nach, sobald die App wieder online ist."
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    /// Supplement ticks of today, fresh from the server when online.
    @MainActor
    static func supplementTicksToday() async -> Int {
        let store = SupplementStore.shared
        await store.flush()
        await store.refresh()
        return store.takenCount(on: EventStore.dayString(Date())).taken
    }

    @MainActor
    static func clearSupplements(count: Int) async -> String {
        let outcome = await SupplementStore.shared.setAll(on: EventStore.dayString(Date()), taken: false)
        let what = count == 1 ? "1 Häkchen" : "\(count) Häkchen"
        switch outcome {
        case .synced:
            return "\(what) von heute entfernt."
        case .queued:
            return "\(what) entfernt. Keine Verbindung, BIOS trägt das nach, sobald die App wieder online ist."
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    /// One intake of a plan item now with the plan dose (Siri "X genommen").
    @MainActor
    static func medicationNow(id: String, name: String, now: Date = Date()) async -> String {
        let plan = MedicationPlanStore.shared
        let log = MedicationStore.shared
        // Fresh list first: the day count is then the server's (like the app counter).
        await log.flush()
        await log.refresh()
        let day = EventStore.dayString(now)
        var item = plan.allItems.first(where: { $0.serverID == id }) ?? MedicationPlanItem(name: name)
        item.serverID = id
        let outcome = await plan.log(item, at: now)
        switch outcome {
        case .synced, .queued:
            let taken = plan.taken(item, on: day)
            let target = item.target
            var text = "Eingetragen: \(item.name), heute \(taken) von \(target)"
            if taken > target {
                text += ", mehr als geplant"
            }
            text += "."
            if case .queued = outcome {
                text += " Keine Verbindung, wird nachgereicht, sobald BIOS online ist."
            }
            return text
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    /// A spoken time in the future ("um 20 Uhr" said in the morning) means the
    /// day before; the server rejects intakes more than 5 min ahead.
    static func pastTime(_ date: Date, now: Date = Date()) -> Date {
        if date > now.addingTimeInterval(5 * 60) {
            return Calendar.current.date(byAdding: .day, value: -1, to: date) ?? now
        }
        return date
    }

    @MainActor
    static func medication(id: String, name: String, amount: String? = nil, at date: Date = Date()) async -> String {
        let store = MedicationPlanStore.shared
        let day = EventStore.dayString(date)
        var item = store.allItems.first(where: { $0.serverID == id }) ?? MedicationPlanItem(name: name)
        item.serverID = id
        let dose = MedicationPlanItem.dose(amount, for: item)
        let outcome = await store.log(item, at: date, dose: dose)
        let calendar = Calendar.current
        var when = "um \(BIOSFormat.time(date))"
        if calendar.isDateInYesterday(date) {
            when = "gestern " + when
        } else if !calendar.isDateInToday(date) {
            when = "am \(BIOSFormat.shortDate(date)) " + when
        }
        let what = [name, dose].compactMap { $0 }.joined(separator: " ")
        switch outcome {
        case .synced, .queued:
            let taken = store.taken(item, on: day)
            let progress = calendar.isDateInToday(date) ? ", heute \(taken) von \(item.target)" : ""
            if case .queued = outcome {
                return "\(what) \(when) gespeichert\(progress). Wird nachgereicht, sobald BIOS online ist."
            }
            return "\(what) \(when) eingetragen\(progress)."
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    @MainActor
    static func temperature(_ celsius: Double) async -> String {
        let store = VitalsStore.shared
        let value = BIOSFormat.number(celsius, digits: 1)
        let outcome = await store.addTemperature(celsius, method: store.lastMethod)
        switch outcome {
        case .synced:
            return "\(value) °C gespeichert."
        case .queued:
            return "\(value) °C gespeichert, wird nachgereicht, sobald BIOS online ist."
        case .failed(let message):
            return "Nicht gespeichert: \(message)."
        }
    }

    /// Queues and sends the mark through the shared EventStore (offline safe),
    /// returns the German confirmation Siri speaks.
    @MainActor
    static func markAlcohol(_ date: Date) async -> String {
        let day = EventStore.dayString(date)
        let label = EventStore.dayLabel(day)
        let outcome = await EventStore.shared.set(day, marked: true)
        switch outcome {
        case .synced:
            return "Alkohol für \(label) in BIOS eingetragen."
        case .queued:
            return "Keine Verbindung. BIOS trägt Alkohol für \(label) nach, sobald die App wieder online ist."
        case .failed(let message):
            return "Nicht eingetragen: \(message)."
        }
    }
}

// MARK: - Phrases

struct BIOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogAlcoholIntent(),
            phrases: [
                "Alkohol in \(.applicationName)",
                "\(.applicationName) Alkohol",
                "\(.applicationName) heute Alkohol",
                "Alkohol in \(.applicationName) eintragen",
            ],
            shortTitle: "Alkohol eintragen",
            systemImageName: "wineglass"
        )
        AppShortcut(
            intent: LogAlcoholYesterdayIntent(),
            phrases: [
                "Gestern Alkohol in \(.applicationName)",
                "\(.applicationName) gestern Alkohol",
            ],
            shortTitle: "Alkohol gestern",
            systemImageName: "wineglass"
        )
        AppShortcut(
            intent: SupplementsTakenIntent(),
            phrases: [
                "Supplements genommen in \(.applicationName)",
                "\(.applicationName) Supplements genommen",
            ],
            shortTitle: "Supplements genommen",
            systemImageName: "pills"
        )
        AppShortcut(
            intent: SupplementTakenIntent(),
            phrases: [
                "\(\.$supplement) genommen in \(.applicationName)",
                "\(.applicationName) \(\.$supplement)",
                "\(\.$supplement) in \(.applicationName) abhaken",
            ],
            shortTitle: "Supplement genommen",
            systemImageName: "pill"
        )
        AppShortcut(
            intent: SupplementsResetIntent(),
            phrases: [
                "Alle Supplements austragen in \(.applicationName)",
                "Supplements austragen in \(.applicationName)",
                "Supplements zurücksetzen in \(.applicationName)",
                "\(.applicationName) Supplements zurücksetzen",
                "\(.applicationName) alle Supplements austragen",
            ],
            shortTitle: "Supplements austragen",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: SupplementResetIntent(),
            phrases: [
                "\(\.$supplement) zurücksetzen in \(.applicationName)",
            ],
            shortTitle: "Supplement zurücksetzen",
            systemImageName: "arrow.uturn.backward.circle"
        )
        AppShortcut(
            intent: MedicationTakenIntent(),
            phrases: [
                "\(\.$medication) genommen in \(.applicationName)",
                "\(.applicationName) \(\.$medication) genommen",
                "\(\.$medication) in \(.applicationName) genommen",
            ],
            shortTitle: "Medikament genommen",
            systemImageName: "cross.case.fill"
        )
        AppShortcut(
            intent: LogMedicationIntent(),
            phrases: [
                "\(\.$medication) in \(.applicationName)",
                "\(\.$medication) eintragen in \(.applicationName)",
            ],
            shortTitle: "Medikament eintragen",
            systemImageName: "cross.case"
        )
        AppShortcut(
            intent: LogTemperatureIntent(),
            phrases: [
                "Temperatur in \(.applicationName)",
                "\(.applicationName) Temperatur",
                "Temperatur in \(.applicationName) eintragen",
            ],
            shortTitle: "Temperatur eintragen",
            systemImageName: "thermometer"
        )
    }
}
