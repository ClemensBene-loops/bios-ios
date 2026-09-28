import Foundation

/// Körper: `GET/PATCH /v1/body`, `DELETE /v1/body/weights/{id}` (since 2026-09-28).
extension APIClient {
    /// `GET /v1/body`: height, weight, BMI, history.
    func fetchBody() async throws -> JSONValue {
        try await getJSON(path: ["v1", "body"])
    }

    /// `PATCH /v1/body` `{"height_cm"?, "weight_kg"?, "date"?}`; 4xx is returned, not thrown.
    func patchBody(_ body: [String: JSONValue]) async throws -> LabHTTPResult {
        try await bodyWrite("PATCH", path: ["v1", "body"], body: .object(body))
    }

    /// `DELETE /v1/body/weights/{id}`: removes an own weight entry.
    func deleteBodyWeight(id: String) async throws -> LabHTTPResult {
        try await bodyWrite("DELETE", path: ["v1", "body", "weights", id], body: nil)
    }

    private func bodyWrite(_ method: String, path: [String], body: JSONValue?) async throws -> LabHTTPResult {
        var request = makeRequest(path: path, method: method)
        request.timeoutInterval = 20
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let json = data.isEmpty ? nil : try? JSONDecoder().decode(JSONValue.self, from: data)
        return LabHTTPResult(status: http.statusCode, json: json)
    }
}
