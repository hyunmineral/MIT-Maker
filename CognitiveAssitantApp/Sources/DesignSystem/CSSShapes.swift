import SwiftUI

// MARK: - Reproducing CSS border-radius

/// Four corner radii (elliptical radii allowed) following the same rules as CSS `border-radius`.
///
/// The robot face's eyes and mouth are drawn in the original prototype with "radii larger than the box", like
/// `border-radius: 120px 120px 0 0`. CSS has a rule that compares such values edge by edge and scales them down
/// (§ CSS Backgrounds 3, "Overlapping curves"), so that scaling is implemented too.
struct CornerRadii: Equatable {
    var topLeading:     CGSize
    var topTrailing:    CGSize
    var bottomTrailing: CGSize
    var bottomLeading:  CGSize

    static func all(_ r: CGFloat) -> CornerRadii {
        let s = CGSize(width: r, height: r)
        return CornerRadii(topLeading: s, topTrailing: s, bottomTrailing: s, bottomLeading: s)
    }

    /// `border-radius: r r 0 0`
    static func top(_ r: CGFloat) -> CornerRadii {
        let s = CGSize(width: r, height: r)
        return CornerRadii(topLeading: s, topTrailing: s, bottomTrailing: .zero, bottomLeading: .zero)
    }

    /// `border-radius: 0 0 r r`
    static func bottom(_ r: CGFloat) -> CornerRadii {
        let s = CGSize(width: r, height: r)
        return CornerRadii(topLeading: .zero, topTrailing: .zero, bottomTrailing: s, bottomLeading: s)
    }

    /// CSS scaling rule: if the minimum over the edges of (edge length / sum of the two radii touching that edge)
    /// is less than 1, multiply every radius by that ratio.
    func resolved(in size: CGSize) -> CornerRadii {
        var f: CGFloat = 1
        func consider(_ length: CGFloat, _ sum: CGFloat) {
            guard sum > 0 else { return }
            f = min(f, length / sum)
        }
        consider(size.width,  topLeading.width + topTrailing.width)
        consider(size.width,  bottomLeading.width + bottomTrailing.width)
        consider(size.height, topLeading.height + bottomLeading.height)
        consider(size.height, topTrailing.height + bottomTrailing.height)
        guard f < 1 else { return self }
        return scaled(by: f)
    }

    func scaled(by f: CGFloat) -> CornerRadii {
        CornerRadii(
            topLeading:     CGSize(width: topLeading.width * f,     height: topLeading.height * f),
            topTrailing:    CGSize(width: topTrailing.width * f,    height: topTrailing.height * f),
            bottomTrailing: CGSize(width: bottomTrailing.width * f, height: bottomTrailing.height * f),
            bottomLeading:  CGSize(width: bottomLeading.width * f,  height: bottomLeading.height * f)
        )
    }

    /// Inner border radius, inset by `border-<edge>-width`.
    /// CSS rule: subtract that axis's border width per axis (negative becomes 0).
    func inset(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) -> CornerRadii {
        func shrink(_ s: CGSize, _ h: CGFloat, _ v: CGFloat) -> CGSize {
            CGSize(width: max(0, s.width - h), height: max(0, s.height - v))
        }
        return CornerRadii(
            topLeading:     shrink(topLeading,     leading,  top),
            topTrailing:    shrink(topTrailing,    trailing, top),
            bottomTrailing: shrink(bottomTrailing, trailing, bottom),
            bottomLeading:  shrink(bottomLeading,  leading,  bottom)
        )
    }

    var components: [Double] {
        [topLeading.width, topLeading.height,
         topTrailing.width, topTrailing.height,
         bottomTrailing.width, bottomTrailing.height,
         bottomLeading.width, bottomLeading.height].map(Double.init)
    }

    init(topLeading: CGSize, topTrailing: CGSize, bottomTrailing: CGSize, bottomLeading: CGSize) {
        self.topLeading = topLeading
        self.topTrailing = topTrailing
        self.bottomTrailing = bottomTrailing
        self.bottomLeading = bottomLeading
    }

    init(components c: [Double]) {
        let v = c.count == 8 ? c : Array(repeating: 0, count: 8)
        self.init(
            topLeading:     CGSize(width: v[0], height: v[1]),
            topTrailing:    CGSize(width: v[2], height: v[3]),
            bottomTrailing: CGSize(width: v[4], height: v[5]),
            bottomLeading:  CGSize(width: v[6], height: v[7])
        )
    }
}

/// A rectangle path with elliptical corners. Interprets `CornerRadii` by the CSS rules.
struct CSSRoundedRect: Shape {
    var radii: CornerRadii

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let r = radii.resolved(in: rect.size)
        let k: CGFloat = 0.5522847498   // Bézier approximation constant for a circular arc
        let (x, y, w, h) = (rect.minX, rect.minY, rect.width, rect.height)

        var p = Path()
        p.move(to: CGPoint(x: x + r.topLeading.width, y: y))

        p.addLine(to: CGPoint(x: x + w - r.topTrailing.width, y: y))
        p.addCurve(
            to: CGPoint(x: x + w, y: y + r.topTrailing.height),
            control1: CGPoint(x: x + w - r.topTrailing.width * (1 - k), y: y),
            control2: CGPoint(x: x + w, y: y + r.topTrailing.height * (1 - k))
        )

        p.addLine(to: CGPoint(x: x + w, y: y + h - r.bottomTrailing.height))
        p.addCurve(
            to: CGPoint(x: x + w - r.bottomTrailing.width, y: y + h),
            control1: CGPoint(x: x + w, y: y + h - r.bottomTrailing.height * (1 - k)),
            control2: CGPoint(x: x + w - r.bottomTrailing.width * (1 - k), y: y + h)
        )

        p.addLine(to: CGPoint(x: x + r.bottomLeading.width, y: y + h))
        p.addCurve(
            to: CGPoint(x: x, y: y + h - r.bottomLeading.height),
            control1: CGPoint(x: x + r.bottomLeading.width * (1 - k), y: y + h),
            control2: CGPoint(x: x, y: y + h - r.bottomLeading.height * (1 - k))
        )

        p.addLine(to: CGPoint(x: x, y: y + r.topLeading.height))
        p.addCurve(
            to: CGPoint(x: x + r.topLeading.width, y: y),
            control1: CGPoint(x: x, y: y + r.topLeading.height * (1 - k)),
            control2: CGPoint(x: x + r.topLeading.width * (1 - k), y: y)
        )

        p.closeSubpath()
        return p
    }
}

/// A CSS box drawn with only `border-top` / `border-bottom`.
///
/// Once the width is at least the box height, the inner hole disappears and the shape becomes solid.
/// That lets "closed eye → open eye → smiling eye (∩)" be expressed with **a single shape**,
/// and expression changes interpolate naturally.
struct CSSBorderShape: Shape {
    var radii: CornerRadii
    var borderTop: CGFloat
    var borderBottom: CGFloat

    /// Bundles the 8 radii + 2 borders into one vector to animate expression changes.
    var animatableData: AnimatableVector {
        get { AnimatableVector(radii.components + [Double(borderTop), Double(borderBottom)]) }
        set {
            radii = CornerRadii(components: Array(newValue.values.prefix(8)))
            borderTop = CGFloat(newValue.values.count > 8 ? newValue.values[8] : 0)
            borderBottom = CGFloat(newValue.values.count > 9 ? newValue.values[9] : 0)
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = CSSRoundedRect(radii: radii).path(in: rect)

        let top = max(0, borderTop)
        let bottom = max(0, borderBottom)
        let innerHeight = rect.height - top - bottom
        guard innerHeight > 0.01 else { return p }   // no hole = solid shape

        let innerRect = CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: innerHeight)
        let innerRadii = radii
            .resolved(in: rect.size)
            .inset(top: top, leading: 0, bottom: bottom, trailing: 0)
        p.addPath(CSSRoundedRect(radii: innerRadii).path(in: innerRect))
        return p   // filling with even-odd punches out the inside
    }
}

// MARK: - Vector for animation

/// Makes a `Double` bundle of unspecified length animatable.
/// Used when one shape interpolates several parameters at once (8 radii + 2 borders).
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double] = []) { self.values = values }

    static var zero: AnimatableVector { AnimatableVector() }

    private static func combine(
        _ a: AnimatableVector, _ b: AnimatableVector,
        _ op: (Double, Double) -> Double
    ) -> AnimatableVector {
        let n = max(a.values.count, b.values.count)
        var out = [Double]()
        out.reserveCapacity(n)
        for i in 0..<n {
            let l = i < a.values.count ? a.values[i] : 0
            let r = i < b.values.count ? b.values[i] : 0
            out.append(op(l, r))
        }
        return AnimatableVector(out)
    }

    static func + (l: AnimatableVector, r: AnimatableVector) -> AnimatableVector { combine(l, r, +) }
    static func - (l: AnimatableVector, r: AnimatableVector) -> AnimatableVector { combine(l, r, -) }

    mutating func scale(by rhs: Double) {
        for i in values.indices { values[i] *= rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}

// MARK: - Repeating diagonal pattern (photo placeholder)

/// CSS `repeating-linear-gradient(45deg, base 0 band, stripe band 2*band)`
struct DiagonalStripes: View {
    var base: Color
    var stripe: Color
    var band: CGFloat = 8

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            // Band width at 45° → converted to horizontal width
            let w = band * 1.4142135
            var x = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + w, y: 0))
                p.addLine(to: CGPoint(x: x + w + size.height, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(stripe))
                x += w * 2
            }
        }
        .drawingGroup()
    }
}
