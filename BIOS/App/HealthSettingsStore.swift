import Foundation
import os

/// Settings of the Gesundheits-Score (Mehr > Gesundheits-Score):
/// `strength_goal_per_week` 0...7 (0 = part Krafttraining off). Loaded from
/// `GET /v1/health/settings`, until then the value of the dashboard block
/// `health.settings`. A change is shown at once and reverted with a calm
/// message when the server rejects it or is unreachable. A server without the
/// endpoint (404) is not an error: the section says so.
@MainActor
final class HealthSettingsStore: ObservableObject {
    static let shared = HealthSettingsStore()

    /// Value shown in the UI (nil = not known yet).
    @Published private(set) var strengthGoal: Int?
    @Published private(set) var range: ClosedRange<Int> = 0...7
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    /// Message of the last failed change; nil after a successful one.
    @Published private(set) var saveError: String?
    /// The server answered 404 (older server without the settings).
    @Published private(set) var isUnavailable = false

    private static let log = Logger(subsystem: "at.bene.bios", category: "health-settings")
    private var loadedFromServer = false

    /// Dashboard value (`health.settings.strength_goal_per_week`) until the server answered.
    func adoptDashboardValue(_ value: Int?) {
        guard !loadedFromServer, !isSaving, let value else { return }
        strengthGoal = clamp(value)
    }

    func refresh() async {
        if isLoading || isSaving { return }
        guard let client = APIClient.fromConfig() else { return }
        isLoading = true
        do {
            let json = try await client.fetchHealthSettings()
            apply(json)
            loadedFromServer = true
            isUnavailable = false
        } catch {
            if let apiError = error as? APIError, apiError == .http(404) {
                isUnavailable = true
            } else if !ErrorKind.isCancellation(error) {
                Self.log.error("Health settings refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isLoading = false
    }

    /// Saves a new weekly goal; returns true when the server took it.
    @discardableResult
    func setStrengthGoal(_ value: Int) async -> Bool {
        let next = clamp(value)
        guard next != strengthGoal, !isSaving else { return false }
        guard let client = APIClient.fromConfig() else {
            saveError = APIError.notConfigured.errorDescription
            return false
        }
        let previous = strengthGoal
        strengthGoal = next
        isSaving = true
        saveError = nil
        var saved = false
        do {
            let result = try await client.patchHealthSettings(.object(["strength_goal_per_week": .number(Double(next))]))
            if result.isSuccess {
                if let json = result.json { apply(json) }
                loadedFromServer = true
                saved = true
            } else if result.status == 404 {
                strengthGoal = previous
                isUnavailable = true
                saveError = "Der Server kennt diese Einstellung noch nicht."
            } else {
                strengthGoal = previous
                saveError = "Nicht gespeichert: " + result.errorText
            }
        } catch {
            strengthGoal = previous
            if !ErrorKind.isCancellation(error) {
                saveError = ErrorKind.isOffline(error)
                    ? "Keine Verbindung, nicht gespeichert. Der alte Wert gilt weiter."
                    : "Nicht gespeichert, der alte Wert gilt weiter."
                Self.log.error("Health settings failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        isSaving = false
        return saved
    }

    private func apply(_ json: JSONValue) {
        if let option = json.obj("options")?.obj("strength_goal_per_week"),
           let low = option.int("min"), let high = option.int("max"), low <= high {
            range = low...high
        }
        if let value = json.obj("settings")?.int("strength_goal_per_week") {
            strengthGoal = clamp(value)
        }
    }

    private func clamp(_ value: Int) -> Int {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }
}
