import SwiftUI

/// The memory card shown on screen during conversation (last-session summary / old photo / enrolment notice).
struct MemoryCard: Equatable {
    var kind: String     // e.g. "Last session · Jul 20"
    var title: String    // e.g. "Granddaughter Emma · finals"
    var body: String     // e.g. "\"She has tests this week\""
}

/// One of the 4 metrics in the staff overlay.
struct Metric: Identifiable, Equatable {
    let key: Key
    let label: String
    var percent: Double      // 0…100
    var value: String        // e.g. "1/1", "92%", "—"
    var color: Color
    var note: String

    var id: Key { key }

    enum Key: String, CaseIterable {
        case recall      // short-term recall rate
        case consistency // long-term memory consistency
        case speech      // speech amount · vocabulary
        case mood        // mood · emotional tone

        var label: String {
            switch self {
            case .recall:      "Short-term recall"
            case .consistency: "Long-term consistency"
            case .speech:      "Speech · vocabulary"
            case .mood:        "Mood · affect"
            }
        }
    }

    /// Before the session starts. **All four cells are still unmeasured.**
    ///
    /// Numbers like `92%` · `70%` used to be hard-coded here. That meant values showed on screen
    /// as soon as the session opened, before anything had happened — that's not measurement.
    static let baseline: [Metric] = Key.allCases.map {
        Metric(key: $0, reading: .unmeasured("Before the session"))
    }

    init(key: Key, reading: MetricEngine.Reading) {
        self.key = key
        self.label = key.label
        self.percent = reading.percent
        self.value = reading.value
        self.color = Metric.color(for: reading.band)
        self.note = reading.note
    }

    init(key: Key, label: String, percent: Double, value: String,
         color: Color, note: String) {
        self.key = key
        self.label = label
        self.percent = percent
        self.value = value
        self.color = color
        self.note = note
    }

    /// Applies a calculated result to this cell.
    mutating func apply(_ reading: MetricEngine.Reading) {
        percent = reading.percent
        value = reading.value
        note = reading.note
        color = Metric.color(for: reading.band)
    }

    /// Band → colour. **Colour is the screen's job; calculation is `MetricEngine`'s job.**
    static func color(for band: MetricEngine.Band) -> Color {
        switch band {
        case .good:       Theme.green
        case .watch:      Theme.amber
        case .alert:      Theme.red
        case .unmeasured: Theme.cream(0.5)
        }
    }
}

/// **The channel that updated metrics from choices has been removed.**
///
/// `Choice.metricUpdates` used to change the on-screen numbers directly. That meant whichever
/// choice staff pressed was the "measurement". Now metrics come only from stored records
/// (`MetricEngine`) — **closing off the very path by which the script could produce numbers.**

/// One line of the "quiet record" in the staff overlay. Never appears on the elder screen.
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    var tag: String      // e.g. "Recall hit"
    var text: String     // e.g. "Anchor #1 recalled · 8 min 12 sec delay"
    var color: Color
}

/// One answer the elder can choose (in the real app, the speech recognition result takes this place).
struct Choice: Identifiable {
    let id = UUID()
    var label: String
    var log: LogEntry?
    /// Whether it's a 'missed' branch, such as recall failure. Used to branch the next step.
    var missed: Bool = false
    /// **Delayed recall verdict.** If present, the planted anchor is judged with this.
    ///
    /// Previously only exact/failed were recorded, with a single `missed`. `AnchorOutcome` defines four
    /// and even has weights, yet only 0 and 1 were used —
    /// **partial recall, the most common form in early decline, was being recorded as failure.**
    var recall: AnchorOutcome?
    /// A choice that goes back to the start
    var resets: Bool = false
}

/// One step of the session script = one screen.
struct SessionStep: Identifiable {
    let id = UUID()
    var face: FaceStyle
    var status: String       // status at top left (for staff)
    var caption: String      // what the robot says (large text)
    /// Whether to read `caption` aloud. **Status displays** like "Resting" on the resting/end screens
    /// aren't the robot speaking, so they aren't read. Speech produced by the conversation engine is always true.
    var speaks: Bool = true
    var listening: Bool = false
    var card: MemoryCard?
    var choices: [Choice] = []
}
