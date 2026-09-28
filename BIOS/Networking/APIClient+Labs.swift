import Foundation

/// Answer of a lab write (PATCH, DELETE): HTTP status and the JSON body. 4xx is
/// not thrown, so the UI can show the server's German 409/422 text.
struct LabHTTPResult: Sendable {
    let status: Int
    let json: JSONValue?

    var isSuccess: Bool { (200..<300).contains(status) }

    /// `error` of `{"ok": false, "error": "..."}`, else a short calm fallback.
    var errorText: String {
        if let text = json?.str("error") ?? json?.str("detail") { return text }
        switch status {
        case 404: return "Dokument nicht mehr vorhanden."
        case 409: return "Die Auswertung läuft noch. Bitte gleich noch einmal versuchen."
        case 413: return "Zu viele Änderungen auf einmal."
        case 422: return "Der Server hat eine Angabe nicht angenommen."
        default: return "Server lehnt ab (HTTP \(status))."
        }
    }
}

/// Labor: `/v1/labs`, `/v1/labs/catalog`, `/v1/labs/markers/{id}`,
/// `/v1/labs/documents[/{id}[/file]]`. Upload: `LabUpload` (SharedUpload/).
extension APIClient {
    /// `GET /v1/labs`: due list, groups with markers, review counts.
    func fetchLabs() async throws -> JSONValue {
        try await getJSON(path: ["v1", "labs"])
    }

    /// `GET /v1/labs/catalog`: groups, markers, document kinds.
    func fetchLabCatalog() async throws -> JSONValue {
        try await getJSON(path: ["v1", "labs", "catalog"])
    }

    /// `GET /v1/labs/markers/{id}`: history, refs, target, links (GMI).
    func fetchLabMarker(id: String) async throws -> JSONValue {
        try await getJSON(path: ["v1", "labs", "markers", id])
    }

    /// `GET /v1/labs/documents`: documents newest first, without discarded ones.
    func fetchLabDocuments() async throws -> JSONValue {
        try await getJSON(path: ["v1", "labs", "documents"])
    }

    /// `GET /v1/labs/documents/{id}`: document plus its values.
    func fetchLabDocument(id: String) async throws -> JSONValue {
        try await getJSON(path: ["v1", "labs", "documents", id])
    }

    /// `PATCH /v1/labs/documents/{id}`: review step (edit, discard values, confirm, retry).
    func patchLabDocument(id: String, body: JSONValue) async throws -> LabHTTPResult {
        try await labWrite("PATCH", path: ["v1", "labs", "documents", id], body: body)
    }

    /// `DELETE /v1/labs/documents/{id}`: discards the document, its file and values.
    func deleteLabDocument(id: String) async throws -> LabHTTPResult {
        try await labWrite("DELETE", path: ["v1", "labs", "documents", id], body: nil)
    }

    /// `GET /v1/labs/documents/{id}/file`: the original for the preview
    /// (never cached on disk). Returns the data and its content type.
    func fetchLabFile(id: String) async throws -> (data: Data, contentType: String?) {
        var request = makeRequest(path: ["v1", "labs", "documents", id, "file"], method: "GET")
        request.timeoutInterval = 60
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let result = try await LabUpload.session.data(for: request)
        guard let http = result.1 as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        let type = http.value(forHTTPHeaderField: "Content-Type")
        return (result.0, type)
    }

    /// Network errors, 429 and 5xx are retried once after 1 s; any other status is returned.
    private func labWrite(_ method: String, path: [String], body: JSONValue?) async throws -> LabHTTPResult {
        var request = makeRequest(path: path, method: method)
        request.timeoutInterval = 20
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        var lastError: Error = APIError.invalidResponse
        for attempt in 1...2 {
            if attempt > 1 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            let result: (Data, URLResponse)
            do {
                result = try await session.data(for: request)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                continue
            }
            guard let http = result.1 as? HTTPURLResponse else {
                lastError = APIError.invalidResponse
                continue
            }
            let status = http.statusCode
            if status == 429 || (500..<600).contains(status) {
                lastError = APIError.http(status)
                continue
            }
            let json = result.0.isEmpty ? nil : try? JSONDecoder().decode(JSONValue.self, from: result.0)
            return LabHTTPResult(status: status, json: json)
        }
        throw lastError
    }
}
