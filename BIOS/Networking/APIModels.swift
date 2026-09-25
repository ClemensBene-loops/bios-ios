import Foundation

/// Body of `POST {base}/v1/devices`.
struct DeviceRegistration: Encodable, Sendable {
    /// APNs device token, lowercase hex.
    let token: String
    /// "sandbox" or "production" (see `AppConfig.apnsEnvironment`).
    let environment: String
    let bundleID: String
    let deviceName: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case token
        case environment
        case bundleID = "bundle_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
    }
}

/// Response of `GET {base}/v1/summary` (used from Phase 3 on).
///
/// The inner documents mirror the server's `whoop_check.json` and
/// `outlook.json`; they are kept as generic JSON until the UI needs typed fields.
struct SummaryResponse: Decodable, Sendable {
    let whoopCheck: JSONValue?
    let outlook: JSONValue?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case whoopCheck = "whoop_check"
        case outlook
        case generatedAt = "generated_at"
    }
}

/// Minimal, lossless representation of an arbitrary JSON value.
enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// Member of an object, or nil.
    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self {
            return object[key]
        }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self {
            return value
        }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}
