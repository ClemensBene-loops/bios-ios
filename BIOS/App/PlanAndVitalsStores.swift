import Foundation
import os

// Medication plan (GET/PUT /v1/medication-plan, intake via POST /v1/medications
// with plan_item_id) and vitals entered in the app (POST/DELETE/GET /v1/vitals:
// temperature, blood pressure). Same pattern as the other log stores:
// optimistic local state, persisted queue, retried on launch and foreground.
// No names are hard coded: the plan lives only on the server.

// MARK: - Medication plan

/// One plan item of today from the dashboard (`intake.medication_plan_today`).
struct PlanTodayStatus: Equatable {
    let id: String
    let taken: Int
    let perDay: Int
    let lastTakenAt: String?

    init?(json: JSONValue) {
        guard let id = LogQueue.idString(json["id"]) else { return nil }
        self.id = id
        taken = json.int("taken") ?? 0
        perDay = json.int("per_day") ?? 1
        lastTakenAt = json.str("last_taken_at")
    }
}

struct MedicationPlanItem: Identifiable, Codable, Equatable {
    var serverID: String?
    var localID: UUID
    var name: String
    /// "Inhalator", "Tablette" (free text).
    var form: String?
    /// Dose as text ("1", "2 Hübe").
    var dose: String?
    var unit: String?
    /// Planned times "HH:MM".
    var times: [String]
    var perDay: Int?
    var activeFrom: String?
    var activeTo: String?
    var note: String?

    var id: String { serverID ?? localID.uuidString }

    init(name: String) {
        serverID = nil
        localID = UUID()
        self.name = name
        times = []
    }

    init?(json: JSONValue) {
        guard let name = json.str("name") else { return nil }
        serverID = LogQueue.idString(json["id"])
        localID = UUID()
        self.name = name
        form = json.str("form")
        dose = json.str("dose") ?? json.double("dose").map { BIOSFormat.number($0, digits: $0.rounded() == $0 ? 0 : 1) }
        unit = json.str("unit")
        times = json.strings("times").filter { $0.count == 5 }
        perDay = json.int("per_day")
        activeFrom = json.str("active_from")
        activeTo = json.str("active_to")
        note = json.str("note")
    }

    /// PUT body entry: missing fields are omitted, `per_day` defaults to the times.
    var json: JSONValue {
        func add(_ key: String, _ value: String?, into object: inout [String: JSONValue]) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { object[key] = .string(trimmed) }
        }
        var object: [String: JSONValue] = ["name": .string(name.trimmingCharacters(in: .whitespaces))]
        add("id", serverID, into: &object)
        add("form", form, into: &object)
        add("dose", dose, into: &object)
        add("unit", unit, into: &object)
        add("note", note, into: &object)
        add("active_from", activeFrom.map { String($0.prefix(10)) }, into: &object)
        add("active_to", activeTo.map { String($0.prefix(10)) }, into: &object)
        let cleanTimes = Array(Set(times.filter { $0.count == 5 })).sorted()
        object["times"] = .array(cleanTimes.map { JSONValue.string($0) })
        if let perDay {
            object["per_day"] = .number(Double(Swift.max(1, Swift.min(12, perDay))))
        }
        return .object(object)
    }

    /// Target intakes per day: `per_day`, else the number of times, at least 1.
    var target: Int {
        perDay ?? Swift.max(1, times.count)
    }

    func isActive(on day: String) -> Bool {
        if let from = activeFrom, day < String(from.prefix(10)) { return false }
        if let to = activeTo, day > String(to.prefix(10)) { return false }
        return true
    }

    /// "2 Hübe · Inhalator" (dose with unit, form).
    var doseText: String {
        let dosePart = [dose, unit].compactMap { $0 }.joined(separator: " ")
        return [dosePart.isEmpty ? nil : dosePart, form].compactMap { $0 }.joined(separator: " · ")
    }

    /// "08:00, 20:00 · 2x täglich"
    var scheduleText: String {
        var parts: [String] = []
        if !times.isEmpty { parts.append(times.sorted().joined(separator: ", ")) }
        parts.append("\(target)x täglich")
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class MedicationPlanStore: ObservableObject {
    static let shared = MedicationPlanStore()

    @Published private(set) var items: [MedicationPlanItem] = []
    @Published private(set) var pendingItems: [MedicationPlanItem]?
    /// Today's status per plan item from the dashboard (server counts).
    @Published var today: [PlanTodayStatus] = []
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private static let log = Logger(subsystem: "at.bene.bios", category: "medplan")
    private static let itemsFile = "medication_plan_items.json"
    private static let itemsQueueFile = "medication_plan_pending.json"

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        items = LogQueue.load(Self.itemsFile, as: [MedicationPlanItem].self) ?? []
        if let queued = LogQueue.load(Self.itemsQueueFile, as: [MedicationPlanItem].self), !queued.isEmpty {
            pendingItems = queued
        }
    }

    var allItems: [MedicationPlanItem] {
        pendingItems ?? items
    }

    func activeItems(on day: String) -> [MedicationPlanItem] {
        allItems.filter { $0.isActive(on: day) }
    }

    /// Taken today: the higher of the local log and the server count (the
    /// server knows intakes from other devices, the log knows queued ones).
    func taken(_ item: MedicationPlanItem, on day: String) -> Int {
        guard let id = item.serverID else { return 0 }
        let local = MedicationStore.shared.count(planItemID: id, on: day)
        let isToday = day == EventStore.dayString(Date())
        let server = isToday ? (today.first { $0.id == id }?.taken ?? 0) : 0
        return Swift.max(local, server)
    }

    /// (taken, target) summed over the plan of a day.
    func progress(on day: String) -> (taken: Int, total: Int) {
        let active = activeItems(on: day)
        let taken = active.reduce(0) { $0 + Swift.min(taken($1, on: day), $1.target) }
        return (taken, active.reduce(0) { $0 + $1.target })
    }

    /// Logs one intake of a plan item now (or at `date`).
    @discardableResult
    func log(_ item: MedicationPlanItem, at date: Date = Date()) async -> EventStore.Outcome {
        let dose = item.dose.map { [$0, item.unit].compactMap { $0 }.joined(separator: " ") }
        return await MedicationStore.shared.add(
            name: item.name, dose: dose, note: nil, at: date, planItemID: item.serverID
        )
    }

    @discardableResult
    func saveItems(_ list: [MedicationPlanItem]) async -> EventStore.Outcome {
        pendingItems = list
        LogQueue.save(list, Self.itemsQueueFile)
        return await flush()
    }

    @discardableResult
    func flush() async -> EventStore.Outcome {
        if isSyncing { return .queued }
        guard let list = pendingItems else { return .synced }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return .queued
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let answer = try await client.putMedicationPlan(list.map(\.json))
            let parsed = (answer?.list("items") ?? []).compactMap { MedicationPlanItem(json: $0) }
            items = parsed.isEmpty ? list : parsed
            LogQueue.save(items, Self.itemsFile)
            pendingItems = nil
            removeQueueFile()
            lastError = nil
            BIOSShortcuts.updateAppShortcutParameters()
            return .synced
        } catch {
            if LogQueue.keep(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                return .queued
            }
            pendingItems = nil
            removeQueueFile()
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard let client = APIClient.fromConfig() else {
            #if DEBUG
            if items.isEmpty { loadSample() }
            #endif
            return
        }
        do {
            if let json = try await client.fetchMedicationPlan() {
                items = json.list("items").compactMap { MedicationPlanItem(json: $0) }
                LogQueue.save(items, Self.itemsFile)
                fetchedAt = Date()
                BIOSShortcuts.updateAppShortcutParameters()
            }
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                Self.log.info("Plan refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func removeQueueFile() {
        if let url = LogQueue.url(Self.itemsQueueFile) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    #if DEBUG
    /// Invented example items (Debug without server config only).
    private func loadSample() {
        var first = MedicationPlanItem(name: "Beispielmedikament A")
        first.serverID = "sample_a"
        first.form = "Tablette"
        first.dose = "1"
        first.times = ["08:00", "13:00"]
        var second = MedicationPlanItem(name: "Beispielmedikament B")
        second.serverID = "sample_b"
        second.form = "Inhalator"
        second.dose = "2"
        second.unit = "Hübe"
        second.times = ["08:00", "20:00"]
        items = [first, second]
    }
    #endif
}

// MARK: - Vitals

struct VitalReading: Identifiable, Codable, Equatable {
    static let temperature = "temperature"
    static let bloodPressure = "blood_pressure"

    var serverID: String?
    let localID: UUID
    let kind: String
    /// "YYYY-MM-DDTHH:MM" local time.
    var measuredAt: String
    var value: Double?
    var sys: Int?
    var dia: Int?
    var pulse: Int?
    var method: String?
    var note: String?

    var id: String { localID.uuidString }

    init(kind: String, measuredAt: String) {
        serverID = nil
        localID = UUID()
        self.kind = kind
        self.measuredAt = measuredAt
    }

    init?(json: JSONValue) {
        guard let kind = json.str("kind"), let measuredAt = json.str("measured_at") else { return nil }
        serverID = LogQueue.idString(json["id"])
        localID = UUID()
        self.kind = kind
        self.measuredAt = measuredAt
        value = json.double("value")
        sys = json.int("sys")
        dia = json.int("dia")
        pulse = json.int("pulse")
        method = json.str("method")
        note = json.str("note")
    }

    var body: JSONValue {
        var object: [String: JSONValue] = [
            "kind": .string(kind),
            "measured_at": .string(measuredAt),
        ]
        if kind == Self.temperature {
            object["value"] = value.map { JSONValue.number(($0 * 10).rounded() / 10) } ?? JSONValue.null
        } else {
            object["sys"] = sys.map { JSONValue.number(Double($0)) } ?? JSONValue.null
            object["dia"] = dia.map { JSONValue.number(Double($0)) } ?? JSONValue.null
            object["pulse"] = pulse.map { JSONValue.number(Double($0)) } ?? JSONValue.null
        }
        if let method { object["method"] = .string(method) }
        if let note { object["note"] = .string(note) }
        return .object(object)
    }

    var date: Date? {
        BIOSDate.parse(measuredAt.count == 16 ? measuredAt + ":00" : measuredAt)
    }

    /// "37,8 °C" or "128/82 mmHg"
    var valueText: String {
        if kind == Self.temperature {
            return value.map { "\(BIOSFormat.number($0, digits: 1)) °C" } ?? "n. v."
        }
        let pair = "\(sys.map(String.init) ?? "?")/\(dia.map(String.init) ?? "?") mmHg"
        return pulse.map { "\(pair) · Puls \($0)" } ?? pair
    }
}

enum PendingVital: Codable, Equatable {
    case add(localID: UUID)
    case delete(serverID: String)
}

@MainActor
final class VitalsStore: ObservableObject {
    static let shared = VitalsStore()

    /// Server readings plus local, not yet confirmed ones (newest first).
    @Published private(set) var entries: [VitalReading] = []
    @Published private(set) var pending: [PendingVital] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private static let entriesFile = "vitals_entries.json"
    private static let queueFile = "vitals_pending.json"
    private static let methodKey = "bios.temperatureMethod"
    static let methods = ["infrarot", "Ohr", "Stirn", "oral", "Achsel", "rektal"]

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        entries = LogQueue.load(Self.entriesFile, as: [VitalReading].self) ?? []
        pending = LogQueue.load(Self.queueFile, as: [PendingVital].self) ?? []
    }

    var hasPending: Bool { !pending.isEmpty }

    /// Last used temperature method (default "infrarot").
    var lastMethod: String {
        UserDefaults.standard.string(forKey: Self.methodKey) ?? "infrarot"
    }

    func latest(_ kind: String) -> VitalReading? {
        entries.first { $0.kind == kind }
    }

    func recent(_ kind: String, limit: Int = 30) -> [VitalReading] {
        Array(entries.filter { $0.kind == kind }.prefix(limit))
    }

    func isPending(_ reading: VitalReading) -> Bool {
        reading.serverID == nil
    }

    // MARK: Changes

    @discardableResult
    func addTemperature(_ celsius: Double, method: String?, at date: Date = Date()) async -> EventStore.Outcome {
        var reading = VitalReading(kind: VitalReading.temperature, measuredAt: MedicationStore.stamp(date))
        reading.value = (celsius * 10).rounded() / 10
        reading.method = method
        if let method { UserDefaults.standard.set(method, forKey: Self.methodKey) }
        return await add(reading)
    }

    @discardableResult
    func addBloodPressure(sys: Int, dia: Int, pulse: Int?, at date: Date = Date()) async -> EventStore.Outcome {
        var reading = VitalReading(kind: VitalReading.bloodPressure, measuredAt: MedicationStore.stamp(date))
        reading.sys = sys
        reading.dia = dia
        reading.pulse = pulse
        return await add(reading)
    }

    private func add(_ reading: VitalReading) async -> EventStore.Outcome {
        entries.insert(reading, at: 0)
        sortEntries()
        pending.append(.add(localID: reading.localID))
        persist()
        return await flush()
    }

    func delete(_ reading: VitalReading) {
        entries.removeAll { $0.localID == reading.localID }
        if let serverID = reading.serverID {
            pending.append(.delete(serverID: serverID))
        } else {
            pending.removeAll { $0 == .add(localID: reading.localID) }
        }
        persist()
        Task { @MainActor in
            await self.flush()
        }
    }

    @discardableResult
    func flush() async -> EventStore.Outcome {
        if isSyncing { return .queued }
        guard !pending.isEmpty else { return .synced }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return .queued
        }
        isSyncing = true
        defer { isSyncing = false }
        var changed = false
        while let change = pending.first {
            do {
                switch change {
                case .add(let localID):
                    if let index = entries.firstIndex(where: { $0.localID == localID }) {
                        let answer = try await client.postVital(entries[index].body)
                        let serverID = LogQueue.idString(answer?["id"]) ?? LogQueue.idString(answer?.obj("item")?["id"])
                        if let current = entries.firstIndex(where: { $0.localID == localID }) {
                            entries[current].serverID = serverID ?? "unbekannt"
                        }
                    }
                case .delete(let serverID):
                    if serverID != "unbekannt" {
                        try await client.deleteVital(id: serverID)
                    }
                }
                pending.removeFirst()
                persist()
                changed = true
            } catch {
                if LogQueue.keep(error) {
                    lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                    return .queued
                }
                // Rejected (422, e.g. out of range): drop it, keep the message.
                if case .add(let localID) = change {
                    entries.removeAll { $0.localID == localID }
                }
                pending.removeFirst()
                persist()
                lastError = error.localizedDescription
                return .failed(error.localizedDescription)
            }
        }
        lastError = nil
        if changed {
            // Tile, hero context and the charts show the new reading.
            Task { @MainActor in
                await DashboardStore.shared.refresh(force: true)
                await SeriesStore.shared.reload(metrics: ["body_temp", "bp_sys", "bp_dia", "bp_pulse"])
            }
        }
        return .synced
    }

    func refresh(days: Int = 90) async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            guard let json = try await client.fetchVitals(days: days) else { return }
            let server = json.list("items").compactMap { VitalReading(json: $0) }
            let deleted = Set(pending.compactMap { change -> String? in
                if case .delete(let id) = change { return id }
                return nil
            })
            let local = entries.filter { $0.serverID == nil }
            entries = local + server.filter { !deleted.contains($0.serverID ?? "") }
            sortEntries()
            persist()
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }

    private func sortEntries() {
        entries.sort { $0.measuredAt > $1.measuredAt }
    }

    private func persist() {
        LogQueue.save(entries, Self.entriesFile)
        LogQueue.save(pending, Self.queueFile)
    }
}
