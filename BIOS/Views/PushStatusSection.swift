import SwiftUI
import UIKit

/// Compact footer section: push permission, APNs registration, token upload
/// and the last push (Phase 2 status), plus build info in the footer.
struct PushStatusSection: View {
    @ObservedObject var state: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
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
            if let push = state.lastPush {
                PushRow(push: push)
            }
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        let server = AppConfig.isServerConfigured ? "Server konfiguriert" : "Server nicht konfiguriert"
        let apns = AppConfig.apnsEnvironment == "sandbox" ? "APNs Sandbox" : "APNs Production"
        return "BIOS \(AppConfig.versionString) · \(apns) · \(server)"
    }

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
                text: "Gesendet \(BIOSFormat.timestamp(date))",
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(status.text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Title, body and metadata of the last received or opened push.
struct PushRow: View {
    let push: PushInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(push.title.isEmpty ? "(ohne Titel)" : push.title)
                .font(.subheadline.weight(.semibold))
            if !push.body.isEmpty {
                Text(push.body)
                    .font(.footnote)
                    .lineLimit(4)
            }
            Label(metadata, systemImage: push.kind == .opened ? "hand.tap" : "bell")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var metadata: String {
        var parts: [String] = []
        parts.append(push.kind == .opened ? "Letzte Mitteilung, geöffnet" : "Letzte Mitteilung, empfangen")
        parts.append(BIOSFormat.timestamp(push.date))
        if !push.threadID.isEmpty {
            parts.append(push.threadID)
        }
        return parts.joined(separator: " · ")
    }
}
