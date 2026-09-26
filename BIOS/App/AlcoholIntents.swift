import AppIntents
import Foundation

// Siri / Shortcuts: "Alkohol in BIOS" marks today, "Gestern Alkohol in BIOS"
// marks yesterday. App Intents in the main app target need no extension,
// entitlement or Info.plist key; the phrases are registered by
// `BIOSShortcuts` at build time (App Intents metadata extraction).

/// Marks a day with alcohol (default today). Runs without opening the app.
struct LogAlcoholIntent: AppIntent {
    static let title: LocalizedStringResource = "Alkohol eintragen"

    @Parameter(title: "Tag")
    var date: Date?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await AlcoholIntentRunner.mark(date ?? Date())
        return .result(dialog: "\(text)")
    }
}

/// Marks yesterday with alcohol (own intent, so Siri needs no follow-up question).
struct LogAlcoholYesterdayIntent: AppIntent {
    static let title: LocalizedStringResource = "Alkohol gestern eintragen"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let text = await AlcoholIntentRunner.mark(yesterday)
        return .result(dialog: "\(text)")
    }
}

/// Marks every active supplement as taken today.
struct SupplementsTakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Supplements genommen"

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await AlcoholIntentRunner.supplementsTaken()
        return .result(dialog: "\(text)")
    }
}

enum AlcoholIntentRunner {
    @MainActor
    static func supplementsTaken() async -> String {
        let outcome = await SupplementStore.shared.setAll(on: EventStore.dayString(Date()), taken: true)
        switch outcome {
        case .synced:
            return "Alle Supplements für heute in BIOS eingetragen."
        case .queued:
            return "Keine Verbindung. BIOS trägt die Supplements nach, sobald die App wieder online ist."
        case .failed(let message):
            return "Nicht eingetragen: \(message)."
        }
    }

    /// Queues and sends the mark through the shared EventStore (offline safe),
    /// returns the German confirmation Siri speaks.
    @MainActor
    static func mark(_ date: Date) async -> String {
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

struct BIOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogAlcoholIntent(),
            phrases: [
                "Alkohol in \(.applicationName)",
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
    }
}
