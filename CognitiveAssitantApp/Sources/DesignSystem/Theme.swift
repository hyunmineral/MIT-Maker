import SwiftUI

/// Design tokens.
/// Source: the colour constants `C` and inline styles in `Design/project/Elder Conversation Robot iPad.dc.html`.
enum Theme {

    // MARK: - Palette

    static let cream    = Color(hex: 0xF2EBDC)   // C.cream
    static let blue     = Color(hex: 0x2864F0)   // C.blue
    static let red      = Color(hex: 0xC8442E)   // C.red
    static let green    = Color(hex: 0x1F8A5B)   // C.green
    static let amber    = Color(hex: 0xE8C24A)   // C.amber

    static let ink      = Color(hex: 0x0F1115)
    static let faceText = Color(hex: 0xF7F2E7)

    static let paper      = Color(hex: 0xEDE9E1)   // design canvas background
    static let staffPaper = Color(hex: 0xF7F5F0)   // staff screen background

    static let gray4A = Color(hex: 0x4A4A4A)
    static let gray6B = Color(hex: 0x6B6B6B)
    static let gray8A = Color(hex: 0x8A8A8A)

    /// `border: 1px solid rgba(15,17,21,.1)`
    static let cardBorder = ink.opacity(0.10)

    // MARK: - Convenience initialisers

    /// `rgba(242,235,220,α)`
    static func cream(_ alpha: Double) -> Color { cream.opacity(alpha) }
    /// `rgba(15,17,21,α)`
    static func ink(_ alpha: Double) -> Color { ink.opacity(alpha) }

    // MARK: - Grid · spacing

    /// Layout constants for the 820 × 1180 canvas. Rationale in `Docs/02_design-criteria.md` sections 2 and 6.
    enum Layout {
        /// The base unit for all spacing. Spacing is only given in multiples of this value.
        static let unit: CGFloat = 8

        static let sideMargin: CGFloat = 48
        /// Usable width minus the side margins. 820 − 48 × 2
        static let contentWidth: CGFloat = DesignSpec.width - sideMargin * 2

        /// Height given over to the staff panel at the bottom of the screen in pilot (Wizard of Oz) mode.
        static let staffPanelHeight: CGFloat = 200
        /// Height left for the elder stage in pilot mode. 1180 − 200
        static let stageHeightPilot: CGFloat = DesignSpec.height - staffPanelHeight

        /// y coordinate of the robot's eye centre. The front camera sits at the top centre of the screen, so
        /// this value determines the gaze error — 4.4° at 280pt for 70 cm.
        /// **Above 318pt it exceeds 5° and is perceived as "looking past you".**
        static let eyeCenterY: CGFloat = 280
        /// In pilot mode the stage is squeezed, so the eyes sit a little higher. Raising it further from 240 → 232 was
        /// **to win back vertical budget below**, and the gaze error shrinks along with it (3.8° → 3.7°) —
        /// there's no loss in this direction. The lower bound is where the tallest expression, `.surprise`,
        /// doesn't intrude into `captionTopPilot` (see the calculation below).
        static let eyeCenterYPilot: CGFloat = 232

        /// The y where the line block starts. **Pinned so lines stay in the same place across screens** —
        /// face height varies widely by expression, 288–523, so with centre alignment
        /// lines jump up and down at every step. `Docs/04_screen-design.md` section 2.
        static let captionTop: CGFloat = 560
        /// The pilot stage is only 980, so **to fit 74pt lines without shrinking, the space has to be won here.**
        /// The worst step is **3-line caption + listening waveform + memory card**, and there are three of them
        /// (`Continuity opener` · `Reminiscence` · `openerStep`).
        /// Required = `279.85 + 16 + 44 + 16 + 160` = **515.85**.
        ///
        /// - `500` → budget 480. It overflowed, `FitToHeight` shrank it to 0.914, and
        ///   **74pt rendered as 67.6pt (32.7 arcminutes)** — raising just the constant cancels out the net effect.
        /// - `460` → budget 520. **4.15pt of slack.** Confirmed no shrinking in the simulator on 2026-09-01
        ///   (line pitch 95.75pt · cap height 52.5pt).
        ///
        /// **There's only 4pt of slack.** Touch the waveform or card heights or the line spacing and it overflows immediately.
        /// Overflow doesn't fail with an error but by **the lines silently getting smaller**, so
        /// whenever you edit around here, re-measure the line pitch on a device/simulator.
        ///
        /// **Why it can't go lower**: face bottom = `eyeCenterYPilot + eye height/2 + faceStackGap
        /// + mouth height`. The largest, `.surprise`, is `232 + 59 + 34 + 120 = 445`, leaving 15pt of slack.
        static let captionTopPilot: CGFloat = 460

        /// Between the eyes and mouth. Same value as `RobotFaceView`'s `VStack(spacing:)`.
        static let faceStackGap: CGFloat = 34
        /// Spacing below the line (listening waveform · memory card).
        ///
        /// **Pulled out as a constant because it's a vertical budget item.** At 24 the worst pilot step exceeded the budget
        /// and `FitToHeight` shrank the lines along with it. With lines grown to 74pt
        /// there's already enough visual weight, so narrowing it to 16 doesn't feel cramped.
        static let belowCaptionSpacing: CGFloat = 16
        /// Memory card height.
        static let memoryCardHeight: CGFloat = 160

        static let cardRadius: CGFloat = 24
        static let buttonRadius: CGFloat = 16
        /// Height of staff control buttons. Set larger than the HIG minimum of 44.
        static let staffButtonHeight: CGFloat = 56
        static let staffRowHeight: CGFloat = 64
    }

    // MARK: - Type scale

    /// Text size by role. The canvas scale is 1.0, so **pt is the real size**.
    ///
    /// Legibility tiers (`Docs/02_design-criteria.md` sections 3 and 4):
    /// - **A Must be read** — ≥ 35 arcminutes at 70 cm. Robot lines.
    /// - **B Must be recognisable** — ≥ 22 arcminutes. Memory card.
    /// - **C Staff only** — based on a staff distance of 40 cm.
    ///
    /// **Based on the English screen** (corrected 2026-09-01). Effective arcminutes = `pt × 0.4839` (70 cm),
    /// x-height mm = `pt × 0.0997`. Because Latin lowercase x-height is 0.5176 em.
    ///
    /// The old factors `0.6804` (= em-based) and `0.72` (Hangul glyph ÷ em) **assume a Korean screen**, so
    /// they aren't used for the current screen. Don't cite the arcminute figures in `Docs/04_screen-design.md`,
    /// which haven't been corrected yet, as evidence.
    enum Size {
        /// Tier A (35 arcminutes or more). **The 42.2 arcminutes from the Hangul basis doesn't fit the English screen** —
        /// Latin lowercase x-height is 0.5176 em, so effective arcminutes are `pt × 0.4839`
        /// (70 cm, SF Pro. Matches the on-device ruler measurement of 8.4 mm/6.1 mm).
        ///
        /// 62pt is 30.0 arcminutes — **not tier A, but barely at the presbyopia lower bound**.
        /// 72pt is also short at 34.8 arcminutes — for the same reason `Docs/02_design-criteria.md` section 4 rejected 52pt,
        /// it isn't rounded up to pass. **74pt at 35.8 arcminutes** is the first value
        /// above the lower bound (settled 2026-09-01).
        ///
        /// **At most 3 lines** — at 4 lines the vertical budget overflows and `FitToHeight` shrinks everything.
        /// 3-line height **279.85pt** = `88.35 × 3 + 7.4 × 2` (line height measured in UIKit —
        /// computing with AppKit `NSFont` gives 87, which is **1.35pt too small.** When checking the budget,
        /// use the simulator's measured line pitch of 95.75pt). For the budget see `Layout.captionTopPilot`.
        static let speech: CGFloat = 74
        /// Tier B. Memory card title.
        static let cardTitle: CGFloat = 40
        /// Tier B. Memory card body.
        static let cardBody: CGFloat = 34
        /// Tier C. Memory card category label ("Last session · July 20").
        static let cardKind: CGFloat = 22

        static let staffButton: CGFloat = 20
        static let staffMetric: CGFloat = 18
        static let staffLabel: CGFloat = 13
        static let staffLog: CGFloat = 11
    }

    /// Line-spacing multiple for lines. Block height = `speech × speechLineHeight × line count`.
    static let speechLineHeight: CGFloat = 1.35
    /// Maximum height of the line block (3 lines). 62 × 1.35 × 3
    static let speechMaxHeight: CGFloat = Size.speech * speechLineHeight * 3
}

extension Color {
    /// `Color(hex: 0x2864F0)`
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension Font {
    /// Equivalent of CSS `font: <weight> <size>px "Noto Sans KR"`.
    ///
    /// The Noto Sans KR file isn't bundled; the system font is used. iOS automatically maps Hangul glyphs
    /// to Apple SD Gothic Neo, so letterforms and spacing are almost the same as Noto Sans KR.
    /// To switch to exact Noto, put the font file in `Resources/Fonts` and change only this.
    static func kr(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// CSS `font: 600 10px ui-monospace, Menlo, monospace`
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Approximation of CSS `line-height: <multiple>`.
    ///
    /// SwiftUI adds extra spacing on top of the font's default leading (≈1.25em), so
    /// the requested multiple minus 1.25 is given as `lineSpacing`.
    func cssLineHeight(_ multiple: CGFloat, _ fontSize: CGFloat) -> some View {
        lineSpacing(max(0, fontSize * (multiple - 1.25)))
    }

    /// CSS `letter-spacing: <em>em`
    func letterSpacing(_ em: CGFloat, _ fontSize: CGFloat) -> some View {
        tracking(em * fontSize)
    }
}
