import SwiftUI

/// Pins down on one screen whether understanding **actually runs on this device**.
///
/// A tool in the same spot as `SpeechCheckView`. Where that one separates out "why can't it hear",
/// this one separates out "can it extract facts from what it heard".
///
/// **It runs on its own as soon as it opens.** Diagnostics that need staff to type something before a result appears
/// fail — there's no time to tap away at a keyboard in front of an elder, and no way to know what to
/// enter. The three sentences below are the three kinds of answers this product will actually meet.
struct UnderstandingCheckView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var extractor = FactExtractor()
    @State private var results: [Probe] = Probe.cases
    @State private var isRunning = false

    /// The three kinds of answers that will actually come in. **The third matters most** —
    /// making up a fact from an answer with no facts means the next session opens with a memory that never existed.
    struct Probe: Identifiable {
        let id = UUID()
        var question: String
        var answer: String
        /// What the sample is meant to check.
        var intent: String
        /// Whether a fact should come out.
        var expectsFact: Bool
        var outcome: FactExtractor.Candidate?
        var didRun = false
        /// **How long it takes.** The elder can't be left waiting in silence, so
        /// this number decides whether to "pause the line and wait" or "run it in the background".
        var seconds: Double = 0

        static let cases: [Probe] = [
            Probe(question: "Where did you grow up?",
                  answer: "Oh, all over — my father was in the Navy, but mostly Norfolk.",
                  intent: "Buried answer · the place is not the first noun",
                  expectsFact: true),
            Probe(question: "Who's at home with you these days?",
                  answer: "Just me and the cat now. My daughter Ruth calls on Sundays.",
                  intent: "Two candidates · should pick a person",
                  expectsFact: true),
            Probe(question: "What kind of work did you do?",
                  answer: "Hmm. I don't really remember, dear.",
                  intent: "No fact · must NOT invent one",
                  expectsFact: false),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                probeSection
            }
            .navigationTitle("Understanding check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .task { await runAll() }
    }

    // MARK: - Prerequisites

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: extractor.availability.isReady
                      ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(extractor.availability.isReady ? Theme.green : Theme.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("On-device language model")
                        .font(.body.weight(.medium))
                    Text(extractor.availability.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if isRunning { ProgressView() }
            }
            if let error = extractor.lastError {
                Text(error)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.red)
            }
            Button {
                extractor.refreshAvailability()
                Task { await runAll() }
            } label: {
                Label("Check again", systemImage: "arrow.clockwise")
            }
            .disabled(isRunning)
        } header: {
            Text("Precondition")
        } footer: {
            Text("Understanding runs on this iPad. Nothing the person says is sent anywhere. "
                 + "If this row is red the session still works — it falls back to the three "
                 + "seed questions, and only those answers become facts.")
        }
    }

    // MARK: - Samples

    private var probeSection: some View {
        Section {
            ForEach(results) { probe in
                VStack(alignment: .leading, spacing: 8) {
                    Text(probe.intent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                    Text("“\(probe.answer)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    verdict(for: probe)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Samples")
        } footer: {
            Text("The third sample is the one that matters. A model that invents a job here "
                 + "would hand that invention back as a memory next session.")
        }
    }

    @ViewBuilder
    private func verdict(for probe: Probe) -> some View {
        if !probe.didRun {
            Label("waiting", systemImage: "ellipsis")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if let fact = probe.outcome {
            let good = probe.expectsFact
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%@  ·  %@  ·  %d%%  ·  %.1fs",
                                fact.subject, fact.kind.rawValue,
                                Int(fact.confidence * 100), probe.seconds))
                        .font(.callout.weight(.semibold))
                    Text(fact.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(good ? Theme.green : Theme.red)
            }
        } else {
            Label(probe.expectsFact
                    ? "nothing extracted — should have found one"
                    : String(format: "nothing extracted — correct · %.1fs", probe.seconds),
                  systemImage: probe.expectsFact ? "exclamationmark.triangle.fill"
                                                 : "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(probe.expectsFact ? Theme.red : Theme.green)
        }
    }

    // MARK: - Running

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        for index in results.indices {
            let probe = results[index]
            let began = Date()
            let found = await extractor.extract(question: probe.question, answer: probe.answer)
            results[index].seconds = Date().timeIntervalSince(began)
            results[index].outcome = found
            results[index].didRun = true
        }
    }
}
