import SwiftUI

// Segment "Werte": group chips, search field and the filter over the overview's
// groups. Chips and search work together (group AND query); the chosen group is
// kept for the app session (`LabWerteViewState`), the search text per visit.

/// UI state of "Werte" that survives switching segments and tabs while the app runs.
@MainActor
final class LabWerteViewState: ObservableObject {
    static let shared = LabWerteViewState()

    /// Chip id: "alle" or a group id of the overview.
    @Published var group = LabWerteViewState.all
    /// Card "Eigene Messungen", collapsed by default.
    @Published var ownExpanded = false

    nonisolated static let all = "alle"
}

/// Search over name, short names, marker id and group, tolerant of case,
/// umlauts ("ae" = "ä"), hyphens and spaces ("LDL-C" = "ldl c", "Vit D").
enum LabMarkerSearch {

    /// Common German lab abbreviations per catalog id (generic, no personal data).
    /// The server's printed-name aliases are not sent to the app; this list covers
    /// the usual short names, the marker names themselves carry the rest.
    static let builtInAliases: [String: [String]] = [
        "hba1c": ["A1c", "Langzeitzucker", "Glykohämoglobin"],
        "blood_glucose": ["Glukose", "Glucose", "BZ", "Zucker", "Fingerstich"],
        "glucose": ["Glucose", "BZ", "Zucker"],
        "glucose_fasting": ["Glucose", "BZ", "Zucker", "Nüchternzucker"],
        "bg_capillary": ["BZ", "Zucker", "Glukose"],
        "bg_fingerstick": ["BZ", "Zucker", "Glukose", "Fingerstich"],
        "cholesterol_total": ["Cholesterin", "Chol", "TC"],
        "ldl": ["LDL-C"],
        "hdl": ["HDL-C"],
        "non_hdl": ["Non-HDL"],
        "triglycerides": ["TG", "Triglyzeride"],
        "apob": ["ApoB"],
        "lpa": ["Lp(a)", "Lpa"],
        "nt_probnp": ["BNP"],
        "creatinine": ["Krea", "Crea", "Kreat"],
        "egfr": ["GFR"],
        "urea": ["Urea"],
        "potassium": ["Kalium"],
        "sodium": ["Na", "Natrium"],
        "uric_acid": ["Urat"],
        "alt": ["GPT", "ALAT"],
        "ast": ["GOT", "ASAT"],
        "ggt": ["GGT", "γ-GT", "Gamma GT"],
        "alp": ["AP", "ALP"],
        "bilirubin": ["Bili"],
        "hemoglobin": ["Hb", "HGB"],
        "hematocrit": ["Hk", "Hkt", "HCT"],
        "leukocytes": ["Leukos", "Leuko", "WBC"],
        "erythrocytes": ["Erys", "Ery", "RBC"],
        "platelets": ["Thrombos", "PLT", "Blutplättchen"],
        "iron": ["Fe"],
        "transferrin_sat": ["TSAT"],
        "vitamin_d": ["Vit D", "Vitamin D", "25-OH-D", "D3", "Calcidiol"],
        "vitamin_b12": ["B12", "Vit B12", "Cobalamin"],
        "folate": ["Folat", "Folsäure"],
        "magnesium": ["Mg"],
        "calcium": ["Ca", "Kalzium"],
        "phosphate": ["Phosphor"],
        "crp": ["C-reaktives Protein"],
        "hs_crp": ["hsCRP"],
        "esr": ["BSG", "BSR", "Senkung"],
        "tsh": ["Thyreotropin"],
        "ft4": ["Thyroxin"],
        "ft3": ["Trijodthyronin"],
        "tpo_ak": ["TPO", "Anti-TPO"],
        "fev1": ["Spirometrie", "Lungenfunktion"],
        "fvc": ["Spirometrie", "Lungenfunktion"],
        "fev1_fvc": ["Tiffeneau", "Spirometrie"],
        "ahi": ["Apnoe"],
        "ttg_iga": ["tTG", "Zöliakie"],
    ]

    /// Lowercase, diacritics folded, "ae/oe/ue" and "ß" unified, only letters and digits.
    static func normalize(_ text: String) -> String {
        var folded = text.lowercased().replacingOccurrences(of: "ß", with: "ss")
        folded = folded.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                locale: Locale(identifier: "de_AT"))
        for (pair, single) in [("ae", "a"), ("oe", "o"), ("ue", "u")] {
            folded = folded.replacingOccurrences(of: pair, with: single)
        }
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Whether `marker` (in `group`) matches `query`: the whole query in one field, or
    /// every word of it somewhere ("hdl blutfette"). An empty query matches everything.
    static func matches(_ marker: LabMarkerEntry, group: LabGroup, query: String) -> Bool {
        let whole = normalize(query)
        guard !whole.isEmpty else { return true }
        var fields = [marker.name, marker.id, group.label, group.id] + marker.aliases
        fields += builtInAliases[marker.id] ?? []
        let haystack = fields.map(normalize).filter { !$0.isEmpty }
        if haystack.contains(where: { $0.contains(whole) }) {
            return true
        }
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { normalize(String($0)) }.filter { !$0.isEmpty }
        guard words.count > 1 else { return false }
        return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
    }
}

/// One group after chips and search.
struct LabFilteredGroup: Identifiable {
    let group: LabGroup
    let markers: [LabMarkerEntry]

    var id: String { group.id }
}

/// Groups and markers left after the chip `groupID` and the search `query`.
struct LabWerteFilter {
    let sections: [LabFilteredGroup]
    /// Hits in all groups (for "In anderen Gruppen: 2 Treffer" when the chip hides them).
    let hitsInAllGroups: Int

    init(groups: [LabGroup], groupID: String, query: String) {
        let all = groups.map { group in
            LabFilteredGroup(group: group,
                             markers: group.markers.filter { LabMarkerSearch.matches($0, group: group, query: query) })
        }
        hitsInAllGroups = all.reduce(0) { $0 + $1.markers.count }
        sections = all.filter { !$0.markers.isEmpty && (groupID == LabWerteViewState.all || $0.group.id == groupID) }
    }

    var isEmpty: Bool { sections.isEmpty }
    var hitCount: Int { sections.reduce(0) { $0 + $1.markers.count } }
}

/// Inline search field at the top of "Werte".
struct LabMarkerSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BIOSTheme.text3)
                .accessibilityHidden(true)
            TextField("Werte suchen", text: $text,
                      prompt: Text("Suchen, z. B. LDL, HbA1c, TSH").foregroundColor(BIOSTheme.text3))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .foregroundStyle(BIOSTheme.text1)
                .accessibilityLabel("Laborwerte suchen")
                .accessibilityHint("Name, Kürzel oder Gruppe, zum Beispiel LDL, HbA1c, Ferritin oder TSH")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BIOSTheme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Suche löschen")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

/// Horizontally scrolling filter chips ("Alle", then one per kind or group), shared
/// by "Werte" (groups) and "Befunde" (document kinds).
struct LabFilterChipBar: View {
    let options: [LabFilterOption]
    let selection: String
    let select: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(options) { option in
                        let selected = option.id == selection
                        Button {
                            select(option.id)
                        } label: {
                            Text(option.label)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? Color.black : BIOSTheme.text2)
                                .background(Capsule().fill(selected ? BIOSTheme.text1 : BIOSTheme.card2))
                        }
                        .buttonStyle(.plain)
                        .id(option.id)
                        .accessibilityLabel(option.spoken)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 2)
            }
            .onAppear {
                // A group remembered from earlier in the session may sit off screen.
                if selection != options.first?.id {
                    proxy.scrollTo(selection, anchor: .center)
                }
            }
        }
    }
}

/// Search or chip without a hit.
struct LabNoMatchView: View {
    let query: String
    let groupLabel: String?
    let hitsElsewhere: Int
    let showAllGroups: () -> Void
    let clearSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kein Wert gefunden")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if hitsElsewhere > 0, groupLabel != nil {
                    Button(hitsElsewhere == 1 ? "1 Treffer in allen Gruppen" : "\(hitsElsewhere) Treffer in allen Gruppen",
                           action: showAllGroups)
                }
                if !query.isEmpty {
                    Button("Suche löschen", action: clearSearch)
                }
            }
            .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .biosCard()
    }

    private var detail: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = trimmed.isEmpty ? "Keine Werte in dieser Gruppe." : "Kein gemessener Wert passt zu \"\(trimmed)\""
        if !trimmed.isEmpty, let groupLabel {
            text += " in \(groupLabel)"
        }
        if !trimmed.isEmpty {
            text += ". Nie gemessene Marker erscheinen hier nicht."
        }
        return text
    }
}
