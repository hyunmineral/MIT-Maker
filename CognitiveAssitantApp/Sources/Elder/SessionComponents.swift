import SwiftUI

/// Five bars signalling "I'm listening". Plays `@keyframes wavebar` offset by 0.15 s each.
struct ListeningWave: View {
    var barWidth: CGFloat = 7
    var barHeight: CGFloat = 34
    var spacing: CGFloat = 7
    var color: Color = Theme.blue

    var body: some View {
        Ticker { t in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth * 0.57, style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: barHeight)
                        .scaleEffect(y: CSSKeyframes.waveBar(t, delay: Double(i) * 0.15), anchor: .bottom)
                }
            }
        }
        .frame(height: barHeight)
    }
}

/// A diagonal placeholder marking where a photo will go.
struct PhotoPlaceholder: View {
    var text: String
    var fontSize: CGFloat
    var band: CGFloat = 8

    var body: some View {
        ZStack {
            DiagonalStripes(base: Theme.cream(0.14), stripe: Theme.cream(0.06), band: band)
            Text(text)
                .font(.kr(fontSize))
                .foregroundStyle(Theme.cream(0.5))
                .multilineTextAlignment(.center)
                .cssLineHeight(1.3, fontSize)
        }
    }
}

/// The memory card on the elder screens (shared by last-session summary · old photo · enrolment notice).
///
/// **Tier B size** — title 40pt (27 arcminutes) · body 34pt (23 arcminutes). Sized to be recognised,
/// not read; the robot speaks the content aloud (`Docs/02_design-criteria.md` section 3).
///
/// Previously the title was 22pt and the body 15pt. 15pt is **10 arcminutes** at 70 cm, so elders
/// can't see it at all — it was not a size for anything placed on an elder screen.
struct SessionMemoryCard: View {
    var card: MemoryCard

    var body: some View {
        HStack(spacing: 24) {
            PhotoPlaceholder(text: "Photo", fontSize: 18)
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(card.kind)
                    .font(.kr(Theme.Size.cardKind, .medium))
                    .letterSpacing(0.1, Theme.Size.cardKind)
                    .foregroundStyle(Theme.blue)
                Text(card.title)
                    .font(.kr(Theme.Size.cardTitle, .semibold))
                    .foregroundStyle(Theme.faceText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(card.body)
                    .font(.kr(Theme.Size.cardBody))
                    .foregroundStyle(Theme.cream(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(width: Theme.Layout.contentWidth,
               height: Theme.Layout.memoryCardHeight)
        .background(Theme.cream(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                .strokeBorder(Theme.cream(0.15), lineWidth: 1)
        )
    }
}

/// Answer-choice buttons **pressed by staff** (Wizard of Oz).
///
/// They used to be big 26pt cream pills in the middle of the elder screen. That meant **what the elder would say
/// was written on the screen in advance**, so natural conversation couldn't be observed.
/// Moved down to the staff panel and reduced to tier C 20pt — 13.6 arcminutes at 70 cm,
/// far short of the presbyopia lower bound (30 arcminutes), so **physically unreadable for elders.**
/// At the staff distance of 40 cm it's 23.8 arcminutes, comfortably readable. `Docs/03_product-design.md` section 5.
struct ChoiceButton: View {
    var label: String
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kr(Theme.Size.staffButton, .medium))
                .foregroundStyle(Theme.cream(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 22)
                // **Cap the width.** Script labels are long, and if just two fill the panel
                // the suggestion button next to them is pushed off screen and can't be pressed.
                // Staff know the script, so the first part alone is enough to tell them apart.
                .frame(maxWidth: 260)
                .frame(height: Theme.Layout.staffButtonHeight)
                .background(Theme.cream(pressed ? 0.20 : 0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonRadius,
                                            style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(pressed ? Theme.blue : Theme.cream(0.22), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: pressed)
        ._onPressChange { pressed = $0 }
    }
}

/// Small pill button at the top right of the session screen (staff control).
struct PillButton: View {
    var label: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.kr(13, .medium))
                .foregroundStyle(Theme.cream(0.75))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.cream(hovering ? 0.16 : 0.08))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Theme.cream(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension View {
    /// Passes the pressed state to a callback (equivalent of `style-hover`).
    func _onPressChange(_ handler: @escaping (Bool) -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in handler(true) }
                .onEnded { _ in handler(false) }
        )
    }
}
