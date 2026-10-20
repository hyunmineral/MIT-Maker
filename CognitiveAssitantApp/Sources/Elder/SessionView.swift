import SwiftData
import SwiftUI

/// 1a — interactive screen that walks through a whole session, from face recognition to delayed recall.
///
/// Absolute coordinates on an 820 × 1180 (portrait) canvas. This is the pilot (Wizard of Oz) layout:
/// **the top 980 is the elder stage and the bottom 200 is the staff panel** (`Docs/04_screen-design.md` section 2).
///
/// The stage is **top-aligned**, not centred — the front camera sits at the top centre of the screen,
/// so the eyes' y is the gaze error. Lines always start at the same y regardless of expression.
struct SessionView: View {
    var modeStore: AppModeStore

    @Environment(\.modelContext) private var context
    @State private var model = SessionViewModel()
    @State private var speech = SpeechEngine()
    @State private var presence = PresenceWatcher()
    @State private var nameListener = NameListener()
    /// Whether this step's line **has actually been spoken in full.** Opening the microphone before that
    /// makes the robot transcribe its own voice.
    @State private var spokenStep: Int?
    @State private var showsStaffSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private var mode: AppMode { modeStore.mode }

    var body: some View {
        DesignCanvas {
            ZStack(alignment: .top) {
                Backdrop.session
                elderStage
                if mode.showsStaffPanel {
                    staffPanel
                        .padding(.top, Theme.Layout.stageHeightPilot)
                }

                if model.showsStaffOverlay {
                    metricsOverlay
                        .transition(.opacity)
                }
            }
            .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: model.showsStaffOverlay)
        }
        // Opens the session with the store attached. The opener is decided here.
        .onAppear {
            model.attach(context: context)
            model.onGalleryChanged = reloadGallery
            reloadGallery()
            speakCurrentStep()
            updateWatcher()
        }
        .onDisappear {
            presence.stop()
            nameListener.cancel()
        }
        .onChange(of: model.stepIndex) {
            spokenStep = nil
            speakCurrentStep()
            updateWatcher()
            updateNameListener()
            scheduleAutoAdvance()
        }
        // Don't listen while the robot is saying "What's your name?".
        // If left on, **it transcribes its own voice as the name.**
        .onChange(of: speech.isSpeaking) { wasSpeaking, nowSpeaking in
            if wasSpeaking, !nowSpeaking { spokenStep = model.stepIndex }
            updateNameListener()
            scheduleAutoAdvance()
        }
        // **Keep capturing even mid-utterance.**
        //
        // `onHeard` arrives only once, when silence signals the end. If we only captured then,
        // pressing a choice while the elder was still talking would **lose what was said entirely**
        // and save the script label as the transcript. Holding on to partial results means
        // whenever it's pressed, everything said up to that point is kept.
        .onChange(of: nameListener.partialText) { _, text in
            guard model.isCapturingAnswer else { return }
            model.noteHeard(text)
        }
        // Accepting a suggestion **keeps the step and changes only the line.** Watching `stepIndex`
        // won't make it speak again, so a separate signal is received.
        .onChange(of: model.captionRevision) {
            spokenStep = nil
            speakCurrentStep()
            updateNameListener()
        }
        .onChange(of: model.person) { speakCurrentStep() }
        .onChange(of: mode) { updateWatcher() }
        // Release the camera when the app goes to the background. Keeping it on while off screen exceeds the scope of consent.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                updateWatcher()
                // Also revive name listening when coming back. Reviving only the camera would leave staff waiting
                // at the name step **with the microphone silently dead**.
                updateNameListener()
            } else {
                presence.stop()
                nameListener.cancel()
            }
        }
        // Deployment mode has no staff panel. Staff must still be able to adjust the voice then.
        .twoFingerLongPress { showsStaffSettings = true }
        // Two reasons for full screen rather than a sheet. There are 13 voices, so the default iPad sheet (540pt)
        // needs constant scrolling, and sheets close with a downward swipe, so one could be left half-open
        // on the kiosk. Here it closes **only when Done is pressed**.
        .fullScreenCover(isPresented: $showsStaffSettings) {
            StaffSettingsView(speech: speech, modeStore: modeStore)
        }
    }

    // MARK: - Elder stage (0 … 980)

    private var elderStage: some View {
        ZStack(alignment: .top) {
            RobotFaceView(style: model.step.face)
                .padding(.top, faceTop)

            // Shrink as a whole only when the block below the line overflows. **Don't put a Spacer inside** —
            // the height is then always measured as the available height and shrinking stops working.
            FitToHeight(alignment: .top) {
                VStack(spacing: Theme.Layout.belowCaptionSpacing) {
                    captionBlock
                    if model.step.listening {
                        ListeningWave(barWidth: 9, barHeight: 44, spacing: 10)
                    }
                    if let card = model.step.card {
                        SessionMemoryCard(card: card)
                    }
                }
            }
            .frame(width: Theme.Layout.contentWidth,
                   height: mode.stageHeight - mode.captionTop)
            .padding(.top, mode.captionTop)
        }
        .frame(width: DesignSpec.width, height: mode.stageHeight, alignment: .top)
        .clipped()
    }

    /// How far to lower the face block so the eye centre lands on the prescribed y.
    private var faceTop: CGFloat {
        mode.eyeCenterY - RobotFaceView.eyeInset - model.step.face.eye.height / 2
    }

    /// Lines use `Theme.Size.speech` (74pt); **status text is a dim 30pt**.
    ///
    /// Steps with `speaks == false` ("Resting" · "Session saved") are status displays, not
    /// the robot speaking. They aren't text meant to be read, so there's no reason to give them tier-A size,
    /// and at tier A a sleeping robot would look like it's shouting.
    private var isSpeechCaption: Bool { model.step.speaks }

    private var captionBlock: some View {
        VStack(spacing: 12) {
            Text(model.step.caption)
                .font(.kr(isSpeechCaption ? Theme.Size.speech : 30,
                          isSpeechCaption ? .semibold : .regular))
                .letterSpacing(isSpeechCaption ? -0.02 : 0.3,
                               isSpeechCaption ? Theme.Size.speech : 30)
                .cssLineHeight(Theme.speechLineHeight, Theme.Size.speech)
                .foregroundStyle(isSpeechCaption ? Theme.faceText : Theme.cream(0.28))
                .multilineTextAlignment(.center)
                // Without this it gets squeezed top and bottom and cut to one line.
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.easeInOut(duration: 0.25), value: model.stepIndex)
    }

    // MARK: - Staff panel (980 … 1180)

    /// Holds only what staff touch during a session. **Metrics and logs are not here** —
    /// during a session staff should be watching the elder, not graphs. They expand with the metrics toggle.
    private var staffPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle()
                .fill(Theme.cream(0.09))
                .frame(height: 1)
                .padding(.bottom, 0)

            statusRow
            if model.needsName { nameEntryRow } else { choiceRow }
            controlRow
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Layout.sideMargin)
        .frame(width: DesignSpec.width,
               height: Theme.Layout.staffPanelHeight, alignment: .top)
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isHearing ? Theme.green : Theme.blue)
                .frame(width: 8, height: 8)
            if isHearing {
                // **Show staff exactly what was heard.**
                //
                // Without this, if STT transcribes something wrong it gets saved without anyone noticing.
                // It's more important right now than the step name, so it takes that spot —
                // the staff panel is only 200pt, and adding another row pushes the control buttons out.
                Text("“\(model.heardAnswer)”")
                    .font(.kr(Theme.Size.staffLabel, .medium))
                    .foregroundStyle(Theme.green)
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text(model.statusWithProgress)
                    .font(.kr(Theme.Size.staffLabel, .semibold))
                    .foregroundStyle(Theme.cream(0.85))
            }
            anchorCountdown
            sessionClock
            recordingBanner
            Spacer(minLength: 12)
            voiceStatusButton
        }
        .frame(height: 28)
    }

    /// Elapsed session time. **The target is 18 minutes** — the 8-minute delayed recall must fit within it.
    @ViewBuilder
    private var sessionClock: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            if let label = model.elapsedLabel(at: timeline.date) {
                let over = model.isOverTime(at: timeline.date)
                Label(label, systemImage: over ? "clock.badge.exclamationmark" : "clock")
                    .font(.kr(Theme.Size.staffLabel, .medium))
                    .foregroundStyle(over ? Theme.amber : Theme.cream(0.55))
                    .lineLimit(1)
            }
        }
    }

    /// **Make it visible when recording is off.**
    ///
    /// Without self/guardian consent this session is saved nowhere. If you only find out
    /// after running a whole session, that conversation is already gone.
    @ViewBuilder
    private var recordingBanner: some View {
        if let text = model.recordingBanner {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.kr(Theme.Size.staffLabel, .semibold))
                .foregroundStyle(Theme.red)
                .lineLimit(1)
        }
    }

    /// Whether a free answer is being transcribed and something was actually heard.
    private var isHearing: Bool {
        model.isCapturingAnswer && !model.heardAnswer.isEmpty
    }

    /// Time remaining until asking back.
    ///
    /// **Delayed recall is all about the delay**, so staff must know without watching a clock.
    /// Asking back before it expires keeps the record but excludes it from the recall rate.
    @ViewBuilder
    private var anchorCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let label = model.anchorCountdown(at: timeline.date) {
                let ready = label.hasPrefix("Ready to probe")
                Label(label, systemImage: ready ? "checkmark.circle.fill" : "hourglass")
                    .font(.kr(Theme.Size.staffLabel, .medium))
                    .foregroundStyle(ready ? Theme.green : Theme.amber)
                    .lineLimit(1)
            }
        }
    }

    /// The choices are **staff UI**. At 20pt they're 13.6 arcminutes at the elder's distance (70 cm),
    /// so unreadable, and 23.8 arcminutes at the staff distance (40 cm), so readable.
    /// **Leave it horizontally scrollable.** Just two script choices nearly fill the width,
    /// so simply appending the suggestion button pushes it off screen where it can't be pressed.
    /// The staff panel is fixed at 200pt, so there's no vertical room for another row
    /// (`Docs/04_screen-design.md` section 2).
    private var choiceRow: some View {
        // **Recall verdicts can't be pressed before expiry.** It must redraw every second to unlock at the moment of expiry.
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let unlocked = model.canPickCurrentStep(at: timeline.date)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if !unlocked { probeGateButton }
                    ForEach(model.step.choices) { choice in
                        ChoiceButton(label: choice.label) { model.pick(choice) }
                            .disabled(!unlocked)
                            .opacity(unlocked ? 1 : 0.35)
                    }
                    suggestionButton
                }
                .padding(.trailing, Theme.Layout.sideMargin)
            }
        }
        .frame(height: Theme.Layout.staffButtonHeight)
    }

    /// Button that opens asking back before expiry.
    ///
    /// Just locking it would stall the session in the pilot. **Allow skipping, but record that it was skipped**
    /// — that verdict is excluded from the recall rate.
    private var probeGateButton: some View {
        Button { model.overrideProbeGate() } label: {
            HStack(spacing: 8) {
                Image(systemName: "hourglass.badge.plus")
                Text("Probe now · not counted")
                    .lineLimit(1)
            }
            .font(.kr(Theme.Size.staffButton, .medium))
            .foregroundStyle(Theme.amber)
            .padding(.horizontal, 16)
            .frame(height: Theme.Layout.staffButtonHeight)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.buttonRadius,
                                 style: .continuous)
                    .strokeBorder(Theme.amber.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
    }

    /// **The next line the robot came up with itself — goes out only when staff press it.**
    ///
    /// The only place it can be tested on real input without unverified sentences reaching
    /// the elder. **The rate at which staff press is the quality metric**, so rejections are recorded too.
    ///
    /// **Make it look different** from the script choices. If they looked the same staff would press it absent-mindedly,
    /// breaking the premise that "staff judged and chose it".
    @ViewBuilder
    private var suggestionButton: some View {
        if model.isPlanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("thinking…")
                    .font(.kr(Theme.Size.staffLabel))
                    .foregroundStyle(Theme.cream(0.45))
            }
            .frame(height: Theme.Layout.staffButtonHeight)
        } else if let plan = model.suggestion {
            HStack(spacing: 8) {
                Button { model.acceptSuggestion() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                        Text(plan.line.replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1)
                    }
                    .font(.kr(Theme.Size.staffButton, .medium))
                    .foregroundStyle(Theme.blue)
                    .padding(.horizontal, 16)
                    .frame(height: Theme.Layout.staffButtonHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Layout.buttonRadius,
                                         style: .continuous)
                            .strokeBorder(Theme.blue.opacity(0.55),
                                          style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                }
                Button { model.dismissSuggestion() } label: {
                    Image(systemName: "xmark")
                        .font(.kr(Theme.Size.staffLabel, .semibold))
                        .foregroundStyle(Theme.cream(0.45))
                        .frame(width: 32, height: Theme.Layout.staffButtonHeight)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Field for writing down the name. **Staff fill this role until STT is attached.**
    ///
    /// Appears instead of the choices only at the 'ask name' step of the first-meeting script. The name written here
    /// becomes the next screen's line and is saved with the face the moment confirm is pressed.
    private var nameEntryRow: some View {
        HStack(spacing: 12) {
            TextField(model.capture?.placeholder ?? "Answer", text: $model.typedName)
                .textFieldStyle(.roundedBorder)
                .font(.kr(Theme.Size.staffButton))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .frame(width: 240)

            listeningIndicator

            ChoiceButton(label: model.typedName.isEmpty
                         ? "Listen again"
                         : (model.capture?.confirmLabel ?? "Save it")) {
                if model.typedName.trimmingCharacters(in: .whitespaces).isEmpty {
                    nameListener.start()
                } else {
                    nameListener.cancel()
                    model.commitCapture()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Theme.Layout.staffButtonHeight)
    }

    /// Whether it's listening, and what it heard. **State isn't hidden, so staff can correct it.**
    @ViewBuilder
    private var listeningIndicator: some View {
        switch nameListener.state {
        case .listening:
            HStack(spacing: 8) {
                ListeningWave(barWidth: 3, barHeight: 14, spacing: 3)
                Text(nameListener.partialText.isEmpty
                     ? "Listening…" : "\u{201C}\(nameListener.partialText)\u{201D}")
                    .font(.kr(Theme.Size.staffLabel))
                    .foregroundStyle(Theme.cream(0.75))
                    .lineLimit(1)
                Button("Stop") { nameListener.finish() }
                    .font(.kr(Theme.Size.staffLabel, .semibold))
            }
            .frame(maxWidth: 260, alignment: .leading)
        case let .unavailable(reason):
            Text(reason)
                .font(.kr(Theme.Size.staffLabel))
                .foregroundStyle(Theme.amber)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .leading)
        case .idle:
            Text(model.typedName.isEmpty
                 ? (model.nameReaskExhausted
                    ? "Asked twice — ask them and type it"
                    : "Not heard yet")
                 : "Heard · edit if wrong")
                .font(.kr(Theme.Size.staffLabel))
                .foregroundStyle(Theme.cream(0.45))
                .frame(maxWidth: 260, alignment: .leading)
        }
    }

    /// Advances on its own past steps the camera has already answered.
    ///
    /// **Advances after the line is fully spoken** — "Hello. Come on in." is a greeting the robot actually says,
    /// not a procedure to skip past. Advancing immediately cuts the greeting off.
    /// With voice off, `isSpeaking` never rises, so it just waits a while and moves on.
    private func scheduleAutoAdvance() {
        guard model.autoAdvancesCurrentStep else { return }
        guard !speech.isSpeaking, !speech.isPreparing, !speech.isWarmingUp else { return }
        let index = model.stepIndex
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // If staff touched it in the meantime, leave it alone.
            guard model.stepIndex == index else { return }
            model.autoAdvance()
        }
    }

    /// Starts listening only at the name step, **after the robot has finished speaking**.
    private func updateNameListener() {
        // There are two places to transcribe into. The name and first story are **confirmed by staff**,
        // and the remaining listening steps keep what was said verbatim as the transcript.
        guard model.needsName || model.isCapturingAnswer else {
            nameListener.cancel()
            return
        }
        let confirms = model.needsName
        nameListener.onHeard = { heard in
            if confirms {
                // STT only suggests. It's registered only after staff check, correct and press confirm.
                model.typedName = heard
            } else {
                // Free answers have no confirm step. They become the transcript when staff press a choice.
                model.noteHeard(heard)
            }
        }
        // **Asking again happens only at the name step.** Not answering a recall question
        // isn't a recognition failure but something to observe in itself — the robot must not press for it.
        nameListener.onNothingHeard = { if confirms { reaskName() } }

        if confirms {
            guard model.typedName.isEmpty, !model.nameReaskExhausted else { return }
        }
        guard !speech.isPreparing, !speech.isWarmingUp, !speech.isSpeaking else { return }
        // **Turn on only after the line is fully spoken.** With voice off there's nothing to say, so turn on immediately.
        guard !speech.isEnabled || spokenStep == model.stepIndex else { return }
        nameListener.start(for: confirms ? .shortAnswer : .story)
    }

    /// If it didn't catch it, **the robot asks again instead of showing an error.**
    ///
    /// Showing "recognition failed" on the screen in front of an elder is not this product's job.
    /// People ask again when they don't hear. After asking enough times, it quietly hands over to staff.
    private func reaskName() {
        guard model.reaskName() else { return }
        spokenStep = nil
        speech.speak(model.step.caption, force: true)
        // When speaking ends, `onChange(of: speech.isSpeaking)` turns listening back on.
        if !speech.isEnabled {
            spokenStep = model.stepIndex
            updateNameListener()
        }
    }

    // MARK: - Face watching on the resting screen

    /// The camera runs **only on the resting screen**. It's released once the session starts.
    private func updateWatcher() {
        // Keep it on while resting or **while still working out who it is**.
        // Several frames are needed during the greeting, so the camera isn't released until the recognition step.
        let shouldWatch = mode != .gallery
            && AutoGreet.isEnabled
            && (model.stepIndex == 0 || model.awaitingIdentification)
        guard shouldWatch else {
            presence.stop()
            return
        }
        presence.onPresence = { model.presenceDetected() }
        presence.onIdentified = { arrival in
            model.identify(arrival.outcome, face: arrival.image)
        }
        presence.onStillLooking = {
            // Change the line and **have it spoken directly.** The step doesn't change, so it won't read on its own.
            guard model.stallWhileLooking() else { return }
            spokenStep = nil
            speech.speak(model.step.caption, force: true)
        }
        // Re-arm only on the resting screen. Arming during recognition resets the attempt count.
        if model.stepIndex == 0 { presence.rearm() }
        presence.start()
    }

    private func reloadGallery() {
        presence.gallery = (try? MemoryStore(context: context).faceGallery())
            ?? FaceGallery(elders: [])
    }

    private var controlRow: some View {
        HStack(spacing: 10) {
            PillButton(label: speech.isEnabled ? "Voice off" : "Voice on") {
                speech.isEnabled.toggle()
                if speech.isEnabled { speakCurrentStep() }
            }
            // Staff replay the same line when the elder didn't hear it.
            PillButton(label: "Say again") { speakCurrentStep() }
            PillButton(label: model.overlayToggleLabel) { model.toggleStaffOverlay() }
            PillButton(label: model.personToggleLabel) { model.togglePerson() }
            PillButton(label: "Start over") { model.reset() }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }

    /// A voice status indicator that doubles as the entry button to the settings screen.
    ///
    /// It used to be a 12pt `Menu` at 45% opacity. The idea was to keep it out of the elder's sight, but
    /// **staff couldn't find it either.** A preview playing the instant you picked a voice was also an accident in front of an elder.
    /// Both moved to `VoiceSettingsView`; this remains only a status indicator + entry point.
    private var voiceStatusButton: some View {
        Button { showsStaffSettings = true } label: {
            HStack(spacing: 6) {
                Image(systemName: speech.hasProblem
                      ? "exclamationmark.triangle.fill" : "waveform")
                    .font(.system(size: 11, weight: .semibold))
                Text(speech.statusLabel)
                    .font(.kr(Theme.Size.staffLabel))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(voiceLabelColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.cream(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var voiceLabelColor: Color {
        if speech.hasProblem { return Theme.red }
        if speech.isSpeaking || speech.isPreparing || speech.isWarmingUp { return Theme.blue }
        return Theme.cream(0.75)
    }

    // MARK: - Metrics overlay

    /// Collapsed during the session. Covers the stage only when staff expand it.
    private var metricsOverlay: some View {
        StaffOverlayView(
            personName: model.personName,
            personMeta: model.personMeta,
            metrics: model.metrics,
            log: model.log
        )
        .frame(width: DesignSpec.width, height: mode.stageHeight, alignment: .top)
        .background(Theme.ink.opacity(0.96))
    }

    // MARK: - Voice

    private func speakCurrentStep() {
        let step = model.step
        guard step.speaks else {
            speech.stop()
            return
        }
        speech.speak(step.caption)
    }
}

#Preview("Session") {
    SessionView(modeStore: AppModeStore())
}
