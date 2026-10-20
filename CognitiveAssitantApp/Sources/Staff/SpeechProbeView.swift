import SwiftData
import SwiftUI

/// STT recognition-accuracy measurement screen.
///
/// `Docs/05_implementation-roadmap.md` section 2 — **the table that must be built before starting stage 1**
/// is built here. Elderly English · regional accents · hearing-impaired pronunciation overlap, so until it's measured
/// neither the engine nor the schedule can be decided.
///
/// Procedure: record → check the on-device recognition result → **a person transcribes the correct answer** → word accuracy computed automatically.
/// Recording files are kept, so the same audio can later be fed to cloud engines for comparison.
struct SpeechProbeView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SpeechSample.recordedAt, order: .reverse) private var samples: [SpeechSample]

    @State private var probe = SpeechProbe()
    @State private var note = ""
    @State private var editing: SpeechSample?

    private var consented: Bool { Consent.isGranted(.recording) }

    var body: some View {
        NavigationStack {
            Form {
                if !consented {
                    Section {
                        Label("No voice-recording consent", systemImage: "lock.fill")
                            .foregroundStyle(Theme.red)
                    } footer: {
                        Text("Turn it on under Staff settings → Consent on file before recording.")
                    }
                } else {
                    recorderSection
                }
                summarySection
                samplesSection
            }
            .navigationTitle("STT accuracy probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { probe.stop(); dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .sheet(item: $editing) { sample in
                ReferenceEditor(sample: sample)
            }
        }
        .task {
            _ = await probe.requestPermissions()
            probe.onFinish = { fileName, recognized, duration in
                let sample = SpeechSample(fileName: fileName, recognized: recognized,
                                          note: note, duration: duration)
                context.insert(sample)
                try? context.save()
            }
        }
    }

    // MARK: - Recording

    @ViewBuilder
    private var recorderSection: some View {
        Section {
            TextField("Speaker note — e.g. Dorothy · 85 · Asheville", text: $note)

            Button {
                probe.isRecording ? probe.stop() : probe.start()
            } label: {
                Label(probe.isRecording ? "Stop recording" : "Start recording",
                      systemImage: probe.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .foregroundStyle(probe.isRecording ? Theme.red : Theme.blue)
            }
            .disabled(probe.state == .finishing)

            if probe.isRecording || !probe.partialText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On-device recognition")
                        .font(.caption)
                        .foregroundStyle(Theme.gray6B)
                    Text(probe.partialText.isEmpty ? "…" : probe.partialText)
                        .font(.body)
                }
            }

            if case .denied(let reason) = probe.state {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.red)
            }
            if let error = probe.lastError {
                Text(error).font(.footnote).foregroundStyle(Theme.red)
            }
        } header: {
            Text("Recording")
        } footer: {
            if probe.supportsOnDevice {
                Text("**Recognition is on-device only.** The elder's voice never leaves the iPad. "
                     + "Comparing against a cloud engine is done separately, from the saved recordings.")
            } else {
                Text("⚠️ This iPad has no on-device English recognition model. "
                     + "Settings → General → Keyboard → Dictation, turn on English, and it downloads. "
                     + "**That fact is itself part of the result.**")
                .foregroundStyle(Theme.red)
            }
        }
    }

    // MARK: - Summary

    private var scored: [SpeechSample] { samples.filter(\.isScored) }

    private var averageAccuracy: Double? {
        let values = scored.compactMap(\.wordAccuracy)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Samples", value: "\(samples.count)")
            LabeledContent("Scored", value: "\(scored.count)")
            LabeledContent("Mean word accuracy") {
                if let average = averageAccuracy {
                    Text(Self.percent(average))
                        .foregroundStyle(Self.accuracyColor(average))
                        .monospacedDigit()
                } else {
                    Text("—").foregroundStyle(Theme.gray6B)
                }
            }
            LabeledContent("Total recorded",
                           value: Self.duration(samples.reduce(0) { $0 + $1.duration }))
        } header: {
            Text("Summary")
        } footer: {
            Text("Accuracy is **word-level edit distance**, splitting on whitespace. "
                 + "Read it as **one engine against another**, not as an absolute number. "
                 + "Once 3–5 minutes have piled up, the stage-1 engine can be chosen.")
        }
    }

    // MARK: - Sample list

    private var samplesSection: some View {
        Section("Samples") {
            if samples.isEmpty {
                Text("Nothing yet").foregroundStyle(Theme.gray6B)
            }
            ForEach(samples) { sample in
                Button { editing = sample } label: { row(sample) }
                    .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
    }

    private func row(_ sample: SpeechSample) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sample.note.isEmpty ? "No note" : sample.note)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let accuracy = sample.wordAccuracy {
                    Text(Self.percent(accuracy))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Self.accuracyColor(accuracy))
                        .monospacedDigit()
                } else {
                    Text("Not scored")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                }
            }
            Text(sample.recognized.isEmpty ? "(nothing recognized)" : sample.recognized)
                .font(.footnote)
                .foregroundStyle(Theme.gray6B)
                .lineLimit(2)
            Text("\(Self.duration(sample.duration)) · \(sample.fileName)")
                .font(.caption2)
                .foregroundStyle(Theme.gray8A)
        }
        .padding(.vertical, 2)
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            let sample = samples[index]
            SpeechSampleStore.delete(sample.fileName)
            context.delete(sample)
        }
        try? context.save()
    }

    // MARK: - Display helpers

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func accuracyColor(_ value: Double) -> Color {
        if value >= 0.85 { return Theme.green }
        if value >= 0.6 { return Theme.amber }
        return Theme.red
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 60 ? "\(total / 60) min \(total % 60) sec" : "\(total) sec"
    }
}

/// Correct transcription. **A person has to listen and write it down** for accuracy to be computed.
private struct ReferenceEditor: View {
    @Bindable var sample: SpeechSample
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device recognition") {
                    Text(sample.recognized.isEmpty ? "(none)" : sample.recognized)
                        .foregroundStyle(Theme.gray6B)
                }
                Section {
                    TextField("What the elder actually said", text: $sample.reference,
                              axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Reference")
                } footer: {
                    Text("Play the recording and transcribe it exactly. **Write accents and slurred "
                         + "words as you hear them** — that is what reveals where recognition breaks.")
                }
                if let accuracy = sample.wordAccuracy {
                    Section("Word accuracy") {
                        Text(String(format: "%.0f%%", accuracy * 100))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    }
                }
                Section("Note") {
                    TextField("Speaker note", text: $sample.note)
                }
            }
            .navigationTitle("Scoring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.body.weight(.semibold))
                }
            }
        }
    }
}
