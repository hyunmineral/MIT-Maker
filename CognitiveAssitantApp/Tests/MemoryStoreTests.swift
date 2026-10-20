import Foundation
import Testing
@testable import RobotForElders

/// The store decides **what the next session opens with**. Principle 2 hangs on this.
@Suite("MemoryStore — does memory carry over")
struct MemoryStoreTests {

    @Test("A promised topic comes before the last topic")
    func promisedTopicWins() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let past = store.startSession(for: elder)
        store.record(utterance: "the orchard", isElder: true, in: past, topic: "the orchard")
        store.endSession(past, nextOpenerTopic: "her sister")

        let opener = try #require(store.opener(for: elder))
        // If last time it said "Tell me about that next time", keep that promise first.
        #expect(opener.topic == "her sister")
        #expect(opener.source == .promised)
    }

    @Test("Without a promise, it opens with the last session's last topic")
    func lastTopicIsNext() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let past = store.startSession(for: elder)
        store.record(utterance: "peaches", isElder: true, in: past, topic: "the orchard")
        store.endSession(past, nextOpenerTopic: nil)

        let opener = try #require(store.opener(for: elder))
        #expect(opener.topic == "the orchard")
        #expect(opener.source == .lastTopic)
    }

    @Test("Without a previous session, it opens with something mentioned several times")
    func longTermAnchorIsLast() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Betty Clark")
        store.record(subject: "the county fair", kind: .event, detail: "went every year", for: elder)
        store.record(subject: "the county fair", kind: .event, detail: "went every year", for: elder)
        store.record(subject: "Norfolk", kind: .place, detail: "grew up there", for: elder)

        let opener = try #require(store.opener(for: elder))
        #expect(opener.topic == "the county fair")
        #expect(opener.source == .longTermAnchor)
    }

    @Test("With nothing at all there's no opener — nothing invented")
    func noOpenerWithoutHistory() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "New Person")
        #expect(store.opener(for: elder) == nil)
    }

    @Test("A session with no utterances isn't a record")
    func emptySessionIsDiscarded() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        store.discard(session)
        try store.save()
        // Closing it as is would count it as a 'completed session', inflating the cumulative count.
        #expect(elder.sessions.isEmpty)
    }

    @Test("Mentioning the same topic again raises the count")
    func mentionCountRises() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        store.record(subject: "the orchard", kind: .place, detail: "worked there at twenty", for: elder)
        let fact = store.record(subject: "the orchard", kind: .place,
                                detail: "worked there at twenty", for: elder)
        #expect(fact.mentionCount == 2)
        #expect(elder.facts.count == 1)
    }

    @Test("When an answer changes, **the first statement is kept**")
    func driftKeepsTheOriginal() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        store.record(subject: "the orchard", kind: .place, detail: "worked there at twenty", for: elder)
        let fact = store.record(subject: "the orchard", kind: .place,
                                detail: "worked there at eighteen", for: elder)

        // The fact itself must hold the latest statement and the revision record the previous one,
        // so the consistency card can show the two side by side.
        #expect(fact.detail == "worked there at eighteen")
        #expect(fact.revisions.count == 1)
        #expect(fact.revisions.last?.detail == "worked there at twenty")
    }

    @Test("Counts the number of drifted facts")
    func consistencyCounts() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        store.record(subject: "a", kind: .place, detail: "one", for: elder)
        store.record(subject: "a", kind: .place, detail: "two", for: elder)
        store.record(subject: "b", kind: .person, detail: "same", for: elder)

        let result = store.consistency(for: elder)
        #expect(result.total == 2)
        #expect(result.shaken == 1)
    }

    @Test("Only a set number of faces is accumulated")
    func faceEmbeddingsAreCapped() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        for i in 0..<8 { store.addFaceEmbedding(Data([UInt8(i)]), to: elder) }
        #expect(elder.faceEmbeddings.count == 5)
        // Older ones must be pushed out and recent ones kept.
        #expect(elder.faceEmbeddings.last == Data([7]))
    }

    @Test("Average word count counts only elder utterances")
    func averageWordCountIgnoresRobot() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: "Dorothy Miller")
        let session = store.startSession(for: elder)
        store.record(utterance: "What did you have for lunch today?", isElder: false, in: session)
        store.record(utterance: "tomato soup", isElder: true, in: session)
        store.record(utterance: "I had it with bread", isElder: true, in: session)

        let mean = try #require(store.averageWordCount(in: session))
        #expect(abs(mean - 3.5) < 0.001)
    }
}
