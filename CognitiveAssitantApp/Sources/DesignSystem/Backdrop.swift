import SwiftUI

/// Reproduces CSS `radial-gradient(<rx>% <ry>% at <cx>% <cy>%, inner 0%, outer <stop>%)`.
///
/// SwiftUI's `EllipticalGradient` ties its radius reference to the frame, so unlike CSS
/// you can't specify "120% of width / 90% of height" directly. So a circular gradient is drawn
/// and then stretched per axis into an ellipse.
struct CSSRadialBackdrop: View {
    var inner: Color
    var outer: Color
    /// Centre position (0…1)
    var centerX: CGFloat = 0.5
    var centerY: CGFloat = 0.5
    /// Ellipse radii — as a fraction of width and height
    var radiusX: CGFloat = 1.20
    var radiusY: CGFloat = 0.90
    /// Point at which the outer colour is fully reached (0…1)
    var stop: CGFloat = 0.62

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let unit: CGFloat = 100

            outer.overlay(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: inner, location: 0),
                        .init(color: outer, location: stop),
                        .init(color: outer, location: 1)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: unit
                )
                .frame(width: unit * 2, height: unit * 2)
                .scaleEffect(x: (w * radiusX) / unit, y: (h * radiusY) / unit)
                .position(x: w * centerX, y: h * centerY)
            )
        }
        .clipped()
    }
}

/// Per-screen background presets. 1:1 with each `background:radial-gradient(...)` in the original HTML.
enum Backdrop {
    /// Interactive session screen — `at 50% 15%, #1B2029 → #0C0E13 62%`
    static var session: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x1B2029), outer: Color(hex: 0x0C0E13),
                          centerY: 0.15, stop: 0.62)
    }

    /// 01 Resting — `at 50% 30%, #151920 → #0A0C10 65%`
    static var idle: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x151920), outer: Color(hex: 0x0A0C10),
                          centerY: 0.30, stop: 0.65)
    }

    /// 02·03·04 — `at 50% 25%, #1B2029 → #0C0E13 65%`
    static var standard25: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x1B2029), outer: Color(hex: 0x0C0E13),
                          centerY: 0.25, stop: 0.65)
    }

    /// 05·06·07·08·11 — `at 50% 22%`
    static var standard22: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x1B2029), outer: Color(hex: 0x0C0E13),
                          centerY: 0.22, stop: 0.65)
    }

    /// 09 Recall conversation — `at 50% 20%`
    static var standard20: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x1B2029), outer: Color(hex: 0x0C0E13),
                          centerY: 0.20, stop: 0.65)
    }

    /// 10 Gentle recovery — warm tone `#1D1A17`
    static var warm: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x1D1A17), outer: Color(hex: 0x0C0E13),
                          centerY: 0.22, stop: 0.65)
    }

    /// 12 Call staff — red tone `#231414`
    static var alert: CSSRadialBackdrop {
        CSSRadialBackdrop(inner: Color(hex: 0x231414), outer: Color(hex: 0x0C0E13),
                          centerY: 0.22, stop: 0.65)
    }
}
