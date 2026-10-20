import Testing
@testable import RobotForElders

/// Checks that the script's **index constants point at the actual steps**.
///
/// Inserting a step makes constants like `delayedRecallIndex` silently point at a different place,
/// and then anchors get planted or judged in the wrong place. The compiler
/// won't tell you.
@Suite("SessionScript — do the indices point at the right places")
struct SessionScriptTests {

    @Test("Slots in the enrolled-person script")
    func knownScriptIndices() {
        let steps = SessionScript.known
        #expect(steps[SessionScript.recognitionIndex].status == "Face recognition")
        #expect(steps[SessionScript.greetingIndex].status == "Greeting")
        #expect(steps[SessionScript.openerIndex].status == "Continuity opener")
        #expect(steps[SessionScript.anchorPlantIndex].status == "Planting anchor")
        #expect(steps[SessionScript.reminiscenceIndex].status == "Reminiscence")
        #expect(steps[SessionScript.delayedRecallIndex].status == "Delayed recall probe")
        #expect(steps[SessionScript.gentleAssistIndex].status == "Gentle assist")
        #expect(steps[SessionScript.farewellIndex].status == "Farewell")
    }

    @Test("Slots in the first-meeting script")
    func strangerScriptIndices() {
        let steps = SessionScript.stranger
        #expect(steps[SessionScript.askNameIndex].status == "Asking name")
        #expect(steps[SessionScript.enrollConfirmIndex].status == "Confirm & enroll")
        #expect(steps[SessionScript.seedMemoryIndex].status == "Seeding memory")
    }

    @Test("The anchor is planted before asking back")
    func anchorIsPlantedBeforeItIsProbed() {
        #expect(SessionScript.anchorPlantIndex < SessionScript.delayedRecallIndex)
    }

    @Test("There's a path for all four recall verdicts")
    func allFourOutcomesAreReachable() {
        let probe = SessionScript.known[SessionScript.delayedRecallIndex]
        let assist = SessionScript.known[SessionScript.gentleAssistIndex]
        let outcomes = Set((probe.choices + assist.choices).compactMap(\.recall))
        // Lumping partial recall in with failure misses the change that shows up first.
        #expect(outcomes == [.exact, .partial, .hinted, .missed])
    }

    @Test("Recall after a hint comes only from the recovery step")
    func hintedOnlyAfterTheAnswerIsOffered() {
        let probe = SessionScript.known[SessionScript.delayedRecallIndex]
        #expect(!probe.choices.contains { $0.recall == .hinted })
    }

    @Test("Every line in a listening step is read aloud")
    func listeningStepsSpeak() {
        for step in SessionScript.known + SessionScript.stranger where step.listening {
            #expect(step.speaks, "\(step.status)")
        }
    }

    @Test("The resting and end screens aren't the robot speaking")
    func idleScreensDoNotSpeak() {
        #expect(SessionScript.known.first?.speaks == false)
        #expect(SessionScript.known.last?.speaks == false)
    }

    @Test("Picks the seed not yet asked, in the order hometown → family → occupation")
    func seedOrder() {
        #expect(SessionScript.nextSeed(missingFrom: []) == .hometown)

        let place = Fact(subject: "Norfolk", kind: .place, detail: "grew up")
        #expect(SessionScript.nextSeed(missingFrom: [place]) == .family)

        let person = Fact(subject: "Emma", kind: .person, detail: "granddaughter")
        #expect(SessionScript.nextSeed(missingFrom: [place, person]) == .work)

        let event = Fact(subject: "the mill", kind: .event, detail: "worked there")
        #expect(SessionScript.nextSeed(missingFrom: [place, person, event]) == nil)
    }

    @Test("The farewell previews a topic that actually came up this time")
    func farewellPromisesARealTopic() {
        let named = SessionScript.farewellStep(topic: "the orchard")
        #expect(named.caption.contains("the orchard"))
        // With no topic, it doesn't make a promise about nothing.
        let empty = SessionScript.farewellStep(topic: nil)
        #expect(!empty.caption.contains("next time about"))
    }

    @Test("Without a previous story, it doesn't quote a conversation that never happened")
    func reconnectDoesNotInventHistory() {
        let step = SessionScript.reconnectStep()
        #expect(step.card == nil)
        #expect(!step.caption.contains("Last time"))
    }
}
