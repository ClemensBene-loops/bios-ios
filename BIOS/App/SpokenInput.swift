import Foundation

/// Parsing of spoken or typed Siri answers (German). Siri hands a German
/// decimal comma to a Double parameter as text it cannot convert, so values
/// are taken as String and parsed here.
enum SpokenInput {
    /// Body temperature in °C from "36,6", "36.6", "36 Komma 6", "36,6 Grad",
    /// "sechsunddreißig Komma sechs" or "366" (three digits 340...430 = tenths).
    /// Returns nil for anything outside 34...43 °C.
    static func temperature(_ raw: String) -> Double? {
        var text = raw.lowercased()
            .replacingOccurrences(of: "°c", with: " ")
            .replacingOccurrences(of: "°", with: " ")
            .replacingOccurrences(of: "grad", with: " ")
            .replacingOccurrences(of: "celsius", with: " ")
            .replacingOccurrences(of: "ß", with: "ss")
        for separator in [".", "komma", "punkt", ","] {
            text = text.replacingOccurrences(of: separator, with: " . ")
        }
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }

        // Integer part = tokens before the first ".", decimals = tokens after it.
        let dotIndex = tokens.firstIndex(of: ".")
        let integerTokens = dotIndex.map { Array(tokens[..<$0]) } ?? tokens
        let decimalTokens = dotIndex.map { Array(tokens[tokens.index(after: $0)...]) } ?? []

        guard let integerPart = number(integerTokens.joined()) else { return nil }
        var value = Double(integerPart.value)
        if !decimalTokens.isEmpty {
            // Decimal digits: "6", "65", "sechs", "sechs fünf".
            var digits = ""
            for token in decimalTokens where token != "." {
                if token.allSatisfy(\.isNumber) {
                    digits += token
                } else if let digit = digitWords[token] {
                    digits += String(digit)
                } else {
                    return nil
                }
            }
            guard !digits.isEmpty, let fraction = Double("0." + digits) else { return nil }
            value += fraction
        } else if integerPart.isDigits, (340...430).contains(integerPart.value) {
            // "366" = 36,6 (Siri sometimes drops the comma).
            value = Double(integerPart.value) / 10
        } else if integerPart.isDigits, (3400...4300).contains(integerPart.value) {
            value = Double(integerPart.value) / 100
        }
        value = (value * 10).rounded() / 10
        return (34...43).contains(value) ? value : nil
    }

    /// Answers that mean "keep the default" ("normal", "Standard", "wie geplant").
    static func isDefaultAnswer(_ raw: String?) -> Bool {
        guard let raw else { return true }
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if text.isEmpty { return true }
        let words = ["normal", "standard", "wie immer", "wie geplant", "plan", "laut plan", "ok", "okay",
                     "ja", "passt", "weiter", "egal", "default", "übernehmen", "die übliche", "das übliche"]
        return words.contains(text)
    }

    /// "jetzt", "gerade", "eben": the answer means now.
    static func isNowAnswer(_ raw: String?) -> Bool {
        guard let raw else { return true }
        let text = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.isEmpty || ["jetzt", "gerade", "eben", "gerade eben", "sofort", "now"].contains(text)
    }

    // MARK: Numbers

    private static let digitWords: [String: Int] = [
        "null": 0, "eins": 1, "ein": 1, "eine": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4,
        "fünf": 5, "fuenf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
    ]

    private static let tensWords: [String: Int] = [
        "zwanzig": 20, "dreissig": 30, "vierzig": 40, "fünfzig": 50, "fuenfzig": 50,
    ]

    /// Digits ("36") or a German number word from 0 to 59 ("sechsunddreissig").
    private static func number(_ token: String) -> (value: Int, isDigits: Bool)? {
        if !token.isEmpty, token.allSatisfy(\.isNumber), let value = Int(token) {
            return (value, true)
        }
        if let digit = digitWords[token] { return (digit, false) }
        if let tens = tensWords[token] { return (tens, false) }
        if let range = token.range(of: "und") {
            let unitWord = String(token[..<range.lowerBound])
            let tensWord = String(token[range.upperBound...])
            if let unit = digitWords[unitWord], let tens = tensWords[tensWord] {
                return (tens + unit, false)
            }
        }
        return nil
    }
}
