import Foundation

// Workouts (`GET/POST /v1/workouts`, `DELETE /v1/workouts/{id}`, dashboard `training.recent`):
// Whoop workouts plus the ones entered by hand while no Whoop is worn. The server merges
// both (a manual entry next to a Whoop workout of the same time is dropped); only manual
// entries are deletable.

struct WorkoutItem: Identifiable, Equatable {
    let serverID: String?
    let start: Date?
    let startText: String
    let durationMin: Int
    let kind: String
    let label: String
    let muscleGroup: String?
    let intensity: String?
    let note: String?
    let source: String
    let manual: Bool
    let deletable: Bool

    var id: String { serverID ?? "\(source)|\(startText)|\(kind)" }

    init?(json: JSONValue) {
        guard let startRaw = json.str("start"), let kind = json.str("kind") else { return nil }
        serverID = json.str("id")
        startText = startRaw
        start = BIOSDate.parse(startRaw)
        durationMin = max(0, json.int("duration_min") ?? 0)
        self.kind = kind
        label = json.str("label") ?? WorkoutOptions.label(kind)
        muscleGroup = json.str("muscle_group")
        intensity = json.str("intensity")
        note = json.str("note")
        let source = json.str("source") ?? "whoop"
        self.source = source
        manual = json.flag("manual", fallback: source == "manual")
        deletable = json.flag("deletable", fallback: source == "manual") && json.str("id") != nil
    }

    /// "Krafttraining · Zug"
    var title: String {
        if let group = muscleGroup.flatMap(WorkoutOptions.muscleShort) {
            return "\(label) · \(group)"
        }
        return label
    }

    /// "90 min · hart · manuell"
    var detailLine: String {
        var parts = ["\(durationMin) min"]
        if let intensity { parts.append(intensity) }
        parts.append(manual ? "manuell" : "Whoop")
        return parts.joined(separator: " · ")
    }

    /// "gestern 18:30"
    var whenText: String {
        start.map { BIOSFormat.relative($0) } ?? startText
    }
}

/// One choice of a picker or chip row (server key, German label).
struct WorkoutOption: Identifiable, Equatable {
    let key: String
    let label: String

    var id: String { key }
}

enum WorkoutOptions {
    /// Sport kinds the server accepts (Whoop sport names), in picker order.
    static let kinds: [WorkoutOption] = [
        WorkoutOption(key: "weightlifting", label: "Krafttraining"),
        WorkoutOption(key: "running", label: "Laufen"),
        WorkoutOption(key: "cycling", label: "Radfahren"),
        WorkoutOption(key: "walking", label: "Gehen"),
        WorkoutOption(key: "hiking", label: "Wandern"),
        WorkoutOption(key: "swimming", label: "Schwimmen"),
        WorkoutOption(key: "functional_fitness", label: "Functional Fitness"),
        WorkoutOption(key: "other", label: "Sonstiges"),
    ]

    /// Muscle groups of a strength session (chip text).
    static let muscleGroups: [WorkoutOption] = [
        WorkoutOption(key: "pull", label: "Zug (Rücken)"),
        WorkoutOption(key: "push", label: "Druck (Brust)"),
        WorkoutOption(key: "legs", label: "Beine"),
        WorkoutOption(key: "full", label: "Ganzkörper"),
        WorkoutOption(key: "core", label: "Rumpf"),
    ]

    static let intensities: [WorkoutOption] = ["leicht", "mittel", "hart"].map { WorkoutOption(key: $0, label: $0) }

    static func label(_ kind: String) -> String {
        kinds.first { $0.key == kind }?.label ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func muscleShort(_ key: String) -> String? {
        muscleGroups.first { $0.key == key }?.label
    }

    /// Kinds that count as strength training (muscle group chips are offered).
    static func isStrength(_ kind: String) -> Bool {
        kind == "weightlifting" || kind == "functional_fitness"
    }
}
