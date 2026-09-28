import Foundation

/// The five root tabs.
enum AppTab: String, CaseIterable, Hashable {
    case heute
    case koerper
    case umwelt
    case labor
    case mehr

    var title: String {
        switch self {
        case .heute: return "Heute"
        case .koerper: return "Körper"
        case .umwelt: return "Umwelt"
        case .labor: return "Labor"
        case .mehr: return "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .heute: return "smallcircle.filled.circle"
        case .koerper: return "waveform.path.ecg"
        case .umwelt: return "leaf"
        case .labor: return "testtube.2"
        case .mehr: return "ellipsis.circle"
        }
    }

    /// Value of `bios.tab` in a push payload ("heute", "koerper"/"körper", ...).
    init?(pushValue: String) {
        let value = pushValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "ö", with: "oe")
        switch value {
        case "heute", "today", "home": self = .heute
        case "koerper", "body": self = .koerper
        case "umwelt", "environment", "outlook": self = .umwelt
        case "labor", "labs", "lab", "befunde": self = .labor
        case "mehr", "more", "settings", "system": self = .mehr
        default: return nil
        }
    }
}

/// Screens of the Labor tab (own NavigationStack path).
enum LabRoute: Hashable {
    /// Marker detail (`GET /v1/labs/markers/{id}`).
    case marker(String)
    /// One document: review screen while `zu_pruefen`, else view and edit.
    case document(String)
    /// All documents waiting for a review (push `LAB_REVIEW`, Heute card).
    case reviewList

    /// `bios.detail` values that open the review list.
    static func isReviewDetail(_ raw: String?) -> Bool {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "labor_pruefen" || value == "labs_review" || value == "lab_review"
    }
}

/// Detail screens, pushed onto the NavigationStack of the current tab.
enum DetailRoute: String, CaseIterable, Hashable {
    case gesundheit
    case infekt
    case viren
    case pollen
    case glukose
    case recovery
    case insulin
    case loop
    case alkohol
    case blutdruck

    var title: String {
        switch self {
        case .gesundheit: return "Gesundheits-Score"
        case .alkohol: return "Alkohol-Tage"
        case .blutdruck: return "Blutdruck"
        case .infekt: return "Infekt-Check"
        case .viren: return "Viren im Abwasser"
        case .pollen: return "Pollen"
        case .glukose: return "Glukose"
        case .recovery: return "Recovery und Schlaf"
        case .insulin: return "Insulin"
        case .loop: return "Loop"
        }
    }

    /// Tab a detail belongs to when a push names only the detail.
    var homeTab: AppTab {
        switch self {
        case .viren, .pollen: return .umwelt
        case .alkohol: return .mehr
        default: return .heute
        }
    }

    /// Value of `bios.detail` in a push payload (German ids, English aliases).
    init?(pushValue: String) {
        let value = pushValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "gesundheit", "health", "health_score", "score": self = .gesundheit
        case "infekt", "infection", "whoop", "whoop_check": self = .infekt
        case "viren", "viruses", "virus", "wastewater", "abwasser": self = .viren
        case "pollen", "allergy", "allergie": self = .pollen
        case "glukose", "glucose": self = .glukose
        case "recovery", "schlaf", "sleep": self = .recovery
        case "insulin": self = .insulin
        case "loop", "nightscout": self = .loop
        case "alkohol", "alcohol", "events", "kalender": self = .alkohol
        case "blutdruck", "blood_pressure", "bp": self = .blutdruck
        default: return nil
        }
    }
}

/// Selected tab and the navigation path of every tab. Deep links from a
/// tapped push land here (`open(_:)`).
@MainActor
final class Router: ObservableObject {
    static let shared = Router()

    @Published var selectedTab: AppTab = .heute
    @Published var heutePath: [DetailRoute] = []
    @Published var koerperPath: [DetailRoute] = []
    @Published var umweltPath: [DetailRoute] = []
    @Published var mehrPath: [DetailRoute] = []
    @Published var laborPath: [LabRoute] = []
    /// Body map region to open once the Körper tab shows the systems map
    /// (neutral link from a lab marker; consumed by the body map).
    @Published var bodyMapFocus: String?

    init() {}

    /// Switches to `tab` and shows `detail` on top of its root (or the root only).
    func show(_ tab: AppTab, detail: DetailRoute? = nil) {
        let path = detail.map { [$0] } ?? []
        switch tab {
        case .heute: heutePath = path
        case .koerper: koerperPath = path
        case .umwelt: umweltPath = path
        case .labor: laborPath = []
        case .mehr: mehrPath = path
        }
        selectedTab = tab
    }

    /// Labor tab with an optional screen on top of its root.
    func showLabor(_ route: LabRoute? = nil) {
        laborPath = route.map { [$0] } ?? []
        selectedTab = .labor
    }

    /// Körper tab with the systems map, the region's sheet opens on top.
    func showBodyMapRegion(_ regionID: String) {
        show(.koerper)
        bodyMapFocus = regionID
    }

    func open(_ push: PushInfo) {
        if Router.isLabPush(tab: push.biosTab, detail: push.biosDetail, threadID: push.threadID,
                            category: push.category) {
            let review = LabRoute.isReviewDetail(push.biosDetail) || push.category == "LAB_REVIEW"
            showLabor(review ? .reviewList : nil)
            return
        }
        let target = Router.target(
            tab: push.biosTab,
            detail: push.biosDetail,
            threadID: push.threadID,
            category: push.category
        )
        show(target.tab, detail: target.detail)
    }

    /// A push of the Labor tab: `bios.tab` "labor", `bios.detail` "labor_pruefen",
    /// thread "labs" or category `LAB_REVIEW`.
    nonisolated static func isLabPush(tab: String?, detail: String?, threadID: String, category: String) -> Bool {
        if let tab, AppTab(pushValue: tab) == .labor { return true }
        if tab == nil && LabRoute.isReviewDetail(detail) { return true }
        if tab == nil && detail == nil {
            return threadID.lowercased() == "labs" || category.hasPrefix("LAB_")
        }
        return false
    }

    /// Routing rule for a push: `bios.tab` (+ optional `bios.detail`) first,
    /// then `bios.detail` alone, then the APNs `thread-id`
    /// (whoop -> Heute + Infekt-Check, outlook -> Umwelt, system -> Mehr),
    /// then the category prefix, else Heute.
    nonisolated static func target(tab: String?, detail: String?, threadID: String, category: String)
        -> (tab: AppTab, detail: DetailRoute?) {
        let route = detail.flatMap { DetailRoute(pushValue: $0) }
        if let tab = tab.flatMap({ AppTab(pushValue: $0) }) {
            return (tab, route)
        }
        if let route {
            return (route.homeTab, route)
        }
        switch threadID.lowercased() {
        case "whoop": return (.heute, .infekt)
        case "outlook": return (.umwelt, nil)
        case "system": return (.mehr, nil)
        default: break
        }
        if category.hasPrefix("WHOOP") { return (.heute, .infekt) }
        if category.hasPrefix("OUTLOOK") { return (.umwelt, nil) }
        return (.heute, nil)
    }
}
