import SwiftUI

/// The session script. Demo people are based on a US adult day care setting (`DemoPeople`).
///
/// For now it's a fixed script, but in the real app this array is replaced by the stream of utterances
/// produced by the conversation engine (LLM). The fields of `SessionStep` serve as the contract as is.
enum SessionScript {

    // MARK: - Enrolled person (Dorothy Miller)

    static let known: [SessionStep] = [
        SessionStep(
            face: .sleep,
            status: "Idle · low power",
            caption: "Resting",
            speaks: false,
            choices: [Choice(label: "Someone walks up")]
        ),
        SessionStep(
            face: .neutral,
            status: "Face recognition",
            // Outwardly it only greets. It never says out loud that it didn't recognise someone.
            caption: "Hello.\nCome on in.",
            choices: [
                Choice(label: "Recognition complete",
                       log: LogEntry(tag: "Recognized",
                                     text: "\(DemoPeople.known) · similarity 0.94 · memory loaded",
                                     color: Theme.blue))
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Greeting",
            caption: "\(DemoPeople.knownSpoken)!\nYou made it.",
            choices: [Choice(label: "\"Yeah, I'm here\"")]
        ),
        SessionStep(
            face: .happy,
            status: "Continuity opener",
            caption: "Last time you told me\nabout Emma's tests.\nHow did she do?",
            listening: true,
            card: MemoryCard(kind: "Last session · Jul 20",
                             title: "Granddaughter Emma · finals",
                             body: "\"She has tests this week\""),
            choices: [
                Choice(
                    label: "\"She did great. She's a good student\"",
                    log: LogEntry(tag: "Continuity hit",
                                  text: "Picked up last session's topic · delay 0.8s",
                                  color: Theme.green)
                ),
                Choice(
                    label: "\"Emma… who's that?\"",
                    log: LogEntry(tag: "Attention",
                                  text: "Missed a recently mentioned person",
                                  color: Theme.red),
                    missed: true
                )
            ]
        ),
        SessionStep(
            face: .neutral,
            status: "Planting anchor",
            caption: "What did you have\nfor lunch today?",
            listening: true,
            choices: [
                Choice(
                    label: "\"Tomato soup\"",
                    log: LogEntry(tag: "Anchor set",
                                  text: "#1 lunch=tomato soup · recall in 8 min",
                                  color: Theme.blue)
                )
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Reminiscence",
            caption: "Tell me about\nthe peach orchard\nagain.",
            listening: true,
            card: MemoryCard(kind: "Memory card · 1961",
                             title: "Asheville · peach orchard",
                             body: "Long-term anchor · mentioned 3 times"),
            choices: [
                Choice(
                    label: "\"I worked there when I was eighteen\"",
                    log: LogEntry(tag: "Fact drift",
                                  text: "Recorded \"twenty\" ↔ today \"eighteen\"",
                                  color: Theme.amber)
                )
            ]
        ),
        SessionStep(
            face: .neutral,
            status: "Delayed recall probe",
            caption: "By the way —\nwhat was lunch?",
            listening: true,
            // **There are four verdicts.** Partial recall is the most common form in early decline, so
            // lumping it in with failure misses the change that shows up first.
            choices: [
                Choice(label: "\"Tomato soup, that's it\"", recall: .exact),
                Choice(label: "\"Some kind of soup\"", recall: .partial),
                Choice(label: "\"Gee… what was it\"", missed: true)
            ]
        ),
        SessionStep(
            face: .soft,
            status: "Gentle assist",
            // The robot fills in the answer. If she remembers here it's **recall after a hint**;
            // if it still doesn't come back, that's the failure. The two are different signals.
            caption: "That's all right.\nIt was tomato soup.",
            listening: true,
            choices: [
                Choice(
                    label: "\"Oh right, that's it\"",
                    log: LogEntry(tag: "Recovery",
                                  text: "Recalled once the answer was offered",
                                  color: Theme.blue),
                    recall: .hinted
                ),
                Choice(
                    label: "\"…I still don't have it\"",
                    log: LogEntry(tag: "Recovery",
                                  text: "Moved on without exposing the miss",
                                  color: Theme.blue),
                    recall: .missed
                )
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Farewell",
            // At 74pt, lines 1 and 2 of the old wording were 755.6 / 749.3pt, over the 724 width, and
            // wrapped to 4–5 lines. The lines were re-broken while keeping the meaning.
            caption: "I loved that story.\nTell me about\nyour sister next time.",
            choices: [
                Choice(label: "See session summary",
                       log: LogEntry(tag: "Session end",
                                     text: "18 min · 3 nodes updated · next opener: your sister",
                                     color: Theme.blue))
            ]
        ),
        SessionStep(
            face: .sleep,
            status: "Session closed",
            caption: "Session saved",
            speaks: false,
            choices: [Choice(label: "Start over", resets: true)]
        )
    ]

    /// Every line in the script actually read aloud (deduplicated, in order of appearance).
    static var allSpokenLines: [String] {
        var seen = Set<String>()
        return (known + stranger)
            .filter(\.speaks)
            .map(\.caption)
            .filter { seen.insert($0).inserted }
    }

    static let gentleAssistIndex = 7
    static let delayedRecallIndex = 6
    static let openerIndex = 3
    static let anchorPlantIndex = 4
    /// The place in the known-person script where the name is called. The name of the person the camera recognised goes here.
    static let greetingIndex = 2
    /// **The place the camera has already answered.** In both scripts step 1 is the step that settles "who is it",
    /// and its choices (`Recognition complete` · `Unknown face`) were pressed by staff on its behalf
    /// back when there was no recogniser. If it came in through auto-greet, there's no reason to press them.
    static let recognitionIndex = 1

    /// First-meeting script — the place where staff write down the name.
    static let askNameIndex = 3
    /// First-meeting script — the place where the name is confirmed and **the face is actually enrolled.**
    static let enrollConfirmIndex = 4
    /// First-meeting script — the place that asks about hometown to plant a seed of long-term memory.
    static let seedMemoryIndex = 5

    static let reminiscenceIndex = 5
    static let farewellIndex = 8

    /// **Things to ask someone met for the first time.**
    ///
    /// Exactly the **hometown · children · occupation** that `Docs/03_product-design.md` section 2 names as keys to long-term memory.
    /// Not just anything can be asked; to be useful in this product a question has to meet three conditions at once.
    ///
    /// 1. **It must be well-preserved long-term memory.** Only things that survive even early cognitive decline
    ///    can open recall in the next session. Asking about yesterday fails from the very first conversation
    ///    and becomes the "feels like a test" situation that section 3 forbids.
    /// 2. **It must be comparable when asked again.** Fact drift in 4-2 means asking the same topic
    ///    several times and comparing. Drift only shows in answers that include a time, age or place.
    /// 3. **It must draw out long answers.** 4-3 uses the first session as the speech-amount baseline.
    ///    Yes/no questions can't build a baseline.
    ///
    /// ## What isn't asked
    ///
    /// - **Age · year of birth · today's date** — these are MMSE orientation items themselves. This app doesn't diagnose
    /// - **How the spouse is doing** — asked without knowing about a bereavement, it hurts. Raised only once there's a record
    /// - **Health · hospitals** — the primary goal is an enjoyable time (section 1)
    ///
    /// ## One per session
    ///
    /// A robot met for the first time firing off three questions in a row becomes an interrogation. Pick just one kind
    /// not yet covered, ask it, and fill in the rest in later sessions.
    enum SeedQuestion: CaseIterable {
        /// The deepest and safest. The first session always starts here.
        case hometown
        /// **Recognising people is a more heavily weighted signal** (4-2). It needs a person node to be measured.
        case family
        /// The centre of autobiographical memory, and **the stories run long** — best for the speech-amount baseline.
        case work

        var kind: FactKind {
            switch self {
            case .hometown: .place
            case .family:   .person
            case .work:     .event
            }
        }

        /// What the robot says. If it's a first meeting, it adds the name to open gently.
        func caption(introducing name: String?) -> String {
            switch self {
            case .hometown:
                // **The name must always sit alone on its own line.** At 74pt, putting it on one line like `better, <name>.`
                // makes `Margaret Walsh` 716.8pt, leaving only 7pt of the 724 width,
                // and a slightly longer name wraps the line into 5 lines (over budget).
                // The seed step has no memory card, so **up to 4 lines** fit.
                name.map { "I'd like to know you.\n\($0).\nWhere did you\ngrow up?" }
                    ?? "Where did you\ngrow up?"
            case .family:
                "Who's at home\nwith you these days?"
            case .work:
                "What kind of work\ndid you do?"
            }
        }

        var placeholder: String {
            switch self {
            case .hometown: "Where they grew up"
            case .family:   "Who they live with"
            case .work:     "What they did for work"
            }
        }

        /// `Fact.detail` — becomes the reference for comparison when the same topic is asked again later.
        var detail: String {
            switch self {
            case .hometown: "Where they grew up"
            case .family:   "Who is at home with them"
            case .work:     "What they did for work"
            }
        }

        var status: String {
            switch self {
            case .hometown: "Seeding memory · place"
            case .family:   "Seeding memory · people"
            case .work:     "Seeding memory · work"
            }
        }
    }

    /// Picks one that hasn't been asked yet. `nil` if all are present.
    static func nextSeed(missingFrom facts: [Fact]) -> SeedQuestion? {
        SeedQuestion.allCases.first { question in
            !facts.contains { $0.kind == question.kind }
        }
    }

    /// The step that plants a memory. Goes into both the opener slot and the recall slot.
    static func seedStep(_ question: SeedQuestion, introducing name: String?) -> SessionStep {
        SessionStep(
            face: .happy,
            status: question.status,
            caption: question.caption(introducing: name),
            listening: true,
            choices: [Choice(label: "Heard it",
                             log: LogEntry(tag: "Memory seeded",
                                           text: "First \(question.kind.rawValue) on file",
                                           color: Theme.blue))]
        )
    }

    /// **The opener for someone being properly met for the first time.**
    ///
    /// Someone whose name is known but who has no memories — enrolled, then back for the first time.
    /// There's no previous story so nothing can be asked about it, and using the `known` script's "Emma's tests" would
    /// **claim a conversation that never happened** (`Docs/03_product-design.md` section 8).
    ///
    /// So instead of recall, **a memory is planted.** For someone born in the 1940s, hometown is the deepest and safest
    /// long-term memory, and it becomes the first seed for the next session's opener.
    static func firstMemoryStep(spokenName: String) -> SessionStep {
        SessionStep(
            face: .happy,
            status: "First real session · seeding memory",
            // Same wording as `SeedQuestion.hometown` above. Same rationale for the line breaks.
            caption: "I'd like to know you.\n\(spokenName).\nWhere did you\ngrow up?",
            listening: true,
            choices: [Choice(label: "Heard it",
                             log: LogEntry(tag: "Memory seeded",
                                           text: "First place on file",
                                           color: Theme.blue))]
        )
    }

    /// **Recall conversation.** The topic comes from that person's facts.
    ///
    /// `the peach orchard` used to be hard-coded. That's Dorothy's memory —
    /// used as is with someone else, it **plants a memory that never existed.**
    static func reminiscenceStep(topic: String?) -> SessionStep {
        SessionStep(
            face: .happy,
            status: topic == nil ? "Open reminiscence" : "Reminiscence",
            caption: topic.map { "Tell me about\n\($0)\nagain." }
                ?? "What would you like\nto tell me about\ntoday?",
            listening: true,
            choices: [
                Choice(label: "\"(tells the story)\"",
                       log: LogEntry(tag: "Long-term recall",
                                     text: topic.map { "Told the \($0) story" }
                                         ?? "Told a story · no prior topic on file",
                                     color: Theme.green)),
                Choice(label: "\"I don't remember that\"",
                       log: LogEntry(tag: "Long-term",
                                     text: "Did not pick up a long-term topic",
                                     color: Theme.amber),
                       missed: true)
            ]
        )
    }

    /// **Farewell.** The previewed topic must be one that actually came up this time.
    ///
    /// It used to say "Tell me about your sister next time" while saving
    /// `topics.last` (the orchard). **The promise spoken and the record differed.**
    static func farewellStep(topic: String?) -> SessionStep {
        SessionStep(
            face: .happy,
            status: "Farewell",
            // **The topic sits alone on its own line.** It comes from the store so its length is unknown,
            // and sharing a line with ` next time.` wraps long topics, adding a line.
            caption: topic.map { "I loved that story.\nLet's talk about\n\($0)\nnext time." }
                ?? "It was good to talk.\nLet's do this again.",
            choices: [Choice(label: "\"See you next time\"")]
        )
    }

    /// When it hasn't yet worked out who it is, **it keeps looking while making conversation.**
    ///
    /// Missing a frame or two of the face is normal — heads turn and focus wavers while someone approaches.
    /// Jumping straight to "Nice to meet you" then produces the failure of **asking someone it knows for their name**.
    ///
    /// So it does what a person does: takes one more look while talking about the weather.
    /// **This isn't just buying time** — when spoken to, people look at the screen,
    /// so a frontal frame is captured. The recognition probability itself goes up.
    ///
    /// It has to be something that fits both someone known and someone unknown. The weather does.
    ///
    /// **It asks rather than asserts.** The robot is indoors with no weather data — saying "Lovely weather, isn't it?"
    /// when it's raining is simply wrong. This product doesn't pretend to know what it doesn't.
    /// Only a question gets an answer back, and **answering means looking at the screen**, so a frontal frame comes too.
    static func lookingStall() -> String {
        "How's the weather\nout there today?"
    }

    /// **What it says to ask again** when it didn't catch the name.
    ///
    /// Handled as conversation, not an error display. Showing "recognition failed" on the screen in front of an elder
    /// is not this product's job, and real people ask again when they don't hear.
    ///
    /// **It asks again at most twice** (`nameReaskLimit`). After that it quietly hands over to staff —
    /// a robot repeating itself to an empty chair or an accent it can't parse is worse.
    /// The wording changes slightly each time for the same reason. Saying exactly the same thing twice looks broken.
    static let nameReaskLimit = 2

    static func nameReask(attempt: Int) -> String {
        switch attempt {
        case 1:  "Sorry — could you\nsay that again?"
        // **Dropped `quite` and split one more line.** The first line of the old wording was 725.1pt,
        // 1pt over the 724 width, and was silently wrapping (2026-09-10, caught by the line-budget test).
        // The second line was 713pt with only 11pt of slack, so it was split too.
        default: "I didn't catch that.\nWhat should I\ncall you?"
        }
    }

    /// The opener for someone recognised but **with no previous story yet**.
    ///
    /// Someone enrolled and back for the first time has no previous session to quote. Using the fixed script's
    /// "Emma's tests" as is would **amount to claiming a conversation that never happened**
    /// (`Docs/03_product-design.md` section 8). So it just asks how they've been, without a memory card.
    static func reconnectStep() -> SessionStep {
        SessionStep(
            face: .happy,
            status: "Continuity opener · no history yet",
            caption: "Good to see you again.\nHow have you been?",
            listening: true,
            choices: [
                Choice(label: "\"I'm doing all right\"",
                       log: LogEntry(tag: "Reconnected",
                                     text: "Recognized, but no past topic on file yet",
                                     color: Theme.blue)),
                Choice(label: "\"Who are you again?\"",
                       log: LogEntry(tag: "Attention",
                                     text: "Did not recognize the robot",
                                     color: Theme.amber),
                       missed: true)
            ]
        )
    }

    /// Builds the opener step from a topic taken from the store.
    static func openerStep(topic: String, card: MemoryCard?) -> SessionStep {
        SessionStep(
            face: .happy,
            status: "Continuity opener",
            // This step **has a memory card attached, so 3 lines is the limit**. The old one-liner `Last time you
            // mentioned` was 766.6pt at 74pt, over the width, and became 4 lines.
            // `\(topic)` comes from the store, so its length varies — **it sits alone on its own line.**
            caption: "You mentioned\n\(topic).\nTell me more today.",
            listening: true,
            card: card,
            choices: [
                Choice(
                    label: "\"Sure, I'll tell you\"",
                    log: LogEntry(tag: "Continuity hit",
                                  text: "Picked up last session's topic",
                                  color: Theme.green)
                ),
                Choice(
                    label: "\"What was that about?\"",
                    log: LogEntry(tag: "Attention",
                                  text: "Missed last session's topic",
                                  color: Theme.red),
                    missed: true
                )
            ]
        )
    }

    // MARK: - Someone met for the first time (Margaret Walsh)

    static let stranger: [SessionStep] = [
        SessionStep(
            face: .sleep,
            status: "Idle · low power",
            caption: "Resting",
            speaks: false,
            choices: [Choice(label: "A new person walks up")]
        ),
        SessionStep(
            face: .neutral,
            status: "Face recognition",
            caption: "Hello.\nCome on in.",
            choices: [
                Choice(label: "Unknown face",
                       log: LogEntry(tag: "Unenrolled",
                                     text: "Best match 0.31 · new profile candidate",
                                     color: Theme.amber))
            ]
        ),
        SessionStep(
            face: .surprise,
            status: "First meeting",
            caption: "Oh — we haven't met.\nNice to meet you!",
            choices: [Choice(label: "\"Nice to meet you too\"")]
        ),
        SessionStep(
            face: .neutral,
            status: "Asking name",
            caption: "What's your name?",
            listening: true,
            choices: [
                Choice(label: "\"Margaret Walsh\"",
                       log: LogEntry(tag: "Speech",
                                     text: "\"Margaret Walsh\" · confidence 0.88",
                                     color: Theme.blue))
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Confirm & enroll",
            caption: "Margaret Walsh —\nis that right?",
            card: MemoryCard(kind: "Quiet capture · no shutter",
                             title: "3 face embeddings",
                             body: "On-device only · staff confirms"),
            choices: [
                Choice(label: "\"Yes, that's me\"",
                       log: LogEntry(tag: "Enrolled",
                                     text: "\(DemoPeople.stranger) profile created · empty map",
                                     color: Theme.green)),
                Choice(label: "\"No, it's Margaret Wells\"",
                       log: LogEntry(tag: "Correction",
                                     text: "Name check loop ×1 · spelling fix",
                                     color: Theme.amber))
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Seeding memory",
            caption: "Where did you\ngrow up,\n\(DemoPeople.strangerSpoken)?",
            listening: true,
            choices: [
                Choice(
                    label: "\"Des Moines, Iowa\"",
                    log: LogEntry(tag: "Memory map created",
                                  text: "Place node \"Des Moines, Iowa\" · first anchor",
                                  color: Theme.blue)
                )
            ]
        ),
        SessionStep(
            face: .happy,
            status: "Farewell",
            caption: "Good to meet you.\nTell me more about\nDes Moines next time.",
            choices: [Choice(label: "Start over", resets: true)]
        )
    ]
}
