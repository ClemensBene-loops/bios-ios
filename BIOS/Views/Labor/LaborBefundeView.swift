import SwiftUI

// Segment "Befunde": review banner, waiting/error lines, filter chips by kind,
// documents timeline grouped by month, expandable cards (values or summary
// points of a letter), status badges. Plus the review list for push deep links.

/// "3 Werte erkannt, bitte prüfen" with a button to the review screen.
struct LabReviewBanner: View {
    let review: LabReviewSummary
    let documents: [LabDocument]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "eye")
                .font(.body.weight(.semibold))
                .foregroundStyle(BIOSTheme.contextText)
                .frame(width: 34, height: 34)
                .background(BIOSTheme.context.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            NavigationLink(value: route) {
                Text("Prüfen")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(BIOSTheme.accent, in: Capsule())
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), prüfen")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BIOSTheme.context.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(BIOSTheme.context.opacity(0.35), lineWidth: 1)
        )
    }

    private var route: LabRoute {
        if documents.count == 1, let only = documents.first {
            return .document(only.id)
        }
        return .reviewList
    }

    private var title: String {
        let values = review.values
        if values > 0 {
            return values == 1 ? "1 Wert erkannt, bitte prüfen" : "\(values) Werte erkannt, bitte prüfen"
        }
        return review.documents == 1 ? "1 Befund zu prüfen" : "\(review.documents) Befunde zu prüfen"
    }

    private var subtitle: String {
        var parts: [String] = []
        if documents.count == 1, let only = documents.first {
            parts.append(only.displayTitle)
        } else if review.documents > 1 {
            parts.append("\(review.documents) Dokumente")
        }
        if review.flaggedValues > 0 {
            parts.append(review.flaggedValues == 1 ? "1 unsicher" : "\(review.flaggedValues) unsicher")
        }
        parts.append("erst bestätigte Werte zählen")
        return parts.joined(separator: " · ")
    }
}

/// Segment "Befunde".
struct LaborBefundeSection: View {
    @ObservedObject private var store = LabStore.shared
    let importAction: () -> Void
    @State private var filter = "alle"

    var body: some View {
        let documents = store.documentList
        let review = store.review
        VStack(alignment: .leading, spacing: 12) {
            if review.documents > 0 {
                LabReviewBanner(review: review, documents: store.reviewDocuments)
            }
            if review.waiting > 0 {
                LabInfoLine(
                    symbol: "hourglass",
                    text: review.waiting == 1 ? "1 Dokument wird ausgewertet" : "\(review.waiting) Dokumente werden ausgewertet",
                    detail: review.waitingReason ?? "Meist in ein bis zwei Minuten. Die Liste aktualisiert sich von selbst."
                )
            }
            if review.errors > 0 {
                LabInfoLine(
                    symbol: "exclamationmark.triangle",
                    text: review.errors == 1 ? "1 Dokument konnte nicht ausgewertet werden" : "\(review.errors) Dokumente konnten nicht ausgewertet werden",
                    detail: "Grund und \"Erneut versuchen\" stehen beim Dokument."
                )
            }

            if documents.isEmpty {
                if store.documentsResponse != nil || store.lastError == nil {
                    LabEmptyState(importAction: importAction)
                }
            } else {
                filterChips(documents)
                timeline(filtered(documents))
            }

            LabInfoLine(
                symbol: "square.and.arrow.up",
                text: "Befunde importieren",
                detail: "\"+\" oben rechts, \"Teilen\" > BIOS aus Mail oder Dateien, oder am PC in den Ordner labs/inbox legen."
            )
        }
    }

    private func filtered(_ documents: [LabDocument]) -> [LabDocument] {
        guard filter != "alle" else { return documents }
        return documents.filter { ($0.kind ?? "offen") == filter }
    }

    /// "Alle" plus the kinds that occur.
    private func filterChips(_ documents: [LabDocument]) -> some View {
        var options: [LabFilterOption] = [LabFilterOption(id: "alle", label: "Alle")]
        for document in documents {
            let id = document.kind ?? "offen"
            if !options.contains(where: { $0.id == id }) {
                options.append(LabFilterOption(id: id, label: document.kind == nil ? "Neu" : (document.kindLabel ?? id)))
            }
        }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(options) { option in
                    let selected = option.id == filter
                    Button {
                        filter = option.id
                    } label: {
                        Text(option.label)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.black : BIOSTheme.text2)
                            .background(Capsule().fill(selected ? BIOSTheme.text1 : BIOSTheme.card2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityLabel("Filter \(option.label)")
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Documents grouped by month (server order: newest first).
    private func timeline(_ documents: [LabDocument]) -> some View {
        var sections: [LabMonthSection] = []
        for document in documents {
            let month = document.date.map { LabFormat.month($0) } ?? "Ohne Datum"
            if let index = sections.firstIndex(where: { $0.id == month }) {
                sections[index].documents.append(document)
            } else {
                sections.append(LabMonthSection(id: month, documents: [document]))
            }
        }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(sections) { section in
                LabSectionLabel(title: section.id)
                ForEach(section.documents) { document in
                    LabDocumentCard(document: document)
                }
            }
            if documents.isEmpty {
                Text("Keine Befunde dieser Art.")
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text2)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct LabFilterOption: Identifiable {
    let id: String
    let label: String
}

struct LabMonthSection: Identifiable {
    /// Month title ("September 2026").
    let id: String
    var documents: [LabDocument]
}

/// Calm info line (waiting, errors, import hint).
struct LabInfoLine: View {
    let symbol: String
    let text: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(BIOSTheme.text2)
                .frame(width: 34, height: 34)
                .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text1)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .biosCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

/// Status badge of a document.
struct LabDocumentBadge: View {
    let document: LabDocument

    var body: some View {
        switch document.status {
        case .waiting:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text("wird ausgewertet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text2)
            }
        case .review:
            LabTag(text: "zu prüfen", style: .context, symbol: "eye")
        case .failed:
            LabTag(text: "Fehler", style: .bad, symbol: "exclamationmark.triangle")
        case .confirmed:
            if document.isLetter {
                LabTag(text: "Brief", style: .grey)
            } else {
                LabTag(text: "bestätigt", style: .good, symbol: "checkmark")
            }
        case .discarded, .unknown:
            LabTag(text: document.status.label, style: .grey)
        }
    }
}

/// Expandable document card. Values load on the first expand
/// (`GET /v1/labs/documents/{id}`); letters show their summary points.
struct LabDocumentCard: View {
    let document: LabDocument
    @ObservedObject private var store = LabStore.shared
    @EnvironmentObject private var router: Router
    @State private var expanded = false
    @State private var busy = false
    @State private var actionError: String?
    @State private var confirmDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    LabKindIcon(kind: document.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text1)
                            .multilineTextAlignment(.leading)
                        Text(document.subline)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 6)
                    LabDocumentBadge(document: document)
                    if expandable {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text3)
                    } else if document.status == .review {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(document.displayTitle), \(document.subline), \(document.status.label)")
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)

            switch document.status {
            case .waiting:
                Text(document.statusReason ?? "Wartet auf die Auswertung. Meist in ein bis zwei Minuten.")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed:
                failedBody
            default:
                if expanded {
                    expandedBody
                }
            }
        }
        .biosCard(padding: 14)
        .confirmationDialog("Dokument verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                Task { await discard() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Die Datei und alle erkannten Werte werden am Server gelöscht.")
        }
    }

    private var expandable: Bool {
        document.status == .confirmed
    }

    private var hint: String {
        switch document.status {
        case .review: return "Öffnet die Prüfung"
        case .confirmed: return expanded ? "Klappt die Werte zu" : "Zeigt die Werte"
        default: return ""
        }
    }

    private func toggle() {
        switch document.status {
        case .review:
            router.laborPath.append(.document(document.id))
        case .confirmed:
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            if expanded {
                store.primeDocument(document.id)
                if !document.isLetter || store.document(document.id) == nil {
                    Task { await store.loadDocument(document.id) }
                }
            }
        default:
            break
        }
    }

    @ViewBuilder private var failedBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(document.statusReason ?? "Die Auswertung ist fehlgeschlagen.")
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text1)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    Task { await retry() }
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.mini) }
                        Text("Erneut versuchen")
                    }
                    .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(BIOSTheme.accent)
                .disabled(busy)
                Button("Verwerfen", role: .destructive) {
                    confirmDiscard = true
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            if let actionError {
                Text(actionError)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.midText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var expandedBody: some View {
        let detail = store.document(document.id)
        VStack(alignment: .leading, spacing: 8) {
            if document.isLetter || (detail?.values?.isEmpty ?? true) && !document.summaryPoints.isEmpty {
                Text("Kurzfassung (automatisch erstellt)")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                ForEach(Array((detail?.summaryPoints ?? document.summaryPoints).enumerated()), id: \.offset) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("-")
                            .foregroundStyle(BIOSTheme.text3)
                        Text(entry.element)
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let values = detail?.values?.filter({ !$0.isDiscarded }), !values.isEmpty {
                VStack(spacing: 6) {
                    ForEach(values) { value in
                        HStack(spacing: 8) {
                            Text(value.displayName)
                                .font(.footnote)
                                .foregroundStyle(BIOSTheme.text2)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            Text(value.printedText)
                                .font(.footnote.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text1)
                            if let tag = value.status.tag, value.status.isFlagged {
                                LabTag(text: tag, style: LabTag.style(for: value.status))
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else if detail == nil, !document.isLetter {
                if let error = store.documentErrors[document.id] {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Werte werden geladen")
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                }
            }
            Button {
                router.laborPath.append(.document(document.id))
            } label: {
                Label("Original und Werte bearbeiten", systemImage: "doc.text.magnifyingglass")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(BIOSTheme.accent)
            .padding(.top, 2)
        }
    }

    private func retry() async {
        busy = true
        actionError = await store.retry(document.id)
        busy = false
    }

    private func discard() async {
        busy = true
        actionError = await store.delete(document.id)
        busy = false
    }
}

/// All documents waiting for a review (push "labor_pruefen", Heute card).
struct LabReviewListView: View {
    @ObservedObject private var store = LabStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                let documents = store.reviewDocuments
                if documents.isEmpty {
                    if store.isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Wird geladen")
                                .foregroundStyle(BIOSTheme.text2)
                        }
                        .biosCard()
                    } else {
                        NotEvaluableBox(title: "Nichts zu prüfen", text: "Alle erkannten Werte sind bestätigt oder verworfen.")
                    }
                } else {
                    Text(documents.count == 1 ? "1 Befund wartet auf deine Prüfung." : "\(documents.count) Befunde warten auf deine Prüfung.")
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text2)
                        .padding(.horizontal, 4)
                    ForEach(documents) { document in
                        LabDocumentCard(document: document)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .biosPageBackground()
        .navigationTitle("Zu prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refresh(force: true)
        }
        .task {
            await store.refresh(force: true)
        }
    }
}
