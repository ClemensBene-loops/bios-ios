import SwiftUI

/// Upload card on top of the Labor tab. One file: progress, done (or "Schon
/// vorhanden"), error, as before. Several files: "Wird gesendet, 3 von 5" and a
/// small list with the state of each file; duplicates and errors stay calm per row.
struct LabUploadCard: View {
    let items: [LabUploadItem]
    let open: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BIOSTheme.text1)
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 6)
                if !running {
                    Button {
                        LabStore.shared.clearUpload()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text2)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hinweis schließen")
                }
            }

            if items.count == 1, let only = items.first {
                singleBody(only.phase)
            } else {
                if running {
                    ProgressView(value: overallProgress)
                        .tint(BIOSTheme.accent)
                        .accessibilityLabel("Fortschritt")
                        .accessibilityValue("\(finishedCount) von \(items.count) fertig")
                }
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        LabUploadRow(item: item)
                    }
                }
                if !running {
                    Text(doneText)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Zu den Befunden") {
                        LabStore.shared.clearUpload()
                        open(nil)
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .biosCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    // MARK: One file

    @ViewBuilder
    private func singleBody(_ phase: LabUploadPhase) -> some View {
        switch phase {
        case .queued, .preparing:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .uploading(_, let progress):
            ProgressView(value: progress)
                .tint(BIOSTheme.accent)
                .accessibilityValue("\(Int((progress * 100).rounded())) Prozent")
        case .done(_, let duplicate, let documentID, _):
            Text(duplicate
                 ? "Diese Datei ist schon in BIOS. Es wurde nichts doppelt angelegt."
                 : "Der Server erkennt die Werte jetzt, meist in ein bis zwei Minuten. Danach prüfst du sie unter Befunde.")
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Button(documentID == nil ? "Zu den Befunden" : "Dokument ansehen") {
                LabStore.shared.clearUpload()
                open(documentID)
            }
            .font(.footnote.weight(.semibold))
        case .failed(_, let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Summary

    private var running: Bool {
        items.contains { $0.phase.isRunning }
    }

    private var finishedCount: Int {
        items.filter { $0.phase.isFinished }.count
    }

    private var newCount: Int {
        items.filter { item in
            if case .done(_, false, _, _) = item.phase { return true }
            return false
        }.count
    }

    private var duplicateCount: Int {
        items.filter { item in
            if case .done(_, true, _, _) = item.phase { return true }
            return false
        }.count
    }

    private var failedCount: Int {
        items.filter { item in
            if case .failed = item.phase { return true }
            return false
        }.count
    }

    /// The file being prepared or sent right now.
    private var current: LabUploadItem? {
        items.first { item in
            switch item.phase {
            case .preparing, .uploading: return true
            default: return false
            }
        }
    }

    /// Position of the file being handled ("3 von 5").
    private var currentPosition: Int {
        if let current, let index = items.firstIndex(of: current) {
            return index + 1
        }
        if let index = items.firstIndex(where: { $0.phase.isRunning }) {
            return index + 1
        }
        return items.count
    }

    /// Finished files plus the share of the running transfer.
    private var overallProgress: Double {
        guard !items.isEmpty else { return 0 }
        var done = Double(finishedCount)
        for item in items {
            if case .uploading(_, let progress) = item.phase { done += progress }
        }
        return min(1, done / Double(items.count))
    }

    private var title: String {
        if items.count == 1, let only = items.first {
            switch only.phase {
            case .queued, .preparing: return "Wird vorbereitet"
            case .uploading(_, let progress): return "Wird gesendet, \(Int((progress * 100).rounded())) %"
            case .done(_, let duplicate, _, _): return duplicate ? "Schon vorhanden" : "Hochgeladen"
            case .failed: return "Nicht gesendet"
            }
        }
        if running {
            return "Wird gesendet, \(currentPosition) von \(items.count)"
        }
        if failedCount == items.count {
            return "Nicht gesendet"
        }
        return "\(items.count - failedCount) von \(items.count) Dateien angekommen"
    }

    private var subtitle: String {
        if items.count == 1, let only = items.first {
            return only.name
        }
        if running, let current {
            return current.name
        }
        var parts: [String] = []
        if newCount > 0 { parts.append(newCount == 1 ? "1 neu" : "\(newCount) neu") }
        if duplicateCount > 0 { parts.append("\(duplicateCount) schon vorhanden") }
        if failedCount > 0 { parts.append("\(failedCount) nicht gesendet") }
        return parts.joined(separator: " · ")
    }

    private var doneText: String {
        var text = newCount > 0
            ? "Der Server erkennt die Werte jetzt, meist in ein bis zwei Minuten je Datei. Danach prüfst du sie unter Befunde."
            : "Es wurde nichts Neues angelegt."
        if failedCount > 0 {
            text += " Nicht gesendete Dateien bitte noch einmal importieren."
        }
        return text
    }

    private var symbol: String {
        if running { return "arrow.up.circle" }
        if failedCount == items.count { return "exclamationmark.circle" }
        if items.count == 1, duplicateCount == 1 { return "doc.on.doc" }
        return "checkmark.circle"
    }

    private var tint: Color {
        if running { return BIOSTheme.accent }
        if failedCount == items.count { return BIOSTheme.mid }
        return BIOSTheme.good
    }
}

/// One file of a multi-file import: name and its state in a few words.
struct LabUploadRow: View {
    let item: LabUploadItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(stateColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(stateText)")
    }

    @ViewBuilder private var icon: some View {
        switch item.phase {
        case .queued:
            Image(systemName: "circle.dotted")
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text3)
        case .preparing, .uploading:
            ProgressView()
                .controlSize(.mini)
        case .done(_, let duplicate, _, _):
            Image(systemName: duplicate ? "doc.on.doc" : "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(duplicate ? BIOSTheme.text2 : BIOSTheme.good)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(BIOSTheme.mid)
        }
    }

    private var stateText: String {
        switch item.phase {
        case .queued: return "wartet"
        case .preparing: return "wird vorbereitet"
        case .uploading(_, let progress): return "wird gesendet, \(Int((progress * 100).rounded())) %"
        case .done(_, let duplicate, _, _): return duplicate ? "schon vorhanden, nichts doppelt angelegt" : "angekommen"
        case .failed(_, let message): return message
        }
    }

    private var stateColor: Color {
        switch item.phase {
        case .failed: return BIOSTheme.midText
        default: return BIOSTheme.text2
        }
    }
}
