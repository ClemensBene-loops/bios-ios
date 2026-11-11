import Foundation

/// Workouts entered by hand (no Whoop worn) plus the Whoop ones, from `GET /v1/workouts`.
/// A save or delete goes straight to the server (the id is derived from start and kind, so a
/// repeated save never doubles an entry); afterwards the dashboard reloads, because the
/// health score segment "Bewegung" and the training card read the workouts.
@MainActor
final class WorkoutStore: ObservableObject {
    static let shared = WorkoutStore()

    @Published private(set) var items: [WorkoutItem] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isSaving = false

    private static let durationKey = "bios.workoutDuration"
    private static let kindKey = "bios.workoutKind"

    /// Last used duration in minutes (default 60).
    var lastDuration: Int {
        let value = UserDefaults.standard.integer(forKey: Self.durationKey)
        return value > 0 ? value : 60
    }

    /// Last used kind (default weightlifting).
    var lastKind: String {
        UserDefaults.standard.string(forKey: Self.kindKey) ?? "weightlifting"
    }

    func refresh(days: Int = 14) async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            guard let json = try await client.fetchWorkouts(days: days) else { return }
            items = json.list("items").compactMap { WorkoutItem(json: $0) }
            lastError = nil
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }

    @discardableResult
    func add(kind: String, start: Date, durationMin: Int, muscleGroup: String?, intensity: String?,
             note: String?) async -> EventStore.Outcome {
        guard let client = APIClient.fromConfig() else {
            return .failed(APIError.notConfigured.errorDescription ?? "Server nicht konfiguriert")
        }
        isSaving = true
        defer { isSaving = false }
        var body: [String: JSONValue] = [
            "start": .string(MedicationStore.stamp(start)),
            "duration_min": .number(Double(durationMin)),
            "kind": .string(kind),
            "muscle_group": muscleGroup.map { JSONValue.string($0) } ?? JSONValue.null,
            "intensity": intensity.map { JSONValue.string($0) } ?? JSONValue.null,
        ]
        let trimmed = (note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        body["note"] = trimmed.isEmpty ? JSONValue.null : .string(String(trimmed.prefix(80)))
        do {
            let answer = try await client.postWorkout(.object(body))
            UserDefaults.standard.set(durationMin, forKey: Self.durationKey)
            UserDefaults.standard.set(kind, forKey: Self.kindKey)
            if let item = answer?.obj("item").flatMap({ WorkoutItem(json: $0) }) {
                items.removeAll { $0.id == item.id }
                items.insert(item, at: 0)
                items.sort { ($0.start ?? .distantPast) > ($1.start ?? .distantPast) }
            }
            lastError = nil
            changed()
            return .synced
        } catch {
            let text = ErrorKind.isOffline(error) ? "Keine Verbindung, bitte später nochmal" : error.localizedDescription
            lastError = text
            return .failed(text)
        }
    }

    @discardableResult
    func delete(_ item: WorkoutItem) async -> EventStore.Outcome {
        guard item.deletable, let serverID = item.serverID else { return .failed("Whoop-Workouts lassen sich nicht löschen") }
        guard let client = APIClient.fromConfig() else {
            return .failed(APIError.notConfigured.errorDescription ?? "Server nicht konfiguriert")
        }
        do {
            try await client.deleteWorkout(id: serverID)
            items.removeAll { $0.id == item.id }
            lastError = nil
            changed()
            return .synced
        } catch {
            let text = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            lastError = text
            return .failed(text)
        }
    }

    private func changed() {
        Task { @MainActor in
            await DashboardStore.shared.refresh(force: true)
            await BodyMapStore.refreshAll(force: true)
        }
    }
}
