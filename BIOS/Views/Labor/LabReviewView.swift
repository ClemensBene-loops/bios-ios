import PDFKit
import SwiftUI
import UIKit

/// One document: the review step while `zu_pruefen` (edit kind, date, title,
/// values; assign an unmapped value to a catalog marker and pick a unit from
/// the marker's accepted units; discard single values; "N Werte übernehmen" =
/// PATCH confirm), view
/// and edit when confirmed ("Änderungen speichern"), waiting reason while the
/// extraction runs, reason plus "Erneut versuchen" after an error. "Verwerfen"
/// deletes the document after a confirmation.
struct LabDocumentReviewView: View {
    let documentID: String
    @ObservedObject private var store = LabStore.shared
    @Environment(\.dismiss) private var dismiss

    struct ValueEdit: Equatable {
        var value: String
        var unit: String
        /// Catalog marker chosen in the picker; nil = unchanged.
        var marker: String? = nil
    }

    @State private var edits: [String: ValueEdit] = [:]
    @State private var discarded: Set<String> = []
    @State private var kind = ""
    @State private var title = ""
    @State private var issuer = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var loadedSignature: String?
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    /// Value whose marker is being chosen (sheet).
    @State private var assigning: LabValue?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let document = currentDocument {
                    content(document)
                } else if let error = store.documentErrors[documentID] {
                    NotEvaluableBox(title: "Nicht geladen", text: error)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Dokument wird geladen")
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    .biosCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .biosPageBackground()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .confirmationDialog("Dokument verwerfen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                Task { await discardDocument() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Datei und alle erkannten Werte werden am Server gelöscht. Das lässt sich nicht rückgängig machen.")
        }
        .sheet(item: $assigning) { value in
            LabMarkerPickerSheet(
                value: value,
                selected: effectiveMarkerID(value),
                onPick: { marker in assignMarker(marker, to: value) }
            )
        }
        .task {
            store.primeDocument(documentID)
            syncFromDocument()
            await store.loadDocument(documentID)
            syncFromDocument()
            await store.ensureCatalog()
        }
        .onChange(of: store.documents[documentID]) { _, _ in
            syncFromDocument()
        }
    }

    /// The full document, else the list entry (status, no values yet).
    private var currentDocument: LabDocument? {
        store.document(documentID) ?? store.listEntry(documentID)
    }

    private var navigationTitle: String {
        currentDocument?.status == .review ? "Befund prüfen" : "Befund"
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ document: LabDocument) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.displayTitle)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if !document.subline.isEmpty {
                Text(document.subline)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)

        LabStepsView(status: document.status)

        LabDocumentPreview(document: document)

        switch document.status {
        case .waiting:
            LabInfoLine(symbol: "hourglass",
                        text: "Wird ausgewertet",
                        detail: document.statusReason ?? store.review.waitingReason
                            ?? "Der Server erkennt die Werte gleich. Diese Seite aktualisiert sich von selbst.")
            discardButton
        case .failed:
            failedCard(document)
        default:
            assignmentCard(document)
            if document.isLetter && (document.values ?? []).isEmpty {
                summaryCard(document)
            }
            valuesSection(document)
            actions(document)
        }

        Text("Das Original bleibt auf deinem Server. Die Werte hat Claude erkannt; erst bestätigte Werte erscheinen in Verlauf und Fällig-Liste. Beobachtung, keine Diagnose.")
            .font(.caption)
            .foregroundStyle(BIOSTheme.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func failedCard(_ document: LabDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Auswertung fehlgeschlagen", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(BIOSTheme.midText)
            Text(document.statusReason ?? "Der Server konnte dieses Dokument nicht auswerten.")
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text1)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    Task { await retry() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().controlSize(.mini) }
                        Text("Erneut versuchen")
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BIOSTheme.accent)
                .disabled(saving)
                Button("Verwerfen", role: .destructive) {
                    confirmDelete = true
                }
                .buttonStyle(.bordered)
                .disabled(saving)
            }
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.midText)
            }
        }
        .biosCard()
    }

    private var discardButton: some View {
        Button("Dokument verwerfen", role: .destructive) {
            confirmDelete = true
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func assignmentCard(_ document: LabDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Zuordnung")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Text("Art")
                    .foregroundStyle(BIOSTheme.text2)
                Spacer()
                Picker("Art", selection: $kind) {
                    if kind.isEmpty {
                        Text("Bitte wählen").tag("")
                    }
                    ForEach(store.catalog.kinds) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(BIOSTheme.text1)
            }
            Divider().overlay(BIOSTheme.separator)
            Toggle(isOn: $hasDate.animation()) {
                Text("Abnahme- oder Messdatum")
                    .foregroundStyle(BIOSTheme.text2)
            }
            .tint(BIOSTheme.accent)
            if hasDate {
                DatePicker("Datum", selection: $date, in: ...Date(), displayedComponents: .date)
                    .foregroundStyle(BIOSTheme.text2)
            }
            Divider().overlay(BIOSTheme.separator)
            LabTextFieldRow(label: "Titel", placeholder: "z. B. Laborbefund", text: $title)
            Divider().overlay(BIOSTheme.separator)
            LabTextFieldRow(label: "Quelle", placeholder: "Labor oder Praxis", text: $issuer)
        }
        .font(.subheadline)
        .biosCard()
    }

    private func summaryCard(_ document: LabDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kurzfassung (automatisch erstellt)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(document.summaryPoints.enumerated()), id: \.offset) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("-")
                        .foregroundStyle(BIOSTheme.text3)
                    Text(entry.element)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .biosCard()
    }

    @ViewBuilder
    private func valuesSection(_ document: LabDocument) -> some View {
        let values = (document.values ?? []).filter { !$0.isDiscarded }
        let serverDiscarded = (document.values ?? []).filter(\.isDiscarded).count
        if document.values == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Werte werden geladen")
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text2)
            }
            .biosCard()
        } else if !values.isEmpty {
            LabSectionLabel(title: sectionTitle(document, count: values.count),
                            trailing: serverDiscarded > 0 ? "\(serverDiscarded) verworfen" : nil)
            VStack(spacing: 10) {
                ForEach(values) { value in
                    LabValueEditRow(
                        value: value,
                        discarded: discarded.contains(value.id),
                        valueText: valueBinding(value),
                        unitText: unitBinding(value),
                        marker: store.catalog.marker(effectiveMarkerID(value)),
                        markerChanged: edits[value.id]?.marker.map { $0 != value.markerID } ?? false,
                        canAssign: value.isUnmapped && !store.catalog.markers.isEmpty,
                        assign: { assigning = value },
                        toggleDiscard: { toggleDiscard(value.id) }
                    )
                }
            }
        }
    }

    private func sectionTitle(_ document: LabDocument, count: Int) -> String {
        if document.status == .review {
            return count == 1 ? "1 Wert erkannt, bitte prüfen" : "\(count) Werte erkannt, bitte prüfen"
        }
        return count == 1 ? "1 Wert" : "\(count) Werte"
    }

    @ViewBuilder
    private func actions(_ document: LabDocument) -> some View {
        let keep = (document.values ?? []).filter { !$0.isDiscarded && !discarded.contains($0.id) }.count
        VStack(spacing: 10) {
            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.midText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Verwerfen")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: 130)
                .disabled(saving)

                Button {
                    Task { await save(document) }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().controlSize(.small) }
                        Text(primaryTitle(document, keep: keep))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(BIOSTheme.accent)
                .disabled(saving || (document.status == .confirmed && !isDirty(document)))
            }
        }
        .padding(.top, 4)
    }

    private func primaryTitle(_ document: LabDocument, keep: Int) -> String {
        if document.status == .confirmed {
            return "Änderungen speichern"
        }
        if document.isLetter && keep == 0 {
            return "Kurzfassung übernehmen"
        }
        return keep == 1 ? "1 Wert übernehmen" : "\(keep) Werte übernehmen"
    }

    // MARK: - Editing state

    private func initialValueText(_ value: LabValue) -> String {
        if value.value != nil { return LabFormat.editText(value.value) }
        return value.valueText ?? ""
    }

    private func valueBinding(_ value: LabValue) -> Binding<String> {
        Binding(
            get: { edits[value.id]?.value ?? initialValueText(value) },
            set: { newValue in
                var edit = edits[value.id] ?? ValueEdit(value: initialValueText(value), unit: value.unit ?? "")
                edit.value = newValue
                edits[value.id] = edit
            }
        )
    }

    private func unitBinding(_ value: LabValue) -> Binding<String> {
        Binding(
            get: { edits[value.id]?.unit ?? (value.unit ?? "") },
            set: { newValue in
                var edit = edits[value.id] ?? ValueEdit(value: initialValueText(value), unit: value.unit ?? "")
                edit.unit = newValue
                edits[value.id] = edit
            }
        )
    }

    /// The marker picked in this session, else the value's own catalog marker.
    private func effectiveMarkerID(_ value: LabValue) -> String? {
        edits[value.id]?.marker ?? value.markerID
    }

    private func assignMarker(_ marker: LabCatalogMarker, to value: LabValue) {
        var edit = edits[value.id] ?? ValueEdit(value: initialValueText(value), unit: value.unit ?? "")
        edit.marker = marker.id == value.markerID ? nil : marker.id
        edits[value.id] = edit
        UIAccessibility.post(notification: .announcement, argument: "\(marker.name) zugeordnet")
    }

    private func toggleDiscard(_ id: String) {
        if discarded.contains(id) {
            discarded.remove(id)
        } else {
            discarded.insert(id)
        }
    }

    /// Fills the form from the document once, and again when the server sends a
    /// newer version while nothing was changed yet.
    private func syncFromDocument() {
        guard let document = store.document(documentID) else { return }
        let signature = "\(document.status.rawValue)|\(document.extractedAt?.timeIntervalSince1970 ?? 0)|\(document.confirmedAt?.timeIntervalSince1970 ?? 0)|\(document.values?.count ?? -1)"
        if loadedSignature == signature { return }
        if loadedSignature != nil && isDirty(document) { return }
        loadedSignature = signature
        edits = [:]
        discarded = []
        kind = document.kind ?? ""
        title = document.title ?? ""
        issuer = document.issuer ?? ""
        if let day = BIOSDate.day(document.collectedOn) {
            hasDate = true
            date = day
        } else {
            hasDate = false
            date = document.uploadedAt ?? Date()
        }
    }

    private func isDirty(_ document: LabDocument) -> Bool {
        !documentPatch(document).isEmpty || !valuePatches(document).isEmpty
    }

    private func documentPatch(_ document: LabDocument) -> [String: JSONValue] {
        var patch: [String: JSONValue] = [:]
        if !kind.isEmpty && kind != (document.kind ?? "") {
            patch["kind"] = .string(kind)
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle != (document.title ?? "") {
            patch["title"] = trimmedTitle.isEmpty ? .null : .string(trimmedTitle)
        }
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedIssuer != (document.issuer ?? "") {
            patch["issuer"] = trimmedIssuer.isEmpty ? .null : .string(trimmedIssuer)
        }
        if hasDate {
            let day = Self.dayString(date)
            if day != (document.collectedOn ?? "") {
                patch["collected_on"] = .string(day)
            }
        } else if document.collectedOn != nil {
            patch["collected_on"] = .null
        }
        return patch
    }

    /// Changed and discarded values; throws a German message for an invalid number.
    private func valuePatches(_ document: LabDocument) -> [JSONValue] {
        (try? buildValuePatches(document)) ?? [.null]
    }

    private func buildValuePatches(_ document: LabDocument) throws -> [JSONValue] {
        var result: [JSONValue] = []
        for value in document.values ?? [] where !value.isDiscarded {
            if discarded.contains(value.id) {
                result.append(.object(["id": .string(value.id), "discard": .bool(true)]))
                continue
            }
            guard let edit = edits[value.id] else { continue }
            var patch: [String: JSONValue] = [:]
            let text = edit.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if text != initialValueText(value) {
                if let number = LabFormat.parse(text) {
                    patch["value"] = .number(number)
                } else if value.value != nil || text.isEmpty {
                    throw LabReviewInputError(name: value.displayName)
                } else {
                    patch["value_text"] = .string(text)
                }
            }
            let unit = edit.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            if unit != (value.unit ?? "") {
                patch["unit"] = .string(unit)
            }
            if let marker = edit.marker, marker != value.markerID {
                patch["marker_id"] = .string(marker)
            }
            if !patch.isEmpty {
                patch["id"] = .string(value.id)
                result.append(.object(patch))
            }
        }
        return result
    }

    // MARK: - Actions

    private func save(_ document: LabDocument) async {
        errorText = nil
        let values: [JSONValue]
        do {
            values = try buildValuePatches(document)
        } catch let error as LabReviewInputError {
            errorText = error.message
            return
        } catch {
            errorText = error.localizedDescription
            return
        }
        var body: [String: JSONValue] = [:]
        let documentChanges = documentPatch(document)
        if !documentChanges.isEmpty {
            body["document"] = .object(documentChanges)
        }
        if !values.isEmpty {
            body["values"] = .array(values)
        }
        let confirming = document.status == .review
        if confirming {
            body["confirm"] = .bool(true)
        }
        guard !body.isEmpty else { return }
        saving = true
        let error = await store.patch(documentID, body: body)
        saving = false
        if let error {
            errorText = error
            return
        }
        loadedSignature = nil
        edits = [:]
        discarded = []
        UIAccessibility.post(notification: .announcement,
                             argument: confirming ? "Werte übernommen" : "Änderungen gespeichert")
        if confirming {
            dismiss()
        } else {
            syncFromDocument()
        }
    }

    private func retry() async {
        errorText = nil
        saving = true
        errorText = await store.retry(documentID)
        saving = false
    }

    private func discardDocument() async {
        errorText = nil
        saving = true
        let error = await store.delete(documentID)
        saving = false
        if let error {
            errorText = error
        } else {
            dismiss()
        }
    }

    private static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 2000)-\(BIOSFormat.twoDigits(parts.month ?? 1))-\(BIOSFormat.twoDigits(parts.day ?? 1))"
    }
}

struct LabReviewInputError: Error {
    let name: String

    var message: String {
        "\(name): bitte eine Zahl eingeben (Komma oder Punkt)."
    }
}

/// "1 Hochgeladen · 2 Erkannt · 3 Bestätigt".
struct LabStepsView: View {
    let status: LabDocumentStatus

    var body: some View {
        HStack(spacing: 6) {
            step(1, "Hochgeladen", state: .done)
            step(2, "Erkannt", state: recognized)
            step(3, "Bestätigt", state: status == .confirmed ? .done : (status == .review ? .now : .open))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt: \(status.label)")
    }

    private enum StepState {
        case done
        case now
        case open
    }

    private var recognized: StepState {
        switch status {
        case .review, .confirmed: return .done
        case .waiting: return .now
        default: return .open
        }
    }

    private func step(_ number: Int, _ text: String, state: StepState) -> some View {
        HStack(spacing: 4) {
            Image(systemName: state == .done ? "checkmark.circle.fill" : (state == .now ? "\(number).circle.fill" : "\(number).circle"))
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(state == .open ? BIOSTheme.text3 : (state == .now ? BIOSTheme.accent : BIOSTheme.good))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color.white.opacity(state == .now ? 0.08 : 0.04), in: Capsule())
    }
}

/// Label + text field in one row.
struct LabTextFieldRow: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(BIOSTheme.text2)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(BIOSTheme.text1)
                .submitLabel(.done)
        }
    }
}

/// One extracted value: name, printed reference, value and unit fields,
/// yellow note for review reasons (with page and snippet), discard toggle.
struct LabValueEditRow: View {
    let value: LabValue
    let discarded: Bool
    @Binding var valueText: String
    @Binding var unitText: String
    /// Catalog marker of the value (or the one just picked), for the unit menu.
    let marker: LabCatalogMarker?
    /// A marker was picked in this session and is not saved yet.
    let markerChanged: Bool
    /// Unmapped value and a loaded catalog: "Marker zuordnen" is offered.
    let canAssign: Bool
    let assign: () -> Void
    let toggleDiscard: () -> Void

    var body: some View {
        let unsure = !value.reviewReasons.isEmpty || value.needsReview
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(value.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(discarded ? BIOSTheme.text3 : BIOSTheme.text1)
                        .strikethrough(discarded)
                    if let meta {
                        Text(meta)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 6)
                Button(action: toggleDiscard) {
                    Image(systemName: discarded ? "arrow.uturn.backward.circle" : "trash")
                        .font(.body)
                        .foregroundStyle(discarded ? BIOSTheme.accent : BIOSTheme.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(discarded ? "\(value.displayName) wiederherstellen" : "\(value.displayName) verwerfen")
            }

            if discarded {
                Text("Wird beim Übernehmen verworfen.")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            } else {
                HStack(spacing: 8) {
                    if let symbol = LabFormat.comparatorSymbol(value.comparator) {
                        Text(symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    TextField("Wert", text: $valueText)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Wert \(value.displayName)")
                    TextField("Einheit", text: $unitText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: 110)
                        .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityLabel("Einheit \(value.displayName)")
                    if let choices = marker?.unitChoices, !choices.isEmpty {
                        Menu {
                            ForEach(choices, id: \.self) { unit in
                                Button {
                                    unitText = unit
                                } label: {
                                    if unit == unitText {
                                        Label(unit, systemImage: "checkmark")
                                    } else {
                                        Text(unit)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(BIOSTheme.accent)
                                .frame(width: 28, height: 36)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Einheit wählen, \(value.displayName)")
                    }
                }
                if canAssign || markerChanged {
                    markerRow
                }
                if unsure {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(reasonText, systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BIOSTheme.midText)
                        if let source {
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(unsure && !discarded ? BIOSTheme.mid.opacity(0.10) : BIOSTheme.card,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(unsure && !discarded ? BIOSTheme.mid.opacity(0.55) : Color.clear, lineWidth: 1)
        )
    }

    /// "Marker zuordnen" for an unmapped value, "Zugeordnet: HbA1c · Stoffwechsel" after the choice.
    private var markerRow: some View {
        Button(action: assign) {
            HStack(spacing: 8) {
                Image(systemName: markerChanged ? "checkmark.circle.fill" : "link.badge.plus")
                    .foregroundStyle(markerChanged ? BIOSTheme.good : BIOSTheme.accent)
                if markerChanged, let marker {
                    Text("Zugeordnet: " + ([marker.name] + [marker.groupLabel].compactMap { $0 }).joined(separator: " · "))
                        .foregroundStyle(BIOSTheme.text1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Text("Ändern")
                        .foregroundStyle(BIOSTheme.accent)
                } else {
                    Text("Marker zuordnen")
                        .foregroundStyle(BIOSTheme.accent)
                    Spacer(minLength: 6)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet die Liste der bekannten Marker")
    }

    private var meta: String? {
        var parts: [String] = []
        if let raw = value.rawName, raw != value.displayName {
            parts.append("im Befund: \(raw)")
        }
        if let ref = value.refDisplay { parts.append(ref) }
        if let z = value.zScore { parts.append("z \(BIOSFormat.signed(z, digits: 2))") }
        if value.status.isFlagged, let tag = value.status.tag { parts.append(tag) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var reasonText: String {
        let reasons = value.reviewReasons.map { LabReviewReason.text($0) }
        return reasons.isEmpty ? "Bitte prüfen" : "Bitte prüfen: " + reasons.joined(separator: ", ")
    }

    private var source: String? {
        var parts: [String] = []
        if let page = value.page { parts.append("Seite \(page)") }
        if let snippet = value.snippet { parts.append("\"\(snippet)\"") }
        return parts.isEmpty ? nil : parts.joined(separator: ": ")
    }
}

// MARK: - Marker picker

/// Searchable catalog (`GET /v1/labs/catalog`) grouped like the Labor tab.
/// Picking a marker only changes the form; it is sent with the next save.
struct LabMarkerPickerSheet: View {
    let value: LabValue
    let selected: String?
    let onPick: (LabCatalogMarker) -> Void
    @ObservedObject private var store = LabStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Im Befund")
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                        Text(value.rawName ?? value.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(value.printedText)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    .accessibilityElement(children: .combine)
                    .listRowBackground(BIOSTheme.card)
                }
                if store.catalog.markers.isEmpty {
                    Section {
                        Text("Der Katalog ist noch nicht geladen. Bitte mit Verbindung erneut öffnen.")
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                            .listRowBackground(BIOSTheme.card)
                    }
                } else if sections.isEmpty {
                    Section {
                        Text("Kein Marker passt zu \"\(query)\".")
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                            .listRowBackground(BIOSTheme.card)
                    }
                }
                ForEach(sections) { section in
                    Section(section.label) {
                        ForEach(section.markers) { marker in
                            Button {
                                onPick(marker)
                                dismiss()
                            } label: {
                                row(marker)
                            }
                            .listRowBackground(BIOSTheme.card)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .biosPageBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Marker oder Gruppe suchen")
            .navigationTitle("Marker zuordnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .task {
                await store.ensureCatalog()
            }
        }
    }

    private var sections: [LabCatalogSection] {
        store.catalog.sections(matching: query)
    }

    private func row(_ marker: LabCatalogMarker) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(marker.name)
                    .foregroundStyle(BIOSTheme.text1)
                if !marker.unitChoices.isEmpty {
                    Text(marker.unitChoices.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if marker.id == selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BIOSTheme.accent)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(marker.id == selected ? .isSelected : [])
    }
}

// MARK: - Preview of the original

/// Loads `GET /v1/labs/documents/{id}/file` (memory only) and shows PDF pages
/// or the image; "Vollbild" opens it large.
struct LabDocumentPreview: View {
    let document: LabDocument
    @State private var data: Data?
    @State private var contentType: String?
    @State private var errorText: String?
    @State private var loading = false
    @State private var fullScreen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Original")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if data != nil {
                    Button("Vollbild") { fullScreen = true }
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let data {
                LabFileView(data: data, isPDF: isPDF)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Vorschau des Dokuments")
            } else if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                Button("Erneut laden") {
                    Task { await load() }
                }
                .font(.footnote.weight(.semibold))
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Vorschau wird geladen")
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
            if let meta {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .biosCard()
        .task {
            await load()
        }
        .sheet(isPresented: $fullScreen) {
            NavigationStack {
                Group {
                    if let data {
                        LabFileView(data: data, isPDF: isPDF)
                    }
                }
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(document.displayTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { fullScreen = false }
                    }
                }
            }
        }
    }

    private var isPDF: Bool {
        (contentType ?? document.contentType ?? "").lowercased().contains("pdf")
    }

    private var meta: String? {
        var parts: [String] = []
        parts.append(document.isPDF ? "PDF" : "Bild")
        if let size = LabFormat.size(document.sizeBytes) { parts.append(size) }
        switch document.source ?? "" {
        case "app": parts.append("aus der App")
        case "inbox": parts.append("aus dem Ordner-Import")
        default: break
        }
        if let uploaded = document.uploadedAt { parts.append(BIOSFormat.relative(uploaded)) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard data == nil, !loading else { return }
        guard let client = APIClient.fromConfig() else {
            errorText = APIError.notConfigured.errorDescription
            return
        }
        loading = true
        errorText = nil
        do {
            let file = try await client.fetchLabFile(id: document.id)
            data = file.data
            contentType = file.contentType
        } catch {
            if !ErrorKind.isCancellation(error) {
                if let apiError = error as? APIError, apiError == .http(404) {
                    errorText = "Das Original ist am Server nicht mehr vorhanden."
                } else {
                    errorText = ErrorKind.isOffline(error) ? "Keine Verbindung, Vorschau nicht geladen." : "Vorschau nicht geladen."
                }
            }
        }
        loading = false
    }
}

/// PDF (PDFKit) or image, zoomable in the PDF case.
struct LabFileView: View {
    let data: Data
    let isPDF: Bool

    var body: some View {
        if isPDF {
            LabPDFView(data: data)
        } else if let image = UIImage(data: data) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 900)
            }
            .background(Color.black)
        } else {
            Text("Diese Datei kann hier nicht angezeigt werden.")
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
        }
    }
}

struct LabPDFView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(data: data)
        }
    }
}
