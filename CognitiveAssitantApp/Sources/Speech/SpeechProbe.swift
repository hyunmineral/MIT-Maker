import AVFoundation
import Observation
import Speech

/// Records the elder's speech and transcribes it **on-device**.
///
/// The prerequisite measurement tool from `Docs/05_implementation-roadmap.md` section 2. Without the table it produces,
/// neither the stage-1 (STT) engine nor the schedule can be decided.
///
/// ## ⚠️ It must be on-device
///
/// `SFSpeechRecognizer` defaults to **sending to Apple's servers**. Used as is, the elder's
/// voice leaves the device, which counts as overseas transfer. So it's **pinned** with
/// `requiresOnDeviceRecognition = true` — not left as an on/off option.
/// Comparison with cloud engines is done offline by exporting the recording files separately.
///
/// On-device recognition works only once the English model is downloaded to the device. Without it
/// `supportsOnDeviceRecognition` is false, and that fact is itself part of the measurement results.
@Observable
final class SpeechProbe: NSObject {

    enum State: Equatable {
        case idle
        case denied(String)
        case recording
        case finishing
    }

    private(set) var state: State = .idle
    /// Interim recognition result. Keeps updating while speaking.
    private(set) var partialText: String = ""
    private(set) var lastError: String?
    /// When this recording started.
    private(set) var startedAt: Date?

    /// Whether the English on-device model is on the device. Without it, measurement is impossible.
    var supportsOnDevice: Bool { recognizer?.supportsOnDeviceRecognition ?? false }
    var isRecording: Bool { state == .recording }

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var fileName: String?

    /// When recording ends, passes on (file name, recognition result, duration).
    @ObservationIgnored var onFinish: ((String, String, TimeInterval) -> Void)?

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechOK else {
            await MainActor.run { state = .denied("Speech recognition permission was denied") }
            return false
        }

        let micOK = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micOK else {
            await MainActor.run { state = .denied("Microphone permission was denied") }
            return false
        }
        return true
    }

    // MARK: - Recording

    func start() {
        guard state != .recording else { return }
        // Don't start without recording consent. The screen blocks it too, but check once more here.
        guard Consent.isGranted(.recording) else {
            state = .denied("No voice-recording consent")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .denied("English speech recognition is unavailable")
            return
        }

        do {
            try beginSession()
        } catch {
            lastError = "Could not start recording · \(error.localizedDescription)"
            state = .idle
            cleanUp()
        }
    }

    private func beginSession() throws {
        partialText = ""
        lastError = nil

        // SpeechEngine set the session to .playback. It has to change to record.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep the elder's voice from leaving the device. Fixed, not optional.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let name = "sample-\(Int(Date.now.timeIntervalSince1970)).caf"
        let url = SpeechSampleStore.url(for: name)
        file = try AVAudioFile(forWriting: url, settings: format.settings)
        fileName = name

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            try? self.file?.write(from: buffer)
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in self.partialText = result.bestTranscription.formattedString }
            }
            if let error, self.state == .recording {
                Task { @MainActor in
                    self.lastError = "Recognition failed · \(error.localizedDescription)"
                }
            }
        }

        engine.prepare()
        try engine.start()
        startedAt = .now
        state = .recording
    }

    func stop() {
        guard state == .recording else { return }
        state = .finishing

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()

        // Give the recogniser a moment to process the last buffer. Cutting off immediately clips the final words.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            let duration = self.startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
            if let name = self.fileName {
                self.onFinish?(name, self.partialText, duration)
            }
            self.cleanUp()
            self.state = .idle
        }
    }

    private func cleanUp() {
        task?.cancel()
        task = nil
        request = nil
        file = nil
        fileName = nil
        startedAt = nil

        // Switch back to the playback session so the robot can speak again.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}
