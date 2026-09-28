import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Import from inside the app: "+" -> PDF from Files, a photo from the library
// or the camera. Photos and image files become JPEG, PDFs stay PDF. Before the
// very first upload a one-time notice explains the cloud extraction (stored
// flag, never shown again). The upload itself: LabStore.upload -> LabUpload.

enum LabImportSource: String, Identifiable {
    case file
    case photo
    case camera

    var id: String { rawValue }
}

enum LabImportNotice {
    /// Set once the notice was confirmed; never reset by the app.
    static let acceptedKey = "bios.labs.cloudNoticeAccepted"
}

/// "+" in the toolbar of the Labor tab.
struct LabImportMenu: View {
    let select: (LabImportSource) -> Void

    var body: some View {
        Menu {
            Button {
                select(.file)
            } label: {
                Label("PDF oder Bild aus Dateien", systemImage: "doc")
            }
            Button {
                select(.photo)
            } label: {
                Label("Foto auswählen", systemImage: "photo")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    select(.camera)
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                }
            }
        } label: {
            Image(systemName: "plus.circle")
        }
        .accessibilityLabel("Befund importieren")
        .accessibilityHint("PDF aus Dateien, Foto auswählen oder aufnehmen")
    }
}

extension View {
    /// Presents the import sources for `request` (with the one-time notice first).
    func labImport(request: Binding<LabImportSource?>) -> some View {
        modifier(LabImportModifier(request: request))
    }
}

@MainActor
struct LabImportModifier: ViewModifier {
    @Binding var request: LabImportSource?
    @AppStorage(LabImportNotice.acceptedKey) private var noticeAccepted = false

    @State private var pending: LabImportSource?
    @State private var showNotice = false
    @State private var noticeConfirmed = false
    @State private var showFiles = false
    @State private var showPhotos = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .onChange(of: request) { _, newValue in
                guard let source = newValue else { return }
                request = nil
                if noticeAccepted {
                    present(source)
                } else {
                    pending = source
                    noticeConfirmed = false
                    showNotice = true
                }
            }
            .sheet(isPresented: $showNotice, onDismiss: {
                if noticeConfirmed, let source = pending {
                    pending = nil
                    present(source)
                } else {
                    pending = nil
                }
            }) {
                LabCloudNoticeSheet {
                    noticeAccepted = true
                    noticeConfirmed = true
                    showNotice = false
                } cancel: {
                    showNotice = false
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importFile(url)
                    }
                case .failure(let error):
                    LabStore.shared.reportPreparationError(name: "Datei", message: "Datei nicht geöffnet: \(error.localizedDescription)")
                }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                importPhoto(item)
            }
            .fullScreenCover(isPresented: $showCamera) {
                LabCameraPicker { image in
                    showCamera = false
                    if let image {
                        importImage(image)
                    }
                }
                .ignoresSafeArea()
            }
    }

    private func present(_ source: LabImportSource) {
        switch source {
        case .file: showFiles = true
        case .photo: showPhotos = true
        case .camera: showCamera = true
        }
    }

    // MARK: - Preparing the data

    private func importFile(_ url: URL) {
        let name = url.lastPathComponent
        LabStore.shared.beginPreparing(name: name)
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                LabImportPreparer.prepareFile(url)
            }.value
            await finish(prepared, name: name)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        let name = LabImportPreparer.photoName()
        LabStore.shared.beginPreparing(name: name)
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await finish(.failure("Das Foto ließ sich nicht laden."), name: name)
                    return
                }
                let prepared = await Task.detached(priority: .userInitiated) {
                    LabImportPreparer.prepareImageData(data)
                }.value
                await finish(prepared, name: name)
            } catch {
                await finish(.failure("Das Foto ließ sich nicht laden: \(error.localizedDescription)"), name: name)
            }
        }
    }

    private func importImage(_ image: UIImage) {
        let name = LabImportPreparer.photoName()
        LabStore.shared.beginPreparing(name: name)
        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                LabImportPreparer.prepareImage(image)
            }.value
            await finish(prepared, name: name)
        }
    }

    private func finish(_ prepared: LabPreparedFile, name: String) async {
        switch prepared {
        case .ready(let data, let contentType):
            await LabStore.shared.upload(data: data, contentType: contentType, name: name)
        case .failure(let message):
            LabStore.shared.reportPreparationError(name: name, message: message)
        }
    }
}

/// Result of preparing a picked file for the upload.
enum LabPreparedFile: Sendable {
    case ready(Data, String)
    case failure(String)
}

enum LabImportPreparer {
    /// PDF stays PDF (size checked), images become JPEG.
    static func prepareFile(_ url: URL) -> LabPreparedFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            return .failure("Die Datei ließ sich nicht lesen.")
        }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true || data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
            if data.count > LabUpload.maxBytes {
                return .failure("Die PDF ist größer als 15 MB. Bitte eine kleinere Datei oder einzelne Seiten senden.")
            }
            return .ready(data, "application/pdf")
        }
        return prepareImageData(data)
    }

    static func prepareImageData(_ data: Data) -> LabPreparedFile {
        guard let jpeg = LabUploadImage.jpeg(from: data) else {
            return .failure("Dieses Format wird nicht unterstützt. Bitte als PDF oder Foto senden.")
        }
        return check(jpeg)
    }

    static func prepareImage(_ image: UIImage) -> LabPreparedFile {
        guard let jpeg = LabUploadImage.jpeg(from: image) else {
            return .failure("Das Foto ließ sich nicht umwandeln.")
        }
        return check(jpeg)
    }

    private static func check(_ jpeg: Data) -> LabPreparedFile {
        if jpeg.count > LabUpload.maxBytes {
            return .failure("Das Bild ist auch verkleinert größer als 15 MB.")
        }
        return .ready(jpeg, "image/jpeg")
    }

    /// "Foto 28.09. 10:14.jpg".
    static func photoName(now: Date = Date()) -> String {
        "Foto \(BIOSFormat.shortDate(now)) \(BIOSFormat.time(now)).jpg"
    }
}

/// One-time notice before the first upload.
struct LabCloudNoticeSheet: View {
    let accept: () -> Void
    let cancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundStyle(BIOSTheme.accent)
                    .accessibilityHidden(true)
                Text("Befunde auswerten lassen")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    point("server.rack", "Das Original wird auf deinem BIOS-Server gespeichert.")
                    point("cloud", "Zum Erkennen der Werte schickt der Server das Dokument an die Claude-API (Anthropic). Es wird dort ausgewertet, nicht in BIOS weitergegeben.")
                    point("checkmark.circle", "Du prüfst jeden erkannten Wert, bevor er zählt. Unsichere Werte sind gelb markiert.")
                    point("stethoscope", "Anzeige und Beobachtung, keine Diagnose. Referenzbereiche kommen vom jeweiligen Labor.")
                }
                Text("Dieser Hinweis erscheint nur einmal.")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text3)
                Button(action: accept) {
                    Text("Verstanden, weiter")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(BIOSTheme.accent)
                Button("Abbrechen", action: cancel)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(BIOSTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(BIOSTheme.text2)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// UIImagePickerController with the camera (single photo).
struct LabCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}

/// Upload state on top of the Labor tab: progress, done (or duplicate), error.
struct LabUploadCard: View {
    let phase: LabUploadPhase
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
                    Text(phase.name)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if !phase.isRunning {
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
            switch phase {
            case .preparing:
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
        .biosCard(padding: 14)
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch phase {
        case .preparing: return "Wird vorbereitet"
        case .uploading(_, let progress): return "Wird gesendet, \(Int((progress * 100).rounded())) %"
        case .done(_, let duplicate, _, _): return duplicate ? "Schon vorhanden" : "Hochgeladen"
        case .failed: return "Nicht gesendet"
        }
    }

    private var symbol: String {
        switch phase {
        case .preparing, .uploading: return "arrow.up.circle"
        case .done(_, let duplicate, _, _): return duplicate ? "doc.on.doc" : "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private var tint: Color {
        switch phase {
        case .preparing, .uploading: return BIOSTheme.accent
        case .done: return BIOSTheme.good
        case .failed: return BIOSTheme.mid
        }
    }
}
