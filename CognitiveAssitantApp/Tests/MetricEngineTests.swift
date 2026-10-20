import Testing
@testable import RobotForElders

/// Metrics are **numbers about a person's memory**. If they come out wrong, they go straight into the report.
@Suite("MetricEngine — unmeasured is not the same as 0")
struct MetricEngineTests {

    @Test("Without facts, consistency isn't measured")
    func consistencyWithoutFacts() {
        let reading = MetricEngine.consistency(shaken: 0, total: 0)
        #expect(reading.band == .unmeasured)
        #expect(reading.value == "—")
        // If someone on their first visit showed 0%, it would read as "everything drifted".
        #expect(reading.percent == 0)
        #expect(reading.isMeasured == false)
    }

    @Test("Nothing drifted means 100%")
    func consistencyAllSteady() {
        let reading = MetricEngine.consistency(shaken: 0, total: 23)
        #expect(reading.value == "100%")
        #expect(reading.band == .good)
    }

    @Test("The drift ratio decides the colour")
    func consistencyBands() {
        #expect(MetricEngine.consistency(shaken: 2, total: 23).band == .good)   // 91%
        #expect(MetricEngine.consistency(shaken: 4, total: 20).band == .watch)  // 80%
        #expect(MetricEngine.consistency(shaken: 8, total: 20).band == .alert)  // 60%
    }

    @Test("Without elder utterances, speech amount isn't measured")
    func speechWithoutTurns() {
        #expect(MetricEngine.speech(meanWords: nil, baseline: 9, turns: 0).band == .unmeasured)
        #expect(MetricEngine.speech(meanWords: 8, baseline: 9, turns: 0).band == .unmeasured)
    }

    @Test("The first session isn't something to compare; it's the baseline")
    func firstSessionIsTheBaseline() {
        let reading = MetricEngine.speech(meanWords: 9.4, baseline: nil, turns: 5)
        #expect(reading.value == "baseline")
        #expect(reading.isMeasured)
        #expect(reading.note.contains("baseline"))
    }

    @Test("Compared with her own baseline — not with others")
    func speechComparesToOwnBaseline() {
        // Someone naturally quiet: even at 4 words, if the baseline is 4 it's 'as usual'.
        #expect(MetricEngine.speech(meanWords: 4, baseline: 4, turns: 6).value == "steady")
        // Someone who used to talk a lot dropping to half is a change.
        #expect(MetricEngine.speech(meanWords: 6, baseline: 14, turns: 6).value == "down")
        #expect(MetricEngine.speech(meanWords: 6, baseline: 14, turns: 6).band == .alert)
        #expect(MetricEngine.speech(meanWords: 18, baseline: 12, turns: 6).value == "up")
    }

    @Test("The bar never exceeds 100")
    func speechPercentIsClamped() {
        let reading = MetricEngine.speech(meanWords: 400, baseline: 10, turns: 3)
        #expect(reading.percent == 100)
    }

    @Test("Without a planted anchor there's no recall rate")
    func recallWithoutAnchor() {
        let reading = MetricEngine.recall(rate: nil, probed: 0, total: 0)
        #expect(reading.band == .unmeasured)
        #expect(reading.note.contains("No anchor"))
    }

    @Test("A verdict asked back too early is recorded as 'not measured'")
    func recallProbedTooEarly() {
        let reading = MetricEngine.recall(rate: nil, probed: 1, total: 1)
        #expect(reading.band == .unmeasured)
        #expect(reading.note.contains("under 6 min"))
    }

    @Test("Waiting isn't failure")
    func recallWaiting() {
        let reading = MetricEngine.recall(rate: nil, probed: 0, total: 1)
        #expect(reading.band == .unmeasured)
        #expect(reading.note.contains("waiting"))
    }

    @Test("A measured recall rate shows as is")
    func recallMeasured() {
        let reading = MetricEngine.recall(rate: 0.5, probed: 2, total: 2)
        #expect(reading.percent == 50)
        #expect(reading.value == "2/2")
        #expect(reading.band == .watch)
    }

    @Test("Mood has no way to be measured yet")
    func moodIsNeverInvented() {
        let reading = MetricEngine.mood()
        #expect(reading.band == .unmeasured)
        #expect(reading.value == "—")
    }
}
