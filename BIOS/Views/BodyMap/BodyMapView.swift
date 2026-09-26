import SwiftUI

// Körperkarte (N3c): figure with a soft glow per status, symbol badges, tap on
// a region opens a sheet with its values and links to the existing details;
// below the figure an accessible region list. Heute shows a small card from
// the dashboard block `bodymap`. Geometry: BodyMapShapes.swift, colors and
// texts: BodyMapStyle.swift. Observation, no diagnosis.

// MARK: - Figure

/// The figure of one view. Without `onSelect` it is decorative (Heute card).
struct BodyMapFigure: View {
    let regions: [BodyMapRegion]
    let side: BodyMapSide
    var height: CGFloat = BodyMapStyle.largeHeight
    var showsBadges = true
    var selectedID: String?
    var onSelect: ((BodyMapRegion) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize {
        CGSize(width: height * BodyMapLayout.aspect, height: height)
    }

    private var visible: [BodyMapRegion] {
        regions.filter { $0.side == side && !$0.shapes.isEmpty }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            glowLayer
            BodyOutlineShape()
                .fill(BodyMapStyle.line.opacity(BodyMapStyle.outlineFillOpacity))
            BodyOutlineShape()
                .stroke(BodyMapStyle.line.opacity(BodyMapStyle.outlineOpacity),
                        style: StrokeStyle(lineWidth: showsBadges ? 1.25 : 1, lineCap: .round, lineJoin: .round))
            if showsBadges {
                BodyDetailShape(side: side)
                    .stroke(BodyMapStyle.line.opacity(BodyMapStyle.detailOpacity),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
            ForEach(visible) { region in
                regionShapes(region)
            }
            if showsBadges {
                ForEach(visible) { region in
                    if let badge = region.badge {
                        BodyMapBadge(status: region.status, selected: region.id == selectedID)
                            .position(x: badge.x * size.width, y: badge.y * size.height)
                    }
                }
            }
            if let onSelect {
                ForEach(visible) { region in
                    hitButton(region, onSelect: onSelect)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .padding(showsBadges ? 14 : 4)
    }

    // Blurred glow under the outline; auffällig breathes slowly (not with Reduce Motion).
    private var glowLayer: some View {
        ZStack(alignment: .topLeading) {
            ForEach(visible) { region in
                if let opacity = region.status.glowOpacity {
                    if region.status == .auffaellig && !reduceMotion {
                        glow(region, opacity: opacity)
                            .phaseAnimator([0.75, 1.0]) { content, phase in
                                content.opacity(phase)
                            } animation: { _ in
                                .easeInOut(duration: 1.4)
                            }
                    } else {
                        glow(region, opacity: opacity)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .blur(radius: height / 400 * (showsBadges ? 5 : 7))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ region: BodyMapRegion, opacity: Double) -> some View {
        let color = region.status.color
        return ZStack(alignment: .topLeading) {
            ForEach(Array(region.shapes.enumerated()), id: \.offset) { _, shape in
                let rect = shape.rect(in: size, scale: BodyMapStyle.glowScale)
                Ellipse()
                    .fill(EllipticalGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // Soft fill and fine stroke; keine Daten grey and dashed.
    private func regionShapes(_ region: BodyMapRegion) -> some View {
        let noData = region.status == .keineDaten
        let color = region.status.color
        return ZStack {
            BodyRegionShape(shapes: region.shapes)
                .fill(noData ? BodyMapStyle.noDataFill : color.opacity(BodyMapStyle.regionFillOpacity))
            BodyRegionShape(shapes: region.shapes)
                .stroke(color.opacity(noData ? BodyMapStyle.noDataStrokeOpacity : BodyMapStyle.regionStrokeOpacity),
                        style: StrokeStyle(lineWidth: 1, dash: noData ? BodyMapStyle.noDataDash : []))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Invisible button over the region (ellipses with a minimum size plus the badge).
    private func hitButton(_ region: BodyMapRegion, onSelect: @escaping (BodyMapRegion) -> Void) -> some View {
        let area = BodyRegionHitArea(shapes: region.shapes, badge: showsBadges ? region.badge : nil, figure: size)
        let box = area.box
        return Button {
            onSelect(region)
        } label: {
            Color.clear
                .frame(width: box.width, height: box.height)
                .contentShape(area.shape)
        }
        .buttonStyle(.plain)
        .position(x: box.midX, y: box.midY)
        .accessibilityLabel(region.spokenLabel)
        .accessibilityHint(BodyMapStyle.openHint)
        .accessibilityAddTraits(region.id == selectedID ? .isSelected : [])
    }
}

/// Round badge on the figure: dark disc, colored ring, symbol (dashed for keine Daten).
struct BodyMapBadge: View {
    let status: BodyMapStatus
    var selected = false

    var body: some View {
        ZStack {
            Circle().fill(BodyMapStyle.badgeFill)
            Circle()
                .strokeBorder(status.color, style: StrokeStyle(
                    lineWidth: selected ? BodyMapStyle.badgeSelectedLineWidth : BodyMapStyle.badgeLineWidth,
                    dash: status == .keineDaten ? [2.5, 2] : []
                ))
            Image(systemName: status.badgeSymbol)
                .font(.system(size: 9, weight: status == .auffaellig ? .black : .bold))
                .foregroundStyle(status.color)
        }
        .frame(width: BodyMapStyle.badgeDiameter, height: BodyMapStyle.badgeDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Status symbol in a tinted circle (list rows, sheet header).
struct BodyMapStatusBadge: View {
    let status: BodyMapStatus
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            if let background = status.background {
                Circle().fill(background)
            } else {
                Circle().strokeBorder(BIOSTheme.text3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            }
            Image(systemName: status.badgeSymbol)
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(status.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Körper tab

/// Top of the Körper tab: map card with front/back toggle, legend, region
/// list; tap opens the region sheet. Observes only the body map store.
struct BodyMapSection: View {
    @ObservedObject private var store = BodyMapStore.shared
    @EnvironmentObject private var router: Router
    @State private var side: BodyMapSide = .front
    @State private var selected: BodyMapRegion?
    @State private var pendingRoute: DetailRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model = store.model {
                mapCard(model)
                SectionHeader(title: BodyMapStyle.listTitle)
                regionList(model)
            } else if store.isUnavailable {
                NotEvaluableBox(title: BodyMapStyle.unavailableTitle, text: BodyMapStyle.unavailableText)
            } else if store.isLoading || store.lastError == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(BodyMapStyle.loading)
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text2)
                }
                .biosCard()
            } else {
                NotEvaluableBox(title: BodyMapStyle.noDataTitle, text: store.lastError)
            }
        }
        .sheet(item: $selected, onDismiss: {
            if let route = pendingRoute {
                pendingRoute = nil
                router.koerperPath.append(route)
            }
        }) { region in
            BodyMapRegionSheet(region: region) { route in
                pendingRoute = route
                selected = nil
            }
            .environment(\.locale, BIOSFormat.locale)
        }
        .task {
            await store.refresh()
        }
    }

    private func open(_ region: BodyMapRegion) {
        if region.side != side, !region.shapes.isEmpty {
            side = region.side
        }
        selected = region
    }

    private func mapCard(_ model: BodyMapModel) -> some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    cardTitle
                    Spacer(minLength: 8)
                    sidePicker.frame(width: 170)
                }
                VStack(alignment: .leading, spacing: 8) {
                    cardTitle
                    sidePicker
                }
            }
            BodyMapFigure(regions: model.regions, side: side, selectedID: selected?.id) { region in
                open(region)
            }
            .frame(maxWidth: .infinity)
            .background(
                RadialGradient(colors: [BodyMapStyle.line.opacity(BodyMapStyle.stageGlowOpacity), .clear],
                               center: .center, startRadius: 0, endRadius: BodyMapStyle.largeHeight * 0.55)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(BodyMapStyle.title), \(BodyMapStyle.sideSpoken(side))")
            legend
            Text(BodyMapStyle.sideNote(side))
                .font(.caption)
                .foregroundStyle(BIOSTheme.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if !model.errors.isEmpty {
                Text("\(BodyMapStyle.partialErrors): \(model.errors.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(standText(model))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text3)
                .frame(maxWidth: .infinity)
        }
        .biosCard()
    }

    private var cardTitle: some View {
        Text(BodyMapStyle.title)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private var sidePicker: some View {
        Picker("Ansicht", selection: $side) {
            ForEach(BodyMapSide.allCases, id: \.self) { side in
                Text(BodyMapStyle.sideTitle(side)).tag(side)
            }
        }
        .pickerStyle(.segmented)
    }

    private var legend: some View {
        FlowLayout(spacing: 14, lineSpacing: 6) {
            ForEach(BodyMapStatus.allCases, id: \.self) { status in
                HStack(spacing: 5) {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.color)
                    Text(status.label)
                        .foregroundStyle(BIOSTheme.text2)
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func standText(_ model: BodyMapModel) -> String {
        let stand = model.generatedAt ?? store.fetchedAt
        var parts: [String] = []
        if let stand {
            let when = Calendar.current.isDateInToday(stand) ? BIOSFormat.time(stand) : BIOSFormat.relative(stand)
            parts.append("Stand \(when)")
        }
        if store.showsStaleData {
            parts.append(store.isOffline ? "offline" : "nicht aktualisiert")
        }
        parts.append(model.note)
        return parts.joined(separator: " · ")
    }

    private func regionList(_ model: BodyMapModel) -> some View {
        let regions = model.sortedRegions
        return VStack(spacing: 0) {
            ForEach(Array(regions.enumerated()), id: \.element.id) { index, region in
                if index > 0 {
                    Rectangle()
                        .fill(BIOSTheme.separator)
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }
                BodyMapRegionRow(region: region) {
                    open(region)
                }
            }
        }
        .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// One row of the region list: badge, label, status word and reason.
struct BodyMapRegionRow: View {
    let region: BodyMapRegion
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BodyMapStatusBadge(status: region.status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(region.label)
                        .font(.body.weight(.medium))
                        .foregroundStyle(region.neutral ? BIOSTheme.text2 : BIOSTheme.text1)
                    (Text(region.statusLabel).bold().foregroundStyle(region.status.color)
                        + Text(" · " + region.reason).foregroundStyle(BIOSTheme.text2))
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(region.spokenLabel)
        .accessibilityHint(BodyMapStyle.openHint)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Region sheet

/// Sheet of one region: status with reason, values, buttons to the details.
/// Text styles only, so it follows Dynamic Type.
struct BodyMapRegionSheet: View {
    let region: BodyMapRegion
    let onLink: (DetailRoute) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BodyMapStatusBadge(status: region.status, size: 30)
                    Text(region.label)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(BodyMapStyle.doneButton) {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(BIOSTheme.text1)
                }

                statusBox

                if region.metrics.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: BodyMapStatus.keineDaten.symbol)
                            .foregroundStyle(BIOSTheme.text2)
                        Text(region.neutral ? BodyMapStyle.neutralText : BodyMapStyle.noMetricsText)
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .accessibilityElement(children: .combine)
                } else {
                    sectionLabel(BodyMapStyle.valuesTitle)
                    VStack(spacing: 0) {
                        ForEach(Array(region.metrics.enumerated()), id: \.element.id) { index, metric in
                            if index > 0 {
                                Rectangle()
                                    .fill(BIOSTheme.separator)
                                    .frame(height: 0.5)
                                    .padding(.leading, 14)
                            }
                            BodyMapMetricRow(metric: metric)
                        }
                    }
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if !region.links.isEmpty {
                    sectionLabel(BodyMapStyle.detailsTitle)
                    VStack(spacing: 8) {
                        ForEach(region.links) { link in
                            Button {
                                onLink(link.route)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(link.label)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right")
                                }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BIOSTheme.accent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(BIOSTheme.accent.opacity(0.13),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Öffnet \(link.route.title)")
                        }
                    }
                }

                Text(BodyMapStyle.note)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(region.statusLabel)
                .font(.headline)
                .foregroundStyle(region.status.textColor)
            Text(region.reason)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(region.status.background ?? Color.clear,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(region.status.background == nil ? 0.2 : 0), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(BIOSTheme.text2)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Metric row: label, value with unit and status symbol, the server text below.
/// At accessibility text sizes the value moves under the label.
struct BodyMapMetricRow: View {
    let metric: BodyMapMetric

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if typeSize.isAccessibilitySize {
                label
                HStack(spacing: 8) {
                    value
                    symbol
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    label
                    Spacer(minLength: 8)
                    value
                    symbol
                }
            }
            if let detail = metric.detailText {
                Text(detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.spokenLabel)
    }

    private var label: some View {
        Text(metric.label)
            .font(.subheadline)
            .foregroundStyle(BIOSTheme.text1)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var value: some View {
        if let text = metric.valueText {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text1)
        } else if metric.status == .keineDaten {
            Text(BodyMapStatus.keineDaten.label)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text3)
        }
    }

    private var symbol: some View {
        Image(systemName: metric.status.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(metric.status.color)
    }
}

// MARK: - Heute card

/// Small card on Heute under the Gesundheits-Score: mini figure, counts
/// "n beobachten · n auffällig" and the top reason; tap opens the Körper tab.
struct BodyMapTodayCard: View {
    let summary: BodyMapSummaryModel

    @ObservedObject private var store = BodyMapStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        Button {
            router.show(.koerper)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                BodyMapFigure(regions: figureRegions, side: .front, height: BodyMapStyle.miniHeight, showsBadges: false)
                    .frame(width: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(BodyMapStyle.title)
                        .font(.headline)
                        .foregroundStyle(BIOSTheme.text1)
                    counts
                    if let line = topLine {
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
            }
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(BodyMapStyle.title): \(summary.counts.spoken)." + (topLine.map { " \($0)" } ?? ""))
        .accessibilityHint(BodyMapStyle.todayHint)
        .accessibilityAddTraits(.isButton)
    }

    /// Regions of the loaded map; without one the bundled layout with only the top region colored.
    private var figureRegions: [BodyMapRegion] {
        if let regions = store.model?.regions, !regions.isEmpty {
            return regions
        }
        let top = summary.top
        return BodyMapLayout.regions.map { layout -> BodyMapRegion in
            if let top, top.id == layout.id {
                return BodyMapRegion(layout: layout, status: top.status, reason: top.reason)
            }
            return BodyMapRegion(layout: layout, status: .keineDaten)
        }
    }

    @ViewBuilder private var counts: some View {
        let tally = summary.counts
        HStack(spacing: 8) {
            if tally.attention == 0 {
                if tally.ok > 0 {
                    countItem(BodyMapStyle.allOk, color: BodyMapStatus.ok.color)
                } else {
                    countItem(summary.text, color: BodyMapStatus.keineDaten.color)
                }
            } else {
                if tally.beobachten > 0 {
                    countItem("\(tally.beobachten) beobachten", color: BodyMapStatus.beobachten.color)
                }
                if tally.beobachten > 0 && tally.auffaellig > 0 {
                    Text("·").foregroundStyle(BIOSTheme.text3)
                }
                if tally.auffaellig > 0 {
                    countItem("\(tally.auffaellig) auffällig", color: BodyMapStatus.auffaellig.color)
                }
            }
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }

    private func countItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .foregroundStyle(BIOSTheme.text1)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private var topLine: String? {
        if let top = summary.top, top.status == .beobachten || top.status == .auffaellig {
            return top.reason.map { "\(top.label): \($0)" } ?? top.label
        }
        let counts = summary.counts
        if counts.ok > 0 {
            return "\(counts.ok) Regionen im Rahmen, \(counts.keineDaten) noch ohne Daten"
        }
        return nil
    }
}
