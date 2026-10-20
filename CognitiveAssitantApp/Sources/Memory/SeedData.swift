import Foundation
import SwiftData

/// Demo data inserted when the store is empty.
///
/// To see in the pilot **whether the opener actually works**, there has to be a 'last session'.
/// Dorothy Miller is given a finished session and a previewed topic ("your sister"),
/// so even on the app's first launch `MemoryStore.opener(for:)` behaves according to principle 2.
///
/// This file isn't included in a real deployment — `seedIfEmpty` runs only when the store is empty.
enum SeedData {

    static func seedIfEmpty(_ context: ModelContext) {
        let store = MemoryStore(context: context)
        guard (try? store.allElders())?.isEmpty ?? false else { return }

        seedDorothyMiller(store, context: context)

        // Record the form of address only as far as it's known. `Mrs.` only when marriage or widowhood is known (`FormOfAddress`).
        store.addElder(name: DemoPeople.stranger,
                       honorific: DemoPeople.strangerHonorific,
                       familyName: DemoPeople.strangerFamilyName,
                       hometown: DemoPeople.strangerHometown)
        store.addElder(name: "Robert Hayes", honorific: .mr, familyName: "Hayes",
                       birthYear: 1938)
        store.addElder(name: "Betty Clark", honorific: .ms, familyName: "Clark",
                       birthYear: 1943)
        store.addElder(name: "Frank Sullivan", honorific: .mr, familyName: "Sullivan",
                       birthYear: 1940)

        try? store.save()
    }

    /// Enrolled for 8 months · 74 sessions in total. The person the script assumes.
    private static func seedDorothyMiller(_ store: MemoryStore, context: ModelContext) {
        let now = Date.now
        let elder = store.addElder(name: DemoPeople.known,
                                   honorific: DemoPeople.knownHonorific,
                                   familyName: DemoPeople.knownFamilyName,
                                   invitedFirstName: DemoPeople.knownInvitedFirstName,
                                   birthYear: DemoPeople.knownBirthYear,
                                   hometown: DemoPeople.knownHometown)
        elder.enrolledAt = now.addingTimeInterval(-8 * 30 * 86_400)

        let orchard = store.record(subject: DemoPeople.orchard, kind: .place,
                                   detail: "Worked there at twenty",
                                   for: elder,
                                   at: now.addingTimeInterval(-120 * 86_400))
        orchard.mentionCount = 3

        store.record(subject: DemoPeople.granddaughter, kind: .person,
                     detail: "Finals coming up", for: elder,
                     at: now.addingTimeInterval(-28 * 86_400))
        store.record(subject: DemoPeople.husband, kind: .person,
                     detail: "Passed away first", for: elder,
                     at: now.addingTimeInterval(-200 * 86_400))
        store.record(subject: DemoPeople.son, kind: .person,
                     detail: "Lives in Chicago", for: elder,
                     at: now.addingTimeInterval(-150 * 86_400))

        let last = store.startSession(for: elder)
        last.startedAt = now.addingTimeInterval(-7 * 86_400)
        last.topics = [DemoPeople.granddaughter, DemoPeople.orchard]

        store.record(utterance: "Last time you told me about Emma's tests. How did she do?",
                     isElder: false, in: last, topic: DemoPeople.granddaughter,
                     at: last.startedAt.addingTimeInterval(90))
        store.record(utterance: "She did great. She's a good student",
                     isElder: true, in: last, topic: DemoPeople.granddaughter,
                     at: last.startedAt.addingTimeInterval(96))

        let anchor = store.plantAnchor(prompt: "What did you have for lunch today?",
                                       answer: DemoPeople.lunch, in: last,
                                       at: last.startedAt.addingTimeInterval(240))
        store.probe(anchor, outcome: .exact,
                    at: last.startedAt.addingTimeInterval(240 + 492))

        store.record(metric: "recall", percent: 100, value: "1/1",
                     note: "Delayed recall ok · 8 min 12 s", in: last)
        store.record(metric: "consistency", percent: 92, value: "92%",
                     note: "23 events on file", in: last)
        store.record(metric: "speech", percent: 62, value: "steady",
                     note: "9 words average", in: last)
        store.record(metric: "mood", percent: 70, value: "okay",
                     note: "Tone + word affect", in: last)

        store.endSession(last, nextOpenerTopic: DemoPeople.sister)
        last.endedAt = last.startedAt.addingTimeInterval(18 * 60)
    }
}
