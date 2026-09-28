import SwiftUI

/// Small Labor card on Heute, only when `dashboard.labs` has documents to
/// review or due items (`faellig`/`bald`). Tap opens the Labor tab (the review
/// list when something waits for a review).
struct LabTodayCard: View {
    let labs: DashboardLabsModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "testtube.2")
                    .font(.body)
                    .foregroundStyle(labs.reviewDocuments > 0 ? BIOSTheme.contextText : BIOSTheme.text2)
                    .frame(width: 34, height: 34)
                    .background((labs.reviewDocuments > 0 ? BIOSTheme.context : Color.white).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: "Labor")
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text1)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text3)
                    .frame(maxHeight: .infinity)
            }
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Labor: " + lines.joined(separator: ". "))
        .accessibilityHint("Öffnet den Tab Labor")
    }

    private var lines: [String] {
        var result: [String] = []
        if labs.reviewDocuments > 0 {
            result.append(labs.reviewDocuments == 1 ? "1 Befund zu prüfen" : "\(labs.reviewDocuments) Befunde zu prüfen")
        }
        let open = labs.openDue
        let due = open.filter { $0.status == "faellig" }.map(\.label)
        let soon = open.filter { $0.status == "bald" }
        if !due.isEmpty {
            result.append("Fällig: " + due.joined(separator: ", "))
        }
        if !soon.isEmpty {
            let parts = soon.map { item -> String in
                if let date = BIOSDate.day(item.dueOn) {
                    return "\(item.label) (\(BIOSFormat.shortDate(date)))"
                }
                return item.label
            }
            result.append("Bald fällig: " + parts.joined(separator: ", "))
        }
        return result
    }
}
