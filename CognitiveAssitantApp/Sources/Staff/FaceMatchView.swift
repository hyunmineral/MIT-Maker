import SwiftUI

/// Stage-2 measurement — Feature Print distance between an enrolled face and the current face.
///
/// Passes if same-person distances are clearly smaller than different-person ones.
/// If they overlap, Apple Feature Print alone isn't enough and a face-specific embedding is needed.
struct FaceMatchView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var probe = FaceProbe()
    @State private var match = FaceMatch()
    @State private var consent = ConsentStore()
    @State private var newLabel = ""
    @State private var busy = false
    @State private var virtualProbes: [VirtualProbe] = []
    @State private var virtualSummary: String?

    private struct VirtualProbe: Identifiable {
        let id = UUID()
        var title: String
        var expected: String
        var verdict: String
        var scores: [FaceMatch.Score]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                controls
            }
            .background(Theme.ink)
            .navigationTitle("Face matching probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { probe.stop(); dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .task {
            let ok = await probe.requestPermission()
            if ok, consent.isGranted(.biometric) { probe.start() }
        }
        .onDisappear { probe.stop() }
    }

    private var preview: some View {
        ZStack {
            PreviewRepresentable(view: probe.preview)
            FaceBoxOverlay(boxes: probe.latest.boxes)
            if !consent.isGranted(.biometric) {
                banner("No biometric (face) consent")
            } else if let err = probe.lastError {
                banner(err)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("Name — e.g. Dorothy Miller", text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                    Button("Enroll") { capture(enroll: true) }
                        .disabled(busy || newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Compare now") { capture(enroll: false) }
                        .disabled(busy || match.people.isEmpty)
                }

                Button("Run on virtual people") { runVirtual() }
                    .disabled(busy)

                if let verdict = match.verdict, virtualProbes.isEmpty {
                    Text(verdict)
                        .font(.headline)
                        .foregroundStyle(Theme.faceText)
                }
                if let err = match.lastError {
                    Text(err).foregroundStyle(Theme.red)
                }

                if !match.lastScores.isEmpty, virtualProbes.isEmpty {
                    ForEach(match.lastScores) { score in
                        HStack {
                            Text(score.label)
                            Spacer()
                            Text(String(format: "%.3f", score.distance))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Theme.cream(0.85))
                    }
                }

                if !virtualProbes.isEmpty {
                    ForEach(virtualProbes) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Probe \(row.title)")
                                Spacer()
                                Text(row.verdict)
                                    .font(.headline)
                            }
                            .foregroundStyle(Theme.faceText)
                            ForEach(row.scores) { score in
                                HStack {
                                    Text(score.label)
                                    Spacer()
                                    Text(String(format: "%.3f", score.distance))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(Theme.cream(0.85))
                            }
                        }
                    }
                }

                if let virtualSummary {
                    Text(virtualSummary)
                        .font(.footnote)
                        .foregroundStyle(Theme.cream(0.7))
                }

                if !match.people.isEmpty {
                    Text("Enrolled — \(match.people.map { "\($0.label) ×\($0.samples)" }.joined(separator: " · "))")
                        .font(.footnote)
                        .foregroundStyle(Theme.cream(0.5))
                }

                HStack {
                    Button("Clear enrollments", role: .destructive) {
                        match.clear()
                        virtualProbes = []
                        virtualSummary = nil
                    }
                    .disabled(match.people.isEmpty && virtualProbes.isEmpty)
                    Spacer()
                    Text("Smaller distance = same person. The virtual run does not replace a 70cm measurement.")
                        .font(.caption)
                        .foregroundStyle(Theme.cream(0.4))
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 360)
    }

    private func capture(enroll: Bool) {
        busy = true
        virtualProbes = []
        virtualSummary = nil
        probe.captureFrame { image in
            busy = false
            guard let image else {
                match.fail("Could not grab a frame")
                return
            }
            if enroll {
                match.enroll(label: newLabel, image: image)
            } else {
                match.compare(image: image)
            }
        }
    }

    /// 3 bundled portraits. Enrol frontal and side views, leaving only lighting as the probe.
    private func runVirtual() {
        busy = true
        defer { busy = false }
        match.clear()
        virtualProbes = []
        virtualSummary = nil

        for shot in FaceFixtures.shots where shot.enroll {
            guard let image = FaceFixtures.cgImage(shot.file) else {
                match.fail("Could not read the virtual photo: \(shot.file)")
                return
            }
            match.enroll(label: shot.person, image: image)
            if match.lastError != nil { return }
        }

        var hits = 0
        var rows: [VirtualProbe] = []
        for shot in FaceFixtures.shots where !shot.enroll {
            guard let image = FaceFixtures.cgImage(shot.file) else {
                match.fail("Could not read the virtual photo: \(shot.file)")
                return
            }
            match.compare(image: image)
            let verdict = match.verdict ?? "—"
            if verdict.contains(shot.person) { hits += 1 }
            rows.append(VirtualProbe(title: "\(shot.person) \(shot.variant)",
                                     expected: shot.person,
                                     verdict: verdict,
                                     scores: match.lastScores))
        }
        virtualProbes = rows

        let pairs = match.pairDistances()
        let same = pairs.filter(\.samePerson).map(\.distance)
        let other = pairs.filter { !$0.samePerson }.map(\.distance)
        let sameMax = same.max().map { String(format: "%.3f", $0) } ?? "—"
        let otherMin = other.min().map { String(format: "%.3f", $0) } ?? "—"
        virtualSummary = "\(hits)/3 probes named the right person. "
            + "Same-person max \(sameMax) · different-person min \(otherMin). "
            + "These are generated portraits, so they separate more easily than an Air 5 at 70cm."
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Theme.faceText)
            .padding()
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The same preview bridge as FaceProbeView.
private struct PreviewRepresentable: UIViewRepresentable {
    var view: FaceProbe.PreviewView
    func makeUIView(context: Context) -> FaceProbe.PreviewView { view }
    func updateUIView(_ uiView: FaceProbe.PreviewView, context: Context) {}
}

private struct FaceBoxOverlay: View {
    var boxes: [CGRect]

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                let rect = CGRect(
                    x: box.minX * geo.size.width,
                    y: (1 - box.maxY) * geo.size.height,
                    width: box.width * geo.size.width,
                    height: box.height * geo.size.height
                )
                Rectangle()
                    .strokeBorder(Theme.green, lineWidth: 3)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
