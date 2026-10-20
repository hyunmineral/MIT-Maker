import Foundation
import Testing
@testable import RobotForElders

/// **Delayed recall is all about the delay.** Asking back after one minute measures working memory.
@Suite("RecallAnchor — verifies the delay")
struct RecallAnchorTests {

    @Test("The standard interval is 8 minutes")
    func probeIsDueAfterEightMinutes() {
        let planted = Date()
        let anchor = RecallAnchor(prompt: "lunch?", answer: "tomato soup", plantedAt: planted)
        #expect(anchor.probeDueAt.timeIntervalSince(planted) == 8 * 60)
        #expect(anchor.isDue == false)
    }

    @Test("Verdicts short of 6 minutes are excluded from the recall rate")
    func earlyProbeIsNotValid() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        let anchor = store.plantAnchor(prompt: "lunch?", answer: "tomato soup",
                                       in: session, at: TestStore.minutesAgo(3))
        store.probe(anchor, outcome: .exact)

        #expect(anchor.isValidProbe == false)
        // Recorded, but not included in the rate — values from demos must not pollute the metric.
        #expect(anchor.outcome == .exact)
        #expect(store.recallRate(in: session) == nil)
    }

    @Test("Counted once 6 minutes have passed")
    func validDelayCounts() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        let anchor = store.plantAnchor(prompt: "lunch?", answer: "tomato soup",
                                       in: session, at: TestStore.minutesAgo(9))
        store.probe(anchor, outcome: .exact)

        #expect(anchor.isValidProbe)
        #expect(store.recallRate(in: session) == 1.0)
    }

    @Test("The four verdicts have different weights — partial recall isn't failure")
    func fourOutcomesHaveDifferentWeights() {
        #expect(AnchorOutcome.exact.score == 1.0)
        #expect(AnchorOutcome.partial.score == 0.5)
        #expect(AnchorOutcome.hinted.score == 0.25)
        #expect(AnchorOutcome.missed.score == 0.0)
    }

    @Test("The recall rate over several anchors is a weighted average")
    func rateAveragesWeights() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        let a = store.plantAnchor(prompt: "lunch?", answer: "soup",
                                  in: session, at: TestStore.minutesAgo(20))
        let b = store.plantAnchor(prompt: "who visited?", answer: "Emma",
                                  in: session, at: TestStore.minutesAgo(15))
        store.probe(a, outcome: .exact)     // 1.0
        store.probe(b, outcome: .partial)   // 0.5

        let rate = try #require(store.recallRate(in: session))
        #expect(abs(rate - 0.75) < 0.001)
    }

    @Test("Anchors not yet asked back aren't counted as failures")
    func pendingAnchorIsNotAMiss() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        let a = store.plantAnchor(prompt: "lunch?", answer: "soup",
                                  in: session, at: TestStore.minutesAgo(20))
        store.probe(a, outcome: .exact)
        _ = store.plantAnchor(prompt: "who visited?", answer: "Emma", in: session)

        #expect(store.recallRate(in: session) == 1.0)
        #expect(store.pendingAnchor(in: session)?.answer == "Emma")
    }
}
