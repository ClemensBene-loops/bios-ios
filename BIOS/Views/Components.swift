import SwiftUI
import UIKit

/// Row ids used to scroll to a section when a push is tapped.
enum SectionID {
    static let whoop = "section-whoop"
    static let outlook = "section-outlook"

    /// Target section for a tapped push (thread-id first, category as fallback).
    static func forPush(_ push: PushInfo) -> String {
        if push.threadID == "outlook" || push.category.hasPrefix("OUTLOOK") {
            return outlook
        }
        return whoop
    }
}

extension OverallStatus {
    var symbol: String {
        switch self {
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .ok: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .warn: return .red
        case .info: return .orange
        case .ok: return .green
        case .unknown: return .secondary
        }
    }
}

extension AlertSeverity {
    var symbol: String {
        switch self {
        case .warn: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .other: return "circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .warn: return .red
        case .info: return .orange
        case .other: return .secondary
        }
    }
}

enum LevelColor {
    /// Wastewater level: "sehr niedrig" ... "sehr hoch".
    static func virus(_ level: String) -> Color {
        switch level {
        case "sehr niedrig", "niedrig": return .green
        case "mittel": return .orange
        case "hoch", "sehr hoch": return .red
        default: return .secondary
        }
    }

    /// Pollen level: "keine", "niedrig", "mittel", "hoch".
    static func pollen(_ level: String) -> Color {
        switch level {
        case "niedrig": return .green
        case "mittel": return .orange
        case "hoch": return .red
        default: return .secondary
        }
    }
}

/// First row of a content section: big status symbol, verdict, date line.
struct SectionStatusRow: View {
    let status: OverallStatus
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.symbol)
                .font(.title2)
                .foregroundStyle(status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Row background that briefly lights up after a push tap.
struct HighlightBackground: View {
    let isOn: Bool

    var body: some View {
        Color(uiColor: .secondarySystemGroupedBackground)
            .overlay(Color.accentColor.opacity(isOn ? 0.18 : 0))
    }
}

struct AlertRow: View {
    let alert: AlertItem

    var body: some View {
        Label {
            Text(alert.text)
                .font(.subheadline)
        } icon: {
            Image(systemName: alert.severity.symbol)
                .foregroundStyle(alert.severity.tint)
        }
    }
}

struct ErrorRow: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "exclamationmark.bubble")
                .foregroundStyle(Color.orange)
        }
    }
}

/// The server's ready-made German text, collapsed by default.
struct FullTextDisclosure: View {
    let text: String

    var body: some View {
        DisclosureGroup("Volltext") {
            Text(text)
                .font(.footnote)
                .textSelection(.enabled)
        }
    }
}

/// "Stand" of the shown data, loading indicator and the last refresh error.
struct FreshnessRow: View {
    let fetchedAt: Date?
    let isLoading: Bool
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(standText, systemImage: "clock")
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView()
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let error {
                Label(errorText(error), systemImage: "wifi.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    private var standText: String {
        if let fetchedAt {
            return "Stand: \(BIOSFormat.timestamp(fetchedAt))"
        }
        return isLoading ? "Wird geladen ..." : "Noch nicht geladen"
    }

    private func errorText(_ error: String) -> String {
        fetchedAt == nil ? error : "\(error). Zeige gespeicherten Stand."
    }
}
