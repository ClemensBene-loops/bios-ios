import SwiftUI

/// Brand identity "Seed": cream lowercase "b" with a leaf-shaped counter on
/// dark forest green, plus the stroked wordmark "BIOS". Sources in docs/brand,
/// assets prepared by tools/make_icon.py. Used only by the start animation and
/// the "Über" row; the dashboard keeps the dark BIOSTheme.
enum BIOSBrand {
    /// Icon green, same asset as the UILaunchScreen background (no flash).
    static let green = Color("LaunchBackground")
    /// Wordmark cream (#F7F4E9) and caption tint (#D7E0CE) from the preview.
    static let cream = Color(hex: 0xF7F4E9)
    static let caption = Color(hex: 0xD7E0CE)
    static let tagline = "Let's get shit done."
}

/// The cream "b" (asset BIOSMark, transparent). The asset is a crop that is
/// symmetric around the icon center: `canvasFraction` is its size relative to
/// the full icon square (mirrors MARK_HALF in tools/make_icon.py).
struct BIOSMarkImage: View {
    static let canvasFraction = CGSize(width: 522.0 / 1254.0, height: 694.0 / 1254.0)
    /// Rendered height of the mark in points.
    var height: CGFloat

    /// Mark sized as it sits inside an icon square of side `tile`.
    init(tile: CGFloat) {
        height = tile * Self.canvasFraction.height
    }

    init(height: CGFloat) {
        self.height = height
    }

    var body: some View {
        Image("BIOSMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// Center lines of the wordmark "BIOS" in its SVG viewBox (234 x 82),
/// scaled uniformly (aspect fit) into the given rect. Stroke it with
/// `BIOSWordmark`, which scales the 3.4 unit stroke along.
struct BIOSWordmarkShape: Shape {
    static let viewBox = CGSize(width: 234, height: 82)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        // B: stem, lower bowl, then upper bowl.
        p.move(to: pt(22, 17))
        p.addLine(to: pt(22, 63))
        p.addLine(to: pt(36, 63))
        p.addCurve(to: pt(37, 40), control1: pt(54, 63), control2: pt(56, 40))
        p.addLine(to: pt(22, 40))
        p.move(to: pt(22, 17))
        p.addLine(to: pt(35, 17))
        p.addCurve(to: pt(37, 40), control1: pt(51, 17), control2: pt(53, 40))

        // I
        p.move(to: pt(82, 17))
        p.addLine(to: pt(82, 63))

        // O: ellipse cx 133, cy 40, rx 21, ry 24.
        p.addEllipse(in: CGRect(x: 112, y: 16, width: 42, height: 48))

        // S
        p.move(to: pt(210, 22))
        p.addCurve(to: pt(180, 22), control1: pt(203, 15), control2: pt(187, 14))
        p.addCurve(to: pt(195, 41), control1: pt(171, 34), control2: pt(185, 39))
        p.addCurve(to: pt(198, 64), control1: pt(217, 46), control2: pt(214, 62))
        p.addCurve(to: pt(176, 58), control1: pt(189, 66), control2: pt(180, 62))

        let s = Self.scale(for: rect.size)
        let dx = rect.minX + (rect.width - Self.viewBox.width * s) / 2
        let dy = rect.minY + (rect.height - Self.viewBox.height * s) / 2
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy))
    }

    static func scale(for size: CGSize) -> CGFloat {
        min(size.width / viewBox.width, size.height / viewBox.height)
    }
}

/// Stroked wordmark "BIOS" (round caps and joins, like the SVG). Give it a
/// width; the height follows the 234:82 viewBox.
struct BIOSWordmark: View {
    var color: Color = BIOSBrand.cream

    var body: some View {
        GeometryReader { geo in
            BIOSWordmarkShape()
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: 3.4 * BIOSWordmarkShape.scale(for: geo.size),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .aspectRatio(BIOSWordmarkShape.viewBox.width / BIOSWordmarkShape.viewBox.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("BIOS")
    }
}

/// Cold start splash, replicating docs/brand preview: the mark rises softly
/// (0.9 s, cubic-bezier(.2,.65,.2,1), from 7 pt lower at 94 % scale), the
/// wordmark fades in 0.28 s later and the tagline 0.4 s later (0.7 s each,
/// CSS "ease"). About 1.7 s in total, then `onFinish`. With Reduce Motion
/// everything is static and the splash hands over after about 0.5 s.
/// Purely visual: the TabView underneath loads its data in parallel.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markIn = false
    @State private var wordIn = false
    @State private var taglineIn = false
    @State private var finished = false

    /// Icon square the mark is laid out in (preview: 240 px tile, 130 px wordmark).
    private let tile: CGFloat = 240
    private let wordmarkWidth: CGFloat = 130

    var body: some View {
        ZStack {
            BIOSBrand.green
                .ignoresSafeArea()

            VStack(spacing: 2) {
                BIOSMarkImage(tile: tile)
                    .frame(width: tile, height: tile)
                    .opacity(markIn ? 1 : 0)
                    .scaleEffect(markIn ? 1 : 0.94)
                    .offset(y: markIn ? 0 : 7)

                BIOSWordmark()
                    .frame(width: wordmarkWidth)
                    .opacity(wordIn ? 1 : 0)
                    .offset(y: wordIn ? 0 : 4)
            }

            VStack {
                Spacer()
                Text(verbatim: BIOSBrand.tagline)
                    .font(.system(size: 13, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(BIOSBrand.caption)
                    .opacity(taglineIn ? 1 : 0)
                    .offset(y: taglineIn ? 0 : 4)
                    .padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BIOS. \(BIOSBrand.tagline)")
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await run() }
    }

    private func run() async {
        if reduceMotion {
            markIn = true
            wordIn = true
            taglineIn = true
            try? await Task.sleep(for: .milliseconds(500))
        } else {
            withAnimation(.timingCurve(0.2, 0.65, 0.2, 1, duration: 0.9)) {
                markIn = true
            }
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.7).delay(0.28)) {
                wordIn = true
            }
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.7).delay(0.4)) {
                taglineIn = true
            }
            // Animations end at 1.1 s; short hold, then the 0.35 s fade out.
            try? await Task.sleep(for: .milliseconds(1_350))
        }
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }
}

/// Hosts the app content with the splash on top until it has finished.
/// The content is built right away, so its `.task` loads start immediately.
struct SplashContainer<Content: View>: View {
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.35)) {
                        showSplash = false
                    }
                }
                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 1.04)))
                .zIndex(1)
            }
        }
    }
}

#Preview("Splash") {
    SplashView {}
}

/// "Über" row in Mehr: the app icon in miniature, wordmark and tagline.
struct BrandRow: View {
    private let tile: CGFloat = 44

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
                    .fill(BIOSBrand.green)
                BIOSMarkImage(tile: tile)
            }
            .frame(width: tile, height: tile)

            VStack(alignment: .leading, spacing: 4) {
                BIOSWordmark()
                    .frame(width: 68)
                    // The viewBox has side bearings; align the glyphs, not the box.
                    .padding(.leading, -68 * 20 / 234)
                Text(verbatim: BIOSBrand.tagline)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BIOS. \(BIOSBrand.tagline)")
    }
}
