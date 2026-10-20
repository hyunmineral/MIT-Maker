import Foundation

/// **Computes metrics from actual records.**
///
/// Previously only the recall rate of the four metrics was really computed; the other three were hard-coded
/// as constants in `Choice.metricUpdates`. That meant the on-screen numbers were the same whatever the elder said.
///
/// ## Why no SwiftUI
///
/// Colour isn't decided here; only a `Band` is returned. Keeping the calculation free of the screen
/// means **it can be tested without a device** — every function in this file is pure.
///
/// ## Missing values are not invented
///
/// If it can't be measured, `.unmeasured` is returned and the screen shows `—`. A made-up number
/// in the cognitive report would be a false record about a person's memory
/// (`Docs/03_product-design.md` section 4).
enum MetricEngine {

    /// State of one metric cell. The screen decides the colour.
    enum Band: Equatable {
        case good
        case watch
        case alert
        /// Can't be measured yet. **No number is made up.**
        case unmeasured
    }

    struct Reading: Equatable {
        var percent: Double
        var value: String
        var note: String
        var band: Band

        var isMeasured: Bool { band != .unmeasured }

        static func unmeasured(_ note: String) -> Reading {
            Reading(percent: 0, value: "—", note: note, band: .unmeasured)
        }
    }

    // MARK: - Long-term memory consistency

    /// The proportion of answers that drifted when the same topic was asked again.
    ///
    /// The denominator is all recorded facts; the numerator is facts with a `FactRevision` attached.
    /// **With no facts at all it can't be measured** — someone on their first visit must not show 0%.
    static func consistency(shaken: Int, total: Int) -> Reading {
        guard total > 0 else {
            return .unmeasured("No facts on file yet")
        }
        let steady = Double(total - shaken) / Double(total)
        let percent = steady * 100
        return Reading(
            percent: percent,
            value: "\(Int(percent.rounded()))%",
            note: "Fact drift \(shaken) / \(total)",
            band: percent >= 90 ? .good : (percent >= 70 ? .watch : .alert)
        )
    }

    // MARK: - Speech amount · vocabulary

    /// The bar is full when one turn reaches this many words. Just a scale for the bar length;
    /// the verdict is made **against the person's own baseline**.
    static let wordsFullScale: Double = 20

    /// Compares this session's word count with **the person's own baseline**.
    ///
    /// Not compared with others. How much people talk naturally varies, and what this product looks at is
    /// **that person's change** (`Docs/03_product-design.md` 4-3).
    ///
    /// - Parameters:
    ///   - meanWords: average words per elder turn in this session
    ///   - baseline: the same value from previous sessions. `nil` for the first session
    ///   - turns: number of elder turns in this session
    static func speech(meanWords: Double?, baseline: Double?, turns: Int) -> Reading {
        guard turns > 0, let mean = meanWords, mean > 0 else {
            return .unmeasured("No elder turns yet")
        }
        let percent = min(100, mean / wordsFullScale * 100)
        let words = String(format: "%.0f", mean)

        guard let baseline, baseline > 0 else {
            // The first session isn't something to compare; it **is the baseline itself**.
            return Reading(percent: percent,
                           value: "baseline",
                           note: "\(words) words / turn · first session sets the baseline",
                           band: .watch)
        }

        let ratio = mean / baseline
        let value: String
        let band: Band
        switch ratio {
        case ..<0.7:  value = "down";   band = .alert
        case ..<0.9:  value = "slower"; band = .watch
        case ..<1.1:  value = "steady"; band = .good
        default:      value = "up";     band = .good
        }
        return Reading(percent: percent,
                       value: value,
                       note: "\(words) words / turn · baseline "
                           + String(format: "%.0f", baseline),
                       band: band)
    }

    // MARK: - Short-term recall rate

    /// Recall rate computed only from verdicts that met a valid delay.
    ///
    /// - Parameters:
    ///   - rate: `MemoryStore.recallRate(in:)`. `nil` if there are no valid verdicts
    ///   - probed: number of anchors asked back
    ///   - total: number of anchors planted
    static func recall(rate: Double?, probed: Int, total: Int) -> Reading {
        guard let rate else {
            guard total > 0 else {
                return .unmeasured("No anchor planted yet")
            }
            return .unmeasured(probed == 0
                ? "\(total) anchor(s) waiting"
                : "Delay under 6 min · not measured")
        }
        let percent = rate * 100
        return Reading(
            percent: percent,
            value: "\(probed)/\(total)",
            note: "\(probed) valid delayed probe(s)",
            band: rate >= 0.75 ? .good : (rate >= 0.4 ? .watch : .alert)
        )
    }

    // MARK: - Mood · affect

    /// **There is no way to measure it yet.**
    ///
    /// The design names two sources: voice tone and lexical sentiment (`Docs/03_product-design.md` 4-4).
    /// Neither is implemented on this device. Previously a `70%` baked into the script
    /// was shown, but **that was a picture, not a measurement.**
    ///
    /// Instead of inventing a number, it records that it couldn't measure. Staff must never look at the screen and
    /// tell the family "her mood was 68% today".
    static func mood() -> Reading {
        .unmeasured("No affect measure on this device yet")
    }
}
