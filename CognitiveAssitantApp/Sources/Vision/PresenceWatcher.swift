import CoreGraphics
import Foundation
import Observation

/// Watches on the resting screen for **whether a person has come up**.
///
/// The `resting → matching → opener` of `Docs/03_product-design.md` section 6. Until now staff
/// stood in by pressing `Someone walks up`.
///
/// ## Why not decide from a single frame
///
/// Face detection catches passers-by, posters and the backs of staff heads for a frame or two.
/// Greeting on a single frame makes **a robot talking to an empty room**. So
/// it collects a sample every 0.5 seconds and decides a person has come **only when a majority of a 5-second window was a face**.
///
/// ## The camera runs only on the resting screen
///
/// It calls `stop()` once the session starts. The kiosk is on all day, and keeping the front camera
/// running causes heat and battery problems, but more than that, **opening the camera while it isn't needed itself
/// exceeds the scope of biometric consent** (`Docs/03_product-design.md` section 9).
@Observable
final class PresenceWatcher {

    /// The result of deciding a person has come. The photo is passed along so it can be used for enrolment.
    struct Arrival {
        var outcome: FaceGallery.Outcome
        /// The frame used for the decision. For someone met for the first time, the face is enrolled from this photo.
        var image: CGImage?
    }

    enum State: Equatable {
        case off
        case watching
        /// There's a reason it can't be turned on. Shown as is on the staff screen.
        case unavailable(String)
    }

    private(set) var state: State = .off
    /// Face-detection ratio over the last 5-second window. Shown on the staff panel so it's judged by numbers, not feel.
    private(set) var lastWindowHitRate: Double = 0

    /// **Someone has arrived.** Who it is isn't known yet — the robot starts greeting right away.
    /// People, too, say "Come on in" to whoever opens the door first, and work out who it is in the meantime.
    var onPresence: (() -> Void)?
    /// **It's been settled who it is.** The conclusion after several looks.
    var onIdentified: ((Arrival) -> Void)?
    /// Looked several times and still can't tell. The robot's turn to make conversation. Arrives only once.
    var onStillLooking: (() -> Void)?

    /// Read in from the store. Must be refilled whenever enrolment happens.
    var gallery = FaceGallery(elders: [])

    // MARK: - Decision constants

    /// Sampling interval. The camera keeps running, but decision samples are taken only at this interval.
    private static let sampleInterval: TimeInterval = 0.5
    /// The decision window. **This is the "check every 5 seconds" that was requested.**
    private static let windowSeconds: TimeInterval = 5
    /// At least this fraction of the window must be a face for a person to be considered present.
    private static let arrivalHitRate = 0.6

    /// **Identity is never decided from a single frame.**
    ///
    /// People don't stay still. As they approach, heads turn and focus wavers.
    /// Deciding on one such frame produces the worst failure: **asking someone it knows for their name** —
    /// worse than not recognising them (`Docs/03_product-design.md` section 3).
    ///
    /// So it looks at several frames during the greeting, and **if it recognises them even once, that's who it is.**
    /// Only when every attempt fails is it treated as someone met for the first time.
    private static let identifyAttempts = 6
    private static let identifyInterval: TimeInterval = 0.7
    /// After this many failures, **the robot makes conversation** so the person looks at the screen. And it keeps looking.
    private static let stallAfterAttempts = 3

    private var windowSize: Int { Int(Self.windowSeconds / Self.sampleInterval) }

    @ObservationIgnored private let probe = FaceProbe()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var samples: [Bool] = []
    /// Once it has greeted, it doesn't call again until it returns to the resting screen.
    @ObservationIgnored private var hasFired = false
    /// `start()` is async because of the permission check. If `stop()` arrives in between,
    /// **it must not come back to life** — the camera would linger after the session started.
    @ObservationIgnored private var wantsToRun = false
    @ObservationIgnored private var attemptsMade = 0
    @ObservationIgnored private var bestSoFar: Arrival?
    @ObservationIgnored private var identifyTimer: Timer?

    // MARK: - Lifetime

    func start() {
        guard timer == nil else { return }
        wantsToRun = true
        guard Consent.isGranted(.biometric) else {
            wantsToRun = false
            state = .unavailable("No biometric (face) consent")
            return
        }
        Task { @MainActor in
            guard await probe.requestPermission() else {
                state = .unavailable("Camera permission denied")
                return
            }
            guard wantsToRun, timer == nil else { return }
            samples = []
            hasFired = false
            lastWindowHitRate = 0
            probe.start()
            if let error = probe.lastError {
                state = .unavailable(error)
                return
            }
            state = .watching
            scheduleTimer()
        }
    }

    func stop() {
        wantsToRun = false
        timer?.invalidate()
        timer = nil
        identifyTimer?.invalidate()
        identifyTimer = nil
        probe.stop()
        samples = []
        lastWindowHitRate = 0
        state = .off
    }

    /// When the session returns to the resting screen. Released so it can greet again.
    func rearm() {
        hasFired = false
        samples = []
        lastWindowHitRate = 0
        attemptsMade = 0
        bestSoFar = nil
        identifyTimer?.invalidate()
        identifyTimer = nil
    }

    private func scheduleTimer() {
        let t = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Decision

    @MainActor
    private func sample() {
        guard !hasFired else { return }
        samples.append(probe.latest.count > 0)
        if samples.count > windowSize { samples.removeFirst(samples.count - windowSize) }
        guard samples.count == windowSize else { return }

        let rate = Double(samples.filter { $0 }.count) / Double(windowSize)
        lastWindowHitRate = rate
        guard rate >= Self.arrivalHitRate else { return }

        hasFired = true
        // Start the greeting first. Identity is settled while that line is going out.
        onPresence?()
        attemptsMade = 0
        bestSoFar = nil
        attemptIdentify()
    }

    // MARK: - Identity — look several times

    @MainActor
    private func attemptIdentify() {
        attemptsMade += 1
        probe.captureFrame { [weak self] image in
            guard let self else { return }
            guard let image else {
                self.consider(Arrival(outcome: .noFace, image: nil))
                return
            }
            // There's no reason to run Vision on the main thread.
            let gallery = self.gallery
            Task.detached(priority: .userInitiated) {
                let outcome = gallery.match(image: image)
                await MainActor.run {
                    self.consider(Arrival(outcome: outcome, image: image))
                }
            }
        }
    }

    @MainActor
    private func consider(_ arrival: Arrival) {
        // Recognising them even once is the end. No reason to look further.
        if case .recognized = arrival.outcome {
            settle(arrival)
            return
        }
        if Self.isBetter(arrival, than: bestSoFar) { bestSoFar = arrival }

        if attemptsMade == Self.stallAfterAttempts { onStillLooking?() }

        guard attemptsMade < Self.identifyAttempts else {
            // With an empty gallery, looking several times gives the same result — but the photo is still used for enrolment.
            settle(bestSoFar ?? arrival)
            return
        }
        let t = Timer(timeInterval: Self.identifyInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.attemptIdentify() }
        }
        RunLoop.main.add(t, forMode: .common)
        identifyTimer = t
    }

    @MainActor
    private func settle(_ arrival: Arrival) {
        identifyTimer?.invalidate()
        identifyTimer = nil
        onIdentified?(arrival)
    }

    /// Among the failures, **the closest attempt** is kept. Its photo is also better for enrolment.
    private static func isBetter(_ candidate: Arrival, than current: Arrival?) -> Bool {
        guard let current else { return true }
        return score(candidate.outcome) < score(current.outcome)
    }

    private static func score(_ outcome: FaceGallery.Outcome) -> Float {
        switch outcome {
        case .recognized:               -1
        case let .ambiguous(best, _):   best
        case let .unknown(best):        best ?? 9
        case .noFace:                   10
        }
    }
}
