import Foundation
import os

/// Phase of one upload started in the app (a row of the upload card on top of the Labor tab).
enum LabUploadPhase: Equatable {
    /// Waits for the files before it (uploads run one after another).
    case queued(name: String)
    case preparing(name: String)
    case uploading(name: String, progress: Double)
    case done(name: String, duplicate: Bool, documentID: String?, status: String?)
    case failed(name: String, message: String)

    var name: String {
        switch self {
        case .queued(let name), .preparing(let name), .uploading(let name, _), .done(let name, _, _, _),
             .failed(let name, _):
            return name
        }
    }

    /// Not finished yet (queued, preparing or sending).
    var isRunning: Bool {
        switch self {
        case .queued, .preparing, .uploading: return true
        default: return false
        }
    }

    var isFinished: Bool { !isRunning }
}

/// One file of an import (the app's multi-select): its row in the upload card.
struct LabUploadItem: Identifiable, Equatable {
    let id: Int
    var phase: LabUploadPhase

    var name: String { phase.name }
}

/// A file to upload: the name for the list and how to get its data. The data is
/// read only when its turn comes, so ten photos never sit in memory at once.
struct LabUploadJob {
    let name: String
    let prepare: @MainActor () async -> LabPreparedFile
}

/// Everything of the Labor tab: overview (`GET /v1/labs`), documents
/// (`GET /v1/labs/documents`), marker details and single documents, the
/// catalog's kinds, writes (PATCH/DELETE) and uploads. Each response is cached
/// on disk as raw JSON under its own key ("labs", "labs_documents",
/// "labs_marker_<id>", "labs_document_<id>", "labs_catalog"), like the
/// dashboard, so the tab shows the last state offline. A server without the
/// endpoints (HTTP 404) is not an error: "Server kennt das Labor noch nicht".
@MainActor
final class LabStore: ObservableObject {
    static let shared = LabStore()

    @Published private(set) var overview: LabOverview?
    @Published private(set) var documentsResponse: LabDocumentsResponse?
    @Published private(set) var markers: [String: LabMarkerDetail] = [:]
    @Published private(set) var documents: [String: LabDocument] = [:]
    @Published private(set) var catalog = LabCatalog(json: nil)
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var isLoading = false
    /// Message of the last failed refresh; nil after a successful one.
    @Published private(set) var lastError: String?
    @Published private(set) var isOffline = false
    /// The server answered 404 (older server without the Labor endpoints).
    @Published private(set) var isUnavailable = false
    /// Files of the current (or last) import, in order; empty = no upload card.
    @Published private(set) var uploads: [LabUploadItem] = []
    /// Marker ids whose detail failed to load (with the message).
    @Published private(set) var markerErrors: [String: String] = [:]
    @Published private(set) var documentErrors: [String: String] = [:]

    private static let log = Logger(subsystem: "at.bene.bios", category: "labs")
    static let overviewKey = "labs"
    static let documentsKey = "labs_documents"
    static let catalogKey = "labs_catalog"
    private var lastAttempt: Date?
    private let minimumInterval: TimeInterval = 20
    private var pollTask: Task<Void, Never>?

    init(loadCache: Bool = true) {
        guard loadCache else { return }
        if let cached = DiskCache.load(Self.overviewKey) {
            overview = LabOverview(json: cached.value)
            fetchedAt = cached.fetchedAt
        }
        if let cached = DiskCache.load(Self.documentsKey) {
            documentsResponse = LabDocumentsResponse(json: cached.value)
        }
        if let cached = DiskCache.load(Self.catalogKey) {
            catalog = LabCatalog(json: cached.value)
        }
    }

    static func markerKey(_ id: String) -> String { "labs_marker_" + id }
    static func documentKey(_ id: String) -> String { "labs_document_" + id }

    var showsStaleData: Bool {
        (overview != nil || documentsResponse != nil) && lastError != nil
    }

    /// Review counts: the newer of both answers (both carry `review`).
    var review: LabReviewSummary {
        documentsResponse?.review ?? overview?.review ?? .empty
    }

    var documentList: [LabDocument] {
        documentsResponse?.documents ?? []
    }

    var reviewDocuments: [LabDocument] {
        documentList.filter { $0.status == .review }
    }

    var hasWaiting: Bool {
        documentList.contains { $0.status == .waiting } || review.waiting > 0
    }

    // MARK: - Loading

    /// Overview and documents. `force` ignores the short throttle.
    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        guard let client = APIClient.fromConfig() else {
            lastError = APIError.notConfigured.errorDescription
            return
        }
        isLoading = true
        lastAttempt = Date()
        do {
            let overviewJSON = try await client.fetchLabs()
            let documentsJSON = try await client.fetchLabDocuments()
            let now = Date()
            overview = LabOverview(json: overviewJSON)
            documentsResponse = LabDocumentsResponse(json: documentsJSON)
            fetchedAt = now
            lastError = nil
            isOffline = false
            isUnavailable = false
            DiskCache.save(Self.overviewKey, value: overviewJSON, fetchedAt: now)
            DiskCache.save(Self.documentsKey, value: documentsJSON, fetchedAt: now)
        } catch {
            handle(error, context: "refresh")
        }
        isLoading = false
        if catalogNeedsLoad {
            await loadCatalog()
        }
    }

    private var catalogLoaded = false
    private var catalogNeedsLoad: Bool { !catalogLoaded && !isUnavailable && lastError == nil }

    /// Loads the catalog once per app run (review screen: marker picker, units).
    func ensureCatalog() async {
        guard !catalogLoaded else { return }
        await loadCatalog()
    }

    private func loadCatalog() async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            let json = try await client.fetchLabCatalog()
            catalog = LabCatalog(json: json)
            catalogLoaded = true
            DiskCache.save(Self.catalogKey, value: json, fetchedAt: Date())
        } catch {
            Self.log.info("Lab catalog not loaded: \(error.localizedDescription, privacy: .public)")
        }
    }

    func marker(_ id: String) -> LabMarkerDetail? {
        markers[id]
    }

    /// Puts the disk cache of a marker into memory (call from `.task`, not from `body`).
    func primeMarker(_ id: String) {
        guard markers[id] == nil, let cached = DiskCache.load(Self.markerKey(id)) else { return }
        markers[id] = LabMarkerDetail(json: cached.value, id: id)
    }

    func loadMarker(_ id: String) async {
        guard let client = APIClient.fromConfig() else {
            markerErrors[id] = APIError.notConfigured.errorDescription
            return
        }
        do {
            let json = try await client.fetchLabMarker(id: id)
            markers[id] = LabMarkerDetail(json: json, id: id)
            markerErrors[id] = nil
            DiskCache.save(Self.markerKey(id), value: json, fetchedAt: Date())
        } catch {
            if ErrorKind.isCancellation(error) { return }
            markerErrors[id] = message(for: error, notFound: "Dieser Marker ist am Server nicht bekannt.")
            Self.log.error("Lab marker failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func document(_ id: String) -> LabDocument? {
        documents[id]
    }

    /// Puts the disk cache of a document into memory (call from `.task`, not from `body`).
    func primeDocument(_ id: String) {
        guard documents[id] == nil, let cached = DiskCache.load(Self.documentKey(id)),
              let document = LabDocument(json: cached.value) else { return }
        documents[id] = document
    }

    /// The list entry of a document (no values).
    func listEntry(_ id: String) -> LabDocument? {
        documentList.first { $0.id == id }
    }

    func loadDocument(_ id: String) async {
        guard let client = APIClient.fromConfig() else {
            documentErrors[id] = APIError.notConfigured.errorDescription
            return
        }
        do {
            let json = try await client.fetchLabDocument(id: id)
            if let document = LabDocument(json: json) {
                documents[id] = document
                documentErrors[id] = nil
                DiskCache.save(Self.documentKey(id), value: json, fetchedAt: Date())
            }
        } catch {
            if ErrorKind.isCancellation(error) { return }
            documentErrors[id] = message(for: error, notFound: "Dieses Dokument gibt es nicht mehr.")
            Self.log.error("Lab document failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Writes

    /// PATCH with any body. Returns nil on success, else a calm German message.
    func patch(_ id: String, body: [String: JSONValue]) async -> String? {
        guard let client = APIClient.fromConfig() else {
            return APIError.notConfigured.errorDescription
        }
        do {
            let result = try await client.patchLabDocument(id: id, body: .object(body))
            guard result.isSuccess else {
                return result.errorText
            }
            if let json = result.json?.obj("document"), let document = LabDocument(json: json) {
                documents[id] = document
                DiskCache.save(Self.documentKey(id), value: json, fetchedAt: Date())
            }
            await afterWrite()
            return nil
        } catch {
            if ErrorKind.isCancellation(error) { return nil }
            Self.log.error("Lab patch failed: \(error.localizedDescription, privacy: .public)")
            return ErrorKind.isOffline(error) ? "Keine Verbindung, nicht gespeichert." : "Nicht gespeichert: " + error.localizedDescription
        }
    }

    /// Queues the document for a new extraction (`retry: true`).
    func retry(_ id: String) async -> String? {
        let error = await patch(id, body: ["retry": .bool(true)])
        if error == nil {
            startPolling()
        }
        return error
    }

    /// Discards the document (file and values). nil on success.
    func delete(_ id: String) async -> String? {
        guard let client = APIClient.fromConfig() else {
            return APIError.notConfigured.errorDescription
        }
        do {
            let result = try await client.deleteLabDocument(id: id)
            guard result.isSuccess || result.status == 404 else {
                return result.errorText
            }
            documents[id] = nil
            await afterWrite()
            return nil
        } catch {
            if ErrorKind.isCancellation(error) { return nil }
            Self.log.error("Lab delete failed: \(error.localizedDescription, privacy: .public)")
            return ErrorKind.isOffline(error) ? "Keine Verbindung, nicht verworfen." : "Nicht verworfen: " + error.localizedDescription
        }
    }

    /// Overview, documents, open marker details and the Heute card change after a write.
    private func afterWrite() async {
        await refresh(force: true)
        for id in Array(markers.keys) {
            await loadMarker(id)
        }
        await DashboardStore.shared.refresh(force: true)
    }

    // MARK: - Upload

    private var jobs: [Int: LabUploadJob] = [:]
    private var nextUploadID = 0
    private var uploadRunner: Task<Void, Never>?

    /// A file of the import is still queued, being prepared or sent.
    var isUploading: Bool {
        uploads.contains { $0.phase.isRunning }
    }

    /// Adds files to the import queue; they are prepared and sent one after the
    /// other. A new import after a finished one starts a fresh list.
    func enqueue(_ newJobs: [LabUploadJob]) {
        guard !newJobs.isEmpty else { return }
        if !isUploading {
            uploads = []
        }
        for job in newJobs {
            nextUploadID += 1
            jobs[nextUploadID] = job
            uploads.append(LabUploadItem(id: nextUploadID, phase: .queued(name: job.name)))
        }
        startUploadRunner()
    }

    /// A file that could not even be opened (file importer error): a failed row.
    func reportPreparationError(name: String, message: String) {
        if !isUploading {
            uploads = []
        }
        nextUploadID += 1
        uploads.append(LabUploadItem(id: nextUploadID, phase: .failed(name: name, message: message)))
    }

    /// Hides the upload card (only when nothing runs any more).
    func clearUpload() {
        if isUploading { return }
        uploads = []
    }

    private func startUploadRunner() {
        guard uploadRunner == nil else { return }
        uploadRunner = Task { @MainActor [weak self] in
            while let self, let next = self.uploads.first(where: {
                if case .queued = $0.phase { return true }
                return false
            }) {
                await self.process(next.id)
            }
            guard let self else { return }
            self.uploadRunner = nil
            await self.refresh(force: true)
            self.startPolling()
        }
    }

    /// Prepares and sends one file; a failure only marks its row.
    private func process(_ id: Int) async {
        guard let job = jobs.removeValue(forKey: id) else {
            setPhase(id, .failed(name: "Datei", message: "Nicht mehr verfügbar."))
            return
        }
        let name = job.name
        setPhase(id, .preparing(name: name))
        let prepared = await job.prepare()
        switch prepared {
        case .failure(let message):
            setPhase(id, .failed(name: name, message: message))
        case .ready(let data, let contentType):
            setPhase(id, .uploading(name: name, progress: 0))
            do {
                let result = try await LabUpload.upload(data: data, contentType: contentType) { [weak self] fraction in
                    Task { @MainActor in
                        self?.setProgress(id, fraction)
                    }
                }
                setPhase(id, .done(name: name, duplicate: result.duplicate, documentID: result.documentID,
                                   status: result.documentStatus))
                Self.log.info("Lab upload done (duplicate: \(result.duplicate))")
                // The new document shows in Befunde while the next file is sent.
                await refresh(force: true)
            } catch {
                let text: String
                if error is CancellationError {
                    text = "Abgebrochen."
                } else {
                    text = (error as? LabUploadError)?.errorDescription ?? error.localizedDescription
                }
                setPhase(id, .failed(name: name, message: text))
                Self.log.error("Lab upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func setPhase(_ id: Int, _ phase: LabUploadPhase) {
        guard let index = uploads.firstIndex(where: { $0.id == id }) else { return }
        uploads[index].phase = phase
    }

    private func setProgress(_ id: Int, _ fraction: Double) {
        guard let index = uploads.firstIndex(where: { $0.id == id }),
              case .uploading(let name, _) = uploads[index].phase else { return }
        uploads[index].phase = .uploading(name: name, progress: fraction)
    }

    // MARK: - Polling while a document waits for the extraction

    /// Reloads every 15 s while a document waits (at most 10 min), then stops.
    func startPolling() {
        guard pollTask == nil, hasWaiting else { return }
        pollTask = Task { @MainActor [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.refresh(force: true)
                if !self.hasWaiting {
                    // Extraction finished: the Heute card and the push counts change too.
                    await DashboardStore.shared.refresh(force: true)
                    break
                }
            }
            self?.pollTask = nil
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Errors

    private func handle(_ error: Error, context: String) {
        if ErrorKind.isCancellation(error) { return }
        if let apiError = error as? APIError, apiError == .http(404) {
            isUnavailable = true
            isOffline = false
            lastError = "Server kennt das Labor noch nicht"
        } else {
            isOffline = ErrorKind.isOffline(error)
            lastError = isOffline ? "Keine Verbindung" : error.localizedDescription
        }
        Self.log.error("Labs \(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    private func message(for error: Error, notFound: String) -> String {
        if let apiError = error as? APIError, apiError == .http(404) {
            return notFound
        }
        return ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
    }
}
