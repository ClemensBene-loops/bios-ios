import Foundation

/// Answer of a nudge write: HTTP status and the JSON body (if any). 4xx is not
/// thrown, so the UI can show the server's German 422 text.
struct NudgeHTTPResult: Sendable {
    let status: Int
    let json: JSONValue?

    var isSuccess: Bool { (200..<300).contains(status) }

    /// `error` of `{"ok": false, "error": "..."}`, else a short fallback.
    var errorText: String {
        json?.str("error") ?? json?.str("detail") ?? "Server lehnt ab (HTTP \(status))"
    }
}

/// Bewegungs-Stupser: `GET /v1/nudge`, `PATCH /v1/nudge/settings`, `POST /v1/nudge/action`.
extension APIClient {
    /// `GET /v1/nudge`: settings, today's budget, last check, last nudges, week.
    func fetchNudge() async throws -> JSONValue {
        try await getJSON(path: ["v1", "nudge"])
    }

    /// `PATCH /v1/nudge/settings` with a partial body (`enabled`, `tone`, `hours`, `max_per_day`).
    func patchNudgeSettings(_ body: JSONValue) async throws -> NudgeHTTPResult {
        try await nudgeWrite("PATCH", path: ["v1", "nudge", "settings"], body: body, attempts: 2)
    }

    /// `POST /v1/nudge/action` `{"id", "action"}` from a notification button.
    func postNudgeAction(id: String, action: String) async throws -> NudgeHTTPResult {
        let body: JSONValue = .object(["id": .string(id), "action": .string(action)])
        return try await nudgeWrite("POST", path: ["v1", "nudge", "action"], body: body, attempts: 2)
    }

    /// Network errors, 429 and 5xx are retried once after 1 s; any other status is returned.
    func nudgeWrite(_ method: String, path: [String], body: JSONValue, attempts: Int) async throws -> NudgeHTTPResult {
        var request = makeRequest(path: path, method: method)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        var lastError: Error = APIError.invalidResponse
        for attempt in 1...max(1, attempts) {
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
            let data = result.0
            guard let http = result.1 as? HTTPURLResponse else {
                lastError = APIError.invalidResponse
                continue
            }
            let status = http.statusCode
            if status == 429 || (500..<600).contains(status) {
                lastError = APIError.http(status)
                continue
            }
            let json = data.isEmpty ? nil : try? JSONDecoder().decode(JSONValue.self, from: data)
            return NudgeHTTPResult(status: status, json: json)
        }
        throw lastError
    }
}
