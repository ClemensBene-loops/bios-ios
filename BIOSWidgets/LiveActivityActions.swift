import Foundation

/// Widget-side counterpart of the app's `LiveActivityActions`
/// (BIOS/App/LiveActivityController.swift). The Live Activity intents in
/// Shared/ are compiled into both targets; the system runs LiveActivityIntent
/// in the app's process, so these no-ops only satisfy the compiler here.
enum LiveActivityActions {
    static func taken(medicationID: String, name: String) async {}

    static func later(medicationID: String, minutes: Int) async {}
}
