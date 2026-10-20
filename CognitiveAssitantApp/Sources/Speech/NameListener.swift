import AVFoundation
import Observation
import Speech

/// **Transcribes the name** said by someone met for the first time.
///
/// There's a reason it's kept apart from `SpeechProbe`. That one is a measurement tool that **keeps recording files**
/// to measure recognition accuracy. This one just takes a single name and fills it in on screen,
/// and **never saves audio to a file.** Merging them into one class would pile up measurement recordings
/// with every session.
///
/// ## STT isn't trusted — staff confirm
///
/// As `Docs/05_implementation-roadmap.md` section 2 points out, **proper nouns are STT's weak spot.**
/// Names aren't in the dictionary, and ageing voices, accents and dentures make it worse. Enrolling under a wrong name
/// means the robot calls them the wrong name next time —
/// **calling someone wrongly is worse than not recognising them** (`Docs/03_product-design.md` section 3).
///
/// So the text produced here **only fills the input field and is never saved as is.**
/// Staff can check and correct it, and it's enrolled only when confirm is pressed.
///
/// ## Pinned to on-device
///
/// `requiresOnDeviceRecognition = true`. The elder's voice never leaves the device.
@Observable
final class NameListener {

    enum State: Equatable {
        case idle
        case listening
        /// Why it can't be turned on. Shown as is on the staff panel.
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Interim recognition result. Updated while speaking.
    private(set) var partialText: String = ""

    // MARK: - Instrumentation (for diagnosis)

    /// **The error the recogniser returned.** It used to be thrown away — the cause was arriving here while the screen stayed quiet.
    private(set) var lastError: String?
    /// Loudness of the sound coming from the microphone (RMS, 0…1). **If this doesn't move, no sound is getting in**;
    /// if it moves but no text comes out, it's the recogniser. Separates the two causes without cross-checking.
    private(set) var inputLevel: Float = 0
    /// Number of buffers the tap received. 0 means the audio path never opened at all.
    private(set) var bufferCount = 0
    /// The input format actually opened. 0 Hz means the session wasn't set up for recording.
    private(set) var formatNote = "—"

    var isListening: Bool { state == .listening }

    /// Without the English on-device model, names can't be transcribed. Staff write them by hand.
    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    /// Passes on the transcribed name. Arrives on the main thread.
    @ObservationIgnored var onHeard: ((String) -> Void)?
    /// **When it ends having heard nothing.** If the screen quietly stops, staff can't even tell
    /// whether it was on. It carries on with the robot asking again.
    @ObservationIgnored var onNothingHeard: (() -> Void)?

    // MARK: - End-of-speech detection

    /// **How long to wait depends on what's being listened for.**
    ///
    /// A name is a single phrase, so 2.5 seconds of silence really means it's over. But using the same value
    /// for recall answers **cuts the story off midway** — pausing to find words is a symptom of cognitive decline,
    /// and failing to take in a story because of that symptom is the worst thing this product can do
    /// (`Docs/05_implementation-roadmap.md` section 2).
    enum Purpose {
        /// Name · first story. Takes a short phrase that staff confirm.
        case shortAnswer
        /// Free answer. The elder is telling a story.
        case story

        /// If there's no new speech for this long, it's treated as finished.
        var silenceSeconds: TimeInterval {
            switch self {
            case .shortAnswer: 2.5
            case .story:       5.0
            }
        }

        /// **The microphone isn't left open indefinitely** — this device sits in front of elders.
        /// The story setting is longer because cutting off at 15 seconds chops sentences in the middle.
        var maxSeconds: TimeInterval {
            switch self {
            case .shortAnswer: 15
            case .story:       90
            }
        }
    }

    private var purpose: Purpose = .shortAnswer

    @ObservationIgnored private let recognizer =
        SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var deadline: Timer?
    @ObservationIgnored private var lastHeardAt: Date?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else {
            await MainActor.run { state = .unavailable("Speech recognition permission was denied") }
            return false
        }
        let micOK = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micOK else {
            await MainActor.run { state = .unavailable("Microphone permission was denied") }
            return false
        }
        return true
    }

    // MARK: - Lifetime

    @MainActor
    func start(for purpose: Purpose = .shortAnswer) {
        self.purpose = purpose
        guard state != .listening else { return }
        guard Consent.isGranted(.recording) else {
            state = .unavailable("No voice-recording consent")
            return
        }
        Task { @MainActor in
            guard await requestPermissions() else { return }
            guard let recognizer, recognizer.isAvailable else {
                state = .unavailable("English speech recognition is unavailable")
                return
            }
            guard recognizer.supportsOnDeviceRecognition else {
                // If enabled, audio goes to Apple's servers. Better to write it by hand than that.
                state = .unavailable("No on-device English model — type the name instead")
                return
            }
            do { try begin(with: recognizer) } catch {
                state = .unavailable("Could not start listening · \(error.localizedDescription)")
                cleanUp()
            }
        }
    }

    @MainActor
    private func begin(with recognizer: SFSpeechRecognizer) throws {
        partialText = ""
        lastError = nil
        inputLevel = 0
        bufferCount = 0

        // SpeechEngine set it to .playback. It has to change to listen.
        let session = AVAudioSession.sharedInstance()
        // **Don't use `.measurement`.** That mode turns off all system audio processing,
        // and **that includes echo cancellation (AEC).** This device speaks through the speaker while listening
        // with the same microphone, so with processing off the robot transcribes its own voice.
        //
        // It actually happened on a device on 2026-09-01 — the very sentence the robot said, "What did you have for lunch
        // today?", went into the store as the elder's answer.
        // `.voiceChat` is the call route, so AEC is on.
        //
        // `SpeechProbe` still uses `.measurement`. Its **purpose is measuring recognition accuracy on uncorrected input**,
        // so turning processing on would make the measurement meaningless.
        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        // Hint that the input is likely a person's name.
        request.taskHint = .search
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        formatNote = String(format: "%.0f Hz · %d ch",
                            format.sampleRate, format.channelCount)
        // Installing a tap at 0 Hz lets no sound in. Stop here instead of failing silently.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "NameListener", code: 1, userInfo: [
                NSLocalizedDescriptionKey:
                    "The microphone input format is \(formatNote) — the audio session did not open for recording"
            ])
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += channel[i] * channel[i] }
            let rms = (sum / Float(n)).squareRoot()
            Task { @MainActor in
                self?.bufferCount += 1
                self?.inputLevel = rms
            }
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.lastError = error.localizedDescription
                }
            }
            guard let result else { return }
            Task { @MainActor in
                self.partialText = result.bestTranscription.formattedString
                self.lastHeardAt = .now
            }
        }

        engine.prepare()
        try engine.start()
        lastHeardAt = .now
        state = .listening
        startTimers()
    }

    @MainActor
    private func startTimers() {
        let silence = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .listening else { return }
                guard !self.partialText.isEmpty, let last = self.lastHeardAt else { return }
                if Date.now.timeIntervalSince(last) >= self.purpose.silenceSeconds { self.finish() }
            }
        }
        RunLoop.main.add(silence, forMode: .common)
        silenceTimer = silence

        let cap = Timer(timeInterval: purpose.maxSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        RunLoop.main.add(cap, forMode: .common)
        deadline = cap
    }

    /// When staff stop it by hand, or it stops on its own after going quiet.
    @MainActor
    func finish() {
        guard state == .listening else { return }
        let heard = NameListener.cleanedName(from: partialText)
        cleanUp()
        state = .idle
        if heard.isEmpty { onNothingHeard?() } else { onHeard?(heard) }
    }

    /// Just turns it off without passing on a result. Used when leaving the screen.
    @MainActor
    func cancel() {
        guard state == .listening else { return }
        cleanUp()
        state = .idle
    }

    @MainActor
    private func cleanUp() {
        silenceTimer?.invalidate(); silenceTimer = nil
        deadline?.invalidate(); deadline = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        lastHeardAt = nil

        // Switch back to the playback session so the robot can speak again.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: - Extracting the name

    /// Keeps only the name from the transcribed sentence.
    ///
    /// People answer like "My name is Margaret Walsh". Saved as is, the full name would be
    /// that whole sentence. **Only strip the stock phrase in front and leave the rest alone** —
    /// being any cleverer raises the risk of cutting off the real name. Staff make the final call.
    static func cleanedName(from transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        let leadIns = [
            "my name is", "my name's", "the name is", "they call me",
            "i am", "i'm", "it is", "it's", "this is", "call me", "name is"
        ]
        var changed = true
        while changed {
            changed = false
            let lower = text.lowercased()
            for lead in leadIns where lower.hasPrefix(lead) {
                text = String(text.dropFirst(lead.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,.-"))
                changed = true
                break
            }
        }

        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        // Names aren't long. If a whole sentence is left, keep only the first four words so staff can fix it.
        let words = text.split(separator: " ")
        if words.count > 4 { text = words.prefix(4).joined(separator: " ") }
        return text
    }
}
