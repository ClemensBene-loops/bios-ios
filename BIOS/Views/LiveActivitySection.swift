import SwiftUI

/// Mehr > "Live Activity": toggle plus iOS permission, state and token upload.
struct LiveActivitySection: View {
    @ObservedObject private var controller = LiveActivityController.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: $controller.isEnabled) {
                Label("Live Activity", systemImage: "rectangle.badge.checkmark")
            }
            StatusRow(title: "iOS", status: systemStatus)
            if !controller.systemEnabled {
                Button {
                    if let url = SystemSettings.appSettingsURL {
                        openURL(url)
                    }
                } label: {
                    Label("In Einstellungen erlauben", systemImage: "gearshape")
                }
            }
            Toggle(isOn: $controller.nightPauseEnabled) {
                Label("Nachtpause", systemImage: "moon")
            }
            .disabled(!controller.isEnabled)
            StatusRow(title: "Sperrbildschirm", status: runningStatus)
            StatusRow(title: "BIOS-Server", status: tokenStatus)
        } header: {
            Text("Live Activity")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gesundheits-Score, nächste Einnahme und Supplements auf dem Sperrbildschirm und in der Dynamic Island. Der Server startet sie um 6:30, aktualisiert sie stündlich per Push und beendet sie um 23:30. Läuft keine, startet die App sie beim Öffnen. Genommen und Später direkt in der Dynamic Island.")
                Text("Nachtpause an: Von 23:30 bis 6:30 beendet die App das Banner und startet keins.")
                Text("Aus: Das Banner bleibt nachts mit dem letzten Stand stehen (der Server schickt nachts keine Updates und beendet es um 23:30).")
            }
        }
    }

    private var systemStatus: StatusDisplay {
        controller.systemEnabled
            ? StatusDisplay(text: "Live Activities erlaubt", symbol: "checkmark.circle", tint: BIOSTheme.good)
            : StatusDisplay(text: "In den iOS-Einstellungen für BIOS aus", symbol: "xmark.circle", tint: BIOSTheme.mid)
    }

    private var runningStatus: StatusDisplay {
        if !controller.isEnabled {
            return StatusDisplay(text: "Aus", symbol: "pause.circle", tint: BIOSTheme.text3)
        }
        if controller.isRunning {
            return StatusDisplay(text: "Läuft", symbol: "checkmark.circle", tint: BIOSTheme.good)
        }
        if controller.isInNightPause() {
            return StatusDisplay(text: "Nachtpause bis 6:30", symbol: "moon", tint: BIOSTheme.text3)
        }
        return StatusDisplay(text: "Läuft nicht, startet beim nächsten Öffnen", symbol: "circle.dashed", tint: BIOSTheme.text3)
    }

    private var tokenStatus: StatusDisplay {
        var pushStart = ""
        if #unavailable(iOS 17.2) {
            pushStart = " (Start per Push erst ab iOS 17.2)"
        }
        switch controller.tokenStatus {
        case .none:
            return StatusDisplay(text: "Noch kein Token" + pushStart, symbol: "circle.dashed", tint: BIOSTheme.text3)
        case .notConfigured:
            return StatusDisplay(text: "Server nicht konfiguriert", symbol: "exclamationmark.circle", tint: BIOSTheme.mid)
        case .uploading:
            return StatusDisplay(text: "Token wird gesendet ...", symbol: "arrow.up.circle", tint: BIOSTheme.text2)
        case .succeeded(let date):
            return StatusDisplay(text: "Token gesendet, " + BIOSFormat.relative(date) + pushStart, symbol: "checkmark.circle", tint: BIOSTheme.good)
        case .failed(let message):
            return StatusDisplay(text: message, symbol: "exclamationmark.triangle", tint: BIOSTheme.bad)
        }
    }
}
