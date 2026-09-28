import SwiftUI

/// Tab "Labor": segment "Werte | Befunde", import via "+" (PDF, photo,
/// camera), upload card on top. Werte = due list, summary chips, groups with
/// marker rows (only measured markers); Befunde = documents timeline with the
/// review step. Lab values never color the body map; a marker only links to
/// its region neutrally.
struct LaborView: View {
    @ObservedObject private var store = LabStore.shared
    @EnvironmentObject private var router: Router
    @AppStorage("bios.labor.segment") private var segment = LaborSegment.werte.rawValue
    @State private var importRequest: LabImportSource?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header

                Picker("Ansicht", selection: $segment) {
                    ForEach(LaborSegment.allCases, id: \.rawValue) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Ansicht: Werte oder Befunde")

                LabStatusBanner()

                if let phase = store.uploadPhase {
                    LabUploadCard(phase: phase) { documentID in
                        segment = LaborSegment.befunde.rawValue
                        if let documentID {
                            router.laborPath.append(.document(documentID))
                        }
                    }
                }

                if currentSegment == .werte {
                    LaborWerteSection { importRequest = .file }
                } else {
                    LaborBefundeSection { importRequest = .file }
                }

                if let disclaimer = store.overview?.disclaimer {
                    Text(disclaimer)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                } else {
                    Text("Beobachtung, keine Diagnose")
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                LabStandLine()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .navigationTitle("Labor")
        .navigationDestination(for: LabRoute.self) { route in
            LabRouteView(route: route)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LabImportMenu { source in
                    importRequest = source
                }
            }
        }
        .labImport(request: $importRequest)
        .refreshable {
            await store.refresh(force: true)
        }
        .task {
            await store.refresh()
            store.startPolling()
        }
        .onDisappear {
            store.stopPolling()
        }
    }

    private var currentSegment: LaborSegment {
        LaborSegment(rawValue: segment) ?? .werte
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headerText)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var headerText: String {
        let count = store.documentList.filter { $0.status == .confirmed }.count
        var parts: [String] = []
        parts.append(count == 1 ? "1 Befund" : "\(count) Befunde")
        if let last = BIOSDate.day(store.overview?.lastValueOn) {
            parts.append("zuletzt \(LabFormat.fullDate(last))")
        }
        return parts.joined(separator: " · ")
    }
}

enum LaborSegment: String, CaseIterable {
    case werte
    case befunde

    var title: String {
        switch self {
        case .werte: return "Werte"
        case .befunde: return "Befunde"
        }
    }
}

/// Destinations of the Labor tab's NavigationStack.
struct LabRouteView: View {
    let route: LabRoute

    var body: some View {
        switch route {
        case .marker(let id):
            LabMarkerDetailView(markerID: id)
        case .document(let id):
            LabDocumentReviewView(documentID: id)
        case .reviewList:
            LabReviewListView()
        }
    }
}

/// Offline / not configured / older server, above cached content.
struct LabStatusBanner: View {
    @ObservedObject private var store = LabStore.shared

    var body: some View {
        if store.isUnavailable {
            NotEvaluableBox(title: "Labor noch nicht verfügbar",
                            text: "Der Server kennt das Labor noch nicht. Nach dem Server-Update erscheinen hier Werte und Befunde.")
        } else if store.showsStaleData {
            OfflineBanner(isOffline: store.isOffline, error: store.lastError,
                          stand: store.overview?.generatedAt ?? store.fetchedAt)
        } else if store.overview == nil && store.documentsResponse == nil, let error = store.lastError {
            NotEvaluableBox(title: "Keine Daten", text: error)
        }
    }
}

/// "Stand 13:31", tap refreshes.
struct LabStandLine: View {
    @ObservedObject private var store = LabStore.shared

    var body: some View {
        Button {
            Task { await store.refresh(force: true) }
        } label: {
            HStack(spacing: 6) {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(text)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Aktualisiert Werte und Befunde")
        .padding(.top, 6)
    }

    private var text: String {
        guard let stand = store.fetchedAt else {
            return store.isLoading ? "Wird geladen ..." : "Noch nicht geladen"
        }
        let when = Calendar.current.isDateInToday(stand) ? BIOSFormat.time(stand) : BIOSFormat.relative(stand)
        if store.showsStaleData {
            return "Stand \(when) · " + (store.isOffline ? "offline" : "nicht aktualisiert")
        }
        return "Stand \(when)"
    }
}

// MARK: - Werte

/// Segment "Werte": due card, summary chips, groups with marker rows, empty state.
struct LaborWerteSection: View {
    @ObservedObject private var store = LabStore.shared
    let importAction: () -> Void

    var body: some View {
        let overview = store.overview
        VStack(alignment: .leading, spacing: 12) {
            if store.review.documents > 0 {
                LabReviewBanner(review: store.review, documents: store.reviewDocuments)
            }
            if let due = overview?.due, !due.isEmpty {
                LabDueCard(items: due)
            }
            if let overview, overview.hasValues {
                LabSummaryChips(overview: overview, review: store.review)
                ForEach(overview.groups) { group in
                    LabGroupSection(group: group)
                }
            } else if overview != nil || store.lastError == nil {
                LabEmptyState(importAction: importAction)
            }
        }
    }
}

/// "Fällig": what to measure next, open items first (server order).
struct LabDueCard: View {
    let items: [LabDue]
    @State private var showAll = false

    var body: some View {
        let shown = showAll ? items : Array(items.prefix(4))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Fällig")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            ForEach(shown) { item in
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.subheadline)
                        .foregroundStyle(item.status == "faellig" ? BIOSTheme.mid : BIOSTheme.text2)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.06), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BIOSTheme.text1)
                        Text(item.subline)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    Spacer(minLength: 6)
                    LabTag(text: item.tagText, style: tagStyle(item))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.label), \(item.subline), \(spoken(item))")
            }
            if items.count > 4 {
                Button(showAll ? "Weniger zeigen" : "Alle \(items.count) zeigen") {
                    withAnimation { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .biosCard()
    }

    private func tagStyle(_ item: LabDue) -> LabTag.Style {
        switch item.status {
        case "faellig": return .mid
        case "bald": return .context
        default: return .grey
        }
    }

    private func spoken(_ item: LabDue) -> String {
        switch item.status {
        case "faellig": return "fällig, \(item.tagText)"
        case "bald": return "bald fällig, \(item.tagText)"
        case "unbekannt": return "noch nie gemessen"
        default: return "nächster Termin \(item.tagText)"
        }
    }
}

/// Summary chips over all latest values.
struct LabSummaryChips: View {
    let overview: LabOverview
    let review: LabReviewSummary

    var body: some View {
        let statuses = overview.allMarkers.compactMap { $0.latest?.status }
        let normal = statuses.filter { $0 == .normal }.count
        let flagged = statuses.filter { $0.isFlagged }.count
        let noRef = statuses.filter { $0 == .keineReferenz }.count
        FlowLayout(spacing: 7, lineSpacing: 7) {
            LabTag(text: "\(normal) im Bereich", style: .good, symbol: "checkmark")
            if flagged > 0 {
                LabTag(text: "\(flagged) außerhalb Ref.", style: .mid, symbol: "arrow.up.arrow.down")
            }
            if noRef > 0 {
                LabTag(text: "\(noRef) ohne Referenz", style: .grey)
            }
            if review.values > 0 {
                LabTag(text: "\(review.values) zu prüfen", style: .context, symbol: "eye")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One group: label with count, card with marker rows.
struct LabGroupSection: View {
    let group: LabGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabSectionLabel(title: group.label, trailing: trailing)
            VStack(spacing: 0) {
                ForEach(Array(group.markers.enumerated()), id: \.element.id) { index, marker in
                    if index > 0 {
                        Rectangle()
                            .fill(BIOSTheme.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 14)
                    }
                    NavigationLink(value: LabRoute.marker(marker.id)) {
                        LabMarkerRow(marker: marker)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var trailing: String {
        let count = group.markers.count == 1 ? "1 Marker" : "\(group.markers.count) Marker"
        if group.nFlagged > 0 {
            return "\(count) · \(group.nFlagged) außerhalb"
        }
        return count
    }
}

/// Marker row: name, date and reference, value with unit, tag, bar, sparkline.
struct LabMarkerRow: View {
    let marker: LabMarkerEntry

    var body: some View {
        let point = marker.latest
        let status = point?.status ?? .unknown
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(marker.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text3)
                    }
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(valueText)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text1)
                        if let unit = point?.unit ?? marker.unit {
                            Text(unit)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                        }
                    }
                    if let tag = status.tag {
                        LabTag(text: tag, style: LabTag.style(for: status))
                    }
                }
            }
            HStack(spacing: 10) {
                LabRangeBar(scale: LabBarScale(point: point, target: marker.target), status: status)
                LabSparkline(values: marker.sparkline.map(\.value), status: status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Öffnet den Verlauf")
        .accessibilityAddTraits(.isButton)
    }

    private var valueText: String {
        guard let point = marker.latest else { return "n. v." }
        return LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText)
    }

    private var meta: String {
        guard let point = marker.latest else { return "kein Wert" }
        var parts: [String] = []
        if let date = point.date { parts.append(LabFormat.fullDate(date)) }
        if point.usesZScore, let z = point.zScore {
            var text = "z \(BIOSFormat.signed(z, digits: 2))"
            if let pct = point.pctPredicted { text = "\(BIOSFormat.number(pct)) % Soll · " + text }
            parts.append(text)
        } else if let ref = LabFormat.refRange(low: point.refLow, high: point.refHigh, decimals: marker.decimals, unit: nil) {
            parts.append("Ref. \(ref)")
        } else {
            parts.append("ohne Referenz")
        }
        return parts.joined(separator: " · ")
    }

    private var spoken: String {
        var text = "\(marker.name): \(valueText) \(marker.latest?.unit ?? marker.unit ?? "")"
        if let status = marker.latest?.status, !status.spoken.isEmpty {
            text += ", \(status.spoken)"
        }
        text += ", \(meta)"
        return text
    }
}

/// No confirmed values yet: explanation and the import button.
struct LabEmptyState: View {
    let importAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.title3)
                    .foregroundStyle(BIOSTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(BIOSTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                Text("Noch keine Laborwerte")
                    .font(.headline)
            }
            Text("Lade einen Befund als PDF oder Foto hoch, oder teile ihn aus einer anderen App über \"Teilen\" > BIOS. Der Server erkennt die Werte, du prüfst sie, erst dann erscheinen sie hier mit Referenzbereich und Verlauf. Nie gemessene Marker werden nicht angezeigt.")
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: importAction) {
                Label("Befund importieren", systemImage: "square.and.arrow.down")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BIOSTheme.accent)
        }
        .biosCard()
    }
}
