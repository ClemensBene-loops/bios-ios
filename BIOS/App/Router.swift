import Foundation

/// The four root tabs.
enum AppTab: String, CaseIterable, Hashable {
    case heute
    case koerper
    case umwelt
    case mehr

    var title: String {
        switch self {
        case .heute: return "Heute"
        case .koerper: return "Körper"
        case .umwelt: return "Umwelt"
        case .mehr: return "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .heute: return "smallcircle.filled.circle"
        case .koerper: return "waveform.path.ecg"
        case .umwelt: return "leaf"
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
        case "mehr", "more", "settings", "system": self = .mehr
        default: return nil
        }
    }
}

/// Detail screens, pushed onto the NavigationStack of the current tab.
enum DetailRoute: String, CaseIterable, Hashable {
    case infekt
    case viren
    case pollen
    case glukose
    case recovery
    case insulin
    case loop
    case alkohol

    var title: String {
        switch self {
        case .alkohol: return "Alkohol-Tage"
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
        case "infekt", "infection", "whoop", "whoop_check": self = .infekt
        case "viren", "viruses", "virus", "wastewater", "abwasser": self = .viren
        case "pollen", "allergy", "allergie": self = .pollen
        case "glukose", "glucose": self = .glukose
        case "recovery", "schlaf", "sleep": self = .recovery
        case "insulin": self = .insulin
        case "loop", "nightscout": self = .loop
        case "alkohol", "alcohol", "events", "kalender": self = .alkohol
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

    init() {}

    /// Switches to `tab` and shows `detail` on top of its root (or the root only).
    func show(_ tab: AppTab, detail: DetailRoute? = nil) {
        let path = detail.map { [$0] } ?? []
        switch tab {
        case .heute: heutePath = path
        case .koerper: koerperPath = path
        case .umwelt: umweltPath = path
        case .mehr: mehrPath = path
        }
        selectedTab = tab
    }

    func open(_ push: PushInfo) {
        let target = Router.target(
            tab: push.biosTab,
            detail: push.biosDetail,
            threadID: push.threadID,
            category: push.category
        )
        show(target.tab, detail: target.detail)
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
