import Foundation

// Upload of a lab document (`POST /v1/labs/documents`, raw body with its
// content type). Compiled into the app and the share extension BIOSShare, so
// it depends only on Foundation and `AppConfig` (Shared/AppConfig.swift).
// The server keeps the original, extracts the values later (minute cron) and
// answers at once: 201 new, 200 the same file (SHA-256) is already there.

/// Result of a successful upload (HTTP 200 or 201).
struct LabUploadResult: Equatable, Sendable {
    /// true = HTTP 200: the same file was uploaded before.
    let duplicate: Bool
    let documentID: String?
    /// `document.status`, e.g. "wartet_auf_extraktion", "zu_pruefen", "bestaetigt".
    let documentStatus: String?
    let statusReason: String?
}

/// Upload errors with calm German texts for the UI.
enum LabUploadError: LocalizedError, Equatable {
    case notConfigured
    case empty
    case tooLarge
    case unsupported
    case unauthorized
    case unavailable
    case server(Int, String?)
    case offline
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Server nicht konfiguriert."
        case .empty:
            return "Die Datei ist leer."
        case .tooLarge:
            return "Die Datei ist zu groß für den Server (höchstens 15 MB). Falls auch kleine Dateien scheitern, fehlt am Server noch die Proxy-Einstellung für den Labor-Import."
        case .unsupported:
            return "Dieser Dateityp wird nicht angenommen. Bitte als PDF, JPEG oder PNG senden."
        case .unauthorized:
            return "Der Server lehnt das Secret ab."
        case .unavailable:
            return "Der Server kennt den Labor-Import noch nicht."
        case .server(let status, let message):
            if let message, !message.isEmpty { return message }
            return "Der Server hat die Datei nicht angenommen (HTTP \(status))."
        case .offline:
            return "Keine Verbindung. Bitte später noch einmal senden."
        case .network(let message):
            return "Übertragung fehlgeschlagen: \(message)"
        }
    }
}

enum LabUpload {
    /// Server limit of the upload route.
    static let maxBytes = 15 * 1024 * 1024

    /// URLSession for lab transfers: longer timeouts than the dashboard session
    /// (a 15 MB PDF over mobile data takes a while), no cache.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Content type for a file name / extension ("pdf" -> application/pdf).
    static func contentType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        default: return nil
        }
    }

    /// Uploads `data` with the build-time server config (app or extension Info.plist).
    static func upload(
        data: Data,
        contentType: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> LabUploadResult {
        guard let baseURL = AppConfig.apiBaseURL, let secret = AppConfig.apiSecret else {
            throw LabUploadError.notConfigured
        }
        return try await upload(data: data, contentType: contentType, baseURL: baseURL, secret: secret,
                                progress: progress)
    }

    static func upload(
        data: Data,
        contentType: String,
        baseURL: URL,
        secret: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> LabUploadResult {
        if data.isEmpty { throw LabUploadError.empty }
        if data.count > maxBytes { throw LabUploadError.tooLarge }

        let url = baseURL.appendingPathComponent("v1").appendingPathComponent("labs").appendingPathComponent("documents")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let delegate = UploadProgressDelegate(onProgress: progress)
        let result: (Data, URLResponse)
        do {
            result = try await session.upload(for: request, from: data, delegate: delegate)
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError {
                switch urlError.code {
                case .cancelled:
                    throw CancellationError()
                case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                     .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
                    throw LabUploadError.offline
                default:
                    break
                }
            }
            throw LabUploadError.network(error.localizedDescription)
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw LabUploadError.server(0, nil)
        }
        let body = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
        switch http.statusCode {
        case 200, 201:
            progress(1)
            let document = body?["document"] as? [String: Any]
            let duplicate = (body?["duplicate"] as? Bool) ?? (http.statusCode == 200)
            return LabUploadResult(
                duplicate: duplicate,
                documentID: nonEmpty(document?["id"] as? String),
                documentStatus: nonEmpty(document?["status"] as? String),
                statusReason: nonEmpty(document?["status_reason"] as? String)
            )
        case 401, 403:
            throw LabUploadError.unauthorized
        case 404:
            throw LabUploadError.unavailable
        case 413:
            throw LabUploadError.tooLarge
        case 415:
            throw LabUploadError.unsupported
        case 422:
            throw LabUploadError.empty
        default:
            throw LabUploadError.server(http.statusCode, nonEmpty(body?["error"] as? String))
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Reports the share of the body sent so far (0...1).
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        // The last few percent wait for the server's answer.
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(min(0.97, max(0, fraction)))
    }
}
