import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Import from inside the app: "Befund importieren" -> PDFs or images from Files, photos from the library
// (up to 10 at once each) or the camera. Photos and image files become JPEG, PDFs stay PDF. Before the
// very first upload a one-time notice explains the cloud extraction (stored
// flag, never shown again). The upload itself: LabStore.enqueue (one after another) -> LabUpload.

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

/// The one import button of the Labor tab (same in Werte and Befunde): a wide
/// button "Befund importieren" that opens the sources (Dateien, Foto, Kamera).
struct LabImportMenu: View {
    let select: (LabImportSource) -> Void

    var body: some View {
        Menu {
            Button {
                select(.file)
            } label: {
                Label("PDFs oder Bilder aus Dateien", systemImage: "doc")
            }
            Button {
                select(.photo)
            } label: {
                Label("Fotos auswählen", systemImage: "photo")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    select(.camera)
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera")
                }
            }
        } label: {
            Label("Befund importieren", systemImage: "square.and.arrow.down")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(BIOSTheme.accent)
        .accessibilityLabel("Befund importieren")
        .accessibilityHint("PDFs oder Bilder aus Dateien, Fotos auswählen oder aufnehmen, bis zu zehn auf einmal")
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
    @State private var photoItems: [PhotosPickerItem] = []

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
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    importFiles(urls)
                case .failure(let error):
                    LabStore.shared.reportPreparationError(name: "Datei", message: "Datei nicht geöffnet: \(error.localizedDescription)")
                }
            }
            .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: LabImportPreparer.maxFiles,
                          selectionBehavior: .ordered, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                importPhotos(items)
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

    // MARK: - Queueing the files (read and converted one after another)

    private func importFiles(_ urls: [URL]) {
        let jobs = urls.prefix(LabImportPreparer.maxFiles).map { url in
            LabUploadJob(name: url.lastPathComponent) {
                await Task.detached(priority: .userInitiated) {
                    LabImportPreparer.prepareFile(url)
                }.value
            }
        }
        LabStore.shared.enqueue(Array(jobs))
        if urls.count > LabImportPreparer.maxFiles {
            LabStore.shared.reportPreparationError(
                name: "\(urls.count - LabImportPreparer.maxFiles) weitere Dateien",
                message: "Höchstens \(LabImportPreparer.maxFiles) Dateien auf einmal. Den Rest bitte danach senden."
            )
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        let now = Date()
        let jobs = items.enumerated().map { index, item -> LabUploadJob in
            let name = LabImportPreparer.photoName(now: now, index: items.count > 1 ? index + 1 : nil)
            return LabUploadJob(name: name) { () async -> LabPreparedFile in
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        return .failure("Das Foto ließ sich nicht laden.")
                    }
                    return await Task.detached(priority: .userInitiated) {
                        LabImportPreparer.prepareImageData(data)
                    }.value
                } catch {
                    return .failure("Das Foto ließ sich nicht laden: \(error.localizedDescription)")
                }
            }
        }
        LabStore.shared.enqueue(jobs)
    }

    private func importImage(_ image: UIImage) {
        let job = LabUploadJob(name: LabImportPreparer.photoName()) {
            await Task.detached(priority: .userInitiated) {
                LabImportPreparer.prepareImage(image)
            }.value
        }
        LabStore.shared.enqueue([job])
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

    /// At most this many files per import (file picker, photo picker, share sheet).
    static let maxFiles = 10

    /// "Foto 28.09. 10:14.jpg", with several photos "Foto 28.09. 10:14 (2).jpg".
    static func photoName(now: Date = Date(), index: Int? = nil) -> String {
        let suffix = index.map { " (\($0))" } ?? ""
        return "Foto \(BIOSFormat.shortDate(now)) \(BIOSFormat.time(now))\(suffix).jpg"
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

