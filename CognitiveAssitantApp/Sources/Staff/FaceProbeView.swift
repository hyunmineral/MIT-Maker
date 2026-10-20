import SwiftUI

/// Face detection measurement. **No identity matching** — it only checks whether a face is caught
/// at a 70 cm mount and what its quality score is.
struct FaceProbeView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var probe = FaceProbe()
    @State private var consent = ConsentStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                metrics
            }
            .background(Theme.ink)
            .navigationTitle("Face detection probe")
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
                lock("No biometric (face) consent",
                     "Turn it on under Staff settings → Consent on file.")
            } else if let err = probe.lastError {
                lock(err, nil)
            } else if !probe.isRunning {
                lock("Starting the camera", nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                metric("Faces", probe.latest.count == 0 ? "none" : "\(probe.latest.count)")
                metric("Confidence", percent(probe.latest.confidence))
                metric("Quality", probe.latest.quality.map(percent) ?? "—")
                metric("Hit rate", String(format: "%.0f%%", probe.hitRate * 100))
            }
            Text("Stage 1: is the box steady at a 70cm mounting distance? No photo is saved. Identity matching is stage 2.")
                .font(.footnote)
                .foregroundStyle(Theme.cream(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.cream(0.45))
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.faceText)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func percent(_ v: Float) -> String {
        String(format: "%.0f%%", v * 100)
    }

    private func lock(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.headline).foregroundStyle(Theme.faceText)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(Theme.cream(0.6))
            }
        }
        .padding()
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PreviewRepresentable: UIViewRepresentable {
    var view: FaceProbe.PreviewView
    func makeUIView(context: Context) -> FaceProbe.PreviewView { view }
    func updateUIView(_ uiView: FaceProbe.PreviewView, context: Context) {}
}

/// Vision boxes have their origin at the bottom left · normalised 0…1. SwiftUI's origin is the top left.
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
