import Testing
@testable import RobotForElders

/// **Where this project's safety claim rests.**
///
/// When free generation was pulled, it was decided that "safety comes not from the prompt but from the bounds checks in `resolve()`".
/// This is where that sentence is checked — the model can spit out anything,
/// and what it spits out must not go straight to the elder.
///
/// Needs neither device nor model. A pure function: values in, values out.
@Suite("ReplyPlanner.resolve — whatever the model spits out")
struct ReplyPlannerResolveTests {

    private let topics = ["the peach orchard", "Emma", "Norfolk"]

    @Test("An unknown move falls to the side that doesn't press")
    func unknownMoveFallsBack() {
        let plan = ReplyPlanner.resolve(move: "tell_a_joke", subject: -1,
                                        candidates: topics, seconds: 1)
        #expect(plan.move == .acknowledge)
        #expect(plan.wasFallback)
        #expect(plan.subject == nil)
        // The original value must remain to know whether to fix the prompt or the code.
        #expect(plan.rawMove == "tell_a_joke")
    }

    @Test("An empty string falls to the same place")
    func emptyMoveFallsBack() {
        let plan = ReplyPlanner.resolve(move: "", subject: 0,
                                        candidates: topics, seconds: 1)
        #expect(plan.move == .acknowledge)
        #expect(plan.wasFallback)
    }

    @Test("Pointing at an out-of-range topic doesn't invent a topic")
    func outOfRangeSubjectFallsBack() {
        for index in [-1, 3, 9, 99] {
            let plan = ReplyPlanner.resolve(move: "ask_known", subject: index,
                                            candidates: topics, seconds: 1)
            #expect(plan.move == .followUp, "index \(index)")
            #expect(plan.subject == nil, "index \(index)")
            #expect(plan.wasFallback, "index \(index)")
            // No topic name must leak into the line.
            #expect(plan.line == ReplyPlanner.Move.followUp.line(subject: nil))
        }
    }

    @Test("With no candidates at all, no index can be used")
    func emptyCandidatesFallBack() {
        let plan = ReplyPlanner.resolve(move: "ask_known", subject: 0,
                                        candidates: [], seconds: 1)
        #expect(plan.move == .followUp)
        #expect(plan.subject == nil)
        #expect(plan.wasFallback)
    }

    @Test("With normal input, the string from the store goes into the line as is")
    func validChoiceUsesStoredTopic() {
        let plan = ReplyPlanner.resolve(move: "ask_known", subject: 1,
                                        candidates: topics, seconds: 2.5)
        #expect(plan.move == .askKnown)
        #expect(plan.subject == "Emma")
        #expect(plan.wasFallback == false)
        #expect(plan.line.contains("Emma"))
        #expect(plan.seconds == 2.5)
    }

    @Test("Moves that need no topic ignore the index")
    func movesWithoutSubjectIgnoreIndex() {
        for raw in ["follow_up", "seed_hometown", "seed_family", "seed_work", "acknowledge"] {
            let plan = ReplyPlanner.resolve(move: raw, subject: 42,
                                            candidates: topics, seconds: 1)
            #expect(plan.subject == nil, "\(raw)")
            #expect(plan.wasFallback == false, "\(raw)")
            #expect(plan.move.rawValue == raw, "\(raw)")
        }
    }

    @Test("No move produces an empty line")
    func everyMoveProducesALine() {
        for move in ReplyPlanner.Move.allCases {
            let line = move.line(subject: move.needsSubject ? "Norfolk" : nil)
            #expect(!line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(move.rawValue)")
        }
    }

    @Test("Where she said she can't remember, it doesn't answer with something positive")
    func acknowledgeDoesNotPraise() {
        // `acknowledge` comes up where she couldn't recall. Something like "Well done" there
        // sounds like it didn't understand — keep the tone the script used.
        let line = ReplyPlanner.Move.acknowledge.line(subject: nil).lowercased()
        #expect(!line.contains("good"))
        #expect(!line.contains("great"))
    }
}
