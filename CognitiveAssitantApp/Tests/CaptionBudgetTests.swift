import UIKit
import Testing
@testable import RobotForElders

/// **The build still passes when it overflows.** `FitToHeight` quietly shrinks the block, so the tier-A
/// legibility secured at 74pt (35.8 arcminutes) silently disappears. A failure the eye can't catch.
///
/// `Tools/check-captions.swift` checks the script but scans **only `SessionScript.swift`**.
/// Lines the planner builds appear as is on the elder screen, yet were outside the check.
/// Here they're measured with the UIKit-measured font — 1.35pt larger than the script's AppKit value.
@Suite("Line budget — no line exceeds 724pt")
struct CaptionBudgetTests {

    private let font = UIFont.systemFont(ofSize: Theme.Size.speech, weight: .semibold)

    private func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [
            .font: font,
            .kern: -0.02 * Theme.Size.speech
        ]).width
    }

    private func lines(_ caption: String) -> [String] {
        caption.components(separatedBy: "\n")
    }

    /// **UIKit-measured line height.** 88.35pt at 74pt.
    ///
    /// Computing it as `speech × 1.35` (99.9) overestimates and fails lines that would pass.
    /// Derived from the simulator line pitch of 95.75pt, and the same as `Tools/check-captions.swift`.
    private let measuredLineHeight: CGFloat = 88.35
    private var lineSpacing: CGFloat { Theme.Size.speech * (Theme.speechLineHeight - 1.25) }

    private func captionHeight(lines n: Int) -> CGFloat {
        measuredLineHeight * CGFloat(n) + lineSpacing * CGFloat(n - 1)
    }

    /// The allowed number of lines depends on what's attached below the line.
    private func maxLines(wave: Bool, card: Bool) -> Int {
        let budget = Theme.Layout.stageHeightPilot - Theme.Layout.captionTopPilot
        let below = (wave ? 16 + 44 : 0) + (card ? 16 + 160 : 0) as CGFloat
        var n = 1
        while captionHeight(lines: n + 1) + below <= budget { n += 1 }
        return n
    }

    private var maxLinesWithWave: Int { maxLines(wave: true, card: false) }

    @Test("Lines the planner builds fit within the width")
    func plannerLinesFitWidth() {
        for move in ReplyPlanner.Move.allCases {
            let caption = move.line(subject: move.needsSubject ? "Norfolk" : nil)
            for line in lines(caption) {
                #expect(width(line) <= Theme.Layout.contentWidth,
                        "\(move.rawValue): \"\(line)\" = \(Int(width(line)))pt")
            }
        }
    }

    @Test("Planner lines stay within the line-count budget")
    func plannerLinesFitHeight() {
        for move in ReplyPlanner.Move.allCases {
            let caption = move.line(subject: move.needsSubject ? "Norfolk" : nil)
            #expect(lines(caption).count <= maxLinesWithWave, "\(move.rawValue)")
        }
    }

    /// **Interpolations sit alone on their own line.**
    ///
    /// Topic names come from the store, so their length is unknown. Sharing a line with other text
    /// wraps long names, adding a line, and at that moment the vertical budget bursts.
    @Test("Topic names sit alone on their own line")
    func interpolatedTopicOwnsItsLine() {
        let subject = "the peach orchard"
        let caption = ReplyPlanner.Move.askKnown.line(subject: subject)
        let hosting = lines(caption).filter { $0.contains(subject) }
        #expect(hosting.count == 1)
        let stripped = hosting[0]
            .replacingOccurrences(of: subject, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?—-"))
        #expect(stripped.isEmpty, "\"\(stripped)\" remains on the same line as the topic")
    }

    @Test("Seed questions fit within the width too")
    func seedQuestionsFitWidth() {
        for question in SessionScript.SeedQuestion.allCases {
            for line in lines(question.caption(introducing: nil)) {
                #expect(width(line) <= Theme.Layout.contentWidth,
                        "\"\(line)\" = \(Int(width(line)))pt")
            }
        }
    }

    @Test("In seed questions with a name, the name gets its own line")
    func seedQuestionKeepsNameAlone() {
        let name = "Margaret Walsh"
        let caption = SessionScript.SeedQuestion.hometown.caption(introducing: name)
        let hosting = lines(caption).filter { $0.contains(name) }
        #expect(hosting.count == 1)
        let stripped = hosting[0]
            .replacingOccurrences(of: name, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?—-"))
        #expect(stripped.isEmpty)
    }

    @Test("Re-ask lines and stalling lines fit within the width too")
    func stallAndReaskFitWidth() {
        var captions = [SessionScript.lookingStall()]
        for attempt in 1...SessionScript.nameReaskLimit {
            captions.append(SessionScript.nameReask(attempt: attempt))
        }
        for caption in captions {
            for line in lines(caption) {
                #expect(width(line) <= Theme.Layout.contentWidth,
                        "\"\(line)\" = \(Int(width(line)))pt")
            }
        }
    }

    @Test("Every line the script reads aloud fits within the width")
    func scriptedLinesFitWidth() {
        for caption in SessionScript.allSpokenLines {
            for line in lines(caption) {
                // Interpolation slots in the script are filled at run time, so only the fixed parts are measured here.
                #expect(width(line) <= Theme.Layout.contentWidth,
                        "\"\(line)\" = \(Int(width(line)))pt")
            }
        }
    }

    /// **Does every step fit within the budget for its slot?**
    ///
    /// Listening steps get a waveform, and steps with a memory card get the card, attached below the line.
    /// The more that's attached, the fewer lines are left for the caption (`Docs/04_screen-design.md` section 3).
    @Test("Every step of the script fits the line-count budget")
    func everyStepFitsItsBudget() {
        for step in SessionScript.known + SessionScript.stranger {
            let allowed = maxLines(wave: step.listening, card: step.card != nil)
            #expect(lines(step.caption).count <= allowed,
                    "\(step.status): \(lines(step.caption).count) lines > \(allowed) lines")
        }
    }

    /// Steps that include values from the store. **Lines must not grow even with long values.**
    @Test("Lines containing store values fit the budget too")
    func generatedStepsFitBudget() {
        let longTopic = "the peach orchard"
        let longName = "Margaret Walsh"

        let steps: [SessionStep] = [
            SessionScript.openerStep(topic: longTopic,
                                     card: MemoryCard(kind: "k", title: "t", body: "b")),
            SessionScript.reminiscenceStep(topic: longTopic),
            SessionScript.farewellStep(topic: longTopic),
            SessionScript.farewellStep(topic: nil),
            SessionScript.reconnectStep(),
            SessionScript.firstMemoryStep(spokenName: longName),
        ] + SessionScript.SeedQuestion.allCases.map {
            SessionScript.seedStep($0, introducing: longName)
        }

        for step in steps {
            let allowed = maxLines(wave: step.listening, card: step.card != nil)
            #expect(lines(step.caption).count <= allowed,
                    "\(step.status): \(lines(step.caption).count) lines > \(allowed) lines")
        }
    }

    /// **Interpolations sit alone on their own line** — the same for steps the script builds.
    @Test("The farewell's topic gets its own line")
    func farewellTopicOwnsItsLine() {
        let topic = "the peach orchard"
        let caption = SessionScript.farewellStep(topic: topic).caption
        let hosting = lines(caption).filter { $0.contains(topic) }
        #expect(hosting.count == 1)
        let stripped = hosting[0]
            .replacingOccurrences(of: topic, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,!?—-"))
        #expect(stripped.isEmpty, "\"\(stripped)\" remains on the same line as the topic")
    }
}
