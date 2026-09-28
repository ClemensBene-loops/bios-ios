import SwiftUI

/// Mehr > Körper (and Labor > Eigene Messungen): height and weight with a date,
/// BMI from the server, history of own entries and Whoop values. Saves with
/// `PATCH /v1/body` (validated by the server, 422 text shown); own entries can be
/// removed. The own height always wins over clinic measurements and Whoop.
struct BodyProfileView: View {
    @State private var profile: BodyProfile?
    @State private var loading = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var savedText: String?
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var weightDate = Date()
    @State private var didPrefill = false

    private static let cacheKey = "body_profile"

    var body: some View {
        Form {
            Section {
                LabeledContent("Größe") {
                    Text(heightDisplay)
                        .monospacedDigit()
                }
                LabeledContent("Gewicht") {
                    Text(weightDisplay)
                        .monospacedDigit()
                }
                LabeledContent("BMI") {
                    Text(profile?.bmi.map { BIOSFormat.number($0, digits: 1) } ?? "n. v.")
                        .monospacedDigit()
                }
            } header: {
                Text("Aktuell")
            } footer: {
                Text(profile?.note ?? "Die eigene Größe zählt immer; Größe und Gewicht aus Arztbriefen bleiben im Befund.")
            }

            Section {
                HStack {
                    Text("Größe")
                    Spacer()
                    TextField("180", text: $heightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                        .accessibilityLabel("Größe in Zentimetern")
                    Text("cm")
                        .foregroundStyle(BIOSTheme.text2)
                }
                HStack {
                    Text("Gewicht")
                    Spacer()
                    TextField("80,0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                        .accessibilityLabel("Gewicht in Kilogramm")
                    Text("kg")
                        .foregroundStyle(BIOSTheme.text2)
                }
                DatePicker("Gewogen am", selection: $weightDate, in: ...Date(), displayedComponents: .date)
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if saving { ProgressView().controlSize(.small) }
                        Text("Speichern")
                            .font(.body.weight(.semibold))
                    }
                }
                .disabled(saving || !hasChanges)
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.midText)
                }
                if let savedText {
                    Text(savedText)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
            } header: {
                Text("Ändern")
            } footer: {
                Text("Ein Gewicht pro Tag: ein neuer Eintrag für denselben Tag ersetzt den alten. Die Größe gilt für alle Rechnungen (BMI, später FFMI).")
            }

            if let weights = profile?.weights, !weights.isEmpty {
                Section {
                    ForEach(weights) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.whenText)
                                    .monospacedDigit()
                                Text(entry.sourceLabel)
                                    .font(.caption)
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                            Spacer()
                            Text("\(BIOSFormat.number(entry.kg, digits: 1)) kg")
                                .monospacedDigit()
                        }
                        .swipeActions {
                            if entry.removable, let serverID = entry.serverID {
                                Button("Löschen", role: .destructive) {
                                    Task { await remove(serverID) }
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Verlauf Gewicht")
                } footer: {
                    Text(whoopFooter)
                }
            }
        }
        .navigationTitle("Körper")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .overlay {
            if profile == nil && loading {
                ProgressView()
            }
        }
        .task {
            if profile == nil, let cached = DiskCache.load(Self.cacheKey) {
                apply(BodyProfile(json: cached.value))
            }
            await load()
        }
    }

    // MARK: - Display

    private var heightDisplay: String {
        guard let height = profile?.heightCm else { return "n. v." }
        var text = "\(BIOSFormat.number(height, digits: 0)) cm"
        if profile?.heightSource == "whoop" { text += " (Whoop)" }
        return text
    }

    private var weightDisplay: String {
        guard let weight = profile?.weightKg else { return "n. v." }
        var text = "\(BIOSFormat.number(weight, digits: 1)) kg"
        if let date = profile?.weightDate { text += ", \(LabFormat.fullDate(date))" }
        return text
    }

    private var whoopFooter: String {
        var text = "Wischen löscht eigene Einträge. Whoop-Werte kommen aus deinem Whoop-Profil; der erste gesehene Wert ist undatiert und zählt nur ohne eigenen Eintrag."
        if let hr = profile?.whoopMaxHR { text += " Maximalpuls laut Whoop: \(hr)." }
        return text
    }

    private var parsedHeight: Double? { LabFormat.parse(heightText) }
    private var parsedWeight: Double? { LabFormat.parse(weightText) }

    private var hasChanges: Bool {
        let heightChanged = parsedHeight.map { abs($0 - (profile?.heightCm ?? -1)) > 0.05 } ?? false
        return heightChanged || parsedWeight != nil
    }

    // MARK: - Loading and saving

    private func apply(_ new: BodyProfile) {
        profile = new
        if !didPrefill {
            didPrefill = true
            if let height = new.heightCm { heightText = LabFormat.editText(height) }
        }
    }

    private func load() async {
        guard let client = APIClient.fromConfig() else {
            errorText = APIError.notConfigured.errorDescription
            return
        }
        loading = true
        defer { loading = false }
        do {
            let json = try await client.fetchBody()
            apply(BodyProfile(json: json))
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: Date())
            errorText = nil
        } catch {
            if ErrorKind.isCancellation(error) { return }
            if let apiError = error as? APIError, apiError == .http(404) {
                errorText = "Der Server kennt Körperdaten noch nicht."
            } else {
                errorText = ErrorKind.isOffline(error) ? "Keine Verbindung" : error.localizedDescription
            }
        }
    }

    private func save() async {
        errorText = nil
        savedText = nil
        var payload: [String: JSONValue] = [:]
        let heightRange: ClosedRange<Double> = profile?.heightRange ?? 100.0...250.0
        let weightRange: ClosedRange<Double> = profile?.weightRange ?? 30.0...300.0
        if !heightText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let height = parsedHeight, heightRange.contains(height) else {
                errorText = "Größe bitte in Zentimetern (100 bis 250)."
                return
            }
            if abs(height - (profile?.heightCm ?? -1)) > 0.05 {
                payload["height_cm"] = .number(height)
            }
        }
        if !weightText.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let weight = parsedWeight, weightRange.contains(weight) else {
                errorText = "Gewicht bitte in Kilogramm (30 bis 300)."
                return
            }
            payload["weight_kg"] = .number(weight)
            payload["date"] = .string(Self.dayString(weightDate))
        }
        guard !payload.isEmpty else { return }
        guard let client = APIClient.fromConfig() else {
            errorText = APIError.notConfigured.errorDescription
            return
        }
        saving = true
        defer { saving = false }
        do {
            let result = try await client.patchBody(payload)
            guard result.isSuccess, let json = result.json else {
                errorText = result.errorText
                return
            }
            let updated = BodyProfile(json: json)
            profile = updated
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: Date())
            weightText = ""
            if let height = updated.heightCm { heightText = LabFormat.editText(height) }
            savedText = "Gespeichert."
            await LabStore.shared.refresh(force: true)
        } catch {
            if ErrorKind.isCancellation(error) { return }
            errorText = ErrorKind.isOffline(error) ? "Keine Verbindung, nicht gespeichert." : "Nicht gespeichert: " + error.localizedDescription
        }
    }

    private func remove(_ id: String) async {
        guard let client = APIClient.fromConfig() else { return }
        do {
            let result = try await client.deleteBodyWeight(id: id)
            guard result.isSuccess, let json = result.json else {
                errorText = result.errorText
                return
            }
            profile = BodyProfile(json: json)
            DiskCache.save(Self.cacheKey, value: json, fetchedAt: Date())
            await LabStore.shared.refresh(force: true)
        } catch {
            if ErrorKind.isCancellation(error) { return }
            errorText = ErrorKind.isOffline(error) ? "Keine Verbindung, nicht gelöscht." : "Nicht gelöscht: " + error.localizedDescription
        }
    }

    /// "2026-09-28" in the local calendar.
    private static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        return "\(parts.year ?? 2000)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }
}
