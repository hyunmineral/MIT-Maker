import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// **Extracts facts worth remembering** from what the elder said.
///
/// Until now the only `Fact` accumulating in the store was the one answer to the seed question. The rest of the "elder utterances"
/// were script labels staff clicked (`"She did great. She's a good student"`), so the speech-amount and vocabulary
/// metrics **were counting the script.** This file handles the understanding side of that bottleneck.
/// Transcription (STT) is done by `AnswerListener`.
///
/// ## Why an on-device LLM
///
/// Not knowing what answer will come is the essence of the problem. To "Where did you grow up?" she might answer
/// *"Oh, all over — my father was in the Navy, but mostly Norfolk"*.
/// Rules or regular expressions can't pull `Norfolk` out of that.
///
/// `NLTagger`'s named-entity recognition was also a candidate, but **it only finds places; it doesn't know whether one is the hometown.**
/// `Navy` in the same sentence also gets caught as an organisation. The question and answer have to be judged together.
///
/// ## Nothing leaves the device
///
/// `SystemLanguageModel` is Apple Intelligence's on-device model. It uses no network
/// and has no API key. **The premise that the elder's words never leave the device** ties directly to this project's
/// consent wording, so switching to a server LLM would require obtaining consent again first.
///
/// ## Requires iOS 26
///
/// The deployment target is iOS 17, so it's gated with `@available`. On devices that can't use it,
/// `availability` explains why as a string, and **the session keeps running in seed-question mode** —
/// a lack of understanding is no reason for the conversation to stop.
@Observable
final class FactExtractor {

    /// Shows exactly why it can't be used. **"Unavailable" alone gives staff nothing to act on** —
    /// it separates whether turning on Apple Intelligence will do, or the device simply can't.
    enum Availability: Equatable {
        case ready
        /// The model is downloading. It will be available again shortly.
        case preparing
        case unsupportedOS
        case deviceNotEligible
        case notEnabled
        case unknown(String)

        var isReady: Bool { self == .ready }

        /// One line used as is on the staff screen.
        var label: String {
            switch self {
            case .ready:            "Ready · on-device"
            case .preparing:        "Model downloading — try again shortly"
            case .unsupportedOS:    "Needs iPadOS 26 or later"
            case .deviceNotEligible: "This iPad can't run Apple Intelligence"
            case .notEnabled:       "Turn on Apple Intelligence in Settings"
            case let .unknown(why): why
            }
        }
    }

    private(set) var availability: Availability = .unknown("Not checked yet")
    private(set) var isWorking = false
    /// The last failure reason. If it fails silently, staff can't even tell whether understanding is running.
    private(set) var lastError: String?

    init() { refreshAvailability() }

    func refreshAvailability() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else {
            availability = .unsupportedOS
            return
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            availability = .ready
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible:         availability = .deviceNotEligible
            case .appleIntelligenceNotEnabled: availability = .notEnabled
            case .modelNotReady:             availability = .preparing
            @unknown default:                availability = .unknown("Unavailable")
            }
        @unknown default:
            availability = .unknown("Unavailable")
        }
        #else
        availability = .unsupportedOS
        #endif
    }

    // MARK: - Extraction

    /// Feeds in the question and answer together to extract one fact.
    ///
    /// - Parameters:
    ///   - question: what the robot just said. **Without it, the answer alone can't determine the kind** —
    ///     a single `"Norfolk"` doesn't say whether it's the hometown or somewhere visited last weekend.
    ///   - answer: the elder's words exactly as transcribed.
    /// - Returns: `nil` if there's nothing to extract. **Nothing missing is made up** —
    ///   making a fact out of an empty answer or `"Well, I don't know"` means the next session opens with a memory that never existed.
    func extract(question: String, answer: String) async -> Candidate? {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        guard availability.isReady else { return nil }

        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }

        isWorking = true
        defer { isWorking = false }

        do {
            let session = LanguageModelSession(instructions: Self.instructions)
            let reply = try await session.respond(to: Self.prompt(question: question,
                                                                 answer: trimmed),
                                                  generating: Extraction.self)
            lastError = nil
            return reply.content.candidate
        } catch {
            lastError = String(describing: error)
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - Result

    /// A candidate before going into the store. **A `Fact` isn't created right away** —
    /// staff must be able to check and correct it, and it must be discarded if confidence is low.
    struct Candidate: Equatable {
        var subject: String
        var kind: FactKind
        var detail: String
        /// 0…1. If low, it isn't saved.
        var confidence: Double
    }

    // MARK: - Prompt

    /// **This prompt is where the product principles are upheld.** Unless the model is told explicitly
    /// "leave it blank if you don't know", it will always make up something plausible. A made-up fact becomes the next session's
    /// opener and **hands the elder back a memory they never had as if it were fact.**
    private static let instructions = """
        You extract one memorable fact from what an older adult said to a companion robot.
        The fact becomes a topic the robot will bring up next time, so it must be
        something the person would recognise as their own.

        subject — the specific thing they named, not the category it belongs to.
        Prefer the proper noun they used. This is the single most important field.
          "my father was in the Navy, but mostly Norfolk"  -> Norfolk        NOT upbringing
          "just me and the cat, my daughter Ruth calls"    -> Ruth           NOT family
          "I taught fourth grade for thirty years"         -> teaching       NOT work
          "we had a peach orchard out back"                -> peach orchard  NOT childhood
        Keep their own wording. 1-4 words. Never a category label such as
        upbringing, family, work, hometown, childhood, memories.
        Never a bare pronoun — she, he, they, it, we. If you cannot tell who or
        what a pronoun refers to, that is not a fact you can file: use 0 confidence.

        kind — person, place, event, or thing.

        detail — one short sentence about the subject, in their words.
        Do not echo the whole answer back.

        confidence — how sure you are this is a real fact they stated.
          1.0  they named it plainly           "I grew up in Norfolk"
          0.7  they named it in passing        "mostly Norfolk, I suppose"
          0.4  you had to infer which thing they meant
          0.0  no concrete fact at all
        Use 0.0 for greetings, "I don't know", "I don't remember", feelings with
        no subject, or silence. Leave subject empty when confidence is 0.

        Use ONLY what the person actually said. Never infer a fact they did not state.

        """

    private static func prompt(question: String, answer: String) -> String {
        """
        The robot asked: "\(question.replacingOccurrences(of: "\n", with: " "))"
        The person answered: "\(answer)"
        """
    }
}

// MARK: - Structured output

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension FactExtractor {
    /// The template the model fills in. **Not received as free text and parsed** —
    /// a parse failure becomes a silent failure, and the `Fact` ends up empty.
    @Generable
    struct Extraction {
        /// If only this comes out it isn't a fact — who it refers to won't survive into the next session.
        static let pronouns: Set<String> = [
            "she", "he", "they", "it", "we", "i", "you", "him", "her", "them", "us",
            "this", "that", "these", "those", "someone", "somebody", "something",
        ]

        @Guide(description: "Short noun phrase naming the topic, 1-4 words. Empty if there is no fact.")
        var subject: String

        @Guide(description: "One of: person, place, event, thing")
        var kind: String

        @Guide(description: "One short sentence in the person's own words about the subject.")
        var detail: String

        @Guide(description: "0.0 to 1.0. Use 0.0 when the answer states no concrete fact.")
        var confidence: Double

        var candidate: Candidate? {
            let name = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, confidence > 0 else { return nil }
            // **The prompt alone doesn't stop it.** On a device on 2026-09-01, `"She did great"`
            // produced the subject `She`. Left as is, the next session would open with
            // "Last time you mentioned She".
            guard !Self.pronouns.contains(name.lowercased()) else { return nil }
            return Candidate(subject: name,
                             kind: FactKind(rawValue: kind.lowercased()) ?? .event,
                             detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                             confidence: min(max(confidence, 0), 1))
        }
    }
}
#endif
