import Foundation
import os

// Quick log: supplements (items + daily intake) and medications. Same pattern
// as EventStore: optimistic local state, a persisted queue retried on launch
// and foreground, server state cached for offline display.

enum LogQueue {
    /// Connection problems, server errors and missing config stay queued;
    /// only a rejected request (400/404/422) is dropped.
    static func keep(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .http(let status) = apiError {
            return !(status == 400 || status == 404 || status == 422)
        }
        return true
    }

    static func url(_ name: String) -> URL? {
        DiskCache.directory()?.appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ name: String, as type: T.Type) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        guard let url = url(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Server ids may be strings or numbers.
    static func idString(_ json: JSONValue?) -> String? {
        guard let json else { return nil }
        if let text = json.stringValue, !text.isEmpty { return text }
        if let number = json.finiteNumber {
            return number.rounded() == number ? String(Int(number)) : String(number)
        }
        return nil
    }
}

// MARK: - Supplements

struct SupplementItem: Identifiable, Codable, Equatable {
    /// Server id; nil for an item added locally and not yet saved.
    var serverID: String?
    var localID: UUID
    var name: String
    var brand: String?
    var amount: Double?
    var unit: String?
    var perDay: Double?
    var activeFrom: String?
    var activeTo: String?
    var note: String?

    var id: String { serverID ?? localID.uuidString }

    init(name: String) {
        serverID = nil
        localID = UUID()
        self.name = name
    }

    init?(json: JSONValue) {
        guard let name = json.str("name") else { return nil }
        serverID = LogQueue.idString(json["id"])
        localID = UUID()
        self.name = name
        brand = json.str("brand")
        amount = json.double("amount")
        unit = json.str("unit")
        perDay = json.double("per_day")
        activeFrom = json.str("active_from")
        activeTo = json.str("active_to")
        note = json.str("note")
    }

    /// PUT body entry (API v1): missing fields are omitted, so the server keeps
    /// ids and start dates of known items; `per_day` is an integer 1...10.
    var json: JSONValue {
        func add(_ key: String, _ value: String?, into object: inout [String: JSONValue]) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { object[key] = .string(trimmed) }
        }
        var object: [String: JSONValue] = ["name": .string(name.trimmingCharacters(in: .whitespaces))]
        add("id", serverID, into: &object)
        add("brand", brand, into: &object)
        add("unit", unit, into: &object)
        add("note", note, into: &object)
        add("active_from", activeFrom.map { String($0.prefix(10)) }, into: &object)
        add("active_to", activeTo.map { String($0.prefix(10)) }, into: &object)
        if let amount, amount > 0 {
            object["amount"] = .number(amount)
        }
        if let perDay {
            object["per_day"] = .number(Double(Swift.max(1, Swift.min(10, Int(perDay.rounded())))))
        }
        return .object(object)
    }

    func isActive(on day: String) -> Bool {
        if let from = activeFrom, day < String(from.prefix(10)) { return false }
        if let to = activeTo, day > String(to.prefix(10)) { return false }
        return true
    }

    /// "1000 IE · 1x täglich"
    var doseText: String {
        var parts: [String] = []
        if let amount {
            let digits = amount.rounded() == amount ? 0 : 1
            parts.append(BIOSFormat.number(amount, digits: digits) + (unit.map { " \($0)" } ?? ""))
        } else if let unit {
            parts.append(unit)
        }
        if let perDay {
            let digits = perDay.rounded() == perDay ? 0 : 1
            parts.append("\(BIOSFormat.number(perDay, digits: digits))x täglich")
        }
        return parts.joined(separator: " · ")
    }
}

struct PendingIntake: Codable, Equatable {
    let id: UUID
    let date: String
    /// nil together with `all` = every active item.
    let itemID: String?
    let all: Bool
    let taken: Bool
}

/// Dashboard `intake` block (additive): today's status, streak, medications today.
struct DashboardIntakeModel {
    let taken: Int?
    let total: Int?
    let complete: Bool
    let streakDays: Int?
    let medicationsToday: Int?
    /// Medication plan items of today with taken vs per_day (additive).
    let planToday: [PlanTodayStatus]

    init(json: JSONValue) {
        let today = json.obj("today")
        planToday = json.list("medication_plan_today").compactMap { PlanTodayStatus(json: $0) }
        taken = today?.int("taken")
        total = today?.int("total")
        complete = today?.flag("complete") ?? false
        streakDays = json.int("streak_days")
        if let count = json.int("medications_today") {
            medicationsToday = count
        } else {
            medicationsToday = json["medications_today"]?.arrayValue.count
        }
    }
}

@MainActor
final class SupplementStore: ObservableObject {
    static let shared = SupplementStore()

    @Published private(set) var items: [SupplementItem] = []
    /// day -> item id -> taken (server state).
    @Published private(set) var intake: [String: [String: Bool]] = [:]
    @Published private(set) var pending: [PendingIntake] = []
    /// Item list waiting for PUT (edited offline).
    @Published private(set) var pendingItems: [SupplementItem]?
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false
    @Published var dashboardIntake: DashboardIntakeModel?

    private static let log = Logger(subsystem: "at.bene.bios", category: "supplements")
    private static let itemsFile = "supplements_items.json"
    private static let intakeFile = "supplements_intake.json"
    private static let queueFile = "supplements_pending.json"
    private static let itemsQueueFile = "supplements_pending_items.json"

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        items = LogQueue.load(Self.itemsFile, as: [SupplementItem].self) ?? []
        intake = LogQueue.load(Self.intakeFile, as: [String: [String: Bool]].self) ?? [:]
        pending = LogQueue.load(Self.queueFile, as: [PendingIntake].self) ?? []
        // An empty saved list is ignored: it would wipe all items on the server.
        if let queued = LogQueue.load(Self.itemsQueueFile, as: [SupplementItem].self), !queued.isEmpty {
            pendingItems = queued
        }
    }

    // MARK: State

    /// Items shown for a day (pending edits win), active on that day.
    func activeItems(on day: String) -> [SupplementItem] {
        (pendingItems ?? items).filter { $0.isActive(on: day) }
    }

    var allItems: [SupplementItem] {
        pendingItems ?? items
    }

    func isTaken(_ item: SupplementItem, on day: String) -> Bool {
        var value = intake[day]?[item.id] ?? false
        for change in pending where change.date == day {
            if change.all || change.itemID == item.id {
                value = change.taken
            }
        }
        return value
    }

    /// Days without local changes use the server map (plan of that day);
    /// otherwise the current plan with pending changes applied.
    func takenCount(on day: String) -> (taken: Int, total: Int) {
        if !pending.contains(where: { $0.date == day }), let map = intake[day], !map.isEmpty {
            return (map.values.filter { $0 }.count, map.count)
        }
        let active = activeItems(on: day)
        return (active.filter { isTaken($0, on: day) }.count, active.count)
    }

    func isComplete(on day: String) -> Bool {
        let count = takenCount(on: day)
        return count.total > 0 && count.taken == count.total
    }

    func hasAnyIntake(on day: String) -> Bool {
        takenCount(on: day).taken > 0
    }

    var hasPending: Bool {
        !pending.isEmpty || pendingItems != nil
    }

    // MARK: Changes

    @discardableResult
    func setTaken(_ item: SupplementItem, on day: String, taken: Bool) async -> EventStore.Outcome {
        guard let serverID = item.serverID else {
            return .failed("Präparat ist noch nicht gespeichert")
        }
        pending.append(PendingIntake(id: UUID(), date: day, itemID: serverID, all: false, taken: taken))
        LogQueue.save(pending, Self.queueFile)
        return await flush()
    }

    /// "Alle genommen" (also from Siri): works without a loaded item list.
    @discardableResult
    func setAll(on day: String, taken: Bool) async -> EventStore.Outcome {
        pending.removeAll { $0.date == day }
        pending.append(PendingIntake(id: UUID(), date: day, itemID: nil, all: true, taken: taken))
        LogQueue.save(pending, Self.queueFile)
        return await flush()
    }

    /// Saves the edited list (PUT, optimistic).
    @discardableResult
    func saveItems(_ list: [SupplementItem]) async -> EventStore.Outcome {
        pendingItems = list
        LogQueue.save(list, Self.itemsQueueFile)
        return await flush()
    }

    @discardableResult
    func flush() async -> EventStore.Outcome {
        if isSyncing { return .queued }
        guard hasPending else { return .synced }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return .queued
        }
        isSyncing = true
        defer { isSyncing = false }

        if let list = pendingItems {
            do {
                let answer = try await client.putSupplements(list.map(\.json))
                let parsed = (answer?.list("items") ?? []).compactMap { SupplementItem(json: $0) }
                items = parsed.isEmpty ? list : parsed
                LogQueue.save(items, Self.itemsFile)
                pendingItems = nil
                removeQueueFile(Self.itemsQueueFile)
                BIOSShortcuts.updateAppShortcutParameters()
            } catch {
                if LogQueue.keep(error) {
                    lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                    return .queued
                }
                pendingItems = nil
                removeQueueFile(Self.itemsQueueFile)
                lastError = error.localizedDescription
                return .failed(error.localizedDescription)
            }
        }

        while let change = pending.first {
            do {
                let answer = try await client.postIntake(date: change.date, itemID: change.itemID, all: change.all, taken: change.taken)
                if let day = answer?.obj("day"), let map = day.obj("items")?.objectValue {
                    intake[change.date] = map.mapValues { $0.boolValue ?? false }
                    LogQueue.save(intake, Self.intakeFile)
                } else {
                    apply(change)
                }
                pending.removeAll { $0.id == change.id }
                LogQueue.save(pending, Self.queueFile)
            } catch {
                if LogQueue.keep(error) {
                    lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                    Self.log.info("Intake queued: \(error.localizedDescription, privacy: .public)")
                    return .queued
                }
                pending.removeAll { $0.id == change.id }
                LogQueue.save(pending, Self.queueFile)
                lastError = error.localizedDescription
                return .failed(error.localizedDescription)
            }
        }
        lastError = nil
        return .synced
    }

    func refresh(days: Int = 120) async {
        guard let client = APIClient.fromConfig() else {
            #if DEBUG
            if items.isEmpty { loadSample() }
            #endif
            return
        }
        do {
            if let json = try await client.fetchSupplements() {
                items = json.list("items").compactMap { SupplementItem(json: $0) }
                LogQueue.save(items, Self.itemsFile)
                // Siri learns the supplement names for "<Name> genommen in BIOS".
                BIOSShortcuts.updateAppShortcutParameters()
            }
            if let json = try await client.fetchIntake(days: days) {
                var result: [String: [String: Bool]] = [:]
                for day in json.list("days") {
                    guard let date = day.str("date") else { continue }
                    var map: [String: Bool] = [:]
                    for (key, value) in day.obj("items")?.objectValue ?? [:] {
                        map[key] = value.boolValue ?? (value.finiteNumber.map { $0 != 0 } ?? false)
                    }
                    result[String(date.prefix(10))] = map
                }
                intake = result
                LogQueue.save(intake, Self.intakeFile)
            }
            fetchedAt = Date()
        } catch {
            if !ErrorKind.isCancellation(error) {
                lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }

    private func apply(_ change: PendingIntake) {
        var map = intake[change.date] ?? [:]
        if change.all {
            for item in activeItems(on: change.date) {
                map[item.id] = change.taken
            }
        } else if let id = change.itemID {
            map[id] = change.taken
        }
        intake[change.date] = map
        LogQueue.save(intake, Self.intakeFile)
    }

    private func removeQueueFile(_ name: String) {
        if let url = LogQueue.url(name) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    #if DEBUG
    /// Invented example items (Debug without server config only).
    private func loadSample() {
        var first = SupplementItem(name: "Beispielpräparat A")
        first.serverID = "sample-a"
        first.amount = 1
        first.unit = "Kapsel"
        first.perDay = 1
        var second = SupplementItem(name: "Beispielpräparat B")
        second.serverID = "sample-b"
        second.brand = "Beispielmarke"
        second.amount = 200
        second.unit = "mg"
        second.note = "zum Abendessen"
        items = [first, second]
    }
    #endif
}

// MARK: - Medications

struct MedicationEntry: Identifiable, Codable, Equatable {
    var serverID: String?
    let localID: UUID
    /// "YYYY-MM-DDTHH:MM" local time.
    var takenAt: String
    var name: String
    var dose: String?
    var note: String?
    /// Medication plan item this intake counts for (nil = free entry).
    var planItemID: String?

    var id: String { localID.uuidString }

    init(takenAt: String, name: String, dose: String?, note: String?, planItemID: String? = nil) {
        serverID = nil
        localID = UUID()
        self.takenAt = takenAt
        self.name = name
        self.dose = dose
        self.note = note
        self.planItemID = planItemID
    }

    init?(json: JSONValue) {
        guard let name = json.str("name"), let takenAt = json.str("taken_at") else { return nil }
        serverID = LogQueue.idString(json["id"])
        localID = UUID()
        self.takenAt = takenAt
        self.name = name
        dose = json.str("dose")
        note = json.str("note")
        planItemID = LogQueue.idString(json["plan_item_id"])
    }

    var date: Date? {
        BIOSDate.parse(takenAt.count == 16 ? takenAt + ":00" : takenAt)
    }
}

enum PendingMedication: Codable, Equatable {
    case add(localID: UUID)
    case delete(serverID: String)
}

@MainActor
final class MedicationStore: ObservableObject {
    static let shared = MedicationStore()

    /// Server entries plus local, not yet confirmed ones (newest first).
    @Published private(set) var entries: [MedicationEntry] = []
    @Published private(set) var pending: [PendingMedication] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private static let entriesFile = "medications_entries.json"
    private static let queueFile = "medications_pending.json"

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        entries = LogQueue.load(Self.entriesFile, as: [MedicationEntry].self) ?? []
        pending = LogQueue.load(Self.queueFile, as: [PendingMedication].self) ?? []
    }

    var hasPending: Bool {
        !pending.isEmpty
    }

    /// Distinct names, most recent first (suggestions in the form).
    var recentNames: [String] {
        var names: [String] = []
        for entry in entries.sorted(by: { $0.takenAt > $1.takenAt }) where !names.contains(entry.name) {
            names.append(entry.name)
        }
        return Array(names.prefix(8))
    }

    func count(on day: String) -> Int {
        entries.filter { $0.takenAt.hasPrefix(day) }.count
    }

    /// Intakes of one plan item on a day (local and server entries).
    func count(planItemID: String, on day: String) -> Int {
        entries.filter { $0.planItemID == planItemID && $0.takenAt.hasPrefix(day) }.count
    }

    func isPending(_ entry: MedicationEntry) -> Bool {
        entry.serverID == nil
    }

    // MARK: Changes

    @discardableResult
    func add(name: String, dose: String?, note: String?, at date: Date,
             planItemID: String? = nil) async -> EventStore.Outcome {
        let entry = MedicationEntry(takenAt: Self.stamp(date), name: name, dose: dose, note: note, planItemID: planItemID)
        entries.insert(entry, at: 0)
        sortEntries()
        pending.append(.add(localID: entry.localID))
        persist()
        return await flush()
    }

    func delete(_ entry: MedicationEntry) {
        entries.removeAll { $0.localID == entry.localID }
        if let serverID = entry.serverID {
            pending.append(.delete(serverID: serverID))
        } else {
            pending.removeAll { $0 == .add(localID: entry.localID) }
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
        while let change = pending.first {
            do {
                switch change {
                case .add(let localID):
                    if let index = entries.firstIndex(where: { $0.localID == localID }) {
                        let entry = entries[index]
                        let answer = try await client.postMedication(
                            takenAt: entry.takenAt, name: entry.name, dose: entry.dose, note: entry.note,
                            planItemID: entry.planItemID
                        )
                        let serverID = LogQueue.idString(answer?["id"]) ?? LogQueue.idString(answer?.obj("medication")?["id"])
                        if let current = entries.firstIndex(where: { $0.localID == localID }) {
                            entries[current].serverID = serverID ?? "unbekannt"
                        }
                    }
                case .delete(let serverID):
                    if serverID != "unbekannt" {
                        try await client.deleteMedication(id: serverID)
                    }
                }
                pending.removeFirst()
                persist()
            } catch {
                if LogQueue.keep(error) {
                    lastError = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
                    return .queued
                }
                pending.removeFirst()
                persist()
                lastError = error.localizedDescription
                return .failed(error.localizedDescription)
            }
        }
        lastError = nil
        return .synced
    }

    func refresh(days: Int = 30) async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            guard let json = try await client.fetchMedications(days: days) else { return }
            var list = json.list("medications")
            if list.isEmpty { list = json.list("items") }
            if list.isEmpty { list = json.list("entries") }
            let server = list.compactMap { MedicationEntry(json: $0) }
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
        entries.sort { $0.takenAt > $1.takenAt }
    }

    private func persist() {
        LogQueue.save(entries, Self.entriesFile)
        LogQueue.save(pending, Self.queueFile)
    }

    /// "YYYY-MM-DDTHH:MM" in local time.
    nonisolated static func stamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d", parts.year ?? 1970, parts.month ?? 1,
                      parts.day ?? 1, parts.hour ?? 0, parts.minute ?? 0)
    }
}
