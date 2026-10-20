import Foundation
import SwiftData

/// The memory store (stage 0.5).
///
/// This product's principle 2 is **"old memories fuel the conversation"**, and the session opener always
/// starts with 'that story from last time'. **Without a store there is no last time** — however well STT and the LLM
/// are wired up, everything vanishes the moment the session ends. That's why it comes before stage 1 (STT).
/// Rationale in `Docs/05_implementation-roadmap.md` section 0.
///
/// ## Storage location
///
/// **Everything is on-device.** Under personal-data protection law, face embeddings are **biometric (sensitive) data**,
/// and conversation transcripts and cognitive metrics are health-related data. None of it leaves the device
/// (`Docs/03_product-design.md` section 9).
///
/// ## Colours are not stored
///
/// Metrics store only values and verdicts; colour is applied on screen. Colour is presentation, not data,
/// and changing the palette must not touch stored records.

// MARK: - Elder

@Model
final class Elder {
    /// Full name. There may be people with the same name, so it isn't used as an identifier.
    var name: String
    /// Honorific (`Honorific.rawValue`). Stored as a string to keep the schema simple.
    var honorificRaw: String?
    /// Surname. If empty, it's inferred from the full name — see `FormOfAddress`.
    var familyName: String?
    /// **Whether the person asked to be called by first name.** Defaults to false (see the `FormOfAddress` comments).
    var invitedFirstName: Bool = false
    var birthYear: Int?
    /// Hometown — a seed of long-term memory collected in the first session.
    var hometown: String?
    var enrolledAt: Date
    /// Becomes a target for automatic recognition only after staff approve.
    var isApproved: Bool

    /// Face embeddings. **They never leave the device.**
    /// Empty until stage 3 (Vision); sessions are started by staff picking from the roster.
    var faceEmbeddings: [Data]

    @Relationship(deleteRule: .cascade, inverse: \Session.elder)
    var sessions: [Session] = []

    @Relationship(deleteRule: .cascade, inverse: \Fact.elder)
    var facts: [Fact] = []

    /// Honorific. Stored as a string, read as an enum.
    var honorific: Honorific? {
        get { honorificRaw.flatMap(Honorific.init(rawValue:)) }
        set { honorificRaw = newValue?.rawValue }
    }

    /// **The name the robot calls out loud.** The script, opener and TTS use this value.
    var spokenName: String {
        FormOfAddress.spoken(fullName: name,
                             honorific: honorific,
                             familyName: familyName,
                             invitedFirstName: invitedFirstName)
    }

    init(name: String,
         honorific: Honorific? = nil,
         familyName: String? = nil,
         invitedFirstName: Bool = false,
         birthYear: Int? = nil,
         hometown: String? = nil,
         enrolledAt: Date = .now,
         isApproved: Bool = true,
         faceEmbeddings: [Data] = []) {
        self.name = name
        self.honorificRaw = honorific?.rawValue
        self.familyName = familyName
        self.invitedFirstName = invitedFirstName
        self.birthYear = birthYear
        self.hometown = hometown
        self.enrolledAt = enrolledAt
        self.isApproved = isApproved
        self.faceEmbeddings = faceEmbeddings
    }
}

// MARK: - Session

@Model
final class Session {
    var startedAt: Date
    var endedAt: Date?
    var elder: Elder?

    /// Topics covered in this session. Used to pick the next session's opener.
    var topics: [String]
    /// The next topic previewed in the wrap-up. **Where principle 2 is carried out** —
    /// the next session opens with this value.
    var nextOpenerTopic: String?

    @Relationship(deleteRule: .cascade, inverse: \Utterance.session)
    var utterances: [Utterance] = []

    @Relationship(deleteRule: .cascade, inverse: \RecallAnchor.session)
    var anchors: [RecallAnchor] = []

    @Relationship(deleteRule: .cascade, inverse: \MetricSample.session)
    var metrics: [MetricSample] = []

    var durationMinutes: Int {
        guard let endedAt else { return 0 }
        return max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }

    init(startedAt: Date = .now,
         endedAt: Date? = nil,
         elder: Elder? = nil,
         topics: [String] = [],
         nextOpenerTopic: String? = nil) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.elder = elder
        self.topics = topics
        self.nextOpenerTopic = nextOpenerTopic
    }
}

// MARK: - Utterance

@Model
final class Utterance {
    var text: String
    var at: Date
    var isElder: Bool
    /// Word count. The raw data for the speech-amount metric (`Docs/03_product-design.md` 4-3).
    var wordCount: Int
    var topic: String?
    var session: Session?

    init(text: String, at: Date = .now, isElder: Bool, topic: String? = nil,
         session: Session? = nil) {
        self.text = text
        self.at = at
        self.isElder = isElder
        self.wordCount = Utterance.countWords(text)
        self.topic = topic
        self.session = session
    }

    /// Word count, split on whitespace. In Korean, space-separated words are close to units of meaning, so even without
    /// morphological analysis it's good enough to track speech-amount trends. Only change against the personal baseline is looked at,
    /// so absolute accuracy doesn't matter.
    static func countWords(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

// MARK: - Fact (memory node)

enum FactKind: String, Codable, CaseIterable {
    case person, place, event, thing
}

/// One fact the elder said. Becomes a node in the memory map.
@Model
final class Fact {
    /// Topic name. "the peach orchard" · "Granddaughter Emma"
    var subject: String
    var kindRaw: String
    /// The most recently confirmed content. "worked there at twenty"
    var detail: String
    var firstMentionedAt: Date
    var lastMentionedAt: Date
    var mentionCount: Int
    var elder: Elder?

    /// History of the same fact being told differently. **Recorded as 'changed', not 'wrong'** —
    /// autobiographical memory in later life is naturally reconstructed, and what matters is not individual mismatches but
    /// the trend of accumulated drift (`Docs/03_product-design.md` 4-2).
    @Relationship(deleteRule: .cascade, inverse: \FactRevision.fact)
    var revisions: [FactRevision] = []

    var kind: FactKind {
        get { FactKind(rawValue: kindRaw) ?? .event }
        set { kindRaw = newValue.rawValue }
    }

    init(subject: String, kind: FactKind, detail: String,
         firstMentionedAt: Date = .now, elder: Elder? = nil) {
        self.subject = subject
        self.kindRaw = kind.rawValue
        self.detail = detail
        self.firstMentionedAt = firstMentionedAt
        self.lastMentionedAt = firstMentionedAt
        self.mentionCount = 1
        self.elder = elder
    }
}

@Model
final class FactRevision {
    /// **What she used to say before it changed.** "worked there at twenty"
    ///
    /// `Fact.detail` holds the latest statement. Stacking the new value here would make the first statement
    /// disappear, **leaving nothing to compare against** — that pair is exactly what the consistency metric looks at.
    var detail: String
    /// When it changed.
    var at: Date
    var fact: Fact?

    init(detail: String, at: Date = .now, fact: Fact? = nil) {
        self.detail = detail
        self.at = at
        self.fact = fact
    }
}

// MARK: - Anchor (short-term memory)

enum AnchorOutcome: String, Codable, CaseIterable {
    case exact      // exact recall
    case partial    // right category but different details
    case hinted     // recalled after a hint
    case missed     // not recalled even after a hint

    var label: String {
        switch self {
        case .exact:   "exact recall"
        case .partial: "partial recall"
        case .hinted:  "recalled with a hint"
        case .missed:  "no recall"
        }
    }

    /// Weight for computing the recall rate.
    var score: Double {
        switch self {
        case .exact:   1.0
        case .partial: 0.5
        case .hinted:  0.25
        case .missed:  0.0
        }
    }
}

/// One fact planted early in the session and brought back 8 minutes later.
///
/// **An anchor must come from the elder's own speech.** The moment the robot presents a word to memorise,
/// this product becomes a test, and principles 1 and 3 collapse together
/// (`Docs/03_product-design.md` 4-1).
@Model
final class RecallAnchor {
    /// The question that planted the anchor. "What did you have for lunch today?"
    var prompt: String
    /// The fact the elder answered. "tomato soup"
    var answer: String
    var plantedAt: Date
    /// When to ask back. Currently the planting time + 8 minutes.
    var probeDueAt: Date
    var probedAt: Date?
    var outcomeRaw: String?
    var session: Session?

    var outcome: AnchorOutcome? {
        get { outcomeRaw.flatMap(AnchorOutcome.init(rawValue:)) }
        set { outcomeRaw = newValue?.rawValue }
    }

    /// The actual delay. **The same verdict is worth something different if the delay is short.**
    var delaySeconds: TimeInterval? {
        guard let probedAt else { return nil }
        return probedAt.timeIntervalSince(plantedAt)
    }

    var isDue: Bool { probedAt == nil && Date.now >= probeDueAt }

    /// Time remaining until asking back. Used for the countdown on the staff panel.
    var remainingUntilDue: TimeInterval? {
        guard probedAt == nil else { return nil }
        return max(0, probeDueAt.timeIntervalSince(.now))
    }

    /// **Whether this verdict can count as a short-term memory measurement.**
    ///
    /// Delayed recall is all about the delay. Asking back one minute after planting the anchor measures working memory,
    /// not delayed recall. Verdicts that fall short of 75% of the standard interval are recorded but
    /// **excluded from the recall-rate calculation** — values from demos or operator mistakes must not pollute the metric.
    var isValidProbe: Bool {
        guard let delay = delaySeconds else { return false }
        return delay >= RecallAnchor.minimumValidDelay
    }

    /// The standard interval for delayed recall. Anything shorter isn't a short-term memory measurement.
    static let probeDelay: TimeInterval = 8 * 60
    /// The lower bound accepted as a valid delay (75% of the standard).
    static let minimumValidDelay: TimeInterval = 6 * 60

    init(prompt: String, answer: String, plantedAt: Date = .now,
         session: Session? = nil) {
        self.prompt = prompt
        self.answer = answer
        self.plantedAt = plantedAt
        self.probeDueAt = plantedAt.addingTimeInterval(RecallAnchor.probeDelay)
        self.session = session
    }
}

// MARK: - Metric

/// One metric produced in a session.
///
/// **Colour is not stored.** Colour is presentation, and changing the palette must not touch records.
@Model
final class MetricSample {
    /// rawValue of `Metric.Key`.
    var key: String
    var percent: Double
    /// Display value used as is on screen. "1/1" · "92%" · "Neutral"
    var value: String
    var note: String
    var at: Date
    var session: Session?

    init(key: String, percent: Double, value: String, note: String,
         at: Date = .now, session: Session? = nil) {
        self.key = key
        self.percent = percent
        self.value = value
        self.note = note
        self.at = at
        self.session = session
    }
}
