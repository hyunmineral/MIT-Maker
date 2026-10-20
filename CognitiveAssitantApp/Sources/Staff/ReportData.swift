import Foundation

/// **Extracts the values the reports show from the records.**
///
/// There's one reason the calculation was separated from the screens (`CognitiveReportView` · `WeeklyDigestView`)
/// — **it has to be testable without a device.** Everything here is a pure function.
///
/// Previously all three screens had Dorothy Miller's values hard-coded. Seat someone else
/// and the same graph appeared.
enum ReportData {

    /// One week's value. **`nil` if there are no samples** — it must be distinguished from 0.
    struct WeekPoint: Equatable {
        var weekStart: Date
        var percent: Double?
    }

    /// Folds into weeks. If a week has several sessions, it's their average.
    ///
    /// - Parameters:
    ///   - samples: (time, value) pairs. Values are 0…100
    ///   - weeks: how many weeks to look at
    ///   - now: reference time for the last week
    static func weekly(samples: [(at: Date, percent: Double)],
                       weeks: Int,
                       now: Date = .now,
                       calendar: Calendar = .current) -> [WeekPoint] {
        guard weeks > 0 else { return [] }
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now

        return (0..<weeks).reversed().compactMap { back -> WeekPoint? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else { return nil }
            let inWeek = samples.filter { $0.at >= start && $0.at < end }.map(\.percent)
            let mean = inWeek.isEmpty
                ? nil
                : inWeek.reduce(0, +) / Double(inWeek.count)
            return WeekPoint(weekStart: start, percent: mean)
        }
    }

    /// The trend in one line. **With fewer than two values, it isn't called a trend.**
    ///
    /// Writing "declining" from a single point isn't observation, it's staging.
    static func trend(_ points: [WeekPoint]) -> String {
        let measured = points.compactMap(\.percent)
        guard let last = measured.last else { return "No measurement yet" }
        guard measured.count >= 2, let first = measured.first else {
            return "One week measured · no trend yet"
        }
        let delta = last - first
        let weeks = measured.count
        if abs(delta) < 5 { return "Steady across \(weeks) measured weeks" }
        let direction = delta < 0 ? "Down" : "Up"
        return "\(direction) \(Int(abs(delta).rounded())) points across \(weeks) weeks"
    }

    /// Whether it's trending down. Used to pick the wording of the closing paragraph.
    static func isFalling(_ points: [WeekPoint], by threshold: Double = 5) -> Bool {
        let measured = points.compactMap(\.percent)
        guard let first = measured.first, let last = measured.last,
              measured.count >= 2 else { return false }
        return first - last >= threshold
    }

    // MARK: - Weekly digest

    /// One thing to tell staff this week.
    struct Note: Identifiable, Equatable {
        enum Kind: String {
            /// A change worth noticing. An observation, not a diagnosis.
            case followUp
            /// Good news. **Kept in the same list so it isn't all warnings.**
            case good
            /// Something staff need to do.
            case ask

            /// Order in the list. Changes first, requests last.
            var priority: Int {
                switch self {
                case .followUp: 0
                case .good:     1
                case .ask:      2
                }
            }
        }

        /// What the notice is about. **Distinguished by value, not by string** —
        /// merging the same kind into one must not mean digging through titles.
        enum Topic {
            case recallDown
            case speechUp
            case factDrift
            case address
            case longGap
        }

        var id: String { "\(kind.rawValue)-\(title)" }
        var kind: Kind
        var topic: Topic
        /// Who the notice is about. **Kept separately so merging doesn't parse titles.**
        var subject: String
        var title: String
        var body: String
    }

    /// One person's summary for this week.
    ///
    /// - Parameters:
    ///   - name: the name to use on screen
    ///   - recall: weekly recall-rate points
    ///   - speech: weekly speech-amount points
    ///   - driftedFacts: topics whose answers changed this week
    ///   - needsAddress: whether the form of address is still unset
    ///   - daysSinceLastSession: days since the last session. `nil` if there are no sessions
    static func notes(name: String,
                      recall: [WeekPoint],
                      speech: [WeekPoint],
                      driftedFacts: [String],
                      needsAddress: Bool,
                      daysSinceLastSession: Int?) -> [Note] {
        var notes: [Note] = []

        if isFalling(recall) {
            notes.append(Note(
                kind: .followUp,
                topic: .recallDown,
                subject: name,
                title: "\(name) — delayed recall is down",
                body: "\(trend(recall)). Share it with the family and suggest a visit "
                    + "to their doctor. This is a change to watch, not a diagnosis."))
        }

        let speechMeasured = speech.compactMap(\.percent)
        if let first = speechMeasured.first, let last = speechMeasured.last,
           speechMeasured.count >= 2, last - first >= 5 {
            notes.append(Note(
                kind: .good,
                topic: .speechUp,
                subject: name,
                title: "\(name) — talking more",
                body: "\(trend(speech)). Whatever you are doing in these sessions, keep it."))
        }

        if !driftedFacts.isEmpty {
            let list = driftedFacts.prefix(3).joined(separator: " · ")
            notes.append(Note(
                kind: .followUp,
                topic: .factDrift,
                subject: name,
                title: "\(name) — a story changed",
                body: "The answer moved on: \(list). Both versions are kept. "
                    + "Ask again gently next time; do not correct them."))
        }

        if needsAddress {
            notes.append(Note(
                kind: .ask,
                topic: .address,
                subject: name,
                title: "\(name) — how should the robot address them?",
                body: "No title is on file, so the robot says the full recorded name. "
                    + "Set Mr. / Mrs. / Ms. on their card, or record that they asked "
                    + "for their first name."))
        }

        if let days = daysSinceLastSession, days >= 14 {
            notes.append(Note(
                kind: .ask,
                topic: .longGap,
                subject: name,
                title: "\(name) — not seen in \(days) days",
                body: "The opener still holds their last topic. A gap this long "
                    + "makes the first question feel further away."))
        }

        return notes
    }

    // MARK: - Tidying the list

    /// Turns several people's notices **into a readable list**.
    ///
    /// If the same request repeats once per person, the changes that actually matter get pushed down.
    /// Form-of-address requests are merged into one line, ordered changes → good news → requests.
    static func merged(_ notes: [Note]) -> [Note] {
        let address = notes.filter { $0.topic == .address }
        var rest = notes.filter { $0.topic != .address }

        if !address.isEmpty {
            let names = address.map(\.subject)
            rest.append(Note(
                kind: .ask,
                topic: .address,
                subject: names.count == 1 ? names[0] : "\(names.count) people",
                title: names.count == 1
                    ? "\(names[0]) — how should the robot address them?"
                    : "\(names.count) people need a form of address",
                body: "\(names.joined(separator: " · ")). No title is on file, so the robot "
                    + "says the full recorded name. Set Mr. / Mrs. / Ms. on their card, "
                    + "or record that they asked for their first name."))
        }

        return rest.sorted { $0.kind.priority < $1.kind.priority }
    }
}
