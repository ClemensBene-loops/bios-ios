import SwiftUI

// Gesundheits-Score ring, shared by the app (hero on Heute, score detail) and
// the widget extension (Live Activity lock screen and Dynamic Island).
// Compiled into both targets from Shared/ (project.yml). One geometry, one
// pillar order, one set of pillar colors: no copies per view.

// MARK: - Pillars (order and colors)

/// The six pillars in the server ring order (`ORDER` in the BIOS repo,
/// analysis/health_score.py): clockwise from the top Schlaf, Erholung,
/// Stoffwechsel, Kreislauf, Abwehr, Routine. Design A colors.
enum HealthPillarPalette {
    struct Pillar: Hashable, Sendable {
        let key: String
        let label: String
        let hex: UInt32

        var color: Color { Color(activityHex: hex) }
    }

    static let pillars: [Pillar] = [
        Pillar(key: "sleep", label: "Schlaf", hex: 0xB39DFA),
        Pillar(key: "recovery", label: "Erholung", hex: 0x68D8CB),
        Pillar(key: "metabolism", label: "Stoffwechsel", hex: 0x5AA7FF),
        Pillar(key: "circulation", label: "Kreislauf", hex: 0x8EC7A4),
        Pillar(key: "immune", label: "Abwehr", hex: 0xFFD23F),
        Pillar(key: "routine", label: "Routine", hex: 0xD6C28C),
    ]

    /// Canonical keys in ring order.
    static let order: [String] = pillars.map(\.key)

    /// Canonical key for a server key or German label ("Schlaf" -> "sleep").
    /// Unknown keys come back unchanged.
    static func canonical(_ key: String, label: String? = nil) -> String {
        let text = (key + " " + (label ?? "")).lowercased()
        if text.contains("sleep") || text.contains("schlaf") { return "sleep" }
        if text.contains("recover") || text.contains("erholung") { return "recovery" }
        if text.contains("metab") || text.contains("stoffwechsel") || text.contains("glucose") { return "metabolism" }
        if text.contains("circ") || text.contains("kreislauf") || text.contains("cardio") { return "circulation" }
        if text.contains("immun") || text.contains("abwehr") || text.contains("infect") { return "immune" }
        if text.contains("routine") || text.contains("habit") { return "routine" }
        return key
    }

    /// Ring slot 0...5 of a pillar, nil for an unknown key.
    static func index(of key: String, label: String? = nil) -> Int? {
        order.firstIndex(of: canonical(key, label: label))
    }

    static func pillar(_ key: String, label: String? = nil) -> Pillar? {
        index(of: key, label: label).map { pillars[$0] }
    }

    /// Design color of a pillar, nil for an unknown key.
    static func color(_ key: String, label: String? = nil) -> Color? {
        pillar(key, label: label)?.color
    }

    /// German label of a pillar, the key itself when unknown.
    static func defaultLabel(_ key: String) -> String {
        pillar(key)?.label ?? key
    }
}

// MARK: - Geometry

/// Six equal arcs, start at 12 o'clock, clockwise. A fixed visible gap `g`
/// (in points, converted to an angle per radius) separates the arcs, and the
/// round cap overhang `c = (lineWidth / 2) / r` is taken off both ends so a
/// cap ends inside its own segment:
///
///     span     = 2π / n
///     g        = gapPoints / r
///     c        = (lineWidth / 2) / r
///     a0       = i · span + g/2 + c
///     a1       = (i + 1) · span − g/2 − c
///     fill_end = a0 + (a1 − a0) · score / 100
///
/// If `a1 <= a0` (small radius, thick line) the segment uses a butt cap and
/// `a0 = i · span + g/2`, `a1 = (i + 1) · span − g/2`. `r` is the center line
/// of the stroke. Checked numerically in the N1a mockup (smallest gap between
/// two drawn arcs including caps: 2.97 pt for all four ring sizes).
enum HealthRingGeometry {
    /// Visible gap between two arcs in points.
    static let gapPoints: Double = 3

    struct Segment: Hashable, Sendable {
        /// Radians clockwise from 12 o'clock.
        let start: Double
        let end: Double
        let roundCap: Bool

        var lineCap: CGLineCap { roundCap ? .round : .butt }

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

    static func segments(radius: Double, lineWidth: Double, count: Int = 6) -> [Segment] {
        guard count > 0, radius > 0 else { return [] }
        let span = 2 * Double.pi / Double(count)
        let g = gapPoints / radius
        let c = Swift.max(lineWidth, 0) / 2 / radius
        return (0..<count).map { i in
            let a0 = Double(i) * span + g / 2 + c
            let a1 = Double(i + 1) * span - g / 2 - c
            if a1 > a0 {
                return Segment(start: a0, end: a1, roundCap: true)
            }
            return Segment(start: Double(i) * span + g / 2, end: Double(i + 1) * span - g / 2, roundCap: false)
        }
    }
}

// MARK: - View

/// The six-arc ring. `values` in ring order (0...100, nil = pillar missing),
/// `colors` per slot (defaults to the palette). A value shows a dim track
/// from a0 to a1 plus a fill up to fill_end; value 0 shows the track only; a
/// missing pillar shows a grey dashed track. The view's frame is the center
/// line circle (2 · radius); the stroke reaches lineWidth / 2 beyond it.
struct HealthSegmentRing: View {
    enum Track {
        /// White 8 % (app).
        case neutral
        /// Pillar color 18 % (Live Activity on the dark banner).
        case tinted
    }

    let values: [Double?]
    var colors: [Color] = HealthPillarPalette.pillars.map(\.color)
    let radius: CGFloat
    let lineWidth: CGFloat
    var track: Track = .neutral

    /// Dashed track of a missing pillar.
    static let missingColor = Color(activityHex: 0xA0A8B4).opacity(0.55)

    var body: some View {
        let segments = HealthRingGeometry.segments(radius: Double(radius), lineWidth: Double(lineWidth),
                                                   count: HealthPillarPalette.pillars.count)
        ZStack {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                let color = colors.indices.contains(index) ? colors[index] : HealthPillarPalette.pillars[index].color
                if let value = slotValue(at: index) {
                    Circle()
                        .trim(from: HealthRingGeometry.Segment.trim(segment.start),
                              to: HealthRingGeometry.Segment.trim(segment.end))
                        .stroke(trackColor(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: segment.lineCap))
                    if value > 0 {
                        Circle()
                            .trim(from: HealthRingGeometry.Segment.trim(segment.start),
                                  to: HealthRingGeometry.Segment.trim(segment.fillEnd(score: value)))
                            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: segment.lineCap))
                    }
                } else {
                    Circle()
                        .trim(from: HealthRingGeometry.Segment.trim(segment.start),
                              to: HealthRingGeometry.Segment.trim(segment.end))
                        .stroke(Self.missingColor,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                                   dash: [lineWidth * 0.55, lineWidth * 0.75]))
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: radius * 2, height: radius * 2)
        .accessibilityHidden(true)
    }

    /// Finite value of a slot, nil when missing.
    private func slotValue(at index: Int) -> Double? {
        guard values.indices.contains(index), let value = values[index], value.isFinite else { return nil }
        return value
    }

    private func trackColor(_ color: Color) -> Color {
        switch track {
        case .neutral: return Color.white.opacity(0.08)
        case .tinted: return color.opacity(0.18)
        }
    }
}
