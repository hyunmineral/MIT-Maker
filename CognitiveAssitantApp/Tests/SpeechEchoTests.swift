import Testing
@testable import RobotForElders

/// A defect that actually happened on 2026-09-01 — the robot's question was saved as the elder's answer,
/// and `Fact "She"` was produced from it.
@Suite("SpeechEcho — its own voice isn't recorded as the elder's words")
struct SpeechEchoTests {

    private let caption = "What did you have\nfor lunch today?"

    @Test("Echoing back the whole line is discarded")
    func fullEchoIsDropped() {
        #expect(SpeechEcho.isEcho(heard: "What did you have for lunch today?",
                                  caption: caption))
    }

    @Test("Treated as the same words even if line breaks and punctuation differ")
    func punctuationDoesNotMatter() {
        #expect(SpeechEcho.isEcho(heard: "what did you have for lunch today",
                                  caption: caption))
        #expect(SpeechEcho.isEcho(heard: "What did you have", caption: caption))
    }

    @Test("Normal speech that echoes the question while answering is kept")
    func partialRepeatWithAnswerSurvives() {
        // Blocking partial matches too would discard normal speech like this.
        #expect(!SpeechEcho.isEcho(heard: "What did I have? Soup.", caption: caption))
        #expect(!SpeechEcho.isEcho(heard: "for lunch I had tomato soup", caption: caption))
    }

    @Test("Short answers aren't checked")
    func shortAnswersAreNeverEchoes() {
        // A single "yes" must not be discarded just because it appears in the line.
        #expect(!SpeechEcho.isEcho(heard: "lunch", caption: caption))
        #expect(!SpeechEcho.isEcho(heard: "Yes", caption: "Yes, tell me more"))
    }

    @Test("Completely different words are accepted as is")
    func realAnswerIsKept() {
        #expect(!SpeechEcho.isEcho(heard: "I had tomato soup", caption: caption))
    }
}
