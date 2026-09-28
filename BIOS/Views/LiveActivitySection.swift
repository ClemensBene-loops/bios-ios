import SwiftUI

/// Mehr > "Sperrbildschirm-Widget": the recommended way to see BIOS on the lock
/// screen (a Live Activity would also sit in the Dynamic Island next to Loop).
struct LockScreenWidgetSection: View {
    @State private var reloadedAt: Date?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("So fügst du es hinzu", systemImage: "lock.rectangle.stack")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text3)
                        Text(step)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            Button {
                LockScreenWidgets.reload()
                reloadedAt = Date()
            } label: {
                Label(reloadedAt == nil ? "Widgets jetzt aktualisieren" : "Aktualisierung angestoßen",
                      systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Sperrbildschirm-Widget statt Live Activity")
        } footer: {
            Text("Rechteckig: Gesundheits-Score, Infekt-Status, nächste Einnahme (nur die Uhrzeit, kein Name) und Supplements. Rund: Score als Ring. Zeile: z. B. \"BIOS 49 · Infekt Tag 4\". Das Widget holt die Daten selbst etwa alle 30 Minuten vom BIOS-Server und nach jedem Aktualisieren in der App. Die Dynamic Island bleibt frei für Loop.")
        }
    }

    static let steps = [
        "Sperrbildschirm lang drücken und \"Anpassen\" tippen.",
        "\"Sperrbildschirm\" wählen, dann auf das Feld \"Widgets hinzufügen\" unter der Uhr tippen.",
        "In der Liste \"BIOS\" suchen und die Größe wählen (rechteckig, rund) oder die Zeile über der Uhr antippen.",
        "\"Fertig\" tippen. Auf dem Home-Bildschirm gibt es BIOS zusätzlich als kleines Widget.",
    ]
}

/// Mehr > "Live Activity": toggle plus iOS permission, state and token upload.
/// Default off: iOS shows a Live Activity always in the Dynamic Island too.
struct LiveActivitySection: View {
    @ObservedObject private var controller = LiveActivityController.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle(isOn: $controller.isEnabled) {
                Label("Live Activity", systemImage: "rectangle.badge.checkmark")
            }
            if controller.isEnabled {
                Label {
                    Text("Erscheint auch in der Dynamic Island neben Loop. Für den Sperrbildschirm allein: Widget oben hinzufügen und die Live Activity ausschalten.")
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(BIOSTheme.mid)
                }
            }
            StatusRow(title: "iOS", status: systemStatus)
            if !controller.systemEnabled && controller.isEnabled {
                Button {
                    if let url = SystemSettings.appSettingsURL {
                        openURL(url)
                    }
                } label: {
                    Label("In Einstellungen erlauben", systemImage: "gearshape")
                }
            }
            if controller.isEnabled {
                Toggle(isOn: $controller.nightPauseEnabled) {
                    Label("Nachtpause", systemImage: "moon")
                }
                StatusRow(title: "Sperrbildschirm", status: runningStatus)
                StatusRow(title: "BIOS-Server", status: tokenStatus)
            }
        } header: {
            Text("Live Activity")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if controller.isEnabled {
                    Text("Gesundheits-Score, nächste Einnahme und Supplements auf dem Sperrbildschirm und in der Dynamic Island. Der Server startet sie um 6:30, aktualisiert sie stündlich per Push und beendet sie um 23:30. Läuft keine, startet die App sie beim Öffnen. Genommen und Später direkt in der Dynamic Island.")
                    Text("Nachtpause an: Von 23:30 bis 6:30 beendet die App das Banner und startet keins.")
                } else {
                    Text("Aus (Standard): iOS zeigt eine Live Activity immer auch in der Dynamic Island, dort bleibt Loop. Die App beendet laufende Banner und meldet das Start-Token beim Server ab, der 6:30-Start bleibt damit aus.")
                }
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
