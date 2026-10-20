import SwiftData
import SwiftUI

/// 15 Personal cognitive report · Cognitive report
///
/// It doesn't diagnose. It shows only the 'changes' over the last 8 weeks and recommends a consultation.
///
/// **Reads from the memory store.** Until 2026-09-10 this screen was a picture with Dorothy Miller's values
/// hard-coded — seat someone else and the same bars appeared. Now it folds the `MetricSample`s left when
/// sessions close into weeks and draws them.
struct CognitiveReportView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Elder.name) private var elders: [Elder]

    /// Whose report it is. If not specified, **the person who most recently had a session**.
    var subject: Elder?

    /// The period viewed. 8 weeks isn't swamped by seasonal variation and is still a span people can remember.
    private static let weeks = 8

    private let columns = [GridItem(.flexible(), spacing: 20)]

    private var elder: Elder? {
        subject ?? elders
            .filter { !$0.sessions.isEmpty }
            .max(by: { ($0.sessions.map(\.startedAt).max() ?? .distantPast)
                     < ($1.sessions.map(\.startedAt).max() ?? .distantPast) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let elder {
                Text("\(elder.name) · \(Self.weeks)-week trend")
                    .font(.kr(36, .bold))
                    .foregroundStyle(Theme.ink)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    recallCard(for: elder)
                    consistencyCard(for: elder)
                    speechCard(for: elder)
                    moodCard
                }
                closingNote(for: elder)
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 40)
        .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .topLeading)
        .background(Theme.staffPaper)
    }

    /// **With no sessions at all, no graph is drawn.** Even empty bars would be read as 0%.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No sessions recorded yet")
                .font(.kr(36, .bold))
                .foregroundStyle(Theme.ink)
            Text("This report is built from what the sessions actually recorded. "
                 + "It stays empty until someone has a session with participant consent on.")
                .font(.kr(20))
                .foregroundStyle(Theme.gray6B)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Reading from the store

    /// Weekly points for this metric. Looks only at samples left when sessions closed.
    private func points(_ key: Metric.Key, for elder: Elder) -> [ReportData.WeekPoint] {
        let samples = elder.sessions
            .flatMap(\.metrics)
            .filter { $0.key == key.rawValue }
            .map { (at: $0.at, percent: $0.percent) }
        return ReportData.weekly(samples: samples, weeks: Self.weeks)
    }

    /// The most recent value actually measured.
    private func latest(_ key: Metric.Key, for elder: Elder) -> MetricSample? {
        elder.sessions.flatMap(\.metrics)
            .filter { $0.key == key.rawValue }
            .max(by: { $0.at < $1.at })
    }

    // MARK: - Short-term recall rate

    private func recallCard(for elder: Elder) -> some View {
        let series = points(.recall, for: elder)
        let falling = ReportData.isFalling(series)
        let value = latest(.recall, for: elder)?.percent
        return ReportCard {
            cardHeader(title: "Delayed recall",
                       value: value.map { "\(Int($0.rounded()))%" } ?? "—",
                       valueColor: value == nil ? Theme.gray8A
                                 : (falling ? Theme.red : Theme.blue))
            WeeklyBars(points: series, alert: falling)
            Text(ReportData.trend(series))
                .font(.kr(19, .semibold))
                .foregroundStyle(falling ? Theme.red : Theme.gray6B)
        }
    }

    // MARK: - Long-term memory consistency

    /// Facts whose answers changed. **The two statements are placed side by side** — showing only one makes comparison impossible.
    private func consistencyCard(for elder: Elder) -> some View {
        let drifted = elder.facts.filter { !$0.revisions.isEmpty }
        let total = elder.facts.count
        let reading = MetricEngine.consistency(shaken: drifted.count, total: total)
        return ReportCard {
            cardHeader(title: "Long-term consistency",
                       value: reading.value,
                       valueColor: Metric.color(for: reading.band))

            VStack(alignment: .leading, spacing: 10) {
                if let fact = drifted.max(by: { ($0.revisions.last?.at ?? .distantPast)
                                              < ($1.revisions.last?.at ?? .distantPast) }),
                   let previous = fact.revisions.last {
                    (Text("\"\(fact.subject) — ") + Text(previous.detail).bold() + Text("\""))
                        .font(.kr(20))
                        .foregroundStyle(Theme.gray4A)
                    (Text("→ now \"") + Text(fact.detail).bold() + Text("\""))
                        .font(.kr(20))
                        .foregroundStyle(Theme.gray4A)
                } else if total > 0 {
                    Text("Every story has held so far.")
                        .font(.kr(20))
                        .foregroundStyle(Theme.gray4A)
                }
                Text(reading.note)
                    .font(.kr(18))
                    .foregroundStyle(Theme.gray8A)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Speech amount · vocabulary

    private func speechCard(for elder: Elder) -> some View {
        let store = MemoryStore(context: context)
        let closed = elder.sessions.filter { $0.endedAt != nil }
            .sorted { $0.startedAt < $1.startedAt }
        let latestMean = closed.last.flatMap { store.averageWordCount(in: $0) }
        let baseline = store.speechBaseline(for: elder)
        let delta = (latestMean != nil && baseline != nil) ? latestMean! - baseline! : nil

        return ReportCard(spacing: 12) {
            Text("Talk · vocabulary")
                .font(.kr(24, .bold))
                .foregroundStyle(Theme.ink)
            HStack(alignment: .firstTextBaseline, spacing: 26) {
                Text(latestMean.map { String(format: "%.1f words avg", $0) } ?? "—")
                    .font(.kr(34, .bold))
                    .foregroundStyle(Theme.ink)
                if let delta, abs(delta) >= 0.1 {
                    Text(String(format: "%@ %.1f", delta < 0 ? "▼" : "▲", abs(delta)))
                        .font(.kr(22))
                        .foregroundStyle(delta < 0 ? Theme.red : Theme.green)
                }
            }
            Text(baseline.map { String(format: "Baseline %.1f · their own first session", $0) }
                 ?? "First session sets the baseline")
                .font(.kr(19))
                .foregroundStyle(Theme.gray6B)
        }
    }

    // MARK: - Mood · emotional tone

    /// **Can't be measured yet.** There used to be a marker on the scale here,
    /// but what set its position wasn't a measurement but a number hard-coded in the code.
    private var moodCard: some View {
        ReportCard(spacing: 12) {
            Text("Mood")
                .font(.kr(24, .bold))
                .foregroundStyle(Theme.ink)
            Text("Not measured on this device")
                .font(.kr(26, .bold))
                .foregroundStyle(Theme.gray8A)
            Text("Reading affect needs voice tone or lexical valence. Neither is built yet, "
                 + "so this card stays empty rather than showing a number nobody measured.")
                .font(.kr(19))
                .foregroundStyle(Theme.gray6B)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Closing — no diagnosis

    /// **The report must always end here.**
    ///
    /// List only the metrics and stop, and readers put a name on it themselves — "it must be dementia".
    /// This paragraph is there to stop that one step. The app only makes change noticeable;
    /// a doctor gives it a name (`Docs/03_product-design.md` section 1).
    ///
    /// **The wording follows the data.** It used to always say "8 consecutive weeks of decline" —
    /// it read that way even when things were improving.
    private func closingNote(for elder: Elder) -> some View {
        let recall = points(.recall, for: elder)
        let falling = ReportData.isFalling(recall)
        let measured = recall.compactMap(\.percent).count

        let body: String
        if measured == 0 {
            body = "Nothing has been measured yet. Sessions with a delayed recall probe "
                 + "fill this in — the probe only counts after the delay is up."
        } else if falling {
            body = "The app watches for change; it does not name it. "
                 + "\(ReportData.trend(recall)) while the old stories held. "
                 + "Share this with the family and suggest a visit to their doctor."
        } else {
            body = "The app watches for change; it does not name it. "
                 + "\(ReportData.trend(recall)). Nothing here asks for action today."
        }

        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "stethoscope")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 6) {
                Text("This is not a diagnosis.")
                    .font(.kr(22, .bold))
                    .foregroundStyle(Theme.ink)
                Text(body)
                    .font(.kr(19))
                    .foregroundStyle(Theme.gray4A)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Shared pieces

    private func cardHeader(title: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.kr(24, .bold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.kr(30, .bold))
                .foregroundStyle(valueColor)
        }
    }
}

/// Weekly bar. **Unmeasured weeks are left blank** — drawn as 0 they read as a sharp drop.
struct WeeklyBars: View {
    var points: [ReportData.WeekPoint]
    var alert: Bool
    var height: CGFloat = 120

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                if let percent = point.percent {
                    UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: 5,
                                           style: .continuous)
                        .fill(alert ? Theme.red : Theme.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, height * percent / 100))
                } else {
                    // A week with no samples. Keep its place but don't draw a value.
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.ink(0.07))
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                }
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// Report card shell — white background + 1px border + 16 corner radius.
struct ReportCard<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            )
    }
}
