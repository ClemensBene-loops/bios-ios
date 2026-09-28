import Foundation

/// Quick-log endpoints (supplements, intake, medications). Bodies are built as
/// `JSONValue`, answers are read leniently; an empty body is fine.
extension APIClient {
    func requestJSON(_ method: String, path: [String], query: [URLQueryItem] = [],
                     body: JSONValue? = nil) async throws -> JSONValue? {
        var request = makeRequest(path: path, query: query, method: method)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let data = try await send(request)
        if data.isEmpty { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// `GET /v1/supplements`
    func fetchSupplements() async throws -> JSONValue? {
        try await requestJSON("GET", path: ["v1", "supplements"])
    }

    /// `PUT /v1/supplements` with the complete list (the server keeps history).
    func putSupplements(_ items: [JSONValue]) async throws -> JSONValue? {
        try await requestJSON("PUT", path: ["v1", "supplements"], body: .object(["items": .array(items)]))
    }

    /// `POST /v1/intake`: one item (`item_id`) or all active items (`all`).
    @discardableResult
    func postIntake(date: String, itemID: String?, all: Bool, taken: Bool) async throws -> JSONValue? {
        let body: JSONValue = .object([
            "date": .string(date),
            "item_id": itemID.map { JSONValue.string($0) } ?? JSONValue.null,
            "all": .bool(all),
            "taken": .bool(taken),
        ])
        return try await requestJSON("POST", path: ["v1", "intake"], body: body)
    }

    /// `GET /v1/intake?days=N`
    func fetchIntake(days: Int) async throws -> JSONValue? {
        try await requestJSON("GET", path: ["v1", "intake"], query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// `POST /v1/medications` -> `{"id": ...}`. With `plan_item_id` the server
    /// counts the intake against that plan item (name/dose default to the plan).
    func postMedication(takenAt: String, name: String, dose: String?, note: String?,
                        planItemID: String? = nil) async throws -> JSONValue? {
        var object: [String: JSONValue] = [
            "taken_at": .string(takenAt),
            "name": .string(name),
            "dose": dose.map { JSONValue.string($0) } ?? JSONValue.null,
            "note": note.map { JSONValue.string($0) } ?? JSONValue.null,
        ]
        if let planItemID {
            object["plan_item_id"] = .string(planItemID)
        }
        return try await requestJSON("POST", path: ["v1", "medications"], body: .object(object))
    }

    /// `GET /v1/medication-plan` (same shape as supplements, items with `times`).
    func fetchMedicationPlan() async throws -> JSONValue? {
        try await requestJSON("GET", path: ["v1", "medication-plan"])
    }

    /// `PUT /v1/medication-plan` with the complete plan (the server keeps history).
    func putMedicationPlan(_ items: [JSONValue]) async throws -> JSONValue? {
        try await requestJSON("PUT", path: ["v1", "medication-plan"], body: .object(["items": .array(items)]))
    }

    /// `POST /v1/vitals` (temperature or blood pressure) -> `{"id", "item"}`.
    func postVital(_ body: JSONValue) async throws -> JSONValue? {
        try await requestJSON("POST", path: ["v1", "vitals"], body: body)
    }

    /// `DELETE /v1/vitals/{id}`
    func deleteVital(id: String) async throws {
        _ = try await requestJSON("DELETE", path: ["v1", "vitals", id])
    }

    /// `GET /v1/vitals?days=N`
    func fetchVitals(days: Int) async throws -> JSONValue? {
        try await requestJSON("GET", path: ["v1", "vitals"], query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// `DELETE /v1/medications/{id}`
    func deleteMedication(id: String) async throws {
        _ = try await requestJSON("DELETE", path: ["v1", "medications", id])
    }

    /// `GET /v1/medications?days=N`
    func fetchMedications(days: Int) async throws -> JSONValue? {
        try await requestJSON("GET", path: ["v1", "medications"], query: [URLQueryItem(name: "days", value: String(days))])
    }
}
