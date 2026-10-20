import AVFoundation
import SwiftUI

/// Staff-only settings screen — mode and voice.
///
/// It used to sit as a 12pt menu on the session top bar. The idea was to keep it out of the elder's sight, but
/// **it was so faint even staff couldn't find it.** `Docs/02_design-criteria.md` decided that deployment mode has
/// no staff UI at all, so putting it on the top bar never worked in the first place.
/// So it was split off into a full screen, with only the entry hidden (`TwoFingerLongPress`).
///
/// It's laid over the elder canvas (820 × 1180 absolute coordinates) as a sheet, so the canvas scale
/// doesn't apply here. **It uses ordinary iPadOS sizes for a staff distance of 40 cm.**
struct StaffSettingsView: View {
    @Bindable var speech: SpeechEngine
    @Bindable var modeStore: AppModeStore
    @State private var consent = ConsentStore()
    @State private var showsSpeechProbe = false
    @State private var showsFaceProbe = false
    @State private var showsUnderstandingCheck = false
    @State private var showsReplyLatency = false
    @State private var showsReplyPlan = false
    @State private var showsFaceMatch = false
    @State private var showsSpeechCheck = false

    @Environment(\.dismiss) private var dismiss
    @State private var showsKeySheet = false
    /// How many script lines are stored for the current voice. It means counting files, so it isn't done on every render.
    @State private var cachedForVoice = 0

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                consentSection
                engineSection
                rateSection
                previewLineSection

                switch speech.provider {
                case .apple:  appleVoiceSection
                case .openAI: openAIVoiceSection; openAICacheSection; openAIKeySection
                }

                statusSection
                probeSection
            }
            .navigationTitle("Staff settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { speech.stop(); dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .fullScreenCover(isPresented: $showsSpeechProbe) {
            SpeechProbeView()
        }
        .fullScreenCover(isPresented: $showsFaceProbe) {
            FaceProbeView()
        }
        .fullScreenCover(isPresented: $showsSpeechCheck) {
            SpeechCheckView()
        }
        .fullScreenCover(isPresented: $showsFaceMatch) {
            FaceMatchView()
        }
        .fullScreenCover(isPresented: $showsUnderstandingCheck) {
            UnderstandingCheckView()
        }
        .fullScreenCover(isPresented: $showsReplyLatency) {
            ReplyLatencyView()
        }
        .fullScreenCover(isPresented: $showsReplyPlan) {
            ReplyPlanView()
        }
        .sheet(isPresented: $showsKeySheet) {
            APIKeySheet {
                speech.syncProviderWithKey()
                refreshCachedCount()
            }
        }
        .onAppear {
            speech.refreshVoices()
            refreshCachedCount()
        }
        .onChange(of: speech.openAIVoice) { refreshCachedCount() }
        .onChange(of: speech.isWarmingUp) { refreshCachedCount() }
        // Cut the sound even when leaving without closing the settings screen.
        .onDisappear { speech.stop() }
    }

    // MARK: - Mode

    /// Switching to deployment mode removes every staff element from the screen.
    /// **The only way back is a two-finger long press**, so make that clear here.
    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $modeStore.mode) {
                ForEach(AppMode.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Mode")
        } footer: {
            Text(modeStore.mode.detail)
                .foregroundStyle(modeStore.mode == .deployment ? Theme.red : Theme.gray6B)
        }
    }

    // MARK: - Consent

    /// Records the consents obtained, item by item.
    ///
    /// **This is not the legal consent itself but a record of that fact.** The actual consent forms are kept
    /// on paper by the centre, and the app opens and closes features according to that state.
    /// Lumping them into "consent was given" leads to obtaining only conversation-record consent and then
    /// sending voice overseas (`Docs/03_product-design.md` section 9).
    private var consentSection: some View {
        Section {
            ForEach(Consent.Kind.allCases) { kind in
                Toggle(isOn: Binding(
                    get: { consent.isGranted(kind) },
                    set: { granted in
                        consent.set(kind, granted)
                        // If overseas transfer is turned off, the engine must not stay on OpenAI.
                        speech.enforceOverseasConsent()
                        // **Request the OS permission right where it's switched on.** If it's asked deep inside the feature,
                        // it fails silently without the OS ever being asked when an earlier condition blocks it.
                        if granted { Task { await SystemPermissions.request(for: kind) } }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.label)
                        Text(kind.detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.gray6B)
                    }
                }
            }
        } header: {
            Text("Consent on file")
        } footer: {
            Text("A feature opens only where the box is checked. The signed forms stay with the center. "
                 + "Turning one on also asks iOS for the permission it needs, so the box is the only "
                 + "switch staff have to find.")
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        Section {
            Picker("Engine", selection: $speech.provider) {
                ForEach(SpeechEngine.Provider.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            // Without overseas-transfer consent, OpenAI can't be chosen at all.
            .disabled(!speech.canUseOpenAI)

            if !speech.canUseOpenAI {
                Label("Without international-transfer consent, only Apple voices are available",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
            }
        } header: {
            Text("Engine")
        } footer: {
            switch speech.provider {
            case .apple:
                Text("Runs entirely on the device. No network, no billing, no personal data sent. "
                     + "In exchange, conversational English can sound flatter.")
            case .openAI:
                Text("Much better quality, but the spoken lines leave for OpenAI — "
                     + "and those lines carry the elder's name and personal history. "
                     + "Each line is cached on the device and never sent twice.")
            }
        }
    }

    // MARK: - Speech rate

    /// The rate elders can follow varies from person to person. **A value tuned in the pilot**, so
    /// it's a slider. Too slow and the speech drags, which actually makes it harder to follow.
    private var rateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rate")
                    Spacer()
                    Text(speech.rateLabel)
                        .foregroundStyle(Theme.gray6B)
                        .monospacedDigit()
                }
                HStack(spacing: 12) {
                    Text("Slower").font(.caption).foregroundStyle(Theme.gray8A)
                    Slider(value: $speech.rateScale,
                           in: SpeechEngine.minRateScale...SpeechEngine.maxRateScale,
                           step: 0.02)
                    Text("Normal").font(.caption).foregroundStyle(Theme.gray8A)
                }
            }
            Button {
                speech.previewVoice()
            } label: {
Label("Hear it at this rate", systemImage: "play.circle")
            }
            if speech.rateScale != SpeechEngine.defaultRateScale {
                Button("Back to default (\(Int(SpeechEngine.defaultRateScale * 100))%)") {
                    speech.rateScale = SpeechEngine.defaultRateScale
                }
            }
        } header: {
            Text("Speaking rate")
        } footer: {
            Text("100% is Apple's default rate. Lower it if the elder cannot keep up, but "
                 + "too low and the words drag out and get harder to follow. "
                 + "**Tune it with the elder in front of you.**")
        }
    }

    // MARK: - Preview sentence

    private var previewLineSection: some View {
        Section {
            Picker("Line", selection: $speech.previewLine) {
                ForEach(speech.previewCandidates, id: \.self) { line in
                    Text(line).tag(line)
                }
            }
        } header: {
            Text("Preview line")
        } footer: {
            Text("These are the lines the script actually speaks. A short greeting tells you "
                 + "nothing about pacing on a long sentence — try the longest line too.")
        }
    }

    // MARK: - Apple voices

    @ViewBuilder
    private var appleVoiceSection: some View {
        Section {
            if speech.appleVoices.isEmpty {
                Label("No English voices are installed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.red)
            } else {
                ForEach(speech.appleVoices, id: \.identifier) { voice in
                    voiceRow(
                        title: voice.name,
                        badge: Self.qualityBadge(voice.quality),
                        badgeColor: Self.qualityColor(voice.quality),
                        isSelected: speech.selectedVoiceID == voice.identifier,
                        isPlaying: speech.previewingVoiceID == voice.identifier,
                        select: { speech.selectedVoiceID = voice.identifier },
                        play: { speech.previewApple(voice) }
                    )
                }
            }
        } header: {
            Text("Voices · English, installed on this iPad")
        } footer: {
            if speech.hasOnlyDefaultQuality || speech.appleVoices.isEmpty {
                Text("Only Default quality is installed. The default English voice sounds robotic "
                     + "and is not fit for conversation. Download an Enhanced or Premium voice below.")
                .foregroundStyle(Theme.red)
            } else {
                Text("Premium sounds more natural than Enhanced, and Enhanced more than Default.")
            }
        }

        Section {
            Button {
                openSystemSettings()
            } label: {
                Label("Get English voices in Settings", systemImage: "arrow.up.forward.app")
            }
            Button {
                speech.refreshVoices()
            } label: {
Label("Refresh the list", systemImage: "arrow.clockwise")
            }
        } footer: {
            Text("Settings → Accessibility → Spoken Content → Voices → English. "
                 + "After downloading you must tap Refresh for it to appear above.")
        }
    }

    // MARK: - OpenAI voices

    @ViewBuilder
    private var openAIVoiceSection: some View {
        Section {
            if speech.hasAPIKey {
                ForEach(OpenAITTSClient.voices, id: \.self) { name in
                    voiceRow(
                        title: name,
                        badge: nil,
                        badgeColor: .clear,
                        isSelected: speech.openAIVoice == name,
                        isPlaying: speech.previewingVoiceID == name,
                        select: { speech.openAIVoice = name },
                        play: { speech.previewOpenAI(name) }
                    )
                }
            } else {
                Label("Enter an API key to choose a voice", systemImage: "key")
                    .foregroundStyle(Theme.gray6B)
            }
        } header: {
            Text("Voices · OpenAI")
        } footer: {
            if speech.hasAPIKey {
                Text("Start with coral · sage · marin. "
                     + "Previews are cached too, so none of these calls is wasted.")
            }
        }
    }

    @ViewBuilder
    private var openAICacheSection: some View {
        if speech.hasAPIKey {
            Section {
                HStack {
                    Text("Cached lines")
                    Spacer()
                    Text("\(cachedForVoice) / \(speech.scriptLineCount)")
                        .foregroundStyle(cachedForVoice == speech.scriptLineCount
                                         ? Theme.green : Theme.gray6B)
                        .monospacedDigit()
                }

                if speech.isWarmingUp {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: Double(speech.warmUpDone),
                                     total: Double(max(speech.warmUpTotal, 1)))
                        Text("Generating \(speech.warmUpDone) / \(speech.warmUpTotal)")
                            .font(.footnote)
                            .foregroundStyle(Theme.gray6B)
                    }
                } else {
                    Button {
                        speech.warmUpScript()
                    } label: {
                        Label("Pre-generate all", systemImage: "square.and.arrow.down")
                    }
                }

                Button(role: .destructive) {
                    speech.clearCache()
                    refreshCachedCount()
                } label: {
Label("Delete all cached audio", systemImage: "trash")
                }
            } header: {
                Text("Cached audio · \(speech.openAIVoice)")
            } footer: {
                Text("The cache key covers voice, model, instructions and rate. "
                     + "Change the voice and it regenerates from zero — "
                     + "**settle on a voice first**, then pre-generate. "
                     + "Once pre-generated, a session uses no network at all.")
            }
        }
    }

    @ViewBuilder
    private var openAIKeySection: some View {
        Section {
            Button {
                showsKeySheet = true
            } label: {
                if let masked = APIKeyStore.maskedKey {
Label("Change API key · \(masked)", systemImage: "key")
                } else {
Label("Enter API key…", systemImage: "key")
                }
            }
        } footer: {
            Text("The key is stored only in this device's Keychain. "
                 + "Move it to a server before deployment — "
                 + "a key shipped inside a client app can always be extracted.")
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(speech.statusLabel)
                    .foregroundStyle(speech.hasProblem ? Theme.red : Theme.gray6B)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Voice on", isOn: $speech.isEnabled)
        } footer: {
            if speech.hasProblem {
                Text("Red text means a failure. 401 is the key, 429 is credit or rate limit. "
                     + "It falls back to an Apple voice, so you still hear sound — "
                     + "**if the text is red, what you hear is not OpenAI.**")
                .foregroundStyle(Theme.red)
            }
        }
    }

    // MARK: - Measurement tools

    /// `Docs/05_implementation-roadmap.md` section 2 — the table that must be built before starting stage 1.
    private var probeSection: some View {
        Section {
            Button {
                showsSpeechProbe = true
            } label: {
                Label("STT accuracy probe", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(!consent.isGranted(.recording))
            Button {
                showsFaceProbe = true
            } label: {
Label("Face detection probe", systemImage: "face.dashed")
            }
            .disabled(!consent.isGranted(.biometric))
            Button {
                showsFaceMatch = true
            } label: {
                Label("Face matching probe", systemImage: "person.crop.rectangle.badge.checkmark")
            }
            .disabled(!consent.isGranted(.biometric))
            Button {
                showsSpeechCheck = true
            } label: {
                Label("Speech check — why is it not hearing?",
                      systemImage: "stethoscope")
            }
            Button {
                showsUnderstandingCheck = true
            } label: {
                Label("Understanding check — can it use what it hears?",
                      systemImage: "brain")
            }
            Button {
                showsReplyLatency = true
            } label: {
                Label("Reply latency — can it speak its own lines?",
                      systemImage: "timer")
            }
            Button {
                showsReplyPlan = true
            } label: {
                Label("Reply plan — choosing, not writing",
                      systemImage: "arrow.triangle.branch")
            }
            Toggle(isOn: Binding(
                get: { AutoGreet.isEnabled },
                set: { AutoGreet.isEnabled = $0 }
            )) {
                Label("Greet automatically at Resting", systemImage: "sensor.fill")
            }
            .disabled(!consent.isGranted(.biometric))
        } header: {
            Text("Probes")
        } footer: {
            Text("STT needs recording consent; the face probes need biometric consent. "
                 + "Detection only asks whether a face is visible, matching only measures Feature Print distance. "
                 + "Automatic greeting watches the front camera while the screen is Resting: it samples every "
                 + "0.5s and greets when a face is present for most of a 5-second window. A recognized person is "
                 + "greeted by name; anyone else is asked for their name and enrolled from that conversation. "
                 + "The camera is released as soon as the session starts.")
        }
    }

    // MARK: - Shared rows

    /// One voice row. **Selection and playback are separate** — tap the row to choose, tap the speaker to hear it.
    private func voiceRow(title: String,
                          badge: String?,
                          badgeColor: Color,
                          isSelected: Bool,
                          isPlaying: Bool,
                          select: @escaping () -> Void,
                          play: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: select) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Theme.blue : Theme.gray8A)
                        .font(.title3)
                    Text(title)
                        .foregroundStyle(Theme.ink)
                    if let badge {
                        Text(badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(badgeColor)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: play) {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? Theme.blue : Theme.gray6B)
            }
            .buttonStyle(.plain)
            .disabled(speech.isPreparing)
        }
        .frame(minHeight: Theme.Layout.staffRowHeight)
    }

    private func refreshCachedCount() {
        cachedForVoice = speech.hasAPIKey ? speech.cachedCount(forVoice: speech.openAIVoice) : 0
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private static func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium:  "Premium"
        case .enhanced: "Enhanced"
        default:        "Default"
        }
    }

    private static func qualityColor(_ quality: AVSpeechSynthesisVoiceQuality) -> Color {
        switch quality {
        case .premium:  Theme.green
        case .enhanced: Theme.blue
        default:        Theme.red
        }
    }
}
