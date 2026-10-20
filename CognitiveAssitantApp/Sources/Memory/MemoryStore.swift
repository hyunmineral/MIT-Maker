import Foundation
import SwiftData

/// Queries against the memory store.
///
/// Gathers queries in one place so views don't handle `ModelContext` directly. In particular **the opener lookup**
/// (`opener(for:)`) is where principle 2 is carried out, and must be called with the same rules from several screens.
struct MemoryStore {
    var context: ModelContext

    // MARK: - Elder

    /// All enrolled elders. Sorted by name.
    func allElders() throws -> [Elder] {
        try context.fetch(
            FetchDescriptor<Elder>(sortBy: [SortDescriptor(\.name)])
        )
    }

    /// Today's roster. Currently everyone enrolled, but once centre attendance is integrated only this changes.
    func todayRoster() throws -> [Elder] {
        try allElders()
    }

    @discardableResult
    func addElder(name: String,
                  honorific: Honorific? = nil,
                  familyName: String? = nil,
                  invitedFirstName: Bool = false,
                  birthYear: Int? = nil,
                  hometown: String? = nil) -> Elder {
        let elder = Elder(name: name, honorific: honorific, familyName: familyName,
                          invitedFirstName: invitedFirstName,
                          birthYear: birthYear, hometown: hometown)
        context.insert(elder)
        return elder
    }

    // MARK: - Face

    /// Targets for automatic recognition. **Only people who are approved and have a face enrolled** come back.
    func faceGallery() throws -> FaceGallery {
        FaceGallery(elders: try allElders())
    }

    func elder(with id: PersistentIdentifier) -> Elder? {
        context.model(for: id) as? Elder
    }

    /// Enrols one face.
    ///
    /// **Several are accumulated.** The print changes with head angle and lighting, so keeping only one
    /// means the same person isn't recognised. `FaceGallery` uses the closest of them.
    func addFaceEmbedding(_ print: Data, to elder: Elder, limit: Int = 5) {
        elder.faceEmbeddings.append(print)
        if elder.faceEmbeddings.count > limit {
            elder.faceEmbeddings.removeFirst(elder.faceEmbeddings.count - limit)
        }
    }

    // MARK: - Session

    /// This elder's session today. Used for the status text in the roster.
    func todaySession(for elder: Elder) -> Session? {
        let start = Calendar.current.startOfDay(for: .now)
        return elder.sessions
            .filter { $0.startedAt >= start }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    /// The most recently **finished** session. A session in progress can't be the basis for an opener.
    func lastCompletedSession(for elder: Elder) -> Session? {
        elder.sessions
            .filter { $0.endedAt != nil }
            .max(by: { $0.startedAt < $1.startedAt })
    }

    @discardableResult
    func startSession(for elder: Elder) -> Session {
        let session = Session(elder: elder)
        context.insert(session)
        return session
    }

    /// Closes the session, leaving the next opener topic.
    func endSession(_ session: Session, nextOpenerTopic: String?) {
        session.endedAt = .now
        session.nextOpenerTopic = nextOpenerTopic
    }

    /// Discards the session without keeping it as a record.
    ///
    /// Used for **sessions with no utterances at all**, such as when the app was turned on and off or only the person was switched.
    /// Closing it as is would count it as a 'completed session', inflating the cumulative count,
    /// and since it has no topic it would overwrite the next opener with `nil`, cutting principle 2.
    func discard(_ session: Session) {
        context.delete(session)
    }

    // MARK: - Opener — where principle 2 is carried out

    /// What to open this elder's session with.
    ///
    /// There is an order of priority.
    /// 1. **The topic the last session previewed** — if the wrap-up promised "Tell me about your sister next time",
    ///    that comes first. Keeping promises is the heart of a sense of connection.
    /// 2. The last topic covered in the previous session
    /// 3. The most frequently mentioned old fact — well-preserved long-term memory
    /// 4. Otherwise `nil` — it's the first session. Collect a first story instead of an opener
    func opener(for elder: Elder) -> Opener? {
        if let last = lastCompletedSession(for: elder) {
            if let promised = last.nextOpenerTopic, !promised.isEmpty {
                return Opener(topic: promised, source: .promised, session: last)
            }
            if let recent = last.topics.last {
                return Opener(topic: recent, source: .lastTopic, session: last)
            }
        }
        if let anchorFact = elder.facts.max(by: { $0.mentionCount < $1.mentionCount }) {
            return Opener(topic: anchorFact.subject, source: .longTermAnchor, session: nil)
        }
        return nil
    }

    struct Opener {
        enum Source {
            /// The topic the last session said it would ask about next
            case promised
            /// The last topic of the previous session
            case lastTopic
            /// A long-term memory mentioned several times
            case longTermAnchor
        }

        var topic: String
        var source: Source
        /// The session it's based on. Used for the memory card's "Last session · July 20".
        var session: Session?
    }

    // MARK: - Fact

    /// Records a fact the elder said.
    ///
    /// If the same topic already exists with different content, it's kept as **fact drift**.
    /// Not overwritten — the comparison history itself is the raw data for the long-term memory consistency metric.
    @discardableResult
    func record(subject: String, kind: FactKind, detail: String,
                for elder: Elder, at date: Date = .now) -> Fact {
        if let existing = elder.facts.first(where: { $0.subject == subject }) {
            existing.mentionCount += 1
            existing.lastMentionedAt = date
            if existing.detail != detail {
                // **Keep the value from before the change.** Putting in the new value would make the first statement
                // disappear — `Fact.detail` is already the latest, so stacking the new value again
                // leaves nothing to compare against. That pair is exactly what the consistency card shows.
                let revision = FactRevision(detail: existing.detail, at: date, fact: existing)
                context.insert(revision)
                existing.revisions.append(revision)
                existing.detail = detail
            }
            return existing
        }

        let fact = Fact(subject: subject, kind: kind, detail: detail,
                        firstMentionedAt: date, elder: elder)
        context.insert(fact)
        elder.facts.append(fact)
        return fact
    }

    /// Number of drifted facts / total number of facts. Numerator and denominator of the long-term memory consistency metric.
    func consistency(for elder: Elder) -> (shaken: Int, total: Int) {
        let total = elder.facts.count
        let shaken = elder.facts.filter { !$0.revisions.isEmpty }.count
        return (shaken, total)
    }

    // MARK: - Anchor

    @discardableResult
    func plantAnchor(prompt: String, answer: String, in session: Session,
                     at date: Date = .now) -> RecallAnchor {
        let anchor = RecallAnchor(prompt: prompt, answer: answer, plantedAt: date, session: session)
        context.insert(anchor)
        session.anchors.append(anchor)
        return anchor
    }

    /// Anchors due to be asked back. Checked at a natural point during the session.
    func dueAnchors(in session: Session) -> [RecallAnchor] {
        session.anchors.filter(\.isDue)
    }

    func probe(_ anchor: RecallAnchor, outcome: AnchorOutcome, at date: Date = .now) {
        anchor.probedAt = date
        anchor.outcome = outcome
    }

    /// Recall rate. The average of the verdict weights.
    ///
    /// **Only verdicts that met a valid delay (6 minutes or more) count.** Anchors not yet asked back or asked back
    /// too early aren't short-term memory measurements, so they're excluded — which is why it can be `nil`.
    func recallRate(in session: Session) -> Double? {
        let scored = session.anchors
            .filter(\.isValidProbe)
            .compactMap(\.outcome)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0) { $0 + $1.score } / Double(scored.count)
    }

    /// Among anchors not yet asked back, the one that comes due first. Used for the countdown.
    func pendingAnchor(in session: Session) -> RecallAnchor? {
        session.anchors
            .filter { $0.probedAt == nil }
            .min(by: { $0.probeDueAt < $1.probeDueAt })
    }

    // MARK: - Utterance

    @discardableResult
    func record(utterance text: String, isElder: Bool, in session: Session,
                topic: String? = nil, at date: Date = .now) -> Utterance {
        let utterance = Utterance(text: text, at: date, isElder: isElder,
                                  topic: topic, session: session)
        context.insert(utterance)
        session.utterances.append(utterance)
        if let topic, !session.topics.contains(topic) {
            session.topics.append(topic)
        }
        return utterance
    }

    /// Average word count of the elder's utterances in this session.
    ///
    /// **Never compared with other elders.** Some people are naturally quiet — only change against
    /// the personal baseline is looked at (`Docs/03_product-design.md` 4-3).
    func averageWordCount(in session: Session) -> Double? {
        let elderUtterances = session.utterances.filter(\.isElder)
        guard !elderUtterances.isEmpty else { return nil }
        let total = elderUtterances.reduce(0) { $0 + $1.wordCount }
        return Double(total) / Double(elderUtterances.count)
    }

    /// Personal baseline — the average word count of the first session. Later sessions are compared with it.
    func speechBaseline(for elder: Elder) -> Double? {
        guard let first = elder.sessions
            .filter({ $0.endedAt != nil })
            .min(by: { $0.startedAt < $1.startedAt })
        else { return nil }
        return averageWordCount(in: first)
    }

    // MARK: - Metric

    func record(metric key: String, percent: Double, value: String, note: String,
                in session: Session, at date: Date = .now) {
        let sample = MetricSample(key: key, percent: percent, value: value,
                                  note: note, at: date, session: session)
        context.insert(sample)
        session.metrics.append(sample)
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }
}
