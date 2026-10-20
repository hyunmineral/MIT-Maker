import SwiftUI
import UIKit

/// A hidden entry point that opens staff functions by **long-pressing with two fingers** anywhere on screen.
///
/// In deployment mode there is no staff UI on screen at all (`Docs/02_design-criteria.md` section 6).
/// Staff still need to change the voice or check status, so there must be one way in.
///
/// **Why two fingers** — elders must not be able to open it by accident, and staff who know it must be able
/// to open it instantly. A one-finger long press opens just by resting a hand on the screen.
/// It also doesn't conflict with the premise that elders don't touch the screen (principle 4) —
/// this isn't elder input but a staff unlock.
///
/// **Why attach it to the window rather than a view** — a gesture on a transparent view covering the whole canvas
/// blocks every button beneath it. Attaching it to the window with `cancelsTouchesInView = false` lets
/// ordinary taps pass through while catching only the two-finger long press.
struct TwoFingerLongPress: UIViewRepresentable {
    var minimumDuration: Double = 1.5
    var action: () -> Void

    func makeUIView(context: Context) -> PassthroughView {
        let view = PassthroughView()
        context.coordinator.action = action
        context.coordinator.install(from: view, duration: minimumDuration)
        return view
    }

    func updateUIView(_ view: PassthroughView, context: Context) {
        context.coordinator.action = action
        context.coordinator.install(from: view, duration: minimumDuration)
    }

    static func dismantleUIView(_ view: PassthroughView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// An empty view that only takes up space and passes every touch through. The gesture is attached to the window.
    final class PassthroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void = {}

        private weak var host: UIWindow?
        private var recognizer: UILongPressGestureRecognizer?
        /// If the view isn't attached to a window yet, try again on the next run loop.
        /// The number of attempts is capped in case it never attaches.
        private var attempts = 0

        func install(from view: UIView, duration: Double) {
            guard recognizer == nil else { return }

            guard let window = view.window else {
                guard attempts < 20 else { return }
                attempts += 1
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.install(from: view, duration: duration)
                }
                return
            }

            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(fire))
            gesture.numberOfTouchesRequired = 2
            gesture.minimumPressDuration = duration
            // Remove this and the buttons underneath stop responding.
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            window.addGestureRecognizer(gesture)

            recognizer = gesture
            host = window
        }

        func remove() {
            if let recognizer { host?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
        }

        @objc func fire(_ gesture: UILongPressGestureRecognizer) {
            // Only on `.began`. Otherwise it fires several times while the fingers lift.
            guard gesture.state == .began else { return }
            action()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

extension View {
    /// Opens staff functions with a two-finger long press anywhere on screen.
    func twoFingerLongPress(minimumDuration: Double = 1.5,
                            perform action: @escaping () -> Void) -> some View {
        background(TwoFingerLongPress(minimumDuration: minimumDuration, action: action))
    }
}
