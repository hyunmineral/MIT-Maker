import AVFoundation
import Observation

/// Pilot stage 0 — the robot reads its lines aloud.
///
/// Two engines can be swapped in.
///
/// - **Apple** (`AVSpeechSynthesizer`): on-device. No network, billing or personal-data transfer.
///   In exchange, English conversational quality may be lower.
/// - **OpenAI** (`/v1/audio/speech`): much better quality. In exchange there's network use and billing, and
///   the line text goes to OpenAI — lines contain the elder's name and personal history.
///
/// Audio received from OpenAI is stored in `VoiceCache`. The stage-0 script is fixed, so
/// once fetched it means **0 s latency · no extra billing · works offline**.
/// On failure it quietly falls back to Apple — better than going silent in front of an elder.
///
/// Elder answers are still entered on their behalf by staff pressing choices at the bottom of the screen (Wizard of Oz).
/// In stage 1 STT, and in stage 2 the conversation engine, fill that role.
@Observable
final class SpeechEngine: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

    enum Provider: String, CaseIterable, Identifiable {
        case apple, openAI
        var id: String { rawValue }
        var label: String {
            switch self {
            case .apple:  "Apple · offline"
            case .openAI: "OpenAI"
            }
        }
    }

    // MARK: - State

    /// Staff can switch it off. To keep it quiet during development and demos.
    var isEnabled: Bool = true {
        didSet { if !isEnabled { stop() } }
    }

    var provider: Provider = .apple {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
            stop()
        }
    }

    var openAIVoice: String = "marin" {
        didSet { UserDefaults.standard.set(openAIVoice, forKey: Self.voiceKeyOpenAI) }
    }

    private(set) var isSpeaking = false
    /// Waiting for the OpenAI response. Skipped if it's in the cache.
    private(set) var isPreparing = false
    /// The last failure reason. Shows as one line in the top bar.
    private(set) var lastError: String?

    /// Progress of pre-generating everything.
    private(set) var warmUpDone = 0
    private(set) var warmUpTotal = 0
    var isWarmingUp: Bool { warmUpTotal > 0 && warmUpDone < warmUpTotal }

    var hasAPIKey: Bool { APIKeyStore.hasKey }
    var cachedCount: Int { VoiceCache.fileCount }

    // MARK: - Internals

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var audioPlayer: AVAudioPlayer?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    /// The tone for speaking to elders. Only applied by `gpt-4o-mini-tts`.
    @ObservationIgnored
    private let instructions = """
        Speak in a warm, kind voice, slowly and clearly, as if talking with an older adult. \
        Don't rush. Leave a little space between sentences.
        """

    @ObservationIgnored private let model = "gpt-4o-mini-tts"
    /// Slowed slightly so elders can follow. Tone is handled by `instructions`.
    @ObservationIgnored private let openAISpeed = 0.95

    private static let providerKey = "SpeechEngine.provider"
    private static let voiceKeyOpenAI = "SpeechEngine.openAIVoice"
    private static let voiceKeyApple = "SpeechEngine.selectedVoiceID"

    override init() {
        super.init()
        synthesizer.delegate = self
        activateAudioSession()
        refreshVoices()

        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.providerKey),
           let saved = Provider(rawValue: raw) {
            provider = saved
        }
        if let voice = defaults.string(forKey: Self.voiceKeyOpenAI) {
            openAIVoice = voice
        }
        if defaults.object(forKey: Self.rateKey) != nil {
            rateScale = defaults.double(forKey: Self.rateKey)
        }
        // If the key was deleted but the engine is still OpenAI, every line fails and then falls back. Revert ahead of time.
        if provider == .openAI && !APIKeyStore.hasKey {
            provider = .apple
        }
        enforceOverseasConsent()
    }

    /// Without overseas-transfer consent, the OpenAI path is not used.
    ///
    /// Lines contain **names and personal history** ("Dorothy! You made it.").
    /// Once sent without consent it can't be undone, so separately from blocking it in the settings screen,
    /// the engine blocks it once more. `Docs/03_product-design.md` section 9.
    func enforceOverseasConsent() {
        guard provider == .openAI, !Consent.isGranted(.overseas) else { return }
        provider = .apple
        lastError = "No international-transfer consent · switched to an Apple voice"
    }

    // MARK: - Speaking

    /// Reads the line on the elder screen.
    ///
    /// Lines contain `\n` for on-screen line breaks. Reading them as is breaks the flow of the sentence, so
    /// they're replaced with spaces — line breaks are **visual layout**, not pauses in speech.
    ///
    /// - Parameter force: speak even when voice is switched off. For previews only.
    func speak(_ text: String, force: Bool = false) {
        stop()
        guard isEnabled || force else { return }

        let spoken = Self.normalized(text)
        guard !spoken.isEmpty else { return }

        switch provider {
        case .apple:  speakWithApple(spoken)
        case .openAI: speakWithOpenAI(spoken)
        }
    }

    func stop() {
        fetchTask?.cancel()
        fetchTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        isPreparing = false
        previewingVoiceID = nil
    }

    /// Plays the preview sentence in the currently selected voice.
    /// It has to work even with voice switched off so staff can check it in advance.
    func previewVoice() {
        speak(previewLine, force: true)
    }

    static let defaultPreviewLine = "Dorothy! You made it."

    /// The sentence used for previews. Staff can pick it from the script —
    /// a short greeting alone can't compare the rhythm of longer sentences.
    var previewLine: String = SpeechEngine.defaultPreviewLine

    /// Preview sentence candidates. They're the actual lines that get read, so you hear exactly how
    /// the chosen voice will sound on site.
    var previewCandidates: [String] { SessionScript.allSpokenLines }

    /// The voice whose preview is currently playing. Used to mark only that row in the list.
    private(set) var previewingVoiceID: String?

    /// Listens to just that voice **without changing the selection** in the list.
    ///
    /// It used to play automatically the moment you picked one, but touching the menu in front of an elder
    /// meant the robot suddenly blurting something out, so playback was split into an explicit action.
    func previewApple(_ voice: AVSpeechSynthesisVoice) {
        stop()
        let utterance = AVSpeechUtterance(string: Self.normalized(previewLine))
        utterance.voice = voice
        utterance.rate = appleRate
        previewingVoiceID = voice.identifier
        synthesizer.speak(utterance)
    }

    /// Listens to one OpenAI voice. Uses no network if it's in the cache.
    ///
    /// **Previews accumulate in the cache too.** The preview sentences are script lines verbatim, so
    /// it's not a wasted call — it moves `Pre-generate all` one line ahead.
    func previewOpenAI(_ name: String) {
        stop()
        guard Consent.isGranted(.overseas) else {
            lastError = "Preview needs international-transfer consent"
            return
        }
        guard let key = APIKeyStore.load() else {
            lastError = "No API key"
            return
        }
        let text = Self.normalized(previewLine)
        let signature = VoiceCache.signature(text: text, model: model, voice: name,
                                             instructions: instructions, speed: openAISpeed)
        previewingVoiceID = name

        if VoiceCache.has(signature) {
            play(VoiceCache.url(for: signature))
            return
        }

        let client = OpenAITTSClient(apiKey: key, model: model, voice: name,
                                     instructions: instructions, speed: openAISpeed)
        isPreparing = true
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await client.synthesize(text)
                try VoiceCache.store(data, for: signature)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isPreparing = false
                    self.lastError = nil
                    self.play(VoiceCache.url(for: signature))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isPreparing = false
                    self.previewingVoiceID = nil
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Number of script lines read aloud. The denominator of cache progress.
    var scriptLineCount: Int { SessionScript.allSpokenLines.count }

    /// How many script lines are already stored for the given OpenAI voice.
    ///
    /// The voice is part of the cache key, so **each voice is counted separately.** The fact that changing the voice
    /// starts again from 0 should show plainly on screen.
    func cachedCount(forVoice name: String) -> Int {
        SessionScript.allSpokenLines.reduce(into: 0) { total, line in
            let signature = VoiceCache.signature(text: Self.normalized(line), model: model,
                                                 voice: name, instructions: instructions,
                                                 speed: openAISpeed)
            if VoiceCache.has(signature) { total += 1 }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - OpenAI path

    private func speakWithOpenAI(_ text: String) {
        // The last line of defence. Check once more right before the line actually goes out.
        guard Consent.isGranted(.overseas) else {
            lastError = "No international-transfer consent · switched to an Apple voice"
            provider = .apple
            speakWithApple(text)
            return
        }
        guard let key = APIKeyStore.load() else {
            lastError = "No API key"
            speakWithApple(text)
            return
        }

        let client = makeClient(key: key)
        let signature = signature(for: text)

        // If it's in the cache, don't touch the network.
        if VoiceCache.has(signature) {
            play(VoiceCache.url(for: signature))
            return
        }

        isPreparing = true
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await client.synthesize(text)
                try VoiceCache.store(data, for: signature)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isPreparing = false
                    self.lastError = nil
                    self.play(VoiceCache.url(for: signature))
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isPreparing = false
                    self.lastError = error.localizedDescription
                    // Better to speak at lower quality than to go silent in front of an elder.
                    self.speakWithApple(text)
                }
            }
        }
    }

    private func makeClient(key: String) -> OpenAITTSClient {
        OpenAITTSClient(apiKey: key, model: model, voice: openAIVoice,
                        instructions: instructions, speed: openAISpeed)
    }

    private func signature(for text: String) -> String {
        VoiceCache.signature(text: text, model: model, voice: openAIVoice,
                             instructions: instructions, speed: openAISpeed)
    }

    private func play(_ url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            isSpeaking = true
            player.play()
        } catch {
            lastError = "Playback failed · \(error.localizedDescription)"
            isSpeaking = false
        }
    }

    // MARK: - Pre-generate all

    /// Fetches every line of the script in advance to fill the cache.
    ///
    /// Press it once before the pilot starts and the session uses no network at all.
    /// Even if the centre's Wi-Fi is flaky, nothing cuts out in front of the elder.
    func warmUpScript() {
        // Pre-generating also sends sentences overseas. Don't start without consent.
        guard Consent.isGranted(.overseas) else {
            lastError = "Pre-generating needs international-transfer consent"
            return
        }
        guard let key = APIKeyStore.load() else {
            lastError = "No API key"
            return
        }
        let lines = SessionScript.allSpokenLines
        let client = makeClient(key: key)

        warmUpDone = 0
        warmUpTotal = lines.count

        Task { [weak self] in
            guard let self else { return }
            for line in lines {
                let text = Self.normalized(line)
                let signature = self.signature(for: text)
                if !VoiceCache.has(signature) {
                    do {
                        let data = try await client.synthesize(text)
                        try VoiceCache.store(data, for: signature)
                    } catch {
                        await MainActor.run { self.lastError = error.localizedDescription }
                    }
                }
                await MainActor.run { self.warmUpDone += 1 }
            }
            await MainActor.run {
                if self.lastError == nil { self.warmUpTotal = 0; self.warmUpDone = 0 }
            }
        }
    }

    /// For when you want to regenerate with a different voice. Deletes every saved mp3.
    func clearCache() {
        stop()
        VoiceCache.clear()
    }

    /// Call after entering or deleting the key.
    ///
    /// If there's no key but the engine is still OpenAI, every line fails and then falls back —
    /// delaying the first words in front of the elder. Without a key, revert to Apple ahead of time.
    func syncProviderWithKey() {
        lastError = nil
        if !APIKeyStore.hasKey {
            provider = .apple
        }
        enforceOverseasConsent()
    }

    /// OpenAI can be chosen only with overseas-transfer consent. The settings screen locks on this value.
    var canUseOpenAI: Bool { Consent.isGranted(.overseas) }

    // MARK: - Apple path

    private func speakWithApple(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentAppleVoice
        utterance.rate = appleRate
        utterance.postUtteranceDelay = 0.15
        synthesizer.speak(utterance)
    }

    /// Speech-rate multiplier. **A value that has to be tuned in the pilot in front of elders**, so
    /// it's not hard-coded but adjusted in staff settings.
    ///
    /// Default 0.78 — Apple's default rate is too fast for elders to follow.
    /// Lowering it too far drags the speech out and makes it harder to follow, so 0.6 is the floor.
    var rateScale: Double = SpeechEngine.defaultRateScale {
        didSet {
            UserDefaults.standard.set(rateScale, forKey: Self.rateKey)
            stop()
        }
    }

    static let defaultRateScale: Double = 0.78
    static let minRateScale: Double = 0.6
    static let maxRateScale: Double = 1.0
    private static let rateKey = "SpeechEngine.rateScale"

    private var appleRate: Float {
        AVSpeechUtteranceDefaultSpeechRate * Float(rateScale)
    }

    /// Rate label shown on screen. 100% is Apple's default.
    var rateLabel: String { "\(Int(rateScale * 100))%" }

    /// English voices installed on the device. Sorted by quality, highest first.
    private(set) var appleVoices: [AVSpeechSynthesisVoice] = []

    /// The Apple voice staff chose. Changing it saves to the device immediately —
    /// the kiosk is switched off and on every day, so staff can't be made to choose again at every start.
    var selectedVoiceID: String = "" {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: Self.voiceKeyApple) }
    }

    var currentAppleVoice: AVSpeechSynthesisVoice? {
        appleVoices.first { $0.identifier == selectedVoiceID } ?? appleVoices.first
    }

    /// True if there are no enhanced or premium voices at all. The menu explains how to download them.
    var hasOnlyDefaultQuality: Bool {
        !appleVoices.isEmpty && appleVoices.allSatisfy { $0.quality == .default }
    }

    func label(for voice: AVSpeechSynthesisVoice) -> String {
        "\(voice.name) · \(Self.qualityName(voice.quality))"
    }

    /// Re-reads the list of installed voices.
    ///
    /// The app doesn't notice new voices downloaded in Settings on its own, so the menu has a refresh.
    /// Where to get them: **Settings → Accessibility → Spoken Content → Voices → English**.
    func refreshVoices() {
        appleVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                let (a, b) = (Self.rank(of: $0.quality), Self.rank(of: $1.quality))
                return a == b ? $0.name < $1.name : a > b
            }

        let saved = UserDefaults.standard.string(forKey: Self.voiceKeyApple) ?? ""
        selectedVoiceID = appleVoices.contains { $0.identifier == saved }
            ? saved
            : (appleVoices.first?.identifier ?? "")
    }

    private static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:  "Premium"
        case .enhanced: "Enhanced"
        default:        "Default"
        }
    }

    private static func rank(of quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium:  3
        case .enhanced: 2
        default:        1
        }
    }

    // MARK: - Top bar display

    var statusLabel: String {
        if isWarmingUp { return "Generating \(warmUpDone)/\(warmUpTotal)" }
        if isPreparing { return "Fetching…" }
        if isSpeaking  { return "Speaking" }
        if let lastError { return lastError }
        switch provider {
        case .apple:
            return appleVoices.isEmpty ? "No English voice"
                                       : (currentAppleVoice.map(label(for:)) ?? "—")
        case .openAI:
            return "OpenAI · \(openAIVoice)"
        }
    }

    var hasProblem: Bool { lastError != nil }

    // MARK: - Audio session

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // `.playback` ignores the silent switch. It's a kiosk, so nobody is beside it to check the switch.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: - Delegate

    // AVSpeechSynthesizer callbacks have no documented thread guarantee, so hop to main.

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.previewingVoiceID = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.previewingVoiceID = nil
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.previewingVoiceID = nil
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.previewingVoiceID = nil
            self.lastError = "Decoding failed · \(error?.localizedDescription ?? "cause unknown")"
        }
    }
}
