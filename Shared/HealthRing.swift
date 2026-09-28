import SwiftUI

// Gesundheits-Score ring, shared by the app (hero on Heute, score detail) and
// the widget extension (Live Activity lock screen, Dynamic Island, home
// screen widget). Compiled into both targets from Shared/ (project.yml). One
// geometry, one segment order, one set of colors: no copies per view.

// MARK: - Segments (order, arcs and colors)

/// Formula 4 (28.09.2026): six ring segments in the server order
/// (`V4_ORDER` in the BIOS repo, analysis/health_score.py), clockwise from
/// 12 o'clock: Schlaf, Erholung, Zucker, Bewegung, Therapie, Labor. Arc length
/// = nominal weight (20, 20, 25, 15, 10, 10). The server sends order, labels
/// and colors in `health.ring`; these are the defaults (Live Activity and
/// widgets get only the six fills in `pillars_mini`).
///
/// Old servers (formula 1 to 3, no `ring`) keep their layout: six equal arcs
/// Schlaf, Erholung, Stoffwechsel, Kreislauf, Abwehr, Routine (`legacy`), Labor
/// (formula 3) as a background pillar without a segment.
enum HealthPillarPalette {
    struct Pillar: Hashable, Sendable {
        let key: String
        let label: String
        let hex: UInt32
        /// Nominal arc length (weight); 1 for the equal legacy arcs.
        let arc: Double

        var color: Color { Color(activityHex: hex) }
    }

    /// Formula 4 ring segments.
    static let pillars: [Pillar] = [
        Pillar(key: "schlaf", label: "Schlaf", hex: 0x5B6CFF, arc: 20),
        Pillar(key: "erholung", label: "Erholung", hex: 0x14B8A6, arc: 20),
        Pillar(key: "zucker", label: "Zucker", hex: 0xF59E0B, arc: 25),
        Pillar(key: "bewegung", label: "Bewegung", hex: 0xF97362, arc: 15),
        Pillar(key: "therapie", label: "Therapie", hex: 0xA855F7, arc: 10),
        Pillar(key: "labor", label: "Labor", hex: 0xE0457B, arc: 10),
    ]

    /// Canonical keys in ring order (formula 4).
    static let order: [String] = pillars.map(\.key)

    /// Arc lengths in ring order (formula 4).
    static let arcs: [Double] = pillars.map(\.arc)

    /// Formula 1 to 3 ring pillars (old servers without `ring`).
    static let legacyPillars: [Pillar] = [
        Pillar(key: "schlaf", label: "Schlaf", hex: 0xB39DFA, arc: 1),
        Pillar(key: "erholung", label: "Erholung", hex: 0x68D8CB, arc: 1),
        Pillar(key: "stoffwechsel", label: "Stoffwechsel", hex: 0x5AA7FF, arc: 1),
        Pillar(key: "kreislauf", label: "Kreislauf", hex: 0x8EC7A4, arc: 1),
        Pillar(key: "abwehr", label: "Abwehr", hex: 0xFFD23F, arc: 1),
        Pillar(key: "routine", label: "Routine", hex: 0xD6C28C, arc: 1),
    ]

    static let legacyOrder: [String] = legacyPillars.map(\.key)

    /// Formula 3 background pillar (grid and detail, no ring segment).
    static let legacyBackground: [Pillar] = [
        Pillar(key: "labor", label: "Labor", hex: 0xE48FB0, arc: 0),
    ]

    /// Grid and detail order of an old server: the six legacy ring pillars, then Labor.
    static let legacyDisplayOrder: [String] = legacyOrder + legacyBackground.map(\.key)

    /// Legacy pillar key -> formula 4 segment it stands for (server `V4_LEGACY_KEYS`).
    static let legacyToSegment: [String: String] = [
        "stoffwechsel": "zucker",
        "kreislauf": "bewegung",
        "routine": "therapie",
    ]

    private static let knownKeys: Set<String> = Set(order + legacyOrder)

    /// Canonical key for a server key or German label ("sleep" -> "schlaf").
    /// Formula 4 keys and legacy keys both stay what they are; unknown keys
    /// come back unchanged.
    static func canonical(_ key: String, label: String? = nil) -> String {
        let lower = key.lowercased()
        if knownKeys.contains(lower) { return lower }
        if lower == "lab" || lower == "labs" { return "labor" }
        let text = (key + " " + (label ?? "")).lowercased()
        if text.contains("sleep") || text.contains("schlaf") { return "schlaf" }
        if text.contains("recover") || text.contains("erholung") { return "erholung" }
        if text.contains("metab") || text.contains("stoffwechsel") { return "stoffwechsel" }
        if text.contains("zucker") || text.contains("glucose") || text.contains("sugar") { return "zucker" }
        if text.contains("bewegung") || text.contains("movement") || text.contains("exercise") { return "bewegung" }
        if text.contains("therap") { return "therapie" }
        if text.contains("circ") || text.contains("kreislauf") || text.contains("cardio") { return "kreislauf" }
        if text.contains("immun") || text.contains("abwehr") || text.contains("infect") { return "abwehr" }
        if text.contains("routine") || text.contains("habit") { return "routine" }
        if text.contains("labor") { return "labor" }
        return key
    }

    /// Formula 4 segment key of a pillar key (legacy keys mapped like the
    /// server does; `abwehr` has no segment any more).
    static func segmentKey(_ key: String, label: String? = nil) -> String? {
        let canonicalKey = canonical(key, label: label)
        if let mapped = legacyToSegment[canonicalKey] { return mapped }
        return order.contains(canonicalKey) ? canonicalKey : nil
    }

    /// Formula 4 ring slot 0...5 of a key (legacy keys mapped), nil when unknown.
    static func index(of key: String, label: String? = nil) -> Int? {
        segmentKey(key, label: label).flatMap { order.firstIndex(of: $0) }
    }

    /// Legacy ring slot 0...5 (old servers), nil for Labor and unknown keys.
    static func legacyIndex(of key: String, label: String? = nil) -> Int? {
        legacyOrder.firstIndex(of: canonical(key, label: label))
    }

    /// Whether a pillar is the formula 3 background pillar (Labor, old servers only).
    static func isLegacyBackground(_ key: String, label: String? = nil) -> Bool {
        let canonicalKey = canonical(key, label: label)
        return legacyBackground.contains { $0.key == canonicalKey }
    }

    /// Formula 4 segment or legacy pillar, nil for an unknown key.
    static func anyPillar(_ key: String, label: String? = nil) -> Pillar? {
        let canonicalKey = canonical(key, label: label)
        return pillars.first { $0.key == canonicalKey }
            ?? legacyPillars.first { $0.key == canonicalKey }
    }

    /// Default color (formula 4 segment first, else legacy), nil when unknown.
    static func color(_ key: String, label: String? = nil) -> Color? {
        anyPillar(key, label: label)?.color
    }

    /// German label, the key itself when unknown.
    static func defaultLabel(_ key: String) -> String {
        anyPillar(key)?.label ?? key
    }
}

// MARK: - Geometry

/// Arcs start at 12 o'clock and run clockwise, each arc's span proportional to
/// its weight (equal weights = equal arcs). A fixed visible gap `g` (in
/// points, converted to an angle per radius) separates the arcs, and the round
/// cap overhang `c = (lineWidth / 2) / r` is taken off both ends so a cap ends
/// inside its own segment:
///
///     span_i   = 2π · w_i / Σw
///     g        = gapPoints / r
///     c        = (lineWidth / 2) / r
///     a0       = start_i + g/2 + c
///     a1       = start_i + span_i − g/2 − c
///     fill_end = a0 + (a1 − a0) · score / 100
///
/// If `a1 <= a0` (small radius, thick line, short arc) the segment uses a butt
/// cap and `a0 = start_i + g/2`, `a1 = start_i + span_i − g/2`. `r` is the
/// center line of the stroke. A weight of 0 gives an empty segment.
enum HealthRingGeometry {
    /// Visible gap between two arcs in points.
    static let gapPoints: Double = 3

    struct Segment: Hashable, Sendable {
        /// Radians clockwise from 12 o'clock.
        let start: Double
        let end: Double
        let roundCap: Bool

        var lineCap: CGLineCap { roundCap ? .round : .butt }

        /// Nothing to draw (weight 0 or no room left after the gaps).
        var isEmpty: Bool { end <= start }

        /// End angle of the fill for a score 0...100 (clamped).
        func fillEnd(score: Double) -> Double {
            let fraction = score.isFinite ? Swift.min(Swift.max(score / 100, 0), 1) : 0
            return start + (end - start) * fraction
        }

        /// Angle as a `Circle().trim` fraction (after the -90° rotation).
        static func trim(_ angle: Double) -> CGFloat {
            CGFloat(Swift.min(Swift.max(angle / (2 * Double.pi), 0), 1))
        }
    }

    /// `count` equal arcs.
    static func segments(radius: Double, lineWidth: Double, count: Int = 6) -> [Segment] {
        guard count > 0 else { return [] }
        return segments(radius: radius, lineWidth: lineWidth, arcs: Array(repeating: 1, count: count))
    }

    /// One arc per weight in `arcs`, spans proportional to the weights.
    static func segments(radius: Double, lineWidth: Double, arcs: [Double]) -> [Segment] {
        let weights = arcs.map { $0.isFinite && $0 > 0 ? $0 : 0 }
        let total = weights.reduce(0, +)
        guard radius > 0, total > 0 else { return [] }
        let g = gapPoints / radius
        let c = Swift.max(lineWidth, 0) / 2 / radius
        var result: [Segment] = []
        var cursor = 0.0
        for weight in weights {
            let span = 2 * Double.pi * weight / total
            if weight <= 0 {
                result.append(Segment(start: cursor, end: cursor, roundCap: false))
            } else {
                let a0 = cursor + g / 2 + c
                let a1 = cursor + span - g / 2 - c
                if a1 > a0 {
                    result.append(Segment(start: a0, end: a1, roundCap: true))
                } else {
                    let b0 = cursor + g / 2
                    result.append(Segment(start: b0, end: Swift.max(b0, cursor + span - g / 2), roundCap: false))
                }
            }
            cursor += span
        }
        return result
    }
}

// MARK: - View

/// How a ring slot is drawn (formula 4 `ring[].status`).
enum HealthRingSlotStyle: Hashable, Sendable {
    /// Track plus fill in the segment color (`ok`).
    case normal
    /// Grey dashed track (`keine_daten`, or no value).
    case missing
    /// Grey solid track without fill (`pause`, `nicht_erfasst`).
    case inactive
    /// Paler track and fill (`verblasst`, Labor older than 180 days).
    case faded
}

/// The segment ring. `values` in ring order (0...100, nil = no value),
/// `colors` per slot (defaults to the palette), `arcs` the arc weights
/// (nil = equal arcs), `styles` per slot (nil = from the value). A value shows
/// a dim track from a0 to a1 plus a fill up to fill_end; value 0 shows the
/// track only; a missing value shows a grey dashed track. The view's frame is
/// the center line circle (2 · radius); the stroke reaches lineWidth / 2
/// beyond it.
struct HealthSegmentRing: View {
    enum Track {
        /// White 8 % (app).
        case neutral
        /// Segment color 18 % (Live Activity on the dark banner).
        case tinted
    }

    let values: [Double?]
    var colors: [Color] = HealthPillarPalette.pillars.map(\.color)
    var arcs: [Double]? = nil
    var styles: [HealthRingSlotStyle]? = nil
    let radius: CGFloat
    let lineWidth: CGFloat
    var track: Track = .neutral

    /// Dashed track of a missing value.
    static let missingColor = Color(activityHex: 0xA0A8B4).opacity(0.55)
    /// Solid track of a paused or not recorded segment.
    static let inactiveColor = Color(activityHex: 0xA0A8B4).opacity(0.30)

    var body: some View {
        let weights = arcs ?? Array(repeating: 1, count: HealthPillarPalette.pillars.count)
        let segments = HealthRingGeometry.segments(radius: Double(radius), lineWidth: Double(lineWidth), arcs: weights)
        ZStack {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                if !segment.isEmpty {
                    slot(segment, index: index)
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func slot(_ segment: HealthRingGeometry.Segment, index: Int) -> some View {
        let color = slotColor(at: index)
        let value = slotValue(at: index)
        let style = slotStyle(at: index, value: value)
        let from = HealthRingGeometry.Segment.trim(segment.start)
        let to = HealthRingGeometry.Segment.trim(segment.end)
        switch style {
        case .missing:
            Circle()
                .trim(from: from, to: to)
                .stroke(Self.missingColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                           dash: [lineWidth * 0.55, lineWidth * 0.75]))
        case .inactive:
            Circle()
                .trim(from: from, to: to)
                .stroke(Self.inactiveColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: segment.lineCap))
        case .normal, .faded:
            let faded = style == .faded
            Circle()
                .trim(from: from, to: to)
                .stroke(faded ? color.opacity(0.10) : trackColor(color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: segment.lineCap))
            if let value, value > 0 {
                Circle()
                    .trim(from: from, to: HealthRingGeometry.Segment.trim(segment.fillEnd(score: value)))
                    .stroke(faded ? color.opacity(0.45) : color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: segment.lineCap))
            }
        }
    }

    /// Finite value of a slot, nil when missing.
    private func slotValue(at index: Int) -> Double? {
        guard values.indices.contains(index), let value = values[index], value.isFinite else { return nil }
        return value
    }

    private func slotColor(at index: Int) -> Color {
        if colors.indices.contains(index) { return colors[index] }
        let palette = HealthPillarPalette.pillars
        return palette.indices.contains(index) ? palette[index].color : Self.missingColor
    }

    /// Explicit style, else normal with a value and missing without one. A
    /// normal or faded slot without a value is drawn as missing.
    private func slotStyle(at index: Int, value: Double?) -> HealthRingSlotStyle {
        let given: HealthRingSlotStyle? = styles.flatMap { $0.indices.contains(index) ? $0[index] : nil }
        switch given {
        case .inactive?: return .inactive
        case .missing?: return .missing
        case .faded?: return value == nil ? .missing : .faded
        case .normal?, nil: return value == nil ? .missing : .normal
        }
    }

    private func trackColor(_ color: Color) -> Color {
        switch track {
        case .neutral: return Color.white.opacity(0.08)
        case .tinted: return color.opacity(0.18)
        }
    }
}
