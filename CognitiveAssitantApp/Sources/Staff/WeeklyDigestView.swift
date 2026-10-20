import SwiftData
import SwiftUI

/// 16 Weekly change digest · Weekly digest
///
/// 'Good news' and 'requests' sit side by side in the same list so it isn't all warnings.
///
/// **Built from records.** Until 2026-09-10 three items were hard-coded as constants —
/// even in a week where nothing happened, "recall rate down 8 weeks" was showing. Now `ReportData.notes`
/// extracts from real records, and **if there's nothing to extract, no rows appear.**
struct WeeklyDigestView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Elder.name) private var elders: [Elder]

    private static let weeks = 8

    /// Number of rows that fit on one screen. **Overflow gets cut off at the bottom and can't be seen** —
    /// if the cut row happens to be an important change, it's as good as missing.
    private static let maxRows = 4

    private var notes: [ReportData.Note] {
        ReportData.merged(rawNotes)
    }

    private var rawNotes: [ReportData.Note] {
        let calendar = Calendar.current
        return elders.flatMap { elder -> [ReportData.Note] in
            let samples = elder.sessions.flatMap(\.metrics)
            func points(_ key: Metric.Key) -> [ReportData.WeekPoint] {
                ReportData.weekly(
                    samples: samples.filter { $0.key == key.rawValue }
                        .map { (at: $0.at, percent: $0.percent) },
                    weeks: Self.weeks)
            }
            // Topics whose answers changed this week.
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .distantPast
            let drifted = elder.facts
                .filter { fact in fact.revisions.contains(where: { $0.at >= weekStart }) }
                .map(\.subject)

            let lastSession = elder.sessions.map(\.startedAt).max()
            let daysSince = lastSession.map {
                calendar.dateComponents([.day], from: $0, to: .now).day ?? 0
            }

            return ReportData.notes(
                name: elder.name,
                recall: points(.recall),
                speech: points(.speech),
                driftedFacts: drifted,
                needsAddress: elder.honorific == nil && !elder.invitedFirstName,
                daysSinceLastSession: daysSince)
        }
    }

    private var weekLabel: String {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? .now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("This week · \(weekLabel)")
                .font(.kr(36, .bold))
                .foregroundStyle(Theme.ink)

            if notes.isEmpty {
                emptyState
            } else {
                ForEach(notes.prefix(Self.maxRows)) { note in
                    row(note)
                }
                if notes.count > Self.maxRows {
                    Text("+ \(notes.count - Self.maxRows) more this week")
                        .font(.kr(19))
                        .foregroundStyle(Theme.gray6B)
                        .padding(.leading, 30)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .topLeading)
        .background(Theme.staffPaper)
    }

    /// **If there's nothing to report, it says so.** Better than a blank screen, and far better than made-up items.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing to flag this week")
                .font(.kr(30, .bold))
                .foregroundStyle(Theme.ink)
            Text("This list is built from what the sessions recorded. "
                 + "An empty week means no measured change crossed the line — "
                 + "not that nobody was seen.")
                .font(.kr(21))
                .cssLineHeight(1.6, 21)
                .foregroundStyle(Theme.gray4A)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        )
    }

    private func label(_ kind: ReportData.Note.Kind) -> (String, Color) {
        switch kind {
        case .followUp: ("Follow up", Theme.red)
        case .good:     ("Good news", Theme.blue)
        case .ask:      ("Please help", Theme.gray6B)
        }
    }

    private func accent(_ kind: ReportData.Note.Kind) -> Color {
        switch kind {
        case .followUp: Theme.red
        case .good:     Theme.blue
        case .ask:      Theme.gray8A
        }
    }

    private func row(_ note: ReportData.Note) -> some View {
        let (title, color) = label(note.kind)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.kr(20, .semibold))
                .letterSpacing(0.06, 20)
                .foregroundStyle(color)
            Text(note.title)
                .font(.kr(30, .bold))
                .foregroundStyle(Theme.ink)
            Text(note.body)
                .font(.kr(21))
                .cssLineHeight(1.6, 21)
                .foregroundStyle(Theme.gray4A)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(.white)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 16, topTrailingRadius: 16,
                                          style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle().fill(accent(note.kind)).frame(width: 8)
        }
    }
}
