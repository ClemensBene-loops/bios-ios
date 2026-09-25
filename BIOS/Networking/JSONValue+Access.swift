import Foundation

// Lenient accessors on top of `JSONValue` (APIModels.swift). Every accessor
// returns nil / empty / a default for a missing member or a wrong type, so
// the models built from server JSON can never crash on a new or missing field.
extension JSONValue {
    func str(_ key: String) -> String? {
        guard let value = self[key]?.stringValue else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Finite number, or nil (NaN/Inf never reach the UI).
    func double(_ key: String) -> Double? {
        guard let value = self[key]?.numberValue, value.isFinite else { return nil }
        return value
    }

    func int(_ key: String) -> Int? {
        self[key]?.intValue
    }

    /// true/false, also accepts 0/1; `fallback` for anything else.
    func flag(_ key: String, fallback: Bool = false) -> Bool {
        if let value = self[key]?.boolValue { return value }
        if let number = self[key]?.numberValue { return number != 0 }
        return fallback
    }

    /// Elements of an array member (empty for anything else).
    func list(_ key: String) -> [JSONValue] {
        self[key]?.arrayValue ?? []
    }

    /// Member that is an object, or nil (null, missing and wrong types are nil).
    func obj(_ key: String) -> JSONValue? {
        guard let value = self[key], value.objectValue != nil else { return nil }
        return value
    }

    /// Array of numbers where null (or a non-number) becomes a gap.
    func optionalNumbers(_ key: String) -> [Double?] {
        list(key).map { element -> Double? in
            guard let value = element.numberValue, value.isFinite else { return nil }
            return value
        }
    }

    /// The value itself as a finite number, or nil.
    var finiteNumber: Double? {
        guard let value = numberValue, value.isFinite else { return nil }
        return value
    }
}
