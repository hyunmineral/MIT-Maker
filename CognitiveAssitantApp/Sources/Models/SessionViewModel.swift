import CoreGraphics
import SwiftData
import SwiftUI

/// State of a conversation session with one elder.
///
/// In stage 0.5 it **was connected to the memory store.** When a session starts it creates a `Session`,
/// records utterances, metrics and anchors, and on finishing closes with the next opener topic previewed.
/// Before the store was attached, everything vanished the moment the session ended —
/// which made principle 2 ("old memories fuel the conversation") impossible.
@Observable
final class SessionViewModel {

    enum Person {
        case known      // Dorothy Miller
        case stranger   // Margaret Walsh
    }

    var person: Person = .known
    private(set) var stepIndex: Int = 0

    /// Whether the metrics overlay is shown.
    ///
    /// **Off by default.** It used to be an always-visible panel at the bottom of the screen, so on was the default,
    /// but now it's an overlay that covers the whole elder stage — during a session staff should be watching
    /// the elder, not graphs (`Docs/04_screen-design.md` section 2).
    var showsStaffOverlay: Bool = false

    var log: [LogEntry] = []
    var metrics: [Metric] = Metric.baseline
    /// Whether there was any recall failure in this session
    private(set) var missed: Bool = false

    // MARK: - Store

    @ObservationIgnored private var store: MemoryStore?
    @ObservationIgnored private var elder: Elder?
    @ObservationIgnored private var session: Session?

    // MARK: - The person the camera identified

    /// The person recognised by face. **`nil` means the existing demo behaviour of the script looking up by name.**
    @ObservationIgnored private var arrivedElder: Elder?
    /// The face of someone met for the first time. Enrolled with this the moment the name is confirmed.
    @ObservationIgnored private var arrivedFace: CGImage?
    /// Whether **the camera opened** this session. If true, no lookup is done by the script person's name —
    /// an unknown person in front of the robot must not be recorded as the seed's Margaret Walsh.
    @ObservationIgnored private var cameFromCamera = false
    /// Whether the identity has been settled. **Until it is, nothing advances past the greeting** —
    /// advancing would mean asking someone known for their name, or calling an unknown person by someone else's name.
    @ObservationIgnored private(set) var isIdentified = false

    /// What was said before enrolment.
    ///
    /// Someone met for the first time has no `Elder` until the name is confirmed, and so no `Session` either.
    /// Throwing away what was said in the meantime **would lose the whole first-meeting conversation** — the first
    /// things that person said to the robot, and the speech-amount baseline (`Docs/03_product-design.md` 4-3)
    /// would be that much emptier. So it's held and attached once it's settled who it is.
    @ObservationIgnored private var pendingUtterances:
        [(text: String, isElder: Bool, topic: String?, at: Date)] = []

    /// Whether it's still working out who it is. The stretch during which the camera must stay on.
    var awaitingIdentification: Bool {
        cameFromCamera && !isIdentified && stepIndex <= SessionScript.recognitionIndex
    }

    /// The name. Filled in by STT and **correctable by staff.** Saved only when confirm is pressed.
    var typedName: String = ""

    /// **What was actually said** at this step. Recorded as the transcript when staff press a choice.
    ///
    /// Unlike the name and first story (`Capture`), it **doesn't need staff confirmation.** If those two are wrong,
    /// the wrong name gets called next time or a memory that never existed appears, but this is the conversation transcript,
    /// and adding a confirm step would make staff type at every step — then they can't watch the elder.
    var heardAnswer = ""

    /// Takes the transcribed speech as this step's answer. **Anything the robot heard of its own voice is discarded.**
    ///
    /// Even with echo cancellation on (`NameListener`'s `.voiceChat`) it isn't complete, and elders sometimes
    /// read the question back word for word. Both have the same result: **the robot's line being saved as the elder's
    /// utterance.** It actually happened on a device on 2026-09-01 —
    /// `"What did you have for lunch today?"` became the elder's answer verbatim.
    ///
    /// The verdict is based only on **whether everything heard is contained in the line**. Blocking partial matches
    /// too would also discard normal speech that echoes the question while answering,
    /// like `"What did I have? Soup."`.
    func noteHeard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !SpeechEcho.isEcho(heard: trimmed, caption: step.caption) else { return }
        heardAnswer = trimmed
    }

    /// Extracts facts from the elder's speech. **It takes about 10 seconds on a device** —
    /// so it runs in the background without blocking the lines.
    @ObservationIgnored let understanding = FactExtractor()

    /// Chooses what to say next. **The robot doesn't yet speak on its own** —
    /// it appears as a suggestion on the staff panel and goes out only when staff press it.
    ///
    /// This is one rung of the ladder this project is climbing. Stage-0 fixed script →
    /// **suggestions staff choose** → autonomy. No rungs are skipped.
    /// Unverified sentences never reach the elder, and **the rate at which staff press
    /// becomes the quality metric** — no separate scoring mechanism is needed.
    @ObservationIgnored let planner = ReplyPlanner()

    /// The suggestion to show staff. Pressing it replaces this step's line with it.
    private(set) var suggestion: ReplyPlanner.Plan?
    private(set) var isPlanning = false

    /// A counter that tells the view the line has changed. **`stepIndex` won't do** —
    /// accepting a suggestion keeps the step the same and only changes the line.
    private(set) var captionRevision = 0
    /// Number of facts saved in this session.
    private var factsThisSession = 0

    /// How many times the name has been asked again. Stops asking once it exceeds `SessionScript.nameReaskLimit`.
    private(set) var nameAttempts = 0
    /// It has asked again as much as it should. Staff need to write it down.
    var nameReaskExhausted: Bool { nameAttempts > SessionScript.nameReaskLimit }

    /// Whether **the elder's answer needs to be written down** at this step.
    ///
    /// Used in three places. All three are places where the answer goes into the store —
    /// let it slip and there's no memory next session.
    enum Capture {
        /// The name of someone met for the first time. Enrolled together with the face.
        case name
        /// The first story — whichever of hometown, family or occupation is missing. Becomes the next session's opener.
        case seed(SessionScript.SeedQuestion)

        var placeholder: String {
            switch self {
            case .name:            "Name"
            case let .seed(q):     q.placeholder
            }
        }

        var confirmLabel: String {
            switch self {
            case .name: "Confirm name"
            case .seed: "Save it"
            }
        }
    }

    var capture: Capture? {
        if person == .stranger {
            if stepIndex == SessionScript.askNameIndex { return .name }
            // Someone met for the first time has no facts at all, so it's always hometown.
            if stepIndex == SessionScript.seedMemoryIndex {
                return .seed(pendingSeed ?? .hometown)
            }
            return nil
        }
        // Write things down only where something is being planted. Which place that is was already decided when assembling the script.
        if stepIndex == SessionScript.openerIndex, opener == nil, let seed = pendingSeed {
            return .seed(seed)
        }
        if stepIndex == SessionScript.reminiscenceIndex, let seed = seedForReminiscence {
            return .seed(seed)
        }
        return nil
    }

    /// When to show the name field. True only at the 'ask name' step of the first-meeting script.
    var needsName: Bool { capture != nil }

    /// **Whether this is a step that transcribes a free answer.**
    ///
    /// A listening step with no `capture`. Until now the elder's utterance here was saved as
    /// the script label staff clicked (`"She did great. She's a good student"`).
    /// Words never said were becoming the raw data for the speech-amount and vocabulary metrics.
    var isCapturingAnswer: Bool { step.listening && capture == nil }

    /// What the camera recognised, as one line on the staff panel. Shows why auto-greet made that call.
    private(set) var arrivalNote: String?
    /// The anchor planted this session. Judged at the delayed recall step.
    @ObservationIgnored private var plantedAnchor: RecallAnchor?

    private(set) var opener: MemoryStore.Opener?

    /// The script with the opener injected.
    ///
    /// Rebuilding it on every access changes `SessionStep.id` · `Choice.id` every time,
    /// making SwiftUI swap out the whole screen. **Build it once and hold on to it.**
    private(set) var steps: [SessionStep] = SessionScript.known

    // MARK: - Consent — may this be recorded?

    /// **Without self/guardian consent, nothing is recorded.**
    ///
    /// The consent screen's description says *"without it, no session can be recorded"*, yet the code
    /// didn't have a single line checking it (found 2026-09-10). The other three (voice · biometric · overseas transfer)
    /// really were locking features, so **only this item behaved differently from its description.**
    ///
    /// Reading isn't blocked. Records already saved remained under the consent at that time,
    /// and deleting them is a separate decision. What's blocked here is **new writes**.
    var isRecording: Bool { Consent.isGranted(.personal) }

    /// One line to show on the staff panel. That recording is off must be visible —
    /// run a whole session without knowing and that conversation is saved nowhere.
    var recordingBanner: String? {
        isRecording ? nil : "Not recording · participant consent is off"
    }

    /// Called once after the view gets its `modelContext`.
    func attach(context: ModelContext) {
        guard store == nil else { return }
        store = MemoryStore(context: context)
        beginSession()
    }

    // MARK: - Session lifetime

    /// Finds the elder for this script and opens a session.
    ///
    /// The stage-0 script is fixed per person, so it looks up by name. In stage 3 (Vision) face recognition,
    /// and until then staff choosing from the roster, take this role.
    private func beginSession() {
        guard let store else { return }
        openedAt = .now
        if let arrived = arrivedElder {
            // If someone was recognised by face, it's them. Don't overwrite with a name lookup.
            elder = arrived
        } else if cameFromCamera {
            // The camera opened it but didn't recognise anyone — **we don't know who it is yet.**
            // Don't open a session until enrolment is finished.
            elder = nil
        } else {
            let name = (person == .known) ? DemoPeople.known : DemoPeople.stranger
            elder = (try? store.allElders())?.first { $0.name == name }
        }

        guard let elder else {
            rebuildSteps()
            return
        }
        opener = store.opener(for: elder)

        guard isRecording else {
            // The conversation goes on but **nothing is written to the store.**
            rebuildSteps()
            refreshMetrics()
            log.insert(LogEntry(tag: "Not recording",
                                text: "Participant & family consent is off — "
                                    + "nothing from this session will be saved",
                                color: Theme.red), at: 0)
            return
        }

        session = store.startSession(for: elder)
        factsThisSession = 0
        heardAnswer = ""
        rebuildSteps()
        try? store.save()
        refreshMetrics()
    }

    /// Closes the session and **previews the next session's opener.** This is where principle 2 carries on.
    private func endSession() {
        guard let store, let session else { return }
        defer { self.session = nil }

        // The app was turned on and off or only the person was switched — a session with no utterances is not a record.
        // Closing it as is would count it as a 'completed session', and with no topic it would overwrite
        // the next opener with nil, **breaking the link of principle 2.**
        guard !session.utterances.isEmpty else {
            store.discard(session)
            try? store.save()
            return
        }

        // **Leave one set of metrics.** The cognitive report's 8-week trend reads these samples.
        recordMetricSamples(in: session, store: store)

        // Pass the last topic covered today to the next opener. The script is fixed, so for now
        // the recall conversation's topic (peach orchard) comes. In stage 2 the conversation engine decides.
        store.endSession(session, nextOpenerTopic: session.topics.last)
        try? store.save()
    }

    // MARK: - Script

    private func rebuildSteps() {
        var next = (person == .known) ? SessionScript.known : SessionScript.stranger

        // If it's someone the camera recognised, **call them by their name.** Leaving the script's hard-coded
        // Dorothy would mean calling someone else Dorothy.
        if person == .known, let elder, elder.name != DemoPeople.known {
            next[SessionScript.greetingIndex].caption = "\(elder.spokenName)!\nYou made it."
        }

        if person == .known {
            if let opener {
                next[SessionScript.openerIndex] = SessionScript.openerStep(
                    topic: opener.topic,
                    card: openerCard(for: opener)
                )
            } else if let elder, let seed = pendingSeed {
                // There's no previous story. There's nothing to recall, so **plant a memory.**
                next[SessionScript.openerIndex] =
                    SessionScript.seedStep(seed, introducing: elder.spokenName)
            } else if arrivedElder != nil {
                // There are facts but no previous session. Don't make anything up; ask how they've been.
                next[SessionScript.openerIndex] = SessionScript.reconnectStep()
            }

            // **[5] and [8] must be that person's too.** The orchard and sister baked into the script
            // are Dorothy's memories, and using them for someone else plants memories that never existed.
            //
            // If there's still something not yet asked, **plant a new topic** instead of recalling.
            // If all we know is the hometown, asking about the hometown at [3] and then recalling
            // the hometown again at [5] would mean telling the same story twice in one session.
            if let seed = seedForReminiscence {
                next[SessionScript.reminiscenceIndex] =
                    SessionScript.seedStep(seed, introducing: nil)
            } else {
                next[SessionScript.reminiscenceIndex] =
                    SessionScript.reminiscenceStep(topic: reminiscenceTopic)
            }
            next[SessionScript.farewellIndex] =
                SessionScript.farewellStep(topic: reminiscenceTopic)
        }

        if person == .stranger, let elder {
            next[SessionScript.seedMemoryIndex].caption =
                "Where did you\ngrow up,\n\(elder.spokenName)?"
        }

        steps = next
    }

    /// The recall conversation topic. **A fact mentioned several times = long-term memory**.
    ///
    /// It's a different kind from the opener (a recent topic). The opener is a recent memory from the last session;
    /// this is a memory built up over time. Seeing both in one session was the script's design.
    private var reminiscenceTopic: String? {
        elder?.facts.max(by: { $0.mentionCount < $1.mentionCount })?.subject
    }

    /// The first story not yet asked about. Filled one at a time, in the order hometown → family → occupation.
    private var pendingSeed: SessionScript.SeedQuestion? {
        guard let elder else { return nil }
        return SessionScript.nextSeed(missingFrom: elder.facts)
    }

    /// What to plant at the recall slot. **If the opener is already planting, that slot stays as recall** —
    /// pressing twice in one session becomes an interrogation.
    private var seedForReminiscence: SessionScript.SeedQuestion? {
        guard opener != nil else { return nil }   // if the opener slot is empty, it goes first
        return pendingSeed
    }

    // MARK: - When the camera recognises someone

    /// Called when `PresenceWatcher` confirms a person on the resting screen.
    ///
    /// **Accepted only on the resting screen.** Arriving mid-session would rewind the conversation on its own.
    /// **Someone has arrived — who it is isn't known yet.**
    ///
    /// The greeting starts right here. In both scripts the line at this point is the same,
    /// `"Hello. Come on in."`, so saying it before the identity is settled doesn't go wrong.
    /// The script being written that way was the intent itself — *outwardly it only greets, and never says
    /// out loud that it didn't recognise someone.*
    func presenceDetected() {
        guard stepIndex == 0 else { return }
        cameFromCamera = true
        isIdentified = false
        advanceFromResting()
    }

    /// When it still can't tell, **it keeps looking while making conversation.** No failure shows on screen.
    ///
    /// Doesn't add a step; only changes the line at that point — if the progress display grew to `2/11`,
    /// the session would look longer.
    /// - Returns: true if the line was changed. False if the identity was already settled.
    @discardableResult
    func stallWhileLooking() -> Bool {
        guard cameFromCamera, !isIdentified else { return false }
        guard stepIndex == SessionScript.recognitionIndex else { return false }
        guard steps.indices.contains(SessionScript.recognitionIndex) else { return false }
        steps[SessionScript.recognitionIndex].caption = SessionScript.lookingStall()
        return true
    }

    /// **It's been settled who it is.** The conclusion after several looks arrives.
    func identify(_ outcome: FaceGallery.Outcome, face: CGImage?) {
        guard cameFromCamera, !isIdentified else { return }
        guard stepIndex <= SessionScript.recognitionIndex else { return }
        isIdentified = true
        arrivedFace = face
        arrivalNote = outcome.logText

        switch outcome {
        case let .recognized(elderID, name, distance):
            if let store, let found = store.elder(with: elderID) {
                arrivedElder = found
                person = .known
                log.insert(LogEntry(tag: "Recognized",
                                    text: String(format: "%@ · distance %.3f · memory loaded",
                                                 name, distance),
                                    color: Theme.blue), at: 0)
            } else {
                becomeStranger(note: outcome.logText)
            }
        case .unknown, .ambiguous, .noFace:
            // **If unknown, don't call a name.** Go to the first-meeting script —
            // that script greets, asks the name, and carries through to enrolment.
            becomeStranger(note: outcome.logText)
        }
        reopenForArrival()
    }

    private func becomeStranger(note: String) {
        arrivedElder = nil
        person = .stranger
        log.insert(LogEntry(tag: "Unenrolled", text: note, color: Theme.amber), at: 0)
    }

    /// Re-establishes the store and script for the settled person.
    ///
    /// The reason not to use `restart(as:)` is that it resets `stepIndex` to 0.
    /// **It must not jump back to the resting screen mid-greeting** — nothing should happen on screen.
    private func reopenForArrival() {
        endSession()          // `discard`ed if there are no utterances. Up to here there never are.
        metrics = Metric.baseline
        missed = false
        plantedAnchor = nil
        typedName = ""
        nameAttempts = 0
        beginSession()        // rebuild the script and opener for this person
        stepIndex = SessionScript.recognitionIndex
    }

    /// When it didn't catch something, **has the robot ask again.**
    ///
    /// Doesn't create a new step; only changes the line at that point — adding steps would grow the progress display
    /// to `4/8`, `4/9`, making the session look longer.
    /// - Returns: true if it asked again. If false, it stops asking and hands over to staff.
    @discardableResult
    func reaskName() -> Bool {
        guard person == .stranger, typedName.isEmpty else { return false }
        guard steps.indices.contains(SessionScript.askNameIndex) else { return false }
        nameAttempts += 1
        guard nameAttempts <= SessionScript.nameReaskLimit else {
            log.insert(LogEntry(tag: "Name not heard",
                                text: "Asked \(SessionScript.nameReaskLimit)× — staff to enter it",
                                color: Theme.amber), at: 0)
            return false
        }
        steps[SessionScript.askNameIndex].caption =
            SessionScript.nameReask(attempt: nameAttempts)
        return true
    }

    /// **Whether this is a step the camera has already answered.**
    ///
    /// If it came in through auto-greet, `FaceGallery` has already settled "who is it".
    /// Asking staff to press that answer again would be the app asking a person what it already knows.
    /// **Not true for a session staff started by hand** — the recogniser didn't run then.
    var autoAdvancesCurrentStep: Bool {
        cameFromCamera && isIdentified && stepIndex == SessionScript.recognitionIndex
    }

    /// Called after the robot has finished speaking that step's line.
    func autoAdvance() {
        guard autoAdvancesCurrentStep, let choice = step.choices.first else { return }
        pick(choice)
    }

    /// Same effect as staff pressing `Someone walks up`.
    private func advanceFromResting() {
        guard stepIndex == 0, let first = steps.first?.choices.first else { return }
        pick(first)
    }

    // MARK: - Enrolling someone met for the first time

    /// Applies the name staff wrote down to the script. The line on the name-confirmation screen changes.
    ///
    /// Doesn't rebuild the step array; **fixes only that place** — rebuilding would change every `SessionStep.id`
    /// and SwiftUI would swap out the whole screen.
    func confirmTypedName() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, person == .stranger else { return }
        guard steps.indices.contains(SessionScript.enrollConfirmIndex) else { return }
        steps[SessionScript.enrollConfirmIndex].caption = "\(name) —\nis that right?"
        if steps.indices.contains(SessionScript.seedMemoryIndex) {
            steps[SessionScript.seedMemoryIndex].caption = "Where did you\ngrow up,\n\(name)?"
        }
    }

    /// **Puts the written-down answer into the store** and advances to the next step.
    ///
    /// It used to ask "Where did you grow up?" and then throw the answer away. The step was named
    /// `Seeding memory` but planted nothing — so there was no memory when the person came back.
    func commitCapture() {
        let text = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let capture, !text.isEmpty else { return }

        switch capture {
        case .name:
            confirmTypedName()
        case let .seed(question):
            if isRecording, let store, let elder {
                // The hometown also goes into `Elder.hometown`. The roster and reports use that field.
                if question == .hometown { elder.hometown = text }
                store.record(subject: text, kind: question.kind,
                             detail: question.detail, for: elder)
                try? store.save()
                log.insert(LogEntry(tag: "Memory seeded",
                                    text: "\(question.kind.rawValue.capitalized) "
                                        + "\"\(text)\" · on file",
                                    color: Theme.blue), at: 0)
            }
            typedName = ""
        }
        // **Keep exactly what was said as the transcript.** If it isn't passed, the script's "Margaret Walsh"
        // gets recorded, and words never said become raw data for the speech-amount and vocabulary metrics.
        if let choice = step.choices.first { pick(choice, spokenOverride: text) }
    }

    /// The moment the name is confirmed — **this is where the person and face are actually saved.**
    ///
    /// Until now this step was staging that only wrote a log. Now it creates an `Elder`
    /// and attaches a print made from the face captured on the resting screen. Next time they come,
    /// `FaceGallery` recognises them by this print.
    private func enrollArrivedPerson() {
        guard let store else { return }
        guard isRecording else {
            log.insert(LogEntry(tag: "Not enrolled",
                                text: "Participant & family consent is off — "
                                    + "no profile was created",
                                color: Theme.red), at: 0)
            return
        }
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            log.insert(LogEntry(tag: "Not enrolled",
                                text: "No name was entered — face was not saved",
                                color: Theme.amber), at: 0)
            return
        }

        // If the person already exists, just add the face. Staff sort out same-name duplicates in the roster.
        let existing = (try? store.allElders())?.first { $0.name == name }
        let target = existing ?? store.addElder(name: name)

        guard let face = arrivedFace, let print = FacePrinting.print(from: face),
              let data = FacePrinting.encode(print) else {
            log.insert(LogEntry(tag: "Enrolled · no face",
                                text: "\(name) was added, but the frame had no usable face",
                                color: Theme.amber), at: 0)
            attach(elder: target, store: store)
            return
        }

        store.addFaceEmbedding(data, to: target)
        log.insert(LogEntry(tag: "Enrolled",
                            text: "\(name) · \(target.faceEmbeddings.count) face(s) on file",
                            color: Theme.green), at: 0)
        attach(elder: target, store: store)
    }

    /// Makes this session that person's record from the moment of enrolment.
    private func attach(elder target: Elder, store: MemoryStore) {
        arrivedElder = target
        elder = target
        if session == nil { session = store.startSession(for: target) }
        flushPendingUtterances(into: store)
        try? store.save()
        onGalleryChanged?()
    }

    /// Moves what was said before enrolment into this session **with the original timestamps**.
    ///
    /// Changing the timestamps to now would make the conversation look bunched into one instant, breaking
    /// the metrics that look at response intervals.
    private func flushPendingUtterances(into store: MemoryStore) {
        guard let session, !pendingUtterances.isEmpty else { return }
        for line in pendingUtterances {
            store.record(utterance: line.text, isElder: line.isElder,
                         in: session, topic: line.topic, at: line.at)
        }
        log.insert(LogEntry(tag: "Transcript",
                            text: "\(pendingUtterances.count) lines from before enrollment kept",
                            color: Theme.blue), at: 0)
        pendingUtterances = []
    }

    /// Tells the screen to re-read the gallery because it has changed.
    @ObservationIgnored var onGalleryChanged: (() -> Void)?

    /// Shows the basis of the opener as a memory card.
    ///
    /// **Uses only what's in the store** — inventing a memory would amount to planting a memory
    /// the elder never had (`Docs/03_product-design.md` section 8).
    ///
    /// The body differs by basis type. In particular **`.promised` is a story not yet told**,
    /// so there can be no utterance to quote — attaching any utterance would make it look as though
    /// the elder said something unrelated to the topic.
    private func openerCard(for opener: MemoryStore.Opener) -> MemoryCard? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"

        switch opener.source {
        case .promised:
            guard let source = opener.session else { return nil }
            return MemoryCard(
                kind: "Last session · \(formatter.string(from: source.startedAt))",
                title: opener.topic,
                body: "A story they promised to tell next"
            )

        case .lastTopic:
            guard let source = opener.session else { return nil }
            // Quote only what was actually said on that topic.
            let quote = source.utterances
                .filter { $0.isElder && $0.topic == opener.topic }
                .last?.text
            return MemoryCard(
                kind: "Last session · \(formatter.string(from: source.startedAt))",
                title: opener.topic,
                body: quote.map { "\"\($0)\"" } ?? "Something from last time"
            )

        case .longTermAnchor:
            let fact = elder?.facts.first { $0.subject == opener.topic }
            return MemoryCard(
                kind: "Memory card · \(fact.map { "mentioned \($0.mentionCount)×" } ?? "long-term")",
                title: opener.topic,
                body: fact?.detail ?? "A story they have told before"
            )
        }
    }

    // MARK: - Derived values

    var step: SessionStep {
        steps[min(stepIndex, steps.count - 1)]
    }

    /// Progress display at the top in the form "Face recognition · 2/10"
    var statusWithProgress: String {
        "\(step.status) · \(stepIndex + 1)/\(steps.count)"
    }

    var personName: String {
        guard let elder else {
            if cameFromCamera {
                let typed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
                return typed.isEmpty ? "Unidentified · not enrolled" : "New · \(typed)"
            }
            return person == .known ? DemoPeople.known : "New · \(DemoPeople.stranger)"
        }
        if let year = elder.birthYear {
            let age = Calendar.current.component(.year, from: .now) - year
            return "\(elder.name) (\(age))"
        }
        return elder.name
    }

    var personMeta: String {
        guard let store, let elder else { return "Collecting baseline" }
        let completed = elder.sessions.filter { $0.endedAt != nil }.count
        guard completed > 0 else { return "Enrolled today · collecting baseline" }

        let months = max(1, Calendar.current.dateComponents(
            [.month], from: elder.enrolledAt, to: .now).month ?? 0)
        let facts = store.consistency(for: elder)
        return "Enrolled \(months) mo · \(completed) sessions · \(facts.total) facts"
    }

    var personToggleLabel: String {
        person == .known ? "Switch to new person" : "Switch to enrolled elder"
    }

    var overlayToggleLabel: String {
        showsStaffOverlay ? "Hide metrics" : "Show metrics"
    }

    // MARK: - Actions

    func pick(_ choice: Choice, spokenOverride: String? = nil) {
        if choice.resets {
            reset()
            return
        }

        record(choice, spokenOverride: spokenOverride)

        if let entry = choice.log {
            log.insert(entry, at: 0)
            if log.count > 5 { log.removeLast(log.count - 5) }
        }

        missed = missed || choice.missed

        // The moment the name is confirmed is the enrolment point. If they say no, nothing is enrolled.
        if person == .stranger, stepIndex == SessionScript.enrollConfirmIndex,
           !choice.missed, choice.label.hasPrefix("\"Yes") {
            enrollArrivedPerson()
        }

        // **Clear it before advancing to the next step.** Otherwise what was said at the previous step
        // gets recorded again as the next step's answer.
        heardAnswer = ""
        suggestion = nil
        probeOverridden = false

        var next = stepIndex + 1
        // If delayed recall succeeded, the 'gentle recovery' screen isn't needed, so skip it.
        if person == .known, stepIndex == SessionScript.delayedRecallIndex, !choice.missed {
            next = SessionScript.gentleAssistIndex + 1
        }
        stepIndex = min(next, steps.count - 1)

        // Close the session on reaching the last screen. The next opener is previewed here.
        if stepIndex == steps.count - 1 { endSession() }
    }

    /// Whether this choice is **something the elder actually said**. Otherwise `nil`.
    ///
    /// Only script choice labels that start with a quote mark are utterances — things like `Unknown face`
    /// are staff instructions. Where something was written down, that value takes priority.
    private func spokenAnswer(_ choice: Choice, _ override: String?) -> String? {
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        guard choice.label.hasPrefix("\"") else { return nil }
        return choice.label.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Records this choice in the store — utterance · anchor · metrics.
    ///
    /// - Parameter spokenOverride: what was actually said. Passed from places that wrote it down or heard it via STT.
    ///   **Without it, the script choice label is recorded as the utterance** — if a place that wrote something down
    ///   doesn't pass this, words the elder never said remain as the transcript.
    private func record(_ choice: Choice, spokenOverride: String? = nil) {
        guard isRecording else { return }
        let currentTopic = topic(at: stepIndex)
        // A value explicitly passed by a write-down place takes priority; otherwise use what was heard at this step.
        let heard = heardAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = spokenOverride ?? (heard.isEmpty ? nil : heard)

        // If it's still unknown who it is, hold on to it and move it over at enrolment.
        guard let store, let session else {
            guard cameFromCamera else { return }
            if step.speaks {
                pendingUtterances.append((step.caption, false, currentTopic, .now))
            }
            if let spoken = spokenAnswer(choice, override) {
                pendingUtterances.append((spoken, true, currentTopic, .now))
            }
            return
        }

        // What the robot just said.
        if step.speaks {
            store.record(utterance: step.caption, isElder: false,
                         in: session, topic: currentTopic)
        }

        // The elder's answer. Of the choice labels, **only those starting with a quote mark** are real utterances;
        // things like "Someone walks up" are staff instructions and aren't recorded.
        if let spoken = spokenAnswer(choice, override) {
            store.record(utterance: spoken, isElder: true,
                         in: session, topic: currentTopic)

            // **Extract facts from what was said.** Runs in the background so the lines aren't blocked —
            // the elder is already hearing the next line, and the result quietly goes into the store.
            if heard == spoken, step.speaks, let elder {
                understand(question: step.caption, answer: spoken, for: elder)
                planNextLine(question: step.caption, answer: spoken, for: elder)
            }

            if stepIndex == SessionScript.anchorPlantIndex {
                plantedAnchor = store.plantAnchor(prompt: step.caption,
                                                  answer: spoken, in: session)
            }
        }

        // **The choice decides the verdict.** It comes from both the delayed recall slot and the recovery slot,
        // and recall after a hint comes only from the recovery slot.
        if let outcome = choice.recall, let anchor = plantedAnchor,
           anchor.probedAt == nil {
            store.probe(anchor, outcome: outcome)
            log.insert(recallLog(for: anchor, outcome: outcome), at: 0)
        }

        try? store.save()
        refreshMetrics()
    }

    // MARK: - Delayed recall measurement

    /// Recall verdict log. **The delay is written as the measured value.**
    private func recallLog(for anchor: RecallAnchor, outcome: AnchorOutcome) -> LogEntry {
        let elapsed = Self.durationLabel(anchor.delaySeconds ?? 0)
        guard anchor.isValidProbe else {
            return LogEntry(
                tag: "Delay too short",
                text: "\(outcome.label) · \(elapsed) delay — under 6 min, excluded from recall rate",
                color: Theme.amber
            )
        }
        return LogEntry(
            tag: outcome == .missed ? "Recall miss" : "Recall hit",
            text: "Anchor \"\(anchor.answer)\" · \(outcome.label) · \(elapsed) delay",
            color: outcome == .missed ? Theme.red : Theme.green
        )
    }

    // MARK: - Metrics — computed from records

    /// **Recomputes the screen's four cells from stored records.**
    ///
    /// Choices used to push numbers in directly. That meant what staff pressed was
    /// the measurement. Now `MetricEngine` does the calculation and this only passes it along.
    ///
    /// **Unmeasured cells stay as `—`.** Mood has no way to be measured yet, so it always shows that.
    private func refreshMetrics() {
        guard let store, let elder else {
            metrics = Metric.baseline
            return
        }
        var next = Metric.baseline
        func set(_ key: Metric.Key, _ reading: MetricEngine.Reading) {
            guard let i = next.firstIndex(where: { $0.key == key }) else { return }
            next[i].apply(reading)
        }

        let facts = store.consistency(for: elder)
        set(.consistency, MetricEngine.consistency(shaken: facts.shaken, total: facts.total))

        if let session {
            let turns = session.utterances.filter(\.isElder).count
            set(.speech, MetricEngine.speech(meanWords: store.averageWordCount(in: session),
                                             baseline: store.speechBaseline(for: elder),
                                             turns: turns))
            let probed = session.anchors.filter { $0.probedAt != nil }.count
            set(.recall, MetricEngine.recall(rate: store.recallRate(in: session),
                                             probed: probed,
                                             total: session.anchors.count))
        }

        set(.mood, MetricEngine.mood())
        metrics = next
    }

    /// When the session closes, **only what was measured** is kept as a record.
    ///
    /// Recording every turn would bury the 8-week trend under the swings within one session. What the cognitive report looks at
    /// is change between sessions, so one set per session is enough.
    /// **Unmeasured cells aren't recorded** — a blank and 0 are different.
    private func recordMetricSamples(in session: Session, store: MemoryStore) {
        refreshMetrics()
        for metric in metrics {
            guard metric.value != "—" else { continue }
            store.record(metric: metric.key.rawValue, percent: metric.percent,
                         value: metric.value, note: metric.note, in: session)
        }
    }

    /// Time remaining until asking back. Used for the countdown on the staff panel.
    ///
    /// **Delayed recall is all about the delay.** Asking back one minute after planting an anchor measures working memory,
    /// not delayed recall. Shown on screen so staff know without watching a clock.
    func anchorCountdown(at now: Date = .now) -> String? {
        guard let store, let session,
              let anchor = store.pendingAnchor(in: session) else { return nil }
        let remaining = anchor.probeDueAt.timeIntervalSince(now)
        guard remaining > 0 else { return "Ready to probe · \(anchor.answer)" }
        return "Probe in \(Self.durationLabel(remaining)) · \(anchor.answer)"
    }

    // MARK: - Session length

    /// Target length of one session. **The 8-minute delayed recall must fit within it**
    /// (`Docs/03_product-design.md` section 3). Any longer and the elder tires; any shorter and
    /// the anchor doesn't mature.
    static let targetMinutes = 18

    /// When this visit started.
    ///
    /// `Session.startedAt` isn't used because **without consent there is no `Session`
    /// at all**. Staff still need to see the time.
    private(set) var openedAt: Date?

    /// Elapsed time shown on the staff panel. Changes colour once it passes the target.
    func elapsedLabel(at now: Date = .now) -> String? {
        guard let openedAt, stepIndex > 0 else { return nil }
        let minutes = Int(now.timeIntervalSince(openedAt) / 60)
        return "\(minutes) / \(Self.targetMinutes) min"
    }

    func isOverTime(at now: Date = .now) -> Bool {
        guard let openedAt else { return false }
        return now.timeIntervalSince(openedAt) > Double(Self.targetMinutes) * 60
    }

    // MARK: - Delayed recall gate

    /// Whether staff opened asking back before expiry. Re-locks when the step advances.
    private(set) var probeOverridden = false

    /// **It's not time to ask back yet.**
    ///
    /// Asking back one minute after planting an anchor measures working memory, not delayed recall.
    /// The screen used to show only a countdown and **didn't stop the press** — in the script
    /// the planting and asking-back slots are two steps apart, so in practice it was pressed before expiry almost every time.
    ///
    /// It blocks but doesn't hard-lock. Staff can't close the session mid-pilot, so
    /// `overrideProbeGate()` allows skipping, and the skip is left in the log.
    func probeNotDue(at now: Date = .now) -> Bool {
        guard stepIndex == SessionScript.delayedRecallIndex else { return false }
        guard let store, let session,
              let anchor = store.pendingAnchor(in: session) else { return false }
        return now < anchor.probeDueAt
    }

    /// Whether this step's choices can be pressed right now.
    func canPickCurrentStep(at now: Date = .now) -> Bool {
        probeOverridden || !probeNotDue(at: now)
    }

    /// Staff decided to ask back before expiry. **It isn't counted in the recall rate.**
    func overrideProbeGate() {
        guard !probeOverridden else { return }
        probeOverridden = true
        log.insert(LogEntry(
            tag: "Probed early",
            text: "Staff opened the probe before the delay was up — not counted in recall",
            color: Theme.amber), at: 0)
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? "\(minutes) min \(secs) sec" : "\(secs) sec"
    }

    /// Topic per step. The script is fixed, so for now it's a table. In stage 2 the conversation engine supplies it.
    // MARK: - Understanding — extracting facts from what was said

    /// Whether enough has been extracted this session. **Not accumulated without limit in one session** —
    /// if ten facts about the same person appear at once, the next opener ends up picking any of them,
    /// and from the elder's point of view the robot suddenly remembers every trivial detail.
    private static let maxFactsPerSession = 3
    /// Discard anything with lower confidence than this. **Missing something is better than making it up.**
    private static let minConfidence = 0.5

    /// Runs in the background and saves one fact.
    ///
    /// It takes about 10 seconds on a device, so **the line isn't held with `await`.** The elder
    /// is already hearing the next line, and the result just needs to arrive before this session ends.
    /// Arriving late costs nothing — what uses it is the **next** session's opener.
    private func understand(question: String, answer: String, for elder: Elder) {
        guard isRecording else { return }
        guard factsThisSession < Self.maxFactsPerSession else { return }
        guard understanding.availability.isReady else { return }
        let elderID = elder.persistentModelID

        Task { @MainActor [weak self] in
            guard let self else { return }
            let found = await understanding.extract(question: question, answer: answer)

            guard let candidate = found else {
                // **Concluding there's no fact is a conclusion too.** If it passes silently, staff
                // can't even tell whether understanding is running.
                log.insert(LogEntry(tag: "Nothing to file",
                                    text: "No fact in that answer",
                                    color: Theme.gray8A), at: 0)
                return
            }
            guard candidate.confidence >= Self.minConfidence else {
                log.insert(LogEntry(tag: "Too unsure",
                                    text: String(format: "\"%@\" · %.0f%% — not filed",
                                                 candidate.subject,
                                                 candidate.confidence * 100),
                                    color: Theme.amber), at: 0)
                return
            }
            // The session may have ended or the person changed in the meantime. Check again.
            guard let store, let current = store.elder(with: elderID),
                  current.persistentModelID == self.elder?.persistentModelID else { return }

            store.record(subject: candidate.subject, kind: candidate.kind,
                         detail: candidate.detail, for: current)
            // **Pass the topic that actually came up this time as a candidate for the next opener.** Without this
            // the next session opens with the script tag.
            if let session, !session.topics.contains(candidate.subject) {
                session.topics.append(candidate.subject)
            }
            try? store.save()
            factsThisSession += 1
            refreshMetrics()
            log.insert(LogEntry(tag: "Heard and filed",
                                text: "\(candidate.subject) · \(candidate.kind.rawValue)",
                                color: Theme.green), at: 0)
        }
    }

    // MARK: - Next-line suggestions

    /// Offers as candidates the stored topics **not yet brought up this session**.
    ///
    /// Bringing back what was just discussed with "By the way, tell me about that"
    /// sounds as if the robot wasn't listening.
    private var suggestionCandidates: [String] {
        guard let elder else { return [] }
        let spokenAlready = Set(session?.topics ?? [])
        return elder.facts
            .sorted { $0.mentionCount > $1.mentionCount }
            .map(\.subject)
            .filter { !spokenAlready.contains($0) }
    }

    /// Picks in the background. **Doesn't make the elder wait** —
    /// it takes about 7 seconds on a device, and meanwhile staff are watching the elder.
    private func planNextLine(question: String, answer: String, for elder: Elder) {
        let elderID = elder.persistentModelID
        let atStep = stepIndex
        suggestion = nil
        isPlanning = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            let plan = await planner.plan(name: elder.spokenName,
                                          candidates: suggestionCandidates,
                                          question: question,
                                          answer: answer)
            isPlanning = false
            // If the step advanced or the person changed in the meantime, discard it.
            // **A suggestion that arrives late and shows up in another place becomes a non sequitur.**
            guard atStep == stepIndex,
                  elderID == self.elder?.persistentModelID else { return }
            suggestion = plan
        }
    }

    /// Staff accepted the suggestion. **Keep the step and change only the line** —
    /// advancing would skip the next place in the script.
    func acceptSuggestion() {
        guard let plan = suggestion, steps.indices.contains(stepIndex) else { return }
        steps[stepIndex].caption = plan.line
        // They'll be answering the new line, so clear the previous answer.
        heardAnswer = ""
        suggestion = nil
        captionRevision += 1

        if isRecording, let store, let session {
            store.record(utterance: plan.line, isElder: false,
                         in: session, topic: plan.subject)
            try? store.save()
        }
        log.insert(LogEntry(tag: "Suggested line used",
                            text: "\(plan.move.rawValue) · chose in "
                                + String(format: "%.1fs", plan.seconds),
                            color: Theme.blue), at: 0)
    }

    /// Staff rejected the suggestion. **Why it wasn't used is the quality metric** — the rate of not pressing
    /// must be recorded just as much as the rate of pressing, to know what to fix next.
    func dismissSuggestion() {
        guard let plan = suggestion else { return }
        suggestion = nil
        log.insert(LogEntry(tag: "Suggestion passed",
                            text: plan.line.replacingOccurrences(of: "\n", with: " "),
                            color: Theme.gray8A), at: 0)
    }

    private func topic(at index: Int) -> String? {
        guard person == .known else { return elder?.hometown }
        switch index {
        case SessionScript.openerIndex:       return opener?.topic
        case SessionScript.reminiscenceIndex: return reminiscenceTopic
        default:                              return nil
        }
    }

    func reset() {
        restart(as: person)
    }

    func togglePerson() {
        restart(as: person == .known ? .stranger : .known)
    }

    /// - Parameter keepingArrival: whether to keep the person the camera just recognised.
    ///   **Discarded** when staff switch by hand — from that moment on, a person decided.
    private func restart(as next: Person, keepingArrival: Bool = false) {
        endSession()
        if !keepingArrival {
            arrivedElder = nil
            arrivedFace = nil
            arrivalNote = nil
            cameFromCamera = false
            isIdentified = false
            pendingUtterances = []
        }
        person = next
        stepIndex = 0
        typedName = ""
        nameAttempts = 0
        log = keepingArrival ? log : []
        metrics = Metric.baseline
        missed = false
        plantedAnchor = nil
        beginSession()
    }

    func toggleStaffOverlay() {
        showsStaffOverlay.toggle()
    }
}
