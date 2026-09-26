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

/// Body of `POST {base}/v1/events`: `{"date": "YYYY-MM-DD", "kind": "alcohol", "note": null}`.
struct EventBody: Encodable, Sendable {
    let date: String
    let kind: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case date
        case kind
        case note
    }

    /// Writes `note` as explicit null instead of omitting it.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(date, forKey: .date)
        try container.encode(kind, forKey: .kind)
        if let note {
            try container.encode(note, forKey: .note)
        } else {
            try container.encodeNil(forKey: .note)
        }
    }
}

/// Response of `GET {base}/v1/summary`.
///
/// The inner documents are the server's `whoop_check.json` and `outlook.json`,
/// kept as generic JSON and read defensively by `BIOSWhoopCheck` / `BIOSOutlook`
/// (SummaryModels.swift), so a new or changed server field never breaks decoding.
/// Codable so the last good response can be cached on disk.
struct SummaryResponse: Codable, Sendable {
    let whoopCheck: JSONValue?
    let outlook: JSONValue?
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
        case whoopCheck = "whoop_check"
        case outlook
        case generatedAt = "generated_at"
    }

    init(whoopCheck: JSONValue?, outlook: JSONValue?, generatedAt: String?) {
        self.whoopCheck = whoopCheck
        self.outlook = outlook
        self.generatedAt = generatedAt
    }

    /// Lenient: a missing or oddly typed member becomes nil instead of an error.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` flattens the optional (Swift 5): nil for missing, null or broken.
        let whoop: JSONValue? = try? container.decodeIfPresent(JSONValue.self, forKey: .whoopCheck)
        let outlook: JSONValue? = try? container.decodeIfPresent(JSONValue.self, forKey: .outlook)
        let generated: JSONValue? = try? container.decodeIfPresent(JSONValue.self, forKey: .generatedAt)
        self.whoopCheck = whoop
        self.outlook = outlook
        self.generatedAt = generated?.stringValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(whoopCheck, forKey: .whoopCheck)
        try container.encodeIfPresent(outlook, forKey: .outlook)
        try container.encodeIfPresent(generatedAt, forKey: .generatedAt)
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

    /// Finite number as Int (never traps on NaN or huge values), or nil.
    var intValue: Int? {
        guard let value = numberValue, value.isFinite, abs(value) < 1_000_000_000 else {
            return nil
        }
        return Int(value.rounded())
    }

    /// Elements of an array, or an empty array for anything else.
    var arrayValue: [JSONValue] {
        if case .array(let value) = self {
            return value
        }
        return []
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    /// Strings of an array member (other element types are skipped).
    func strings(_ key: String) -> [String] {
        (self[key]?.arrayValue ?? []).compactMap { $0.stringValue }
    }
}
