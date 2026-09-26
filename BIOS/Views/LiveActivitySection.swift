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
                    if let url = SystemSettings.notificationsURL {
                        openURL(url)
                    }
                } label: {
                    Label("In Einstellungen erlauben", systemImage: "gearshape")
                }
            }
            StatusRow(title: "Sperrbildschirm", status: runningStatus)
            StatusRow(title: "BIOS-Server", status: tokenStatus)
        } header: {
            Text("Live Activity")
        } footer: {
            Text("Gesundheits-Score, nächste Einnahme und Supplements auf dem Sperrbildschirm und in der Dynamic Island. Startet beim Öffnen der App, falls keine läuft, der Server aktualisiert sie per Push. Nachts (22 bis 6 Uhr) endet sie.")
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
        if LiveActivityController.isNight() {
            return StatusDisplay(text: "Nachtpause bis 6 Uhr", symbol: "moon", tint: BIOSTheme.text3)
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
