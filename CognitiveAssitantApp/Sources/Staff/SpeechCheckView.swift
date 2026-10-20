import AVFoundation
import Speech
import SwiftUI

/// Pins down **why** speech recognition isn't working, on one screen.
///
/// When name transcription fails there are five places it can get stuck — recording consent, speech recognition permission,
/// microphone permission, recogniser availability, and the on-device English model. Missing any one of them, nothing
/// happens silently, so from outside they all look the same.
///
/// **Makes the answer visible without cross-checking.** Shows the five rows as they are and actually
/// listens below. The red row is the cause.
struct SpeechCheckView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var listener = NameListener()
    @State private var consent = ConsentStore()
    @State private var heard: [String] = []
    @State private var refreshToken = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Voice recording consent",
                        ok: consent.isGranted(.recording),
                        detail: consent.isGranted(.recording)
                            ? "Granted" : "Turn it on under Consent on file")
                    row("Speech recognition permission",
                        ok: speechAuth == .authorized,
                        detail: speechAuthText)
                    row("Microphone permission",
                        ok: micGranted,
                        detail: micText)
                    row("English recognizer",
                        ok: recognizer?.isAvailable == true,
                        detail: recognizerText)
                    row("On-device English model",
                        ok: listener.supportsOnDevice,
                        detail: listener.supportsOnDevice
                            ? "Installed — recognition stays on this device"
                            : "Missing. Settings → General → Keyboard → Dictation → English")
                    if speechAuth == .notDetermined
                        || AVAudioApplication.shared.recordPermission == .undetermined {
                        Button {
                            Task {
                                await SystemPermissions.speechRecognition()
                                await SystemPermissions.microphone()
                                refreshToken += 1
                            }
                        } label: {
                            Label("Ask iOS for the permissions now",
                                  systemImage: "hand.raised.fill")
                        }
                    }
                } header: {
                    Text("Preconditions")
                } footer: {
                    Text("Every row must be green before the robot can take a name by voice. "
                         + "A red row is the reason nothing happens. "
                         + "On-device is required on purpose: without it the audio would leave the iPad.")
                }

                Section {
                    switch listener.state {
                    case .listening:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(listener.partialText.isEmpty
                                 ? "Listening… say something"
                                 : listener.partialText)
                                .foregroundStyle(Theme.faceText)
                        }
                        Button("Stop") { listener.finish() }
                    case let .unavailable(reason):
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.red)
                        Button("Try again") { listener.start() }
                    case .idle:
                        Button {
                            listener.onHeard = { heard.insert($0, at: 0) }
                            listener.onNothingHeard = { heard.insert("(nothing heard)", at: 0) }
                            listener.start()
                        } label: {
                            Label("Listen now", systemImage: "mic.circle.fill")
                        }
                    }

                    ForEach(Array(heard.enumerated()), id: \.offset) { _, line in
                        Text(line).monospaced()
                    }
                } header: {
                    Text("Live test")
                } footer: {
                    Text("Say a name out loud. It stops on its own after a short silence, "
                         + "or after 15 seconds. What appears here is exactly what the session "
                         + "would put in the name field — the staff still confirms it.")
                }

                Section {
                    // **These two rows separate a microphone problem from a recogniser problem.**
                    // If the bar moves while speaking, sound is getting in, and if text still
                    // doesn't come out, it's the recogniser. If the bar is dead, it's an audio-path problem.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Input level")
                        ProgressView(value: min(Double(listener.inputLevel) * 12, 1))
                            .tint(listener.inputLevel > 0.005 ? Theme.green : Theme.red)
                        Text(String(format: "RMS %.4f · %d buffers · %@",
                                    listener.inputLevel, listener.bufferCount,
                                    listener.formatNote))
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.cream(0.55))
                    }
                    if let error = listener.lastError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.amber)
                            .font(.footnote)
                    }
                } header: {
                    Text("Is sound arriving?")
                } footer: {
                    Text("Talk while listening. If the bar moves, the microphone is fine and the "
                         + "recognizer is the problem. If the bar stays dead — or buffers stay at 0 — "
                         + "the audio path never opened and the microphone is the problem.")
                }
            }
            .navigationTitle("Speech check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { listener.cancel(); dismiss() }
                        .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Refresh") { consent.reload(); refreshToken += 1 }
                }
            }
        }
        .onDisappear { listener.cancel() }
    }

    private func row(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Theme.green : Theme.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.cream(0.55))
            }
        }
    }

    // MARK: - Actual state

    private var recognizer: SFSpeechRecognizer? {
        _ = refreshToken
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    private var speechAuth: SFSpeechRecognizerAuthorizationStatus {
        _ = refreshToken
        return SFSpeechRecognizer.authorizationStatus()
    }

    private var speechAuthText: String {
        switch speechAuth {
        case .authorized:    "Granted"
        case .denied:        "Denied. Settings → Privacy & Security → Speech Recognition"
        case .restricted:    "Restricted on this device"
        case .notDetermined: "Not asked yet — tap Listen now below"
        @unknown default:    "Unknown"
        }
    }

    private var micGranted: Bool {
        _ = refreshToken
        return AVAudioApplication.shared.recordPermission == .granted
    }

    private var micText: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:      "Granted"
        case .denied:       "Denied. Settings → Privacy & Security → Microphone"
        case .undetermined: "Not asked yet — tap Listen now below"
        @unknown default:   "Unknown"
        }
    }

    private var recognizerText: String {
        guard let recognizer else { return "en-US is not supported on this device" }
        return recognizer.isAvailable ? "Available" : "Temporarily unavailable"
    }
}
