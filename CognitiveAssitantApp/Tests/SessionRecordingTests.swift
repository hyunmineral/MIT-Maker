import Foundation
import Testing
@testable import RobotForElders

/// **Does the app behave as the consent screen describes?**
///
/// The self/guardian consent item said *"without it, no session can be recorded"*, yet
/// the code had no check (found 2026-09-10). The other three really were locking features,
/// so **only this item behaved differently from its description.**
@Suite("Session recording — does self/guardian consent really lock it", .serialized)
struct SessionRecordingTests {

    /// Tests by changing the consent state and **restores it afterwards.** If a test permanently changed
    /// the simulator's app settings, the next test would inherit that state.
    private func withPersonalConsent<T>(_ granted: Bool, _ body: () throws -> T) rethrows -> T {
        let previous = Consent.isGranted(.personal)
        Consent.set(.personal, granted)
        defer { Consent.set(.personal, previous) }
        return try body()
    }

    /// Advances two steps from the resting screen to make the robot speak.
    private func advanceTwice(_ model: SessionViewModel) {
        for _ in 0..<2 {
            guard let choice = model.step.choices.first else { return }
            model.pick(choice)
        }
    }

    @Test("With consent, the session and utterances are kept")
    func recordsWithConsent() throws {
        try withPersonalConsent(true) {
            let store = try TestStore.make()
            let elder = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            #expect(model.isRecording)
            #expect(model.recordingBanner == nil)

            advanceTwice(model)
            #expect(elder.sessions.count == 1)
            #expect(elder.sessions.first?.utterances.isEmpty == false)
        }
    }

    @Test("Without consent, the session itself isn't opened")
    func doesNotRecordWithoutConsent() throws {
        try withPersonalConsent(false) {
            let store = try TestStore.make()
            let elder = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            #expect(model.isRecording == false)
            #expect(model.recordingBanner != nil)

            advanceTwice(model)
            // The conversation goes on, but nothing is written to the store.
            #expect(elder.sessions.isEmpty)
            #expect(model.stepIndex > 0)
        }
    }

    @Test("Even without consent, past records are read to build the opener")
    func stillReadsPastRecords() throws {
        let store = try TestStore.make()
        let elder = store.addElder(name: DemoPeople.known)
        let past = store.startSession(for: elder)
        store.record(utterance: "peaches", isElder: true, in: past, topic: "the orchard")
        store.endSession(past, nextOpenerTopic: "her sister")
        try store.save()

        try withPersonalConsent(false) {
            let model = SessionViewModel()
            model.attach(context: store.context)
            // Records already saved remained under the consent at that time. Only new writes are blocked.
            #expect(model.opener?.topic == "her sister")
            // Still, no new session is opened.
            #expect(elder.sessions.count == 1)
        }
    }

    @Test("Without consent, no metrics are produced either")
    func noMetricSamplesWithoutConsent() throws {
        try withPersonalConsent(false) {
            let store = try TestStore.make()
            let elder = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            advanceTwice(model)

            let samples = elder.sessions.flatMap(\.metrics)
            #expect(samples.isEmpty)
        }
    }
}

/// Delayed recall gate — **verdicts can't be pressed before expiry.**
@Suite("Delayed recall gate", .serialized)
struct ProbeGateTests {

    private func withPersonalConsent<T>(_ granted: Bool, _ body: () throws -> T) rethrows -> T {
        let previous = Consent.isGranted(.personal)
        Consent.set(.personal, granted)
        defer { Consent.set(.personal, previous) }
        return try body()
    }

    /// Pushes the script forward to where the anchor is planted.
    private func runToProbe(_ model: SessionViewModel) {
        while model.stepIndex < SessionScript.delayedRecallIndex {
            guard let choice = model.step.choices.first else { return }
            model.pick(choice)
        }
    }

    @Test("Right after planting an anchor, it can't be asked back")
    func gateHoldsRightAfterPlanting() throws {
        try withPersonalConsent(true) {
            let store = try TestStore.make()
            _ = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            runToProbe(model)

            #expect(model.stepIndex == SessionScript.delayedRecallIndex)
            // Asking back one minute after planting measures working memory, not delayed recall.
            #expect(model.probeNotDue())
            #expect(model.canPickCurrentStep() == false)
        }
    }

    @Test("The lock releases after 8 minutes")
    func gateOpensAfterTheDelay() throws {
        try withPersonalConsent(true) {
            let store = try TestStore.make()
            _ = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            runToProbe(model)

            let later = Date.now.addingTimeInterval(9 * 60)
            #expect(model.probeNotDue(at: later) == false)
            #expect(model.canPickCurrentStep(at: later))
        }
    }

    @Test("Staff can skip it, and the skip is recorded")
    func staffCanOverrideAndItIsLogged() throws {
        try withPersonalConsent(true) {
            let store = try TestStore.make()
            _ = store.addElder(name: DemoPeople.known)
            try store.save()

            let model = SessionViewModel()
            model.attach(context: store.context)
            runToProbe(model)

            model.overrideProbeGate()
            // Just locking it would stall the session mid-pilot. Allow skipping, but leave a trace.
            #expect(model.canPickCurrentStep())
            #expect(model.log.contains { $0.tag == "Probed early" })
        }
    }
}
