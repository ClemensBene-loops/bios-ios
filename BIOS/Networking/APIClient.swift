import Foundation

/// Errors of the BIOS server API, with German messages for the UI.
enum APIError: LocalizedError, Equatable {
    case invalidResponse
    case http(Int)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungültige Antwort vom Server"
        case .notConfigured:
            return "Server nicht konfiguriert"
        case .http(401), .http(403):
            return "Server lehnt das Secret ab (HTTP 401/403)"
        case .http(404):
            return "Endpunkt fehlt am Server (HTTP 404)"
        case .http(let status):
            return "Server-Fehler (HTTP \(status))"
        }
    }
}

/// Small async client for the BIOS server (`/v1/...` below `BIOSAPIBaseURL`).
///
/// Every request carries `Authorization: Bearer <BIOSAPISecret>`. Network
/// errors, HTTP 429 and 5xx are retried with exponential backoff (up to
/// `maxAttempts` attempts in total); other HTTP errors fail immediately.
/// All clients share one URLSession (connection reuse, no per-call sessions).
struct APIClient: Sendable {
    let baseURL: URL
    let secret: String
    let session: URLSession
    let maxAttempts: Int

    static let sharedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    init(baseURL: URL, secret: String, session: URLSession = APIClient.sharedSession, maxAttempts: Int = 3) {
        self.baseURL = baseURL
        self.secret = secret
        self.session = session
        self.maxAttempts = max(1, maxAttempts)
    }

    /// Client from the build-time config, or nil if URL or secret is missing.
    static func fromConfig() -> APIClient? {
        guard let baseURL = AppConfig.apiBaseURL, let secret = AppConfig.apiSecret else {
            return nil
        }
        return APIClient(baseURL: baseURL, secret: secret)
    }

    /// `POST /v1/devices`: registers or refreshes this device's APNs token.
    func registerDevice(_ registration: DeviceRegistration) async throws {
        var request = makeRequest(path: ["v1", "devices"], method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(registration)
        _ = try await send(request)
    }

    /// `GET /v1/summary`: latest Whoop check and outlook (v1 contract, kept for build 2).
    func fetchSummary() async throws -> SummaryResponse {
        let request = makeRequest(path: ["v1", "summary"], method: "GET")
        let data = try await send(request)
        return try JSONDecoder().decode(SummaryResponse.self, from: data)
    }

    /// `GET /v1/dashboard`: ready-made tiles for the Heute tab and friends.
    func fetchDashboard() async throws -> JSONValue {
        try await getJSON(path: ["v1", "dashboard"])
    }

    /// `GET /v1/series?metric=...&days=...[&source=...]`: one logical time series.
    func fetchSeries(metric: String, days: Int, source: String? = nil) async throws -> JSONValue {
        var query = [
            URLQueryItem(name: "metric", value: metric),
            URLQueryItem(name: "days", value: String(days)),
        ]
        if let source, !source.isEmpty {
            query.append(URLQueryItem(name: "source", value: source))
        }
        return try await getJSON(path: ["v1", "series"], query: query)
    }

    /// `POST /v1/events`: marks a day (idempotent per date + kind).
    func postEvent(date: String, kind: String, note: String? = nil) async throws {
        var request = makeRequest(path: ["v1", "events"], method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EventBody(date: date, kind: kind, note: note))
        _ = try await send(request)
    }

    /// `DELETE /v1/events?date=...&kind=...`: removes a mark (no error if absent).
    func deleteEvent(date: String, kind: String) async throws {
        let request = makeRequest(
            path: ["v1", "events"],
            query: [URLQueryItem(name: "date", value: date), URLQueryItem(name: "kind", value: kind)],
            method: "DELETE"
        )
        _ = try await send(request)
    }

    /// `GET /v1/events?days=N`: marked days of the last N days (N <= 400).
    func fetchEvents(days: Int) async throws -> JSONValue {
        try await getJSON(path: ["v1", "events"], query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// `POST /v1/test-push`: the server pushes a short test alert to this token only.
    /// Exactly one attempt: the server allows one test push per minute and token
    /// (HTTP 429), so a retry would only hit the limit.
    func sendTestPush(token: String) async throws -> TestPushResult {
        let single = APIClient(baseURL: baseURL, secret: secret, session: session, maxAttempts: 1)
        var request = single.makeRequest(path: ["v1", "test-push"], method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(TestPushBody(token: token))
        let data = try await single.send(request)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard value.objectValue != nil else { throw APIError.invalidResponse }
        return TestPushResult(json: value)
    }

    /// GET returning a JSON object (anything else is an invalid response).
    func getJSON(path: [String], query: [URLQueryItem] = []) async throws -> JSONValue {
        let request = makeRequest(path: path, query: query, method: "GET")
        let data = try await send(request)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard value.objectValue != nil else { throw APIError.invalidResponse }
        return value
    }

    // MARK: - Internals

    func makeRequest(path: [String], query: [URLQueryItem] = [], method: String) -> URLRequest {
        var url = baseURL
        for component in path {
            url = url.appendingPathComponent(component)
        }
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            if let withQuery = components.url {
                url = withQuery
            }
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        var lastError: Error = APIError.invalidResponse
        for attempt in 1...maxAttempts {
            if attempt > 1 {
                // 1 s, 2 s, 4 s, ...
                let seconds = UInt64(1) << UInt64(attempt - 2)
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }

            let result: (Data, URLResponse)
            do {
                result = try await session.data(for: request)
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                continue
            }

            guard let http = result.1 as? HTTPURLResponse else {
                lastError = APIError.invalidResponse
                continue
            }
            let status = http.statusCode
            if (200..<300).contains(status) {
                return result.0
            }
            if status == 429 || (500..<600).contains(status) {
                lastError = APIError.http(status)
                continue
            }
            throw APIError.http(status)
        }
        throw lastError
    }
}

/// Body of `POST /v1/test-push`.
struct TestPushBody: Encodable, Sendable {
    let token: String
}

/// Answer of `POST /v1/test-push` (HTTP 200 = Apple was reached; `accepted` says
/// whether Apple took the push). Missing fields fall back to nil/false.
struct TestPushResult: Equatable, Sendable {
    let accepted: Bool
    let apnsStatus: Int?
    let apnsReason: String?
    let removed: Bool

    init(json: JSONValue) {
        accepted = json.flag("ok")
        apnsStatus = json.int("apns_status")
        apnsReason = json.str("apns_reason")
        removed = json.flag("removed")
    }
}

/// Classifies refresh errors for the UI.
enum ErrorKind {
    /// Cancellation (task or URLSession) is not an error worth showing.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// No connection (offline, DNS, timeout): the UI says "Offline" instead of an error.
    static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }
}
