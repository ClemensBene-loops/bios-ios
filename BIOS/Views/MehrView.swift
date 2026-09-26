import SwiftUI
import UIKit

/// Tab "Mehr": push status (v1) with "Test-Push senden", data freshness per
/// source, settings (display only, maintained in the server profile), version.
struct MehrView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var dashboardStore: DashboardStore
    @Environment(\.openURL) var openURL
    @State private var testPush: TestPushState = .idle

    /// "Test-Push senden": `POST /v1/test-push` with this device's token.
    enum TestPushState: Equatable {
        case idle
        case sending
        case sent(Date)
        case failed(String)
    }

    var body: some View {
        let dashboard = dashboardStore.dashboard
        List {
            Section {
                StatusRow(title: "Erlaubnis", status: authorizationStatus)
                StatusRow(title: "Apple Push", status: registrationStatus)
                StatusRow(title: "BIOS-Server", status: uploadStatus)
                if state.authorization == .denied {
                    Button {
                        if let url = SystemSettings.notificationsURL {
                            openURL(url)
                        }
                    } label: {
                        Label("In Einstellungen erlauben", systemImage: "gearshape")
                    }
                }
                if let push = state.lastPush {
                    LastPushRow(
                        title: push.title,
                        body: push.body,
                        meta: (push.kind == .opened ? "Letzte Mitteilung, geöffnet" : "Letzte Mitteilung, empfangen")
                            + " · " + BIOSFormat.relative(push.date)
                    )
                } else if let last = dashboard?.push?.last {
                    LastPushRow(
                        title: last.title,
                        body: last.body,
                        meta: "Zuletzt gesendet" + (last.sentAt.map { " · " + BIOSFormat.relative($0) } ?? "")
                    )
                }
                TestPushRow(
                    title: testPush == .sending ? "Wird gesendet ..." : "Test-Push senden",
                    detail: testPushDetail,
                    symbol: testPushSymbol,
                    tint: testPushTint,
                    enabled: testPushBlocker(dashboard) == nil && testPush != .sending
                ) {
                    Task { await sendTestPush() }
                }
            } header: {
                Text("Mitteilungen")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(testPushBlocker(dashboard)
                         ?? "Test-Push geht nur an dieses Gerät, höchstens einmal pro Minute. Die Zustellung steht danach im Server-Log.")
                    if let devices = dashboard?.push?.devices {
                        Text("Registrierte Geräte am Server: \(devices)")
                    }
                }
            }

            LiveActivitySection()

            Section {
                if let items = dashboard?.freshness, !items.isEmpty {
                    ForEach(items) { item in
                        FreshnessRow(item: item, fromCache: dashboardStore.showsStaleData)
                    }
                } else {
                    Text("Noch keine Angaben vom Server")
                        .foregroundStyle(BIOSTheme.text2)
                }
            } header: {
                Text("Datenfrische")
            } footer: {
                Text(freshnessFooter)
            }

            if let errors = dashboard?.errors, !errors.isEmpty {
                Section {
                    ForEach(Array(errors.enumerated()), id: \.offset) { entry in
                        Label {
                            Text(entry.element)
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundStyle(BIOSTheme.mid)
                        }
                    }
                } header: {
                    Text("Hinweise vom Server")
                }
            }

            Section {
                NavigationLink(value: DetailRoute.alkohol) {
                    Label("Alkohol-Tage", systemImage: "wineglass")
                }
            } header: {
                Text("Kontext")
            } footer: {
                Text("Rückwirkend markieren, auch per Siri: \"Alkohol in BIOS\".")
            }

            Section {
                LabeledContent("Allergene", value: allergensText(dashboard))
                LabeledContent("Heimatort", value: dashboard?.pollen?.place ?? dashboard?.environment?.allergy?.place ?? "n. v.")
                Button {
                    if let url = SystemSettings.notificationsURL {
                        openURL(url)
                    }
                } label: {
                    HStack {
                        Label("Mitteilungen in iOS-Einstellungen", systemImage: "gearshape")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
            } header: {
                Text("Einstellungen")
            } footer: {
                Text("Allergene und Ort werden am Server gepflegt (Profil), die App zeigt sie nur an.")
            }

            Section {
                BrandRow()
                LabeledContent("Version", value: AppConfig.versionString)
                LabeledContent("Push-Umgebung", value: AppConfig.apnsEnvironment == "sandbox" ? "APNs Sandbox" : "APNs Production")
                LabeledContent("Server", value: AppConfig.isServerConfigured ? "konfiguriert" : "nicht konfiguriert")
                if let fetched = dashboardStore.fetchedAt {
                    LabeledContent("Datenstand", value: BIOSFormat.relative(fetched))
                }
            } header: {
                Text("Über")
            } footer: {
                Text("BIOS zeigt Beobachtungen, keine Dosierungs- oder Therapiehinweise.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .biosPageBackground()
        .navigationTitle("Mehr")
        .refreshable {
            await dashboardStore.refresh(force: true)
        }
    }

    // MARK: - Test-Push

    /// Why the test push cannot be sent right now (footer text), or nil if it can.
    private func testPushBlocker(_ dashboard: DashboardModel?) -> String? {
        if !AppConfig.isServerConfigured {
            return "Test-Push braucht einen konfigurierten Server."
        }
        if dashboardStore.isOffline {
            return "Offline: Test-Push nicht möglich."
        }
        guard case .registered = state.registration else {
            return "Test-Push braucht einen registrierten Push-Token."
        }
        if dashboard?.push?.testPushAvailable != true {
            return "Der Server bietet noch keinen Test-Push an (Daten neu laden)."
        }
        return nil
    }

    private var testPushDetail: String? {
        switch testPush {
        case .idle, .sending:
            return nil
        case .sent(let date):
            return "Apple hat angenommen, \(BIOSFormat.time(date)). Mitteilung sollte gleich erscheinen."
        case .failed(let message):
            return message
        }
    }

    private var testPushSymbol: String {
        switch testPush {
        case .idle: return "paperplane"
        case .sending: return "hourglass"
        case .sent: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var testPushTint: Color {
        switch testPush {
        case .idle, .sending: return BIOSTheme.accent
        case .sent: return BIOSTheme.good
        case .failed: return BIOSTheme.bad
        }
    }

    private func sendTestPush() async {
        guard case .registered(let token) = state.registration,
              let client = APIClient.fromConfig() else { return }
        testPush = .sending
        do {
            let result = try await client.sendTestPush(token: token)
            testPush = result.accepted ? .sent(Date()) : .failed(Self.rejectionText(result))
        } catch {
            testPush = ErrorKind.isCancellation(error) ? .idle : .failed(Self.errorText(error))
        }
    }

    private static func rejectionText(_ result: TestPushResult) -> String {
        var parts: [String] = []
        if let status = result.apnsStatus { parts.append("HTTP \(status)") }
        if let reason = result.apnsReason { parts.append(reason) }
        var text = "Apple lehnt ab" + (parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")")
        if result.removed { text += ", Token am Server entfernt" }
        return text
    }

    private static func errorText(_ error: Error) -> String {
        if ErrorKind.isOffline(error) { return "Keine Verbindung" }
        if let apiError = error as? APIError {
            switch apiError {
            case .http(429): return "Höchstens ein Test-Push pro Minute, bitte kurz warten."
            case .http(404): return "Dieses Gerät ist am Server nicht registriert."
            case .http(503): return "APNs ist am Server nicht eingerichtet."
            case .http(502): return "Apple ist gerade nicht erreichbar."
            default: return apiError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    private var freshnessFooter: String {
        if dashboardStore.showsStaleData {
            let stand = dashboardStore.fetchedAt.map { " von \(BIOSFormat.relative($0))" } ?? ""
            return "Server nicht erreichbar. Angezeigt wird der gespeicherte Stand\(stand)."
        }
        return "Import stündlich um :17, Infekt-Check 13:25 und 20:25, Ausblick 06:40 und 18:40."
    }

    private func allergensText(_ dashboard: DashboardModel?) -> String {
        let names = UmweltData.allergenNames(dashboard)
        return names.isEmpty ? "n. v." : names.joined(separator: ", ")
    }

    private var authorizationStatus: StatusDisplay {
        switch state.authorization {
        case .notAsked:
            return StatusDisplay(text: "Noch nicht angefragt", symbol: "bell", tint: BIOSTheme.text3)
        case .requesting:
            return StatusDisplay(text: "Wird angefragt ...", symbol: "hourglass", tint: BIOSTheme.mid)
        case .granted:
            return StatusDisplay(text: "Erlaubt", symbol: "bell.badge.fill", tint: BIOSTheme.good)
        case .denied:
            return StatusDisplay(text: "Abgelehnt", symbol: "bell.slash.fill", tint: BIOSTheme.bad)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "exclamationmark.triangle.fill", tint: BIOSTheme.bad)
        }
    }

    private var registrationStatus: StatusDisplay {
        switch state.registration {
        case .pending:
            return StatusDisplay(text: "Noch kein Token", symbol: "antenna.radiowaves.left.and.right", tint: BIOSTheme.text3)
        case .registered(let token):
            return StatusDisplay(text: "Registriert, Token \(token.prefix(8)) ...", symbol: "checkmark.seal.fill", tint: BIOSTheme.good)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "xmark.octagon.fill", tint: BIOSTheme.bad)
        }
    }

    private var uploadStatus: StatusDisplay {
        switch state.upload {
        case .waiting:
            return StatusDisplay(text: "Wartet auf Token", symbol: "icloud", tint: BIOSTheme.text3)
        case .notConfigured:
            return StatusDisplay(text: "Server nicht konfiguriert", symbol: "icloud.slash", tint: BIOSTheme.mid)
        case .uploading:
            return StatusDisplay(text: "Wird gesendet ...", symbol: "arrow.up.circle", tint: BIOSTheme.mid)
        case .succeeded(let date):
            return StatusDisplay(text: "Gesendet \(BIOSFormat.timestamp(date))", symbol: "checkmark.icloud.fill", tint: BIOSTheme.good)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "exclamationmark.icloud.fill", tint: BIOSTheme.bad)
        }
    }
}

struct StatusDisplay {
    let text: String
    let symbol: String
    let tint: Color
}

/// One status line: colored symbol, title, detail text.
struct StatusRow: View {
    let title: String
    let status: StatusDisplay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status.text)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Test-Push senden": button row with symbol, title and the last result.
struct TestPushRow: View {
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(enabled ? tint : BIOSTheme.text3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(enabled ? BIOSTheme.accent : BIOSTheme.text3)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .disabled(!enabled)
        .accessibilityHint("Schickt eine Test-Mitteilung nur an dieses Gerät")
    }
}

struct LastPushRow: View {
    let title: String
    let body_: String
    let meta: String

    init(title: String, body: String, meta: String) {
        self.title = title
        self.body_ = body
        self.meta = meta
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(BIOSTheme.text2)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "(ohne Titel)" : title)
                    .font(.subheadline.weight(.semibold))
                if !body_.isEmpty {
                    Text(body_)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .lineLimit(4)
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Data freshness of one source: status symbol + word, last value, cadence, note.
struct FreshnessRow: View {
    let item: FreshnessItem
    let fromCache: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(word)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [item.lastText]
        if let age = item.ageMinutes, item.lastRaw?.count ?? 0 > 10 {
            parts.append(BIOSFormat.age(minutes: age))
        }
        if let cadence = item.cadence { parts.append(cadence) }
        var text = parts.joined(separator: " · ")
        if let note = item.note { text += "\n" + note }
        return text
    }

    private var symbol: String {
        if fromCache { return "clock" }
        switch item.status {
        case "ok": return "checkmark.circle"
        case "stale": return "exclamationmark.triangle"
        default: return "questionmark.circle"
        }
    }

    private var tint: Color {
        if fromCache { return BIOSTheme.text3 }
        switch item.status {
        case "ok": return BIOSTheme.good
        case "stale": return BIOSTheme.mid
        default: return BIOSTheme.text3
        }
    }

    private var word: String {
        if fromCache { return "aus Cache" }
        switch item.status {
        case "ok": return "aktuell"
        case "stale": return "veraltet"
        default: return "fehlt"
        }
    }
}
