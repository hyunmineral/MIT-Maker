import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The robot **writes its next line on the spot.**
///
/// The session is currently a fixed script, so whatever the elder says, the next line doesn't change.
/// If `FactExtractor` is the listening and understanding side, this is **the speaking side**.
/// (`Docs/05_implementation-roadmap.md` stage 2)
///
/// ## Not attached to the session yet
///
/// **It was built to measure latency first.** On-device inference on a real device took
/// 7.7–11.6 seconds for fact extraction. That much per line would leave the elder waiting through silence for every line.
/// Whether it's in an attachable shape is decided by the numbers measured with this class — `ReplyLatencyView`.
///
/// So **it's received as a stream.** Rather than total completion time, **the time to the first token**
/// decides the design. If the first token arrives quickly, speaking can start, and then the remaining
/// generation time flows by and disappears while speaking.
@Observable
final class ReplyComposer {

    /// What's measured for one generation.
    struct Measurement: Equatable {
        var text: String
        /// Until the first token appears. **This number decides the design.**
        var firstTokenSeconds: Double
        /// Until everything is out.
        var totalSeconds: Double
        var characters: Int { text.count }
        /// Whether it exceeds the 74pt line budget (3 lines × 21 characters).
        var overBudget: Bool { characters > ReplyComposer.maxCharacters }
    }

    /// Line budget. 21 characters per line × 3 lines at `Theme.Size.speech` 74pt
    /// (`Docs/04_screen-design.md` section 3). Over that, `FitToHeight` shrinks the text.
    static let maxCharacters = 63

    /// Whether to open a new session or use one warmed up in advance.
    ///
    /// **The first token arrives at 93–100% of the total** (measured 2026-09-01: 7.3 s / 7.5 s).
    /// That means it's not token generation time but **a fixed cost paid on every call**.
    /// So the question is whether that cost can be moved to before the conversation starts.
    enum Strategy: String, CaseIterable {
        /// Creates a new `LanguageModelSession` on every call. The baseline.
        case fresh
        /// **Create a new session every time, but prewarm only the model.**
        ///
        /// At first a warmed session was reused continuously, but **it actually got slower**
        /// (measured 2026-09-01: 5.0 s → 7.8 s). `LanguageModelSession` accumulates the exchanged
        /// messages as history, so reusing it makes the prompt longer with every call.
        /// It actually grew 6.9 → 6.7 → 9.9 seconds.
        ///
        /// So warming and history were separated. Loading the model up front is a gain;
        /// carrying the history forward is a loss.
        case prewarmed

        var label: String {
            switch self {
            case .fresh:     "new session every time"
            case .prewarmed: "model prewarmed only"
            }
        }
    }

    private(set) var isWorking = false
    private(set) var lastError: String?

    #if canImport(FoundationModels)
    /// A session that only loads the model into memory. **No lines are requested from it** —
    /// requesting them would accumulate history and slow the next call.
    @available(iOS 26.0, *)
    private static var primer: LanguageModelSession?

    /// Loads the model before the conversation starts. **Time spent here isn't time the elder
    /// waits** — that's the whole point of this approach.
    /// In the real product, call it the moment the session screen appears.
    @available(iOS 26.0, *)
    static func warmUp() {
        guard primer == nil else { return }
        let session = LanguageModelSession(instructions: instructions)
        session.prewarm()
        primer = session
    }

    @available(iOS 26.0, *)
    static func dropWarmSession() { primer = nil }
    #endif

    /// What's known about one elder. Prompt length affects latency, so
    /// **the measuring side must also feed in a realistic amount** for the numbers to mean anything.
    struct Context {
        var name: String
        /// Things like `("the peach orchard", "Worked there at twenty")`.
        var facts: [(subject: String, detail: String)]
    }

    func compose(context: Context, question: String, answer: String,
                 strategy: Strategy = .prewarmed) async -> Measurement? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        isWorking = true
        defer { isWorking = false }

        let began = Date()
        var firstAt: Date?
        var text = ""

        do {
            // **Created fresh every time so history isn't carried forward.** Warming loads
            // the model; it doesn't hand down a session.
            if strategy == .prewarmed { Self.warmUp() }
            let session = LanguageModelSession(instructions: Self.instructions)
            let stream = session.streamResponse(to: Self.prompt(context: context,
                                                               question: question,
                                                               answer: answer))
            for try await snapshot in stream {
                if firstAt == nil, !snapshot.content.isEmpty { firstAt = Date() }
                text = snapshot.content
            }
            lastError = nil
            let done = Date()
            return Measurement(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                firstTokenSeconds: (firstAt ?? done).timeIntervalSince(began),
                totalSeconds: done.timeIntervalSince(began)
            )
        } catch {
            lastError = String(describing: error)
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Prompt

    /// **What the script used to guarantee has to be guaranteed again here.**
    ///
    /// The fixed script was safe because people had read it in advance. The moment it moves to generation,
    /// that guarantee is gone — lines that plant a memory that never existed, point out what the elder
    /// failed to recall, or ask two things at once could go straight out.
    ///
    /// Principle 3 (`Docs/03_product-design.md`) matters especially. **The robot never exposes a recall failure
    /// to the elder.** "You told me earlier" must never come out.
    static let instructions = """
        You are a companion robot on a stand, talking with an older adult.
        Write only the robot's next spoken line.

        Hard rules:
        - At most \(maxCharacters) characters. Shorter is better.
        - One thought. Ask at most one question.
        - Plain warm speech, the way a kind neighbour talks. No lists, no emoji.
        - Use ONLY facts given to you or said in this turn. Never invent a memory, \
        a name, a place, or a shared past.
        - NEVER point out that they forgot, repeated themselves, or got something \
        wrong. Never say "you already told me" or "remember?". If they seem lost, \
        move gently to something they know well.
        - Do not mention that you are an AI, a model, or a program.
        - Reply with the line itself. No quotation marks, no stage directions.
        """

    private static func prompt(context: Context, question: String, answer: String) -> String {
        let known = context.facts.isEmpty
            ? "Nothing on file yet."
            : context.facts.map { "- \($0.subject): \($0.detail)" }.joined(separator: "\n")
        return """
        You are talking with \(context.name).

        What you know about them:
        \(known)

        You just asked: "\(question.replacingOccurrences(of: "\n", with: " "))"
        They answered: "\(answer)"

        Your next line:
        """
    }
}
