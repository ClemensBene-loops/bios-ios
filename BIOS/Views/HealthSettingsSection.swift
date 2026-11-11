import SwiftUI

/// Mehr > "Gesundheits-Score": weekly strength goal for the Bewegung
/// segment (formula 4; formula 3 servers: Routine part Krafttraining),
/// `PATCH /v1/health/settings`, 0 = off. After a successful change the dashboard reloads, so score and detail show the new goal.
struct HealthSettingsSection: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @ObservedObject private var store = HealthSettingsStore.shared

    var body: some View {
        Section {
            if store.isUnavailable && store.strengthGoal == nil {
                calmRow("Server kennt die Einstellung noch nicht",
                        detail: "Kommt mit dem nächsten Server-Update.",
                        symbol: "circle.dashed")
            } else if let goal = store.strengthGoal {
                Stepper(value: Binding(
                    get: { store.strengthGoal ?? goal },
                    set: { value in
                        Task {
                            if await store.setStrengthGoal(value) {
                                await dashboardStore.refresh(force: true)
                            }
                        }
                    }
                ), in: store.range) {
                    Label(goalText(goal), systemImage: "dumbbell")
                }
                .disabled(store.isSaving || !AppConfig.isServerConfigured)
                .accessibilityLabel("Krafttraining pro Woche")
                .accessibilityValue(goal == 0 ? "aus" : "\(goal) Tage")
            } else {
                calmRow(store.isLoading ? "Wird geladen ..." : "Noch kein Wert vom Server",
                        detail: AppConfig.isServerConfigured ? nil : APIError.notConfigured.errorDescription,
                        symbol: "hourglass")
            }
            if let error = store.saveError {
                calmRow("Nicht gespeichert", detail: error, symbol: "exclamationmark.circle", tint: BIOSTheme.mid)
            }
        } header: {
            Text("Gesundheits-Score")
        } footer: {
            Text("Krafttraining pro Woche: Ziel für den Bereich Bewegung (Tage mit Krafttraining laut Whoop, gezählt über 14 Tage gegen das doppelte Wochenziel, Kranktage verkleinern das Ziel). 0 schaltet den Bereich aus.")
        }
        .onAppear {
            store.adoptDashboardValue(dashboardStore.dashboard?.health?.strengthGoal)
        }
        .task {
            await store.refresh()
        }
    }

    /// "Krafttraining pro Woche: 3" / "Krafttraining pro Woche: aus"
    private func goalText(_ goal: Int) -> String {
        "Krafttraining pro Woche: " + (goal == 0 ? "aus" : "\(goal)")
    }

    private func calmRow(_ title: String, detail: String?, symbol: String, tint: Color = BIOSTheme.text3) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
