import SwiftUI

/// Geometry for one eye or one mouth.
///
/// The original `FACE` presets sometimes fill the eye solid with `background` (open eye)
/// and sometimes leave only `border-top` (smiling eye ∩). Here the two are unified into one
/// `CSSBorderShape` — once the border is at least as thick as the height the shape becomes solid,
/// so expressions can interpolate seamlessly.
struct FacePart: Equatable {
    var width: CGFloat
    var height: CGFloat
    var radii: CornerRadii
    var borderTop: CGFloat
    var borderBottom: CGFloat
    var opacity: Double

    init(width: CGFloat, height: CGFloat, radii: CornerRadii,
         borderTop: CGFloat = 0, borderBottom: CGFloat = 0, opacity: Double = 1) {
        self.width = width
        self.height = height
        self.radii = radii
        self.borderTop = borderTop
        self.borderBottom = borderBottom
        self.opacity = opacity
    }

    /// A shape filled solid with `background` (= the same as a top border as thick as the height)
    static func solid(_ w: CGFloat, _ h: CGFloat, _ radii: CornerRadii, opacity: Double = 1) -> FacePart {
        FacePart(width: w, height: h, radii: radii, borderTop: h, opacity: opacity)
    }

    /// No mouth (sleeping face). Size 0, so it grows naturally into other mouth shapes.
    static let hidden = FacePart(width: 0, height: 0, radii: .all(0), opacity: 0)
}

/// Robot expression presets. 1:1 with the `FACE` constants in the original script.
struct FaceStyle: Equatable {
    var eye: FacePart
    var eyeGap: CGFloat
    var mouth: FacePart

    /// Sleeping — thin line eyes, no mouth
    static let sleep = FaceStyle(
        eye: .solid(120, 16, .all(999), opacity: 0.4),
        eyeGap: 150,
        mouth: .hidden
    )

    /// Default — round eyes + a small straight mouth
    static let neutral = FaceStyle(
        eye: .solid(110, 110, .all(55)),
        eyeGap: 140,
        mouth: .solid(120, 22, .all(999))
    )

    /// Happy — ∩-shaped eyes + a wide-open mouth
    static let happy = FaceStyle(
        eye: FacePart(width: 120, height: 60, radii: .top(120), borderTop: 22),
        eyeGap: 140,
        mouth: .solid(170, 80, .bottom(200))
    )

    /// Surprised — big round eyes + a round mouth
    static let surprise = FaceStyle(
        eye: .solid(118, 118, .all(59)),
        eyeGap: 140,
        mouth: .solid(120, 120, .all(60))
    )

    /// Sorry · gentle — slightly folded eyes + a thin mouth
    static let soft = FaceStyle(
        eye: FacePart(width: 120, height: 46, radii: .top(120), borderTop: 18),
        eyeGap: 140,
        mouth: .solid(150, 26, .all(999))
    )
}

// MARK: - Rendering

/// Draws one piece of an eye or mouth.
struct FacePartView: View {
    var part: FacePart
    var color: Color = Theme.cream

    var body: some View {
        CSSBorderShape(radii: part.radii, borderTop: part.borderTop, borderBottom: part.borderBottom)
            .fill(color.opacity(part.opacity), style: FillStyle(eoFill: true))
            .frame(width: part.width, height: part.height)
    }
}

/// Two eyes. Blinks once every 6 seconds.
struct EyesView: View {
    var style: FaceStyle
    var color: Color = Theme.cream
    var blinks: Bool = true

    var body: some View {
        if blinks {
            Ticker { t in
                row.scaleEffect(y: CSSKeyframes.blink(t), anchor: .center)
            }
            .frame(height: style.eye.height)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: style.eyeGap) {
            FacePartView(part: style.eye, color: color)
            FacePartView(part: style.eye, color: color)
        }
    }
}

/// The robot face combining halo + eyes + mouth. Used on the interactive session screen.
struct RobotFaceView: View {
    var style: FaceStyle
    var showsGlow: Bool = true

    /// Distance from the top of the view to the top of the eyes. Subtract it when aligning the eyes' absolute y from outside —
    /// the front camera sits at the top centre of the screen, so the eyes' y is the gaze error
    /// (`Docs/02_design-criteria.md` section 5).
    static let eyeInset: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
            if showsGlow {
                BreathingGlow()
                    .offset(y: -14)
            }
            VStack(spacing: Theme.Layout.faceStackGap) {
                EyesView(style: style)
                FacePartView(part: style.mouth)
            }
            .padding(.top, Self.eyeInset)
        }
        .frame(width: 420)
        .animation(.easeInOut(duration: 0.3), value: style)
    }
}
