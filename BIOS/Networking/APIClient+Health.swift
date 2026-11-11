import Foundation

/// Gesundheits-Score settings: `GET/PATCH /v1/health/settings` (since 28.09.2026).
extension APIClient {
    /// `GET /v1/health/settings`: `{"ok", "settings": {"strength_goal_per_week"}, "options": {...}}`.
    func fetchHealthSettings() async throws -> JSONValue {
        try await getJSON(path: ["v1", "health", "settings"])
    }

    /// `PATCH /v1/health/settings` with a partial body; 4xx is returned, not thrown.
    func patchHealthSettings(_ body: JSONValue) async throws -> NudgeHTTPResult {
        try await nudgeWrite("PATCH", path: ["v1", "health", "settings"], body: body, attempts: 2)
    }
}
