import SwiftUI
import WidgetKit

// Lock screen widgets (and a small home screen widget) instead of the Live
// Activity: BIOS stays out of the Dynamic Island, where Loop shows glucose.
// Same content as the Live Activity: `content_state` of GET /v1/live-activity
// (Shared/BIOSActivityAttributes.swift), fetched by the extension itself with
// the build-time config (AppConfig, Shared/). No App Group: the extension
// keeps its own last good state in its own UserDefaults as the offline
// fallback. The app reloads the timelines after a dashboard refresh.
//
// Lock screen = visible to anyone: the widgets never show medication names,
// only the next time.

// MARK: - Timeline

struct BIOSStatusEntry: TimelineEntry {
    enum Source {
        /// Fresh from the server.
        case live
        /// Last good state of the extension (server not reachable).
        case cached
        /// Example values (placeholder, gallery).
        case sample
        /// Nothing yet: not configured or never loaded.
        case empty
    }

    let date: Date
    let state: BIOSActivityState
    let source: Source
    /// When `state` was fetched (live or cached).
    let fetchedAt: Date?
    /// Server URL or secret missing in this build.
    var notConfigured = false

    /// Older than 2 h (like the Live Activity's stale date).
    var isStale: Bool {
        guard let fetchedAt else { return false }
        return date.timeIntervalSince(fetchedAt) > 2 * 3600
    }

    static func sample(_ date: Date = Date()) -> BIOSStatusEntry {
        BIOSStatusEntry(date: date, state: .widgetSample, source: .sample, fetchedAt: date)
    }
}

struct BIOSStatusProvider: TimelineProvider {
    /// Refresh policy: every 30 min (WidgetKit may stretch it within its budget).
    static let refreshInterval: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> BIOSStatusEntry {
        .sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (BIOSStatusEntry) -> Void) {
        if context.isPreview {
            completion(.sample())
            return
        }
        Task {
            completion(await BIOSWidgetData.load())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BIOSStatusEntry>) -> Void) {
        Task {
            let entry = await BIOSWidgetData.load()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(Self.refreshInterval))))
        }
    }
}

/// Fetch and offline cache of the widget (extension-local, no App Group).
enum BIOSWidgetData {
    private static let cacheKey = "bios.widget.state"
    private static let cacheDateKey = "bios.widget.fetchedAt"

    static func load(now: Date = Date()) async -> BIOSStatusEntry {
        guard let baseURL = AppConfig.apiBaseURL, let secret = AppConfig.apiSecret else {
            if let cached = cached() {
                return BIOSStatusEntry(date: now, state: cached.state, source: .cached, fetchedAt: cached.at, notConfigured: true)
            }
            return BIOSStatusEntry(date: now, state: BIOSActivityState(), source: .empty, fetchedAt: nil, notConfigured: true)
        }
        if let state = try? await fetch(baseURL: baseURL, secret: secret) {
            save(state, at: now)
            return BIOSStatusEntry(date: now, state: state, source: .live, fetchedAt: now)
        }
        if let cached = cached() {
            return BIOSStatusEntry(date: now, state: cached.state, source: .cached, fetchedAt: cached.at)
        }
        return BIOSStatusEntry(date: now, state: BIOSActivityState(), source: .empty, fetchedAt: nil)
    }

    /// `GET /v1/live-activity` -> `content_state` (one short attempt).
    static func fetch(baseURL: URL, secret: String) async throws -> BIOSActivityState {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent("live-activity"))
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["content_state"] as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let contentData = try JSONSerialization.data(withJSONObject: content)
        return try JSONDecoder().decode(BIOSActivityState.self, from: contentData)
    }

    private static func save(_ state: BIOSActivityState, at date: Date) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: cacheDateKey)
    }

    private static func cached() -> (state: BIOSActivityState, at: Date)? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let state = try? JSONDecoder().decode(BIOSActivityState.self, from: data) else { return nil }
        let seconds = UserDefaults.standard.double(forKey: cacheDateKey)
        return (state, Date(timeIntervalSince1970: seconds))
    }
}

// MARK: - Widget

struct BIOSStatusWidget: Widget {
    static let kind = "BIOSStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: BIOSStatusProvider()) { entry in
            BIOSStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("BIOS")
        .description("Gesundheits-Score, Infekt-Status, nächste Einnahme und Supplements.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

struct BIOSStatusWidgetView: View {
    let entry: BIOSStatusEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            BIOSCircularView(entry: entry)
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryInline:
            BIOSInlineView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        case .systemSmall:
            BIOSSmallView(entry: entry)
                .containerBackground(for: .widget) { BIOSActivityColors.banner }
        default:
            BIOSRectangularView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

// MARK: - Texts (German)

extension BIOSStatusEntry {
    var hasData: Bool {
        source != .empty
    }

    /// "Infekt · Tag 4", "Infekt-Frühzeichen · Tag 2", "37,8 °C · Erhöht", "Kein Infekt".
    var statusText: String {
        let state = self.state
        switch state.mode {
        case .infection:
            let word = state.infectionKind == "infekt_frueh" ? "Infekt-Frühzeichen" : "Infekt"
            return word + (state.infectionDay.map { " · Tag \($0)" } ?? "")
        case .temperature:
            return (state.temperatureText ?? "Temperatur") + " · " + state.temperatureLabel
        case .normal:
            return "Kein Infekt"
        }
    }

    /// "Infekt Tag 4", "37,8 °C", nil in normal mode (inline, compact).
    var shortStatus: String? {
        switch state.mode {
        case .infection:
            let word = state.infectionKind == "infekt_frueh" ? "Frühzeichen" : "Infekt"
            return word + (state.infectionDay.map { " Tag \($0)" } ?? "")
        case .temperature:
            return state.temperatureText
        case .normal:
            return nil
        }
    }

    /// Next intake time without the name ("Nächste 12:30", "Überfällig 08:00").
    var medicationLine: String {
        guard state.hasNextMedication, let time = state.nextTime else { return "Einnahmen erledigt" }
        if state.nextMedication?.overdue == true { return "Überfällig \(time)" }
        return "Nächste \(time)"
    }

    /// "3/4" or nil without a supplement plan.
    var supplementsShort: String? {
        guard let total = state.supplements?.total, total > 0 else { return nil }
        let taken = min(max(state.supplements?.taken ?? 0, 0), total)
        return "\(taken)/\(total)"
    }

    var emptyText: String {
        notConfigured ? "Server nicht konfiguriert" : "Noch keine Daten, App öffnen"
    }

    /// "Stand 10:15" for stale or cached data, else nil.
    var standText: String? {
        guard source == .cached || isStale, let fetchedAt else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: fetchedAt)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        return Calendar.current.isDateInToday(fetchedAt) ? "Stand \(clock)" : "Stand älter"
    }
}

// MARK: - Lock screen: rectangular

struct BIOSRectangularView: View {
    let entry: BIOSStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("BIOS")
                    .font(.system(size: 13, weight: .semibold))
                if entry.hasData {
                    Text(entry.state.healthScoreText)
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .widgetAccentable()
                    Text(entry.state.healthLevelText)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
            }
            if entry.hasData {
                Text(entry.statusText)
                    .font(.system(size: 13, weight: entry.state.mode == .normal ? .regular : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                ViewThatFits(in: .horizontal) {
                    Text(medicationAndSupplements(long: true))
                    Text(medicationAndSupplements(long: false))
                    Text(entry.medicationLine)
                }
                .font(.system(size: 13))
                .monospacedDigit()
                .lineLimit(1)
            } else {
                Text(entry.emptyText)
                    .font(.system(size: 13))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(entry.isStale ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BIOSWidgetSpoken.label(entry))
    }

    private func medicationAndSupplements(long: Bool) -> String {
        guard let supplements = entry.supplementsShort else { return entry.medicationLine }
        return entry.medicationLine + " · " + (long ? "Supplements " : "Supp. ") + supplements
    }
}

// MARK: - Lock screen: circular

struct BIOSCircularView: View {
    let entry: BIOSStatusEntry

    private var score: Double {
        Double(min(max(entry.state.healthScore ?? 0, 0), 100))
    }

    var body: some View {
        Gauge(value: score, in: 0...100) {
            Text("BIOS")
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text(entry.hasData ? entry.state.healthScoreText : "–")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .widgetAccentable()
                Text(entry.hasData ? levelShort : "BIOS")
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .opacity(entry.isStale ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BIOSWidgetSpoken.label(entry))
    }

    /// Infekt wins over the level word in the tiny circle.
    private var levelShort: String {
        switch entry.state.mode {
        case .infection: return "Infekt"
        case .temperature: return entry.state.temperatureShortText ?? "Temp."
        case .normal: return entry.state.healthLevelText
        }
    }
}

// MARK: - Lock screen: inline

struct BIOSInlineView: View {
    let entry: BIOSStatusEntry

    var body: some View {
        Text(text)
            .accessibilityLabel(BIOSWidgetSpoken.label(entry))
    }

    /// "BIOS 49 · Infekt Tag 4", "BIOS 78 · gut · 12:30".
    private var text: String {
        guard entry.hasData else { return "BIOS · " + entry.emptyText }
        var parts = ["BIOS \(entry.state.healthScoreText)"]
        if let status = entry.shortStatus {
            parts.append(status)
        } else {
            parts.append(entry.state.healthLevelText)
            if entry.state.hasNextMedication, let time = entry.state.nextTime {
                parts.append(time)
            }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Home screen: small

struct BIOSSmallView: View {
    let entry: BIOSStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HealthRingView(state: entry.state, diameter: 50, lineWidth: 4, numberSize: 20, showsLevel: false)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gesundheit")
                        .font(.system(size: 11))
                        .foregroundStyle(BIOSActivityColors.text2)
                    Text(entry.hasData ? entry.state.healthLevelText : "–")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(entry.state.healthLevelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            if entry.hasData {
                Text(entry.statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.state.mode == .normal ? BIOSActivityColors.cream : BIOSActivityColors.attention)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(entry.medicationLine)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(entry.state.nextMedication?.overdue == true ? BIOSActivityColors.attention : BIOSActivityColors.cream)
                    .lineLimit(1)
                if let supplements = entry.supplementsShort {
                    Text("Supplements \(supplements)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(BIOSActivityColors.text2)
                        .lineLimit(1)
                }
            } else {
                Text(entry.emptyText)
                    .font(.system(size: 12))
                    .foregroundStyle(BIOSActivityColors.text2)
                    .lineLimit(3)
            }
            if let stand = entry.standText {
                Text(stand)
                    .font(.system(size: 10))
                    .foregroundStyle(BIOSActivityColors.text2)
            }
        }
        .foregroundStyle(BIOSActivityColors.cream)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BIOSWidgetSpoken.label(entry))
    }
}

// MARK: - VoiceOver

enum BIOSWidgetSpoken {
    static func label(_ entry: BIOSStatusEntry) -> String {
        guard entry.hasData else { return "BIOS, " + entry.emptyText }
        var parts = ["BIOS Gesundheit \(entry.state.healthScoreText), \(entry.state.healthLevelText)", entry.statusText,
                     entry.medicationLine]
        if let supplements = entry.supplementsShort {
            parts.append("Supplements \(supplements)")
        }
        if let stand = entry.standText {
            parts.append(stand)
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sample (illustrative values only, no real data)

extension BIOSActivityState {
    static var widgetSample: BIOSActivityState {
        var state = BIOSActivityState.preview
        state.healthScore = 72
        state.healthLevel = "gut"
        return state
    }
}

#Preview("Rechteckig", as: .accessoryRectangular) {
    BIOSStatusWidget()
} timeline: {
    BIOSStatusEntry.sample()
    BIOSStatusEntry(date: Date(), state: .previewInfection, source: .sample, fetchedAt: Date())
}

#Preview("Rund", as: .accessoryCircular) {
    BIOSStatusWidget()
} timeline: {
    BIOSStatusEntry.sample()
}

#Preview("Zeile", as: .accessoryInline) {
    BIOSStatusWidget()
} timeline: {
    BIOSStatusEntry(date: Date(), state: .previewInfection, source: .sample, fetchedAt: Date())
}

#Preview("Klein", as: .systemSmall) {
    BIOSStatusWidget()
} timeline: {
    BIOSStatusEntry.sample()
}
