import SwiftUI

// Körperkarte: layout and paths, the one place for the figure geometry.
//
// Normalized coordinates 0...1 in a box with width:height = `aspect` (0.5),
// x from the viewer's left, y from the top; the front view shows the left body
// side on the right. Radii: rx relative to the width, ry to the height. The
// values are identical to docs/fixtures/bodymap_layout.json in the BIOS repo
// (analysis.bodymap.LAYOUT) and to the N3b mockup. Invented drawing, no data.
// Lines are open polylines smoothed with uniform Catmull-Rom as cubic Bezier
// segments (control points p1 + (p2 - p0) / 6 and p2 - (p3 - p1) / 6,
// endpoints doubled), exactly like the mockup's `smooth()`.

/// Front or back view of the figure.
enum BodyMapSide: String, CaseIterable, Hashable {
    case front
    case back

    /// Server `view`; unknown values fall back to `.front`.
    init(key: String?) {
        self = BodyMapSide(rawValue: (key ?? "").lowercased()) ?? .front
    }
}

/// Ellipse in normalized coordinates.
struct BodyMapEllipse: Hashable {
    let cx: CGFloat
    let cy: CGFloat
    let rx: CGFloat
    let ry: CGFloat

    /// Bounding rect in a figure of `size` points, radii multiplied by `scale`.
    func rect(in size: CGSize, scale: CGFloat = 1) -> CGRect {
        let width = rx * size.width * 2 * scale
        let height = ry * size.height * 2 * scale
        return CGRect(x: cx * size.width - width / 2, y: cy * size.height - height / 2, width: width, height: height)
    }
}

enum BodyMapLayout {
    /// Layout of one region: view, badge position and ellipses.
    struct Region {
        let id: String
        let side: BodyMapSide
        let badge: CGPoint
        let shapes: [BodyMapEllipse]
    }

    /// `layout_version` of the server contract these numbers belong to.
    static let version = 1
    /// Width:height of the figure box.
    static let aspect: CGFloat = 0.5

    private static func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func E(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> BodyMapEllipse {
        BodyMapEllipse(cx: cx, cy: cy, rx: rx, ry: ry)
    }

    static let head = E(0.5, 0.095, 0.095, 0.06)

    /// 74 points, open polyline from the crotch around the figure back to the crotch.
    static let body: [CGPoint] = [
        P(0.495, 0.63), P(0.48, 0.725), P(0.47, 0.815), P(0.475, 0.88), P(0.465, 0.95), P(0.465, 0.9875),
        P(0.395, 0.9875), P(0.36, 0.97), P(0.37, 0.945), P(0.34, 0.875), P(0.35, 0.81), P(0.325, 0.75),
        P(0.31, 0.655), P(0.32, 0.58), P(0.35, 0.52), P(0.36, 0.455), P(0.335, 0.375), P(0.32, 0.31),
        P(0.295, 0.375), P(0.275, 0.445), P(0.255, 0.52), P(0.225, 0.605), P(0.215, 0.66), P(0.185, 0.69),
        P(0.15, 0.675), P(0.145, 0.63), P(0.165, 0.59), P(0.18, 0.5125), P(0.2, 0.43), P(0.215, 0.365),
        P(0.225, 0.3), P(0.235, 0.2575), P(0.27, 0.23), P(0.33, 0.2175), P(0.41, 0.205), P(0.46, 0.185),
        P(0.465, 0.15), P(0.535, 0.15), P(0.54, 0.185), P(0.59, 0.205), P(0.67, 0.2175), P(0.73, 0.23),
        P(0.765, 0.2575), P(0.775, 0.3), P(0.785, 0.365), P(0.8, 0.43), P(0.82, 0.5125), P(0.835, 0.59),
        P(0.855, 0.63), P(0.85, 0.675), P(0.815, 0.69), P(0.785, 0.66), P(0.775, 0.605), P(0.745, 0.52),
        P(0.725, 0.445), P(0.705, 0.375), P(0.68, 0.31), P(0.665, 0.375), P(0.64, 0.455), P(0.65, 0.52),
        P(0.68, 0.58), P(0.69, 0.655), P(0.675, 0.75), P(0.65, 0.81), P(0.66, 0.875), P(0.63, 0.945),
        P(0.64, 0.97), P(0.605, 0.9875), P(0.535, 0.9875), P(0.535, 0.95), P(0.525, 0.88), P(0.53, 0.815),
        P(0.52, 0.725), P(0.505, 0.63),
    ]

    static let detailsFront: [[CGPoint]] = [
        [P(0.33, 0.2225), P(0.41, 0.2125), P(0.485, 0.215)],
        [P(0.515, 0.215), P(0.59, 0.2125), P(0.67, 0.2225)],
        [P(0.5, 0.24), P(0.5, 0.5)],
    ]

    static let detailsBack: [[CGPoint]] = [
        [P(0.42, 0.25), P(0.38, 0.295), P(0.4, 0.345), P(0.46, 0.335)],
        [P(0.58, 0.25), P(0.62, 0.295), P(0.6, 0.345), P(0.54, 0.335)],
    ]

    static let regions: [Region] = [
        Region(id: "kopf_schlaf", side: .front, badge: P(0.5, 0.09),
               shapes: [E(0.5, 0.09, 0.065, 0.04)]),
        Region(id: "abwehr", side: .front, badge: P(0.5, 0.175),
               shapes: [E(0.5, 0.175, 0.04, 0.0175)]),
        Region(id: "lunge", side: .front, badge: P(0.42, 0.275),
               shapes: [E(0.43, 0.285, 0.06, 0.0475), E(0.57, 0.285, 0.06, 0.0475)]),
        Region(id: "herz", side: .front, badge: P(0.55, 0.315),
               shapes: [E(0.54, 0.31, 0.04, 0.0225)]),
        Region(id: "leber", side: .front, badge: P(0.425, 0.38),
               shapes: [E(0.44, 0.38, 0.075, 0.0225)]),
        Region(id: "stoffwechsel", side: .front, badge: P(0.565, 0.41),
               shapes: [E(0.545, 0.41, 0.065, 0.0175)]),
        Region(id: "muskeln", side: .front, badge: P(0.595, 0.725),
               shapes: [E(0.595, 0.715, 0.055, 0.0675), E(0.405, 0.715, 0.055, 0.0675), E(0.76, 0.375, 0.025, 0.05), E(0.24, 0.375, 0.025, 0.05)]),
        Region(id: "niere", side: .back, badge: P(0.555, 0.445),
               shapes: [E(0.445, 0.445, 0.035, 0.0275), E(0.555, 0.445, 0.035, 0.0275)]),
        Region(id: "knochen", side: .back, badge: P(0.5, 0.28),
               shapes: [E(0.5, 0.4, 0.02, 0.18)]),
    ]

    static func region(_ id: String) -> Region? {
        regions.first { $0.id == id }
    }

    static func details(_ side: BodyMapSide) -> [[CGPoint]] {
        side == .front ? detailsFront : detailsBack
    }
}

// MARK: - Paths

enum BodyMapPath {
    /// Open polyline of normalized points, smoothed (uniform Catmull-Rom, endpoints doubled).
    static func smooth(_ points: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        let pts = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        let count = pts.count
        guard count > 1 else { return path }
        for index in 0..<(count - 1) {
            let p0 = pts[max(index - 1, 0)]
            let p1 = pts[index]
            let p2 = pts[index + 1]
            let p3 = pts[min(index + 2, count - 1)]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }

    static func ellipses(_ shapes: [BodyMapEllipse], in rect: CGRect, scale: CGFloat = 1) -> Path {
        var path = Path()
        for shape in shapes {
            path.addEllipse(in: shape.rect(in: rect.size, scale: scale).offsetBy(dx: rect.minX, dy: rect.minY))
        }
        return path
    }
}

/// Head ellipse and body outline (same for front and back).
struct BodyOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = BodyMapPath.ellipses([BodyMapLayout.head], in: rect)
        path.addPath(BodyMapPath.smooth(BodyMapLayout.body, in: rect))
        return path
    }
}

/// Faint detail lines of one view (collarbones and midline, shoulder blades).
struct BodyDetailShape: Shape {
    let side: BodyMapSide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in BodyMapLayout.details(side) {
            path.addPath(BodyMapPath.smooth(line, in: rect))
        }
        return path
    }
}

/// The ellipses of one region (drawn in the full figure rect).
struct BodyRegionShape: Shape {
    let shapes: [BodyMapEllipse]
    var scale: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        BodyMapPath.ellipses(shapes, in: rect, scale: scale)
    }
}

/// Tap area of a region: its ellipses with a minimum half axis plus a circle
/// around the badge, in points of a figure of `figure` size, relative to `box`.
struct BodyRegionHitArea {
    static let minRadius: CGFloat = 11
    static let badgeRadius: CGFloat = 15

    let rects: [CGRect]
    let badge: CGRect?

    init(shapes: [BodyMapEllipse], badge: CGPoint?, figure: CGSize) {
        rects = shapes.map { shape in
            let rect = shape.rect(in: figure)
            let width = max(rect.width, Self.minRadius * 2)
            let height = max(rect.height, Self.minRadius * 2)
            return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }
        self.badge = badge.map { point in
            let center = CGPoint(x: point.x * figure.width, y: point.y * figure.height)
            return CGRect(x: center.x - Self.badgeRadius, y: center.y - Self.badgeRadius,
                          width: Self.badgeRadius * 2, height: Self.badgeRadius * 2)
        }
    }

    /// Bounding box of all parts in figure points.
    var box: CGRect {
        (rects + (badge.map { [$0] } ?? [])).reduce(CGRect.null) { $0.union($1) }
    }

    var shape: BodyRegionHitShape {
        let origin = box.origin
        return BodyRegionHitShape(parts: (rects + (badge.map { [$0] } ?? [])).map { $0.offsetBy(dx: -origin.x, dy: -origin.y) })
    }
}

/// Union of ellipses in local coordinates (content shape of a region button).
struct BodyRegionHitShape: Shape {
    let parts: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for part in parts {
            path.addEllipse(in: part.offsetBy(dx: rect.minX, dy: rect.minY))
        }
        return path
    }
}
