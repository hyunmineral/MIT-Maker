import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The robot **decides only what to do; the words come from human-written templates.**
///
/// ## Why not generate sentences
///
/// Free generation was measured on a device (`ReplyComposer` · 2026-09-01). Three out of six
/// broke the safety rules. Even with the prohibitions spelled out in the prompt, things like this came out:
///
/// > "I remember working there too, Dorothy. It was a lovely place,
/// >  and we had so much fun together."
///
/// The robot **invents a shared past that never happened** and hands it back to the elder. For someone
/// with memory difficulties there's no worse failure. Like `"Maybe we can have a snack together later?"`,
/// it also promised **things a standing kiosk can't do**.
///
/// **A prompt can't constrain a model of this size.** So the constraint was moved elsewhere.
///
/// ## Safety comes from structure, not the prompt
///
/// The model **only chooses from a closed list** — what to do (`move`), and which item
/// of the list we provide to talk about (`subject`). The sentence is built by `Move.line(subject:)`.
///
/// **It's safe even if the model spits out nonsense.** An unknown `move` falls back to `.acknowledge`,
/// and an out-of-range `subject` is treated as absent. Safety comes not from the model's compliance but from
/// Swift's bounds checks — that's the whole of this design.
///
/// It's faster as a bonus. The tokens generated are just two values, not a sentence.
@Observable
final class ReplyPlanner {

    // MARK: - What the robot can do

    /// **The robot can't say anything that isn't here.** To add more, a person writes the sentence and puts it in.
    enum Move: String, CaseIterable {
        /// Hears more of what was just said. Needs no topic name, so it's always safe.
        case followUp = "follow_up"
        /// Brings up a topic from the store. **Chosen only from the list we provide.**
        case askKnown = "ask_known"
        case seedHometown = "seed_hometown"
        case seedFamily = "seed_family"
        case seedWork = "seed_work"
        /// When the answer has no content or they seem to be struggling. **Don't press.**
        case acknowledge

        /// Whether this move needs a topic name.
        var needsSubject: Bool { self == .askKnown }

        /// The line that actually goes out.
        ///
        /// **Interpolations sit alone on their own line.** At 74pt, a line over 724pt wraps into
        /// 4 lines, the vertical budget bursts, and the text shrinks
        /// (`Docs/04_screen-design.md` section 3 · `Tools/check-captions.swift`).
        func line(subject: String?) -> String {
            switch self {
            case .followUp:
                "Tell me more\nabout that."
            case .askKnown:
                subject.map { "How about\n\($0)?\nTell me about it." }
                    ?? Move.followUp.line(subject: nil)
            case .seedHometown:
                "Where did you\ngrow up?"
            case .seedFamily:
                "Who's at home\nwith you these days?"
            case .seedWork:
                "What kind of work\ndid you do?"
            case .acknowledge:
                // **Don't use "That's good to hear."** This move comes up where
                // the elder has said they can't remember. Answering that with something positive sounds like
                // the robot didn't understand. Follow the tone the script already uses (`That's all right.`).
                "That's all right."
            }
        }
    }

    /// The chosen result.
    struct Plan: Equatable {
        var move: Move
        /// Present only for `askKnown`. **It's a string from the store, not something the model wrote.**
        var subject: String?
        var seconds: Double

        /// The value the model actually returned. **Needed to tell a fallback apart from the model's choice.**
        ///
        /// Without it, when `acknowledge` comes out three times you can't tell whether the model chose it
        /// or we couldn't parse it and dropped to it. That decides whether the thing to tune is the prompt
        /// or the code.
        var rawMove: String
        var rawSubject: Int
        /// Whether the code decided because the model's value couldn't be used.
        var wasFallback: Bool

        var line: String { move.line(subject: subject) }
    }

    /// Upper limit on the topic list shown to the model. `@Guide(.range(...))` requires a compile-time
    /// constant, so it's fixed. Even if the actual count is smaller, it's safe because **the code checks
    /// the bounds**.
    static let maxCandidates = 10

    private(set) var lastError: String?

    // MARK: - Choosing

    func plan(name: String,
              candidates: [String],
              question: String,
              answer: String) async -> Plan? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.isAvailable else { return nil }

        let offered = Array(candidates.prefix(Self.maxCandidates))
        let began = Date()
        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let reply = try await session.respond(
                to: Self.prompt(name: name, candidates: offered,
                                question: question, answer: answer),
                generating: Choice.self)
            lastError = nil
            return Self.resolve(move: reply.content.move,
                                subject: reply.content.subject,
                                candidates: offered,
                                seconds: Date().timeIntervalSince(began))
        } catch {
            lastError = String(describing: error)
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Prompt

    /// Short. **It gives only the criteria for judgement** — sentence rules are no longer needed, because the model
    /// doesn't write sentences. The prompt for free generation was long because it was all "don't write
    /// it like this", and half of it wasn't followed.
    private static let instructions = """
        You help a companion robot choose what to do next with an older adult.
        You do not write what it says — you only choose a move.

        Moves:
        - follow_up: they said something with substance; hear more about it
        - ask_known: move to a topic from the numbered list; give its number
        - seed_hometown / seed_family / seed_work: ask a first-time question
        - acknowledge: they said nothing concrete, sounded unsure, or seem tired; \
        do not press them

        Pick the move that fits what they actually said:
        - They named something concrete (a place, a person, a job, a year)         -> follow_up
        - They gave a real answer but the topic is exhausted, and the list has         something they care about -> ask_known
        - The list is empty and you know nothing about them -> a seed question
        - They said they don't know, don't remember, or gave no content         -> acknowledge

        Never press someone who sounds lost. Use ask_known only with a number         from the list.
        """

    private static func prompt(name: String, candidates: [String],
                               question: String, answer: String) -> String {
        let list = candidates.isEmpty
            ? "(nothing on file yet)"
            : candidates.enumerated()
                .map { "\($0.offset). \($0.element)" }
                .joined(separator: "\n")
        return """
        Talking with \(name).

        Topics on file:
        \(list)

        Robot asked: "\(question.replacingOccurrences(of: "\n", with: " "))"
        They answered: "\(answer)"
        """
    }

    // MARK: - Interpreting the result

    /// **Whatever the model spits out, it becomes safe here.**
    ///
    /// It deliberately takes raw values rather than a `Choice` — tied to a `@Generable` type,
    /// it wouldn't compile in an environment without `FoundationModels`, and then this verdict
    /// couldn't be tested on its own.
    static func resolve(move rawMove: String, subject index: Int,
                        candidates: [String], seconds: Double) -> Plan {
        // An unknown value falls to the side that doesn't press.
        let understood = Move(rawValue: rawMove)
        var move = understood ?? .acknowledge
        var fellBack = understood == nil

        var subject: String?
        if move.needsSubject {
            if candidates.indices.contains(index) {
                subject = candidates[index]
            } else {
                // It pointed out of range. **Don't make up a topic that doesn't exist.**
                move = .followUp
                fellBack = true
            }
        }
        return Plan(move: move, subject: subject, seconds: seconds,
                    rawMove: rawMove, rawSubject: index, wasFallback: fellBack)
    }
}

// MARK: - Structured output

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension ReplyPlanner {
    /// The two fields the model fills. Already narrowed at the decoder stage by `anyOf` and `range`,
    /// and if it still strays, `resolve(_:candidates:seconds:)` catches it.
    @Generable
    struct Choice {
        @Guide(description: "What the robot should do next.",
               .anyOf(["follow_up", "ask_known", "seed_hometown",
                       "seed_family", "seed_work", "acknowledge"]))
        var move: String

        @Guide(description: "For ask_known: the number of the topic. Otherwise -1.",
               .range(-1...9))
        var subject: Int
    }
}
#endif
