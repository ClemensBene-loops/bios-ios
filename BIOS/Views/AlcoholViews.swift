import SwiftUI

/// Heute: compact "Alkohol" card with toggles for today and yesterday
/// (optimistic, queued offline) and a link to the calendar.
struct AlcoholCard: View {
    @EnvironmentObject var events: EventStore

    var body: some View {
        let now = Date()
        let today = EventStore.dayString(now)
        let yesterday = EventStore.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Alkohol", systemImage: "wineglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.context)
                Spacer()
                NavigationLink(value: DetailRoute.alkohol) {
                    HStack(spacing: 4) {
                        Text("Kalender")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.accent)
                }
                .accessibilityLabel("Alkohol-Kalender öffnen")
            }
            HStack(spacing: 8) {
                AlcoholDayButton(title: "Heute", day: today)
                AlcoholDayButton(title: "Gestern", day: yesterday)
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(BIOSTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard(padding: 14)
    }

    private var footer: String {
        if events.hasPending {
            return "Wartet auf Verbindung, wird nachgereicht."
        }
        return "Kontext für den Infekt-Check: nach Alkohol ist Erholung oft gedrückt."
    }
}

/// Toggle for one day: symbol + word show the state (not only color).
struct AlcoholDayButton: View {
    @EnvironmentObject var events: EventStore
    let title: String
    let day: String

    var body: some View {
        let marked = events.isMarked(day)
        let pending = events.isPending(day)
        Button {
            events.toggle(day)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: marked ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(marked ? "eingetragen" : "kein Eintrag")
                        .font(.caption)
                        .foregroundStyle(marked ? Color(hex: 0xD9DFFF) : BIOSTheme.text2)
                }
                Spacer(minLength: 0)
                if pending {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(marked ? BIOSTheme.contextText : BIOSTheme.text1)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(marked ? BIOSTheme.context.opacity(0.18) : BIOSTheme.card2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(marked ? BIOSTheme.context.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityLabel("Alkohol \(title)")
        .accessibilityValue(marked ? "eingetragen" + (pending ? ", wird nachgereicht" : "") : "kein Eintrag")
        .accessibilityHint("Doppeltippen zum Umschalten")
    }
}

/// "Alkohol-Tage": the last 12 months as month grids; tapping a past day
/// toggles its mark (retroactive).
struct AlcoholCalendarView: View {
    @EnvironmentObject var events: EventStore

    var body: some View {
        let months = AlcoholCalendarView.months(count: 12)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    StatItem(label: "letzte 7 Tage", value: "\(events.markedCount(lastDays: 7))", unit: "Tage")
                    StatItem(label: "letzte 30 Tage", value: "\(events.markedCount(lastDays: 30))", unit: "Tage")
                    StatItem(label: "12 Monate", value: "\(events.markedCount(lastDays: 365))", unit: "Tage")
                }
                .biosCard()

                if events.hasPending || events.lastError != nil {
                    NotEvaluableBox(
                        title: events.hasPending ? "Noch nicht übertragen" : "Hinweis",
                        text: events.hasPending
                            ? "\(events.pending.count) Änderung(en) warten auf Verbindung und werden automatisch nachgereicht."
                            : events.lastError
                    )
                }

                ForEach(months, id: \.self) { month in
                    MonthGrid(month: month)
                }

                NoteText(text: "Tippen markiert einen Tag mit Alkohol oder entfernt die Markierung. Der Infekt-Check wertet Erholungseinbrüche nach solchen Tagen als Kontext statt als Infekt. Siri: \"Alkohol in BIOS\" oder \"Gestern Alkohol in BIOS\".")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .refreshable {
            await events.flush()
            await events.refresh()
        }
        .task {
            await events.flush()
            await events.refresh()
        }
    }

    /// First day of this month and the 11 before, newest first.
    static func months(count: Int, now: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        return (0..<count).compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }
    }
}

struct MonthGrid: View {
    @EnvironmentObject var events: EventStore
    let month: Date

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    }

    var body: some View {
        let cells = MonthGrid.cells(for: month)
        let today = EventStore.dayString(Date())
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { name in
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(BIOSTheme.text3)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(cells) { cell in
                    if let date = cell.date {
                        let day = EventStore.dayString(date)
                        DayCell(
                            number: Calendar.current.component(.day, from: date),
                            label: "\(Calendar.current.component(.day, from: date)). \(monthName)",
                            marked: events.isMarked(day),
                            pending: events.isPending(day),
                            isToday: day == today,
                            isFuture: day > today
                        ) {
                            events.toggle(day)
                        }
                    } else {
                        Color.clear
                            .frame(height: 40)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private var title: String {
        let year = Calendar.current.component(.year, from: month)
        return "\(monthName) \(year)"
    }

    private var monthName: String {
        let index = Calendar.current.component(.month, from: month) - 1
        return BIOSFormat.monthsLong[max(0, min(11, index))]
    }

    struct Cell: Identifiable {
        let id: Int
        let date: Date?
    }

    /// Leading blanks (weeks start on Monday) plus one cell per day.
    static func cells(for month: Date) -> [Cell] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday + 5) % 7
        var cells: [Cell] = []
        for index in 0..<leading {
            cells.append(Cell(id: -1 - index, date: nil))
        }
        for day in range {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month)
            cells.append(Cell(id: day, date: date))
        }
        return cells
    }
}

struct DayCell: View {
    let number: Int
    let label: String
    let marked: Bool
    let pending: Bool
    let isToday: Bool
    let isFuture: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(number)")
                    .font(.subheadline.weight(marked || isToday ? .bold : .regular))
                    .monospacedDigit()
                Image(systemName: marked ? "wineglass.fill" : "circle.fill")
                    .font(.system(size: marked ? 9 : 3))
                    .opacity(marked ? 1 : (pending ? 0.8 : 0))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(marked ? BIOSTheme.context.opacity(0.28) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isToday ? BIOSTheme.accent : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(label + (isToday ? ", heute" : ""))
        .accessibilityValue(marked ? "Alkohol eingetragen" : "kein Eintrag")
        .accessibilityHint(isFuture ? "" : "Doppeltippen zum Umschalten")
    }

    private var foreground: Color {
        if isFuture { return BIOSTheme.text3.opacity(0.5) }
        if marked { return BIOSTheme.contextText }
        return BIOSTheme.text1
    }
}

/// Bottom toast for event confirmations.
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x2C2F37).opacity(0.95), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
