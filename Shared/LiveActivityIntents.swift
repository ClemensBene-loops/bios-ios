import AppIntents
import Foundation

// Buttons of the Live Activity ("Genommen", "Später"). LiveActivityIntent
// (iOS 17): the type is compiled into the app AND the widget extension, and
// the system runs `perform()` in the app's process (launched in the
// background if needed), so the intake goes through the app's offline-safe
// stores. `LiveActivityActions` has one implementation per target: the real
// one in BIOS/App/LiveActivityController.swift, a no-op in BIOSWidgets.
// Not discoverable: they only make sense from the banner, not in Shortcuts.

/// "Genommen": logs one intake of the plan item shown in the banner. The
/// server's content state names the medication only; the app resolves the
/// plan item by id (local activity) or by name.
struct LiveActivityTakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Einnahme bestätigen"
    static let isDiscoverable = false

    @Parameter(title: "Plan-ID")
    var medicationID: String?

    @Parameter(title: "Medikament")
    var medicationName: String

    init() {}

    init(medicationID: String?, medicationName: String) {
        self.medicationID = medicationID
        self.medicationName = medicationName
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.taken(medicationID: medicationID, name: medicationName)
        return .result()
    }
}

/// "Später": moves the shown intake by 30 minutes (only in the banner).
struct LiveActivityLaterIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Einnahme später"
    static let isDiscoverable = false

    @Parameter(title: "Plan-ID")
    var medicationID: String?

    @Parameter(title: "Medikament")
    var medicationName: String

    init() {}

    init(medicationID: String?, medicationName: String) {
        self.medicationID = medicationID
        self.medicationName = medicationName
    }

    func perform() async throws -> some IntentResult {
        await LiveActivityActions.later(medicationID: medicationID, name: medicationName, minutes: 30)
        return .result()
    }
}
