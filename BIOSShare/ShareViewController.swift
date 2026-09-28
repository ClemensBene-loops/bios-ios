import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share extension "BIOS" (at.bene.bios.share): takes one PDF or image from the
/// share sheet and uploads it to `POST /v1/labs/documents` (LabUpload,
/// SharedUpload/). Images become JPEG first. The server URL and secret come from
/// this extension's own Info.plist (injected by workflow 4, like BIOSWidgets).
/// Minimal UI: "An BIOS senden", file name, progress, done.
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

/// State of the share sheet.
@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// Before the first upload from the share sheet: short note, then "Senden".
        case notice
        case uploading(Double)
        case done(duplicate: Bool)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var fileName = "Dokument"

    var finish: (() -> Void)?
    var cancel: (() -> Void)?

    /// The extension has its own defaults (no App Group): the note appears once here.
    private static let noticeKey = "bios.share.noticeSeen"
    private var prepared: (data: Data, contentType: String)?
    private var uploadTask: Task<Void, Never>?

    func load(items: [NSExtensionItem]) {
        let providers = items.flatMap { $0.attachments ?? [] }
        if let pdf = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) }) {
            fileName = pdf.suggestedName.map { $0.lowercased().hasSuffix(".pdf") ? $0 : $0 + ".pdf" } ?? "Dokument.pdf"
            pdf.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                // The file only exists during this callback: read it here.
                let data = url.flatMap { try? Data(contentsOf: $0) }
                let message = error?.localizedDescription
                Task { @MainActor [weak self] in
                    self?.received(data: data, contentType: "application/pdf", error: message)
                }
            }
            return
        }
        if let image = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            let base = image.suggestedName ?? "Foto"
            fileName = (base as NSString).deletingPathExtension + ".jpg"
            image.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                let jpeg = data.flatMap { LabUploadImage.jpeg(from: $0) }
                let message = data != nil && jpeg == nil ? "Das Bild ließ sich nicht umwandeln." : error?.localizedDescription
                Task { @MainActor [weak self] in
                    self?.received(data: jpeg, contentType: "image/jpeg", error: message)
                }
            }
            return
        }
        phase = .failed("Nur PDF oder Bilder lassen sich an BIOS senden.")
    }

    private func received(data: Data?, contentType: String, error: String?) {
        guard let data, !data.isEmpty else {
            phase = .failed(error.map { "Datei nicht gelesen: \($0)" } ?? "Die Datei ließ sich nicht lesen.")
            return
        }
        if data.count > LabUpload.maxBytes {
            phase = .failed("Die Datei ist größer als 15 MB. Bitte eine kleinere Datei oder einzelne Seiten senden.")
            return
        }
        prepared = (data, contentType)
        if UserDefaults.standard.bool(forKey: Self.noticeKey) {
            send()
        } else {
            phase = .notice
        }
    }

    /// Starts (or retries) the upload.
    func send() {
        guard let prepared, uploadTask == nil else { return }
        UserDefaults.standard.set(true, forKey: Self.noticeKey)
        phase = .uploading(0)
        let data = prepared.data
        let contentType = prepared.contentType
        uploadTask = Task { @MainActor in
            do {
                let result = try await LabUpload.upload(data: data, contentType: contentType) { [weak self] fraction in
                    Task { @MainActor in
                        self?.setProgress(fraction)
                    }
                }
                self.phase = .done(duplicate: result.duplicate)
                self.uploadTask = nil
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                self.finish?()
            } catch {
                self.uploadTask = nil
                if error is CancellationError { return }
                self.phase = .failed((error as? LabUploadError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func setProgress(_ fraction: Double) {
        guard case .uploading = phase else { return }
        phase = .uploading(fraction)
    }

    func close() {
        uploadTask?.cancel()
        if case .done = phase {
            finish?()
        } else {
            cancel?()
        }
    }

    var canRetry: Bool {
        prepared != nil
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel

    private let card = Color(red: 0.075, green: 0.086, blue: 0.106)
    private let text2 = Color(red: 0.655, green: 0.682, blue: 0.729)
    private let accent = Color(red: 0.353, green: 0.655, blue: 1.0)
    private let good = Color(red: 0.204, green: 0.839, blue: 0.384)
    private let mid = Color(red: 1.0, green: 0.878, blue: 0.478)

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button("Abbrechen") { model.close() }
                    .foregroundStyle(accent)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 16) {
                Text("An BIOS senden")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    Image(systemName: model.fileName.lowercased().hasSuffix(".pdf") ? "doc.text" : "photo")
                        .font(.title3)
                        .foregroundStyle(text2)
                        .accessibilityHidden(true)
                    Text(model.fileName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Datei \(model.fileName)")
                status
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(16)
        .foregroundStyle(Color.white)
        .environment(\.locale, Locale(identifier: "de_AT"))
    }

    @ViewBuilder private var status: some View {
        switch model.phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Datei wird gelesen")
                    .foregroundStyle(text2)
            }
            .font(.subheadline)
        case .notice:
            Text("Der Befund wird auf deinem BIOS-Server gespeichert und dort mit Claude (Anthropic) ausgewertet. Du prüfst die erkannten Werte danach in der App unter Labor. Beobachtung, keine Diagnose.")
                .font(.footnote)
                .foregroundStyle(text2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.send()
            } label: {
                Text("Senden")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        case .uploading(let progress):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(accent)
                Text("Wird gesendet, \(Int((progress * 100).rounded())) %")
                    .font(.footnote)
                    .foregroundStyle(text2)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .done(let duplicate):
            Label(duplicate ? "Schon in BIOS, nichts doppelt angelegt" : "Gesendet. Die Werte prüfst du in der App unter Labor.",
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(good)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.close()
            } label: {
                Text("Fertig")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(mid)
                .fixedSize(horizontal: false, vertical: true)
            if model.canRetry {
                Button {
                    model.send()
                } label: {
                    Text("Erneut senden")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(accent)
            }
        }
    }
}
