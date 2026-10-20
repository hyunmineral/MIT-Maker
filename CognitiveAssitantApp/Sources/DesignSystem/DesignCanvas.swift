import SwiftUI

/// Design canvas size. **1:1 with the portrait logical resolution of the deployment device, iPad Air 5 (M1).**
///
/// 2360 × 1640 px @2x → 820 × 1180 pt. Rendered at scale 1.0, so 1pt is exactly 2px and
/// there is no letterboxing. **pt values are the real size** — the glyph height of a 62pt line is 8.59 mm.
///
/// The previous canvas was 834 × 1194 (iPad Pro 11" 1st gen) and ran scaled down to 0.983 on the Air 5.
/// Once the device was settled it was switched to native. Detailed rationale in `Docs/02_design-criteria.md` section 2.
///
/// Write new screens in **absolute values on the 820 × 1180 basis** too. A responsive layout throws off the scale.
enum DesignSpec {
    static let width: CGFloat = 820
    static let height: CGFloat = 1180
    static let size = CGSize(width: width, height: height)
    static let aspect = width / height
}

/// Fits a screen drawn at 820 × 1180 into the given space, keeping its aspect ratio.
///
/// Drawing the screen in absolute coordinates and scaling it as a whole gives exact per-device pixel mapping.
/// **On the deployment device, iPad Air 5, the scale is 1.0**; on other iPads it is scaled down or up
/// keeping the aspect ratio (on the development iPad Pro 11" 1st gen, 834 × 1194, it is enlarged 1.012× and
/// a 2pt band appears on each side).
struct DesignCanvas<Content: View>: View {
    var background: Color = .black
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / DesignSpec.width, geo.size.height / DesignSpec.height)
            content
                .frame(width: DesignSpec.width, height: DesignSpec.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(background)
        .ignoresSafeArea()
    }
}

/// If the content exceeds the given height it is shrunk to fit as a whole; if there's room it is centred.
///
/// The elder stage of the session screen varies widely in height from step to step: number of lines (2–3) · whether there's a memory card · number of choice buttons.
/// The portrait canvas has little slack, so trimming the margins alone means
/// some step will eventually overflow and be clipped top and bottom (the top bar gets pushed off screen).
/// Clipping makes lines disappear, so it is shrunk to fit the same way `DesignCanvas` does.
///
/// **Don't put a `Spacer` in the content** — the height is then always measured as the available height and shrinking stops working.
/// Give spacing with `VStack(spacing:)`.
/// Generic types can't hold `static` stored properties, so it is pulled outside.
private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct FitToHeight<Content: View>: View {
    /// Where to pin the content in the leftover space. **Use `.top` on the session stage** —
    /// with the default `.center`, lines float up and down depending on whether there's a memory card,
    /// breaking the invariant that "lines are always at the same y" (`Docs/04_screen-design.md` section 2).
    var alignment: Alignment = .center
    @ViewBuilder var content: Content

    @State private var contentHeight: CGFloat = 0

    /// Shrinking must also happen around the alignment anchor so the top doesn't get pushed.
    private var anchor: UnitPoint {
        alignment == .top ? .top : .center
    }

    var body: some View {
        GeometryReader { geo in
            let scale = contentHeight > geo.size.height && contentHeight > 0
                ? geo.size.height / contentHeight
                : 1
            content
                .background(
                    GeometryReader { inner in
                        Color.clear.preference(key: HeightKey.self, value: inner.size.height)
                    }
                )
                .scaleEffect(scale, anchor: anchor)
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
        }
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
    }
}

/// A shrunken thumbnail for the gallery. Shows the original canvas scaled to the given width.
struct ScreenThumbnail<Content: View>: View {
    var width: CGFloat
    var cornerRadius: CGFloat = 14
    @ViewBuilder var content: Content

    private var scale: CGFloat { width / DesignSpec.width }

    var body: some View {
        content
            .frame(width: DesignSpec.width, height: DesignSpec.height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: width, height: DesignSpec.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.16), radius: 5, x: 0, y: 2)
    }
}
