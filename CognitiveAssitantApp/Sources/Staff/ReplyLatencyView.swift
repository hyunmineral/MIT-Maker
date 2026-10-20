import SwiftUI

/// Measures **how fast the robot can generate lines itself**.
///
/// Whether stage 2 (conversation generation) can be attached is decided not by quality but by **latency**.
/// Fact extraction took 7.7–11.6 seconds on a device. That much per line would leave the elder
/// waiting through silence for every line.
///
/// **Time to the first token matters more than total completion time.** If the first token arrives quickly,
/// speaking can start, and the rest of the generation flows by and disappears while speaking.
/// So the two numbers are reported separately.
struct ReplyLatencyView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var composer = ReplyComposer()
    @State private var rounds: [Round] = Round.cases
    @State private var isRunning = false

    /// Three situations that come up in real sessions. **Prompt length affects latency, so
    /// the amount of known facts is also kept close to reality.**
    struct Round: Identifiable {
        let id = UUID()
        var intent: String
        var question: String
        var answer: String
        var facts: [(subject: String, detail: String)]
        /// Results per strategy. Only by measuring the same samples both ways can you tell if a difference is due to the method.
        var results: [ReplyComposer.Strategy: ReplyComposer.Measurement] = [:]
        var didRun = false

        static let cases: [Round] = [
            Round(intent: "First meeting · knows nothing",
                  question: "Where did you grow up?",
                  answer: "Norfolk, mostly. My father was in the Navy.",
                  facts: []),
            Round(intent: "Recall · holding four facts",
                  question: "You mentioned the peach orchard. Tell me more today.",
                  answer: "We had one out back. I worked there when I was eighteen.",
                  facts: [("the peach orchard", "Worked there at twenty"),
                          ("Granddaughter Emma", "Finals coming up"),
                          ("Son Michael", "Lives in Chicago"),
                          ("Late husband", "Passed away first")]),
            Round(intent: "Recall failure · must not point it out",
                  question: "By the way — what was lunch?",
                  answer: "Lunch? I'm not sure I had any today.",
                  facts: [("the peach orchard", "Worked there at twenty"),
                          ("Granddaughter Emma", "Finals coming up")]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                roundSection
            }
            .navigationTitle("Reply latency")
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

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            if hasAnyResult {
                ForEach(ReplyComposer.Strategy.allCases, id: \.self) { strategy in
                    if let first = mean(strategy, \.firstTokenSeconds),
                       let total = mean(strategy, \.totalSeconds) {
                        LabeledContent(strategy.label) {
                            HStack(spacing: 10) {
                                Text(String(format: "first %.1fs", first))
                                    .font(.body.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(first <= 2 ? Theme.green
                                                     : first <= 4 ? Theme.amber : Theme.red)
                                Text(String(format: "total %.1fs", total))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                HStack {
                    Text(isRunning ? "Measuring…" : "Not measured yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isRunning { ProgressView() }
                }
            }
            if let error = composer.lastError {
                Text(error)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Theme.red)
            }
            Button {
                rounds = Round.cases
                Task { await runAll() }
            } label: {
                Label("Measure again", systemImage: "arrow.clockwise")
            }
            .disabled(isRunning)
        } header: {
            Text("Verdict")
        } footer: {
            Text("If the first token arrives within 2 seconds, it can generate while speaking — the latency disappears. "
                 + "Over 4 seconds, it has to pre-generate or fill the gap with a short filler. "
                 + "Total time is a secondary concern.")
        }
    }

    private var hasAnyResult: Bool { rounds.contains { !$0.results.isEmpty } }

    private func mean(_ strategy: ReplyComposer.Strategy,
                      _ key: KeyPath<ReplyComposer.Measurement, Double>) -> Double? {
        let values = rounds.compactMap { $0.results[strategy]?[keyPath: key] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Each situation

    private var roundSection: some View {
        Section {
            ForEach(rounds) { round in
                VStack(alignment: .leading, spacing: 8) {
                    Text(round.intent)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                    Text("“\(round.answer)”")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !round.results.isEmpty {
                        ForEach(ReplyComposer.Strategy.allCases, id: \.self) { strategy in
                            if let m = round.results[strategy] {
                                Text(m.text)
                                    .font(.callout.weight(.medium))
                                HStack(spacing: 10) {
                                    tag(strategy.label, Theme.blue)
                                    tag(String(format: "first %.1fs", m.firstTokenSeconds),
                                        m.firstTokenSeconds <= 2 ? Theme.green : Theme.amber)
                                    tag(String(format: "total %.1fs", m.totalSeconds), Theme.gray8A)
                                    tag("\(m.characters) chars",
                                        m.overBudget ? Theme.red : Theme.green)
                                }
                            }
                        }
                    } else if round.didRun {
                        Text("Couldn't generate")
                            .font(.caption)
                            .foregroundStyle(Theme.red)
                    } else {
                        Text("Waiting…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Samples")
        } footer: {
            Text("The third one tests principle 3. The robot never exposes a recall failure "
                 + "to the elder — if \"You told me earlier\" comes out, it fails. "
                 + "Over \(ReplyComposer.maxCharacters) characters, the line becomes 4 lines and the screen shrinks the text.")
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
    }

    // MARK: - Running

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        // **Loop over strategies on the outside.** Alternating methods per sample mixes in
        // the model's warmed-up state, so you can't tell what made it faster.
        for strategy in ReplyComposer.Strategy.allCases {
            for index in rounds.indices {
                let round = rounds[index]
                let context = ReplyComposer.Context(name: "Dorothy", facts: round.facts)
                if let m = await composer.compose(context: context,
                                                  question: round.question,
                                                  answer: round.answer,
                                                  strategy: strategy) {
                    rounds[index].results[strategy] = m
                }
                rounds[index].didRun = true
            }
        }
    }
}
