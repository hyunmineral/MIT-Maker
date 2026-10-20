import SwiftUI

/// The original prototype's `@keyframes`, ported to functions of time.
///
/// Feed in the absolute time that `TimelineView(.animation)` passes each frame and
/// it returns the same values as CSS `infinite` repetition. Because no state variables are used,
/// several screens shown at once (the gallery) never drift out of step.
enum CSSKeyframes {

    /// `@keyframes blink { 0%,92%,100% { scaleY(1) } 96% { scaleY(.08) } }` — 6-second period
    static func blink(_ time: TimeInterval) -> CGFloat {
        let p = time.truncatingRemainder(dividingBy: 6) / 6
        switch p {
        case ..<0.92:
            return 1
        case ..<0.96:
            return 1 - 0.92 * CGFloat((p - 0.92) / 0.04)
        default:
            return 0.08 + 0.92 * CGFloat((p - 0.96) / 0.04)
        }
    }

    /// Ease-in-out round trip (0 → 1 → 0) approximated with a cosine. Shared by breathe / wavebar.
    static func pingPong(_ time: TimeInterval, period: Double, delay: Double = 0) -> CGFloat {
        let p = (time + delay).truncatingRemainder(dividingBy: period) / period
        return CGFloat((1 - cos(2 * .pi * p)) / 2)
    }

    /// `@keyframes breathe { 0%,100% { opacity:.35; scale(1) } 50% { opacity:.7; scale(1.06) } }`
    static func breathe(_ time: TimeInterval) -> (opacity: Double, scale: CGFloat) {
        let p = pingPong(time, period: 4.5)
        return (0.35 + 0.35 * Double(p), 1 + 0.06 * p)
    }

    /// `@keyframes wavebar { 0%,100% { scaleY(.3) } 50% { scaleY(1) } }` — 0.9-second period
    static func waveBar(_ time: TimeInterval, delay: Double) -> CGFloat {
        0.3 + 0.7 * pingPong(time, period: 0.9, delay: delay)
    }
}

/// A thin wrapper that passes the elapsed time every frame.
struct Ticker<Content: View>: View {
    @ViewBuilder var content: (TimeInterval) -> Content

    var body: some View {
        TimelineView(.animation) { timeline in
            content(timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}

/// A blue halo slowly breathing behind the face.
/// `radial-gradient(circle, rgba(40,100,240,.35), transparent 68%)` + `animation: breathe 4.5s`
struct BreathingGlow: View {
    var width: CGFloat = 420
    var height: CGFloat = 280

    var body: some View {
        Ticker { t in
            let b = CSSKeyframes.breathe(t)
            Ellipse()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Theme.blue.opacity(0.35), location: 0),
                            .init(color: Theme.blue.opacity(0), location: 0.68)
                        ]),
                        center: .center, startRadius: 0, endRadius: width / 2
                    )
                )
                .frame(width: width, height: height)
                .opacity(b.opacity)
                .scaleEffect(b.scale)
        }
        .allowsHitTesting(false)
    }
}

/// `@keyframes fadeup` — entrance effect where the quiet record card rises from below.
extension AnyTransition {
    static var fadeUp: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 14).combined(with: .opacity),
            removal: .opacity
        )
    }
}
