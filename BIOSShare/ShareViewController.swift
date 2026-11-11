import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share extension "BIOS" (at.bene.bios.share): takes 1 to 10 PDFs or images
/// from the share sheet and uploads them one after another to
/// `POST /v1/labs/documents` (LabUpload, SharedUpload/). Images become JPEG
/// first. Each file is read only when its turn comes (the extension has little
/// memory). The server URL and secret come from this extension's own Info.plist
/// (injected by workflow 4, like BIOSWidgets). Minimal UI: "An BIOS senden",
/// file name or list, progress ("3 von 5"), done; duplicates and errors per file.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.024, green: 0.031, blue: 0.043, alpha: 1)
        overrideUserInterfaceStyle = .dark

        model.finish = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        model.cancel = { [weak self] in
            let error = NSError(domain: "at.bene.bios.share", code: NSUserCancelledError)
            self?.extensionContext?.cancelRequest(withError: error)
        }

        let host = UIHostingController(rootView: ShareView(model: model))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        model.load(items: items)
    }
}

/// Data of one attachment (nil with a reason when it could not be read).
struct ShareReadResult: Sendable {
    let data: Data?
    let contentType: String
    let error: String?
}

/// State of the share sheet.
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// Before the first upload from the share sheet: short note, then "Senden".
        case notice
        case running
        case finished
        case failed(String)
    }

    enum FileState: Equatable {
        case waiting
        case reading
        case uploading(Double)
        case done(duplicate: Bool)
        case failed(String)

        var isDone: Bool {
            if case .done = self { return true }
            return false
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }

        var isActive: Bool {
            switch self {
            case .reading, .uploading: return true
            default: return false
            }
        }
    }

    struct Entry: Identifiable, Equatable {
        let id: Int
        let name: String
        let isPDF: Bool
        var state: FileState
    }

    /// At most this many files per share (the activation rule allows 10 per item).
    static let maxFiles = 10

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var entries: [Entry] = []
    /// Files beyond `maxFiles` that were left out.
    @Published private(set) var skipped = 0

    var finish: (() -> Void)?
    var cancel: (() -> Void)?

    /// The extension has its own defaults (no App Group): the note appears once here.
    private static let noticeKey = "bios.share.noticeSeen"
    private var providers: [Int: NSItemProvider] = [:]
    private var uploadTask: Task<Void, Never>?

    func load(items: [NSExtensionItem]) {
        let all = items.flatMap { $0.attachments ?? [] }.filter { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !all.isEmpty else {
            phase = .failed("Nur PDF oder Bilder lassen sich an BIOS senden.")
            return
        }
        skipped = max(0, all.count - Self.maxFiles)
        var photoNumber = 0
        let multiple = all.count > 1
        for (index, provider) in all.prefix(Self.maxFiles).enumerated() {
            let isPDF = provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier)
            let name: String
            if isPDF {
                name = provider.suggestedName.map { $0.lowercased().hasSuffix(".pdf") ? $0 : $0 + ".pdf" } ?? "Dokument.pdf"
            } else if let suggested = provider.suggestedName {
                name = (suggested as NSString).deletingPathExtension + ".jpg"
            } else {
                photoNumber += 1
                name = multiple ? "Foto \(photoNumber).jpg" : "Foto.jpg"
            }
            providers[index] = provider
            entries.append(Entry(id: index, name: name, isPDF: isPDF, state: .waiting))
        }
        if UserDefaults.standard.bool(forKey: Self.noticeKey) {
            send()
        } else {
            phase = .notice
        }
    }

    /// Starts the uploads, or retries the files that failed (sent ones stay sent).
    func send() {
        guard uploadTask == nil, !entries.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: Self.noticeKey)
        for index in entries.indices where entries[index].state.isFailed {
            entries[index].state = .waiting
        }
        phase = .running
        uploadTask = Task { @MainActor in
            for entry in self.entries where entry.state == .waiting {
                if Task.isCancelled { break }
                await self.upload(entry.id)
            }
            self.uploadTask = nil
            if Task.isCancelled { return }
            self.phase = .finished
            if !self.entries.contains(where: { $0.state.isFailed }) {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                self.finish?()
            }
        }
    }

    /// Reads, converts and sends one file.
    private func upload(_ id: Int) async {
        guard let provider = providers[id], let entry = entries.first(where: { $0.id == id }) else { return }
        setState(id, .reading)
        let read = await Self.read(provider, isPDF: entry.isPDF)
        guard let data = read.data, !data.isEmpty else {
            setState(id, .failed(read.error.map { "Datei nicht gelesen: \($0)" } ?? "Die Datei ließ sich nicht lesen."))
            return
        }
        if data.count > LabUpload.maxBytes {
            setState(id, .failed("Größer als 15 MB. Bitte eine kleinere Datei oder einzelne Seiten senden."))
            return
        }
        setState(id, .uploading(0))
        do {
            let result = try await LabUpload.upload(data: data, contentType: read.contentType) { [weak self] fraction in
                Task { @MainActor in
                    self?.setProgress(id, fraction)
                }
            }
            setState(id, .done(duplicate: result.duplicate))
        } catch {
            if error is CancellationError {
                setState(id, .failed("Abgebrochen."))
                return
            }
            setState(id, .failed((error as? LabUploadError)?.errorDescription ?? error.localizedDescription))
        }
    }

    /// The data of one attachment: PDF as is, images as JPEG. Runs the provider's
    /// callback off the main thread; the file only exists during that callback.
    private static func read(_ provider: NSItemProvider, isPDF: Bool) async -> ShareReadResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShareReadResult, Never>) in
            if isPDF {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                    let data = url.flatMap { try? Data(contentsOf: $0) }
                    continuation.resume(returning: ShareReadResult(data: data, contentType: "application/pdf",
                                                                   error: error?.localizedDescription))
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    let jpeg = data.flatMap { LabUploadImage.jpeg(from: $0) }
                    let message = data != nil && jpeg == nil ? "Das Bild ließ sich nicht umwandeln." : error?.localizedDescription
                    continuation.resume(returning: ShareReadResult(data: jpeg, contentType: "image/jpeg", error: message))
                }
            }
        }
    }

    private func setState(_ id: Int, _ state: FileState) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].state = state
    }

    private func setProgress(_ id: Int, _ fraction: Double) {
        guard let index = entries.firstIndex(where: { $0.id == id }), case .uploading = entries[index].state else { return }
        entries[index].state = .uploading(fraction)
    }

    func close() {
        uploadTask?.cancel()
        if entries.contains(where: { $0.state.isDone }) {
            finish?()
        } else {
            cancel?()
        }
    }

    // MARK: Summary for the view

    var isRunning: Bool { phase == .running }

    var canRetry: Bool {
        phase == .finished && entries.contains { $0.state.isFailed }
    }

    var doneCount: Int {
        entries.filter { $0.state.isDone || $0.state.isFailed }.count
    }

    /// "3" in "3 von 5": the file being handled.
    var position: Int {
        if let index = entries.firstIndex(where: { $0.state.isActive }) { return index + 1 }
        return min(entries.count, doneCount + 1)
    }

    var overallProgress: Double {
        guard !entries.isEmpty else { return 0 }
        var done = Double(doneCount)
        for entry in entries {
            if case .uploading(let fraction) = entry.state { done += fraction }
        }
        return min(1, done / Double(entries.count))
    }

    var newCount: Int {
        entries.filter { $0.state == .done(duplicate: false) }.count
    }

    var duplicateCount: Int {
        entries.filter { $0.state == .done(duplicate: true) }.count
    }

    var failedCount: Int {
        entries.filter { $0.state.isFailed }.count
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    private let card = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let card2 = Color(red: 0.11, green: 0.122, blue: 0.145)
    private let text2 = Color(red: 0.655, green: 0.682, blue: 0.729)
    private let accent = Color(red: 0.353, green: 0.655, blue: 1.0)
    private let good = Color(red: 0.204, green: 0.839, blue: 0.384)
    private let mid = Color(red: 1.0, green: 0.878, blue: 0.478)

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button(model.phase == .finished ? "Schließen" : "Abbrechen") { model.close() }
                    .foregroundStyle(accent)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("An BIOS senden")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    files
                    status
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(16)
        .foregroundStyle(Color.white)
        .environment(\.locale, Locale(identifier: "de_AT"))
    }

    // MARK: Files

    @ViewBuilder private var files: some View {
        if model.entries.count == 1, let only = model.entries.first {
            HStack(spacing: 12) {
                Image(systemName: only.isPDF ? "doc.text" : "photo")
                    .font(.title3)
                    .foregroundStyle(text2)
                    .accessibilityHidden(true)
                Text(only.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Datei \(only.name)")
        } else if model.entries.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(model.entries.count) Dateien")
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 6)
                ForEach(model.entries) { entry in
                    row(entry)
                }
                if model.skipped > 0 {
                    Text(model.skipped == 1
                         ? "1 weitere Datei nicht gesendet: höchstens \(ShareModel.maxFiles) auf einmal."
                         : "\(model.skipped) weitere Dateien nicht gesendet: höchstens \(ShareModel.maxFiles) auf einmal.")
                        .font(.caption)
                        .foregroundStyle(text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
        }
    }

    private func row(_ entry: ShareModel.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            rowIcon(entry)
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.footnote)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(stateText(entry.state))
                    .font(.caption)
                    .foregroundStyle(entry.state.isFailed ? mid : text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name), \(stateText(entry.state))")
    }

    @ViewBuilder private func rowIcon(_ entry: ShareModel.Entry) -> some View {
        switch entry.state {
        case .waiting:
            Image(systemName: entry.isPDF ? "doc.text" : "photo")
                .font(.footnote)
                .foregroundStyle(text2)
        case .reading, .uploading:
            ProgressView()
                .controlSize(.mini)
        case .done(let duplicate):
            Image(systemName: duplicate ? "doc.on.doc" : "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(duplicate ? text2 : good)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(mid)
        }
    }

    private func stateText(_ state: ShareModel.FileState) -> String {
        switch state {
        case .waiting: return model.phase == .notice ? "bereit" : "wartet"
        case .reading: return "wird gelesen"
        case .uploading(let progress): return "wird gesendet, \(Int((progress * 100).rounded())) %"
        case .done(let duplicate): return duplicate ? "schon in BIOS, nichts doppelt angelegt" : "gesendet"
        case .failed(let message): return message
        }
    }

    // MARK: Status

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Dateien werden gelesen")
                    .foregroundStyle(text2)
            }
            .font(.subheadline)
        case .notice:
            Text("Befunde werden auf deinem BIOS-Server gespeichert und dort mit Claude (Anthropic) ausgewertet. Du prüfst die erkannten Werte danach in der App unter Labor. Beobachtung, keine Diagnose.")
                .font(.footnote)
                .foregroundStyle(text2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.send()
            } label: {
                Text(model.entries.count > 1 ? "\(model.entries.count) Dateien senden" : "Senden")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        case .running:
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: model.overallProgress)
                    .tint(accent)
                Text(runningText)
                    .font(.footnote)
                    .foregroundStyle(text2)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .finished:
            finishedView
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(mid)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var runningText: String {
        if model.entries.count == 1, case .uploading(let progress)? = model.entries.first?.state {
            return "Wird gesendet, \(Int((progress * 100).rounded())) %"
        }
        if model.entries.count == 1 {
            return "Wird vorbereitet"
        }
        return "Wird gesendet, \(model.position) von \(model.entries.count)"
    }

    @ViewBuilder private var finishedView: some View {
        let failed = model.failedCount
        let total = model.entries.count
        if failed == 0 {
            Label(successText, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(good)
                .fixedSize(horizontal: false, vertical: true)
        } else if total == 1, case .failed(let message)? = model.entries.first?.state {
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(mid)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("\(total - failed) von \(total) gesendet, \(failed) nicht. Die Gründe stehen bei den Dateien.",
                  systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(mid)
                .fixedSize(horizontal: false, vertical: true)
        }
        if model.canRetry {
            Button {
                model.send()
            } label: {
                Text(failed == 1 || total == 1 ? "Erneut senden" : "\(failed) erneut senden")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(accent)
        }
        Button {
            model.close()
        } label: {
            Text("Fertig")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var successText: String {
        let total = model.entries.count
        if total == 1 {
            return model.duplicateCount == 1
                ? "Schon in BIOS, nichts doppelt angelegt"
                : "Gesendet. Die Werte prüfst du in der App unter Labor."
        }
        var text = "\(total) Dateien angekommen"
        if model.duplicateCount > 0 {
            text += ", davon \(model.duplicateCount) schon vorhanden"
        }
        return text + ". Die Werte prüfst du in der App unter Labor."
    }
}
