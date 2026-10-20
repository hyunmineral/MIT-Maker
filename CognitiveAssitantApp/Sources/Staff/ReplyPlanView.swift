import SwiftUI

/// Measures **the choose-only approach** on the same samples as free generation.
///
/// This is where `ReplyLatencyView` tried generating sentences. Three of six broke the safety rules
/// and half went over budget. Here the model doesn't write sentences —
/// it only chooses what to do and which topic, and the line comes from a human-written template.
///
/// **Keeping the samples the same is the point.** Whether safety and length really come from the structure,
/// or it was just luck, can only be told apart with the same input.
struct ReplyPlanView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var planner = ReplyPlanner()
    @State private var rounds: [Round] = Round.cases
    @State private var isRunning = false

    struct Round: Identifiable {
        let id = UUID()
        var intent: String
        var question: String
        var answer: String
        var candidates: [String]
        /// Moves that must not come up here. Shown in red if they do.
        var forbidden: Set<ReplyPlanner.Move>
        var plan: ReplyPlanner.Plan?
        var didRun = false

        static let cases: [Round] = [
            Round(intent: "First meeting · knows nothing",
                  question: "Where did you grow up?",
                  answer: "Norfolk, mostly. My father was in the Navy.",
                  candidates: [],
                  // If the list is empty yet it brings up a known topic, it made it up.
                  forbidden: [.askKnown]),
            Round(intent: "Recall · holding four topics",
                  question: "You mentioned the peach orchard. Tell me more today.",
                  answer: "We had one out back. I worked there when I was eighteen.",
                  candidates: ["the peach orchard", "Granddaughter Emma",
                               "Son Michael", "Late husband"],
                  forbidden: []),
            Round(intent: "Recall failure · must not press",
                  question: "By the way — what was lunch?",
                  answer: "Lunch? I'm not sure I had any today.",
                  candidates: ["the peach orchard", "Granddaughter Emma"],
                  // Asking again where memory is hazy violates principle 3.
                  forbidden: [.followUp]),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                summarySection
                roundSection
            }
            .navigationTitle("Reply plan")
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

    private var summarySection: some View {
        Section {
            if let mean = meanSeconds {
                LabeledContent("Time to choose (average)") {
                    Text(String(format: "%.1fs", mean))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(mean <= 2 ? Theme.green
                                         : mean <= 4 ? Theme.amber : Theme.red)
                }
                LabeledContent("With free generation") {
                    Text("3.9s")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Lines over budget") {
                    Text(overBudget == 0 ? "None" : "\(overBudget)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(overBudget == 0 ? Theme.green : Theme.red)
                }
            } else {
                HStack {
                    Text(isRunning ? "Measuring…" : "Not measured yet")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isRunning { ProgressView() }
                }
            }
            if let error = planner.lastError {
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
            Text("Lines come from human-written templates, so their length is within budget from the start. "
                 + "All the model decides is which template to use and which topic, "
                 + "and topics are referred to only by their number in the list we provide.")
        }
    }

    private var meanSeconds: Double? {
        let values = rounds.compactMap { $0.plan?.seconds }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var overBudget: Int {
        rounds.compactMap { $0.plan?.line.count }
            .filter { $0 > ReplyComposer.maxCharacters }.count
    }

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
                    if let plan = round.plan {
                        let bad = round.forbidden.contains(plan.move)
                        Text(plan.line.replacingOccurrences(of: "\n", with: " "))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(bad ? Theme.red : .primary)
                        HStack(spacing: 10) {
                            tag(plan.move.rawValue, bad ? Theme.red : Theme.green)
                            // **Show exactly what the model said.** Without this
                            // there's no telling a fallback triggering three times from the model choosing that all three times,
                            // so you don't know where to fix.
                            if plan.wasFallback {
                                tag("← fallback (model: \(plan.rawMove)/\(plan.rawSubject))", Theme.amber)
                            }
                            if let subject = plan.subject { tag(subject, Theme.gray8A) }
                            tag(String(format: "%.1fs", plan.seconds), Theme.gray8A)
                            tag("\(plan.line.count) chars",
                                plan.line.count > ReplyComposer.maxCharacters
                                ? Theme.red : Theme.green)
                        }
                        if bad {
                            Text("This move must not come up here")
                                .font(.caption2)
                                .foregroundStyle(Theme.red)
                        }
                    } else if round.didRun {
                        Text("Couldn't choose")
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
            Text("Samples — same as free generation")
        } footer: {
            Text("The first sample has no known topics. If ask_known comes up there "
                 + "it's made up, and when the list is empty the code turns it into follow_up. "
                 + "The third is a place where memory is hazy, so it must not ask again.")
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
    }

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        for index in rounds.indices {
            let round = rounds[index]
            rounds[index].plan = await planner.plan(name: "Dorothy",
                                                    candidates: round.candidates,
                                                    question: round.question,
                                                    answer: round.answer)
            rounds[index].didRun = true
        }
    }
}
