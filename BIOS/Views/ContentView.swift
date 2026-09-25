import SwiftUI
import UIKit

/// Home screen for Phase 2: push status and the last push.
/// Phase 3 adds the latest Whoop check and outlook loaded from the BIOS
/// server (`APIClient.fetchSummary`) and routes taps via `AppState.pendingOpen`.
struct ContentView: View {
    @ObservedObject var state: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }

                Section("Mitteilungen") {
                    StatusRow(title: "Erlaubnis", status: authorizationStatus)
                    StatusRow(title: "Apple Push", status: registrationStatus)
                    StatusRow(title: "BIOS-Server", status: uploadStatus)
                    if state.authorization == .denied {
                        Button {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        } label: {
                            Label("In Einstellungen erlauben", systemImage: "gearshape")
                        }
                    }
                }

                Section("Letzte Mitteilung") {
                    if let push = state.lastPush {
                        PushRow(push: push)
                    } else {
                        Label("Noch keine Mitteilung empfangen", systemImage: "tray")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("BIOS")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.teal)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Version \(AppConfig.versionString)")
                    .font(.subheadline.weight(.semibold))
                Text(AppConfig.isServerConfigured ? "Server konfiguriert" : "Server nicht konfiguriert")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(AppConfig.apnsEnvironment == "sandbox" ? "APNs Sandbox" : "APNs Production")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Status mapping

    private var authorizationStatus: StatusDisplay {
        switch state.authorization {
        case .notAsked:
            return StatusDisplay(text: "Noch nicht angefragt", symbol: "bell", tint: .secondary)
        case .requesting:
            return StatusDisplay(text: "Wird angefragt ...", symbol: "hourglass", tint: .orange)
        case .granted:
            return StatusDisplay(text: "Erlaubt", symbol: "bell.badge.fill", tint: .green)
        case .denied:
            return StatusDisplay(text: "Abgelehnt", symbol: "bell.slash.fill", tint: .red)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private var registrationStatus: StatusDisplay {
        switch state.registration {
        case .pending:
            return StatusDisplay(text: "Noch kein Token", symbol: "antenna.radiowaves.left.and.right", tint: .secondary)
        case .registered(let token):
            return StatusDisplay(text: "Registriert, Token \(token.prefix(8))...", symbol: "checkmark.seal.fill", tint: .green)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "xmark.octagon.fill", tint: .red)
        }
    }

    private var uploadStatus: StatusDisplay {
        switch state.upload {
        case .waiting:
            return StatusDisplay(text: "Wartet auf Token", symbol: "icloud", tint: .secondary)
        case .notConfigured:
            return StatusDisplay(text: "Server nicht konfiguriert", symbol: "icloud.slash", tint: .orange)
        case .uploading:
            return StatusDisplay(text: "Wird gesendet ...", symbol: "arrow.up.circle", tint: .orange)
        case .succeeded(let date):
            return StatusDisplay(
                text: "Gesendet um \(date.formatted(date: .omitted, time: .shortened))",
                symbol: "checkmark.icloud.fill",
                tint: .green
            )
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "exclamationmark.icloud.fill", tint: .red)
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
                    .font(.body)
                Text(status.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Title, body and metadata of a push.
struct PushRow: View {
    let push: PushInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(push.title.isEmpty ? "(ohne Titel)" : push.title)
                .font(.headline)
            if !push.body.isEmpty {
                Text(push.body)
                    .font(.subheadline)
            }
            Label(metadata, systemImage: push.kind == .opened ? "hand.tap" : "bell")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var metadata: String {
        var parts: [String] = []
        parts.append(push.kind == .opened ? "Geöffnet" : "Empfangen")
        parts.append(push.date.formatted(date: .abbreviated, time: .shortened))
        if !push.threadID.isEmpty {
            parts.append("Thread \(push.threadID)")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ContentView(state: AppState.preview())
}
