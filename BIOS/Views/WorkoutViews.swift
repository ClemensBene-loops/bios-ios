import SwiftUI

// "Training eintragen" ("+" on Heute) and the training card on Heute. Manual workouts
// replace the Whoop recording while no band is worn; the server counts them for the
// health score segment "Bewegung" ("manuell erfasst (kein Whoop)").

struct WorkoutLogView: View {
    @ObservedObject private var store = WorkoutStore.shared
    @State private var kind = "weightlifting"
    @State private var start = Date().addingTimeInterval(-3_600)
    @State private var duration = 60
    @State private var muscleGroup: String?
    @State private var intensity: String?
    @State private var note = ""
    @State private var message: String?
    @State private var prepared = false

    var body: some View {
        List {
            Section {
                Picker("Art", selection: $kind) {
                    ForEach(WorkoutOptions.kinds) { option in
                        Text(option.label).tag(option.key)
                    }
                }
                DatePicker("Beginn", selection: $start, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                Stepper(value: $duration, in: 5...300, step: 5) {
                    LabeledContent("Dauer") {
                        Text("\(duration) min")
                            .monospacedDigit()
                    }
                }
                if WorkoutOptions.isStrength(kind) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Muskelgruppe")
                            .font(.subheadline)
                        WorkoutChips(options: WorkoutOptions.muscleGroups, selection: $muscleGroup)
                    }
                    .padding(.vertical, 4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Intensität")
                        .font(.subheadline)
                    WorkoutChips(options: WorkoutOptions.intensities, selection: $intensity)
                }
                .padding(.vertical, 4)
                TextField("Notiz (optional)", text: $note)
                    .onChange(of: note) { _, value in
                        if value.count > 80 { note = String(value.prefix(80)) }
                    }
                Button {
                    save()
                } label: {
                    Label(store.isSaving ? "Speichert ..." : "Speichern", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .disabled(store.isSaving)
            } header: {
                Text("Neu")
            } footer: {
                if let message {
                    Text(message)
                } else {
                    Text("Für Tage ohne Whoop. Zählt im Gesundheits-Score (Bewegung) wie ein Whoop-Workout; ohne Puls gilt nur \"hart\" als intensiv. Siri: \"Krafttraining in BIOS\".")
                }
            }

            WorkoutRecentSection(items: store.items)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !prepared else { return }
            kind = store.lastKind
            duration = store.lastDuration
            start = Date().addingTimeInterval(-Double(duration) * 60)
            prepared = true
        }
        .task {
            await store.refresh()
        }
    }

    private func save() {
        let chosenKind = kind
        let group = WorkoutOptions.isStrength(chosenKind) ? muscleGroup : nil
        let at = start
        let minutes = duration
        let level = intensity
        let text = note
        Task { @MainActor in
            let outcome = await store.add(kind: chosenKind, start: at, durationMin: minutes, muscleGroup: group,
                                          intensity: level, note: text)
            switch outcome {
            case .synced, .queued:
                message = "\(WorkoutOptions.label(chosenKind)) \(minutes) min gespeichert."
                note = ""
                start = Date().addingTimeInterval(-Double(minutes) * 60)
            case .failed(let error):
                message = "Nicht gespeichert: \(error)"
            }
        }
    }
}

/// Single-choice chips; a second tap clears the choice (optional fields).
struct WorkoutChips: View {
    let options: [WorkoutOption]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = selection == option.key
                    Button {
                        selection = selected ? nil : option.key
                    } label: {
                        Text(option.label)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? Color.black : BIOSTheme.text1)
                            .background(selected ? BIOSTheme.accent : BIOSTheme.card2, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Workouts of the last 14 days, manual ones with swipe to delete.
struct WorkoutRecentSection: View {
    @ObservedObject private var store = WorkoutStore.shared
    let items: [WorkoutItem]

    var body: some View {
        Section {
            if items.isEmpty {
                Text("Keine Workouts in 14 Tagen")
                    .foregroundStyle(BIOSTheme.text2)
            }
            ForEach(items) { item in
                WorkoutRow(item: item)
                    .deleteDisabled(!item.deletable)
            }
            .onDelete { offsets in
                let chosen = offsets.compactMap { $0 < items.count ? items[$0] : nil }.filter(\.deletable)
                Task { @MainActor in
                    for item in chosen {
                        await store.delete(item)
                    }
                }
            }
        } header: {
            Text("Letzte 14 Tage")
        } footer: {
            if let error = store.lastError {
                Text(error)
            } else {
                Text("Manuelle Einträge: wischen zum Löschen. Whoop-Workouts kommen vom Band.")
            }
        }
    }
}

struct WorkoutRow: View {
    let item: WorkoutItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body.weight(.semibold))
                Text(item.detailLine)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                if let note = item.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            Spacer(minLength: 8)
            Text(item.whenText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Heute: "Letztes Krafttraining ..." with the server's cautious note, the recent workouts
/// (manual ones deletable via the menu) and "Training eintragen".
struct TrainingCard: View {
    let strength: StrengthModel?
    let recent: [WorkoutItem]
    let onAdd: () -> Void
    @State private var pendingDelete: WorkoutItem?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dumbbell")
                    .font(.body)
                    .foregroundStyle(BIOSTheme.text2)
                    .frame(width: 34, height: 34)
                    .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(strength?.headline ?? "Training")
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text1)
                    if let note = strength?.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if strength?.manual == true {
                        Text("manuell eingetragen")
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onAdd) {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Training eintragen")
            }
            ForEach(recent.prefix(3)) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text1)
                        Text(item.detailLine)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                    Spacer(minLength: 8)
                    Text(item.whenText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text2)
                    if item.deletable {
                        Menu {
                            Button("Löschen", systemImage: "trash", role: .destructive) {
                                pendingDelete = item
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                                .frame(width: 28, height: 24)
                        }
                        .accessibilityLabel("Optionen für \(item.title)")
                    }
                }
            }
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.badText)
            }
        }
        .biosCard(padding: 14)
        .confirmationDialog("Workout löschen?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                guard let item = pendingDelete else { return }
                pendingDelete = nil
                Task { @MainActor in
                    if case .failed(let text) = await WorkoutStore.shared.delete(item) {
                        error = "Nicht gelöscht: \(text)"
                    } else {
                        error = nil
                    }
                }
            }
            Button("Abbrechen", role: .cancel) {
                pendingDelete = nil
            }
        } message: {
            if let item = pendingDelete {
                Text("\(item.title), \(item.whenText), \(item.durationMin) min")
            }
        }
    }
}
