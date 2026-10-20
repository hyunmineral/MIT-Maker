import SwiftData
import SwiftUI

/// 14 Memory map · Memory map
///
/// People, places and events are nodes, and topics that came alive in recent conversation are highlighted in blue.
///
/// **Built from the store.** Until 2026-09-10 the coordinates and names of five nodes were hard-coded
/// — whoever was seated, Dorothy's map appeared. Now it reads `Fact`s and
/// draws them. Coordinates are **placed around a circle in order of how often they were mentioned**.
///
/// The coordinate system is **724 × 940** inside the 820 × 1180 portrait canvas, offset by (48, 150).
struct MemoryMapView: View {

    @Query(sort: \Elder.name) private var elders: [Elder]

    /// Whose map it is. If not specified, the person who most recently had a session.
    var subject: Elder?

    private enum Space {
        static let width = Theme.Layout.contentWidth   // 724
        static let height: CGFloat = 940
        static let origin = CGPoint(x: Theme.Layout.sideMargin, y: 150)
        static var center: CGPoint { CGPoint(x: width / 2, y: height / 2) }
    }

    /// Upper limit on the number of topics placed around the circle. **Beyond it, labels overlap and become unreadable.**
    private static let maxNodes = 8
    /// A topic that came up again within this window is considered 'alive'.
    private static let activeWindowDays = 7

    struct Node {
        var center: CGPoint
        var radius: CGFloat
        var title: String
        var subtitle: String?
        var active: Bool = false
        var isSelf: Bool = false
    }

    private var elder: Elder? {
        subject ?? elders
            .filter { !$0.sessions.isEmpty || !$0.facts.isEmpty }
            .max(by: { ($0.sessions.map(\.startedAt).max() ?? $0.enrolledAt)
                     < ($1.sessions.map(\.startedAt).max() ?? $1.enrolledAt) })
    }

    /// Facts to draw. The most mentioned come first.
    private func facts(of elder: Elder) -> [Fact] {
        elder.facts
            .sorted { ($0.mentionCount, $0.lastMentionedAt) > ($1.mentionCount, $1.lastMentionedAt) }
            .prefix(Self.maxNodes)
            .map { $0 }
    }

    private func selfNode(for elder: Elder) -> Node {
        let subtitle = [elder.birthYear.map(String.init), elder.hometown]
            .compactMap { $0 }
            .joined(separator: " · ")
        return Node(center: Space.center, radius: 86,
                    title: FormOfAddress.givenName(from: elder.name),
                    subtitle: subtitle.isEmpty ? nil : subtitle,
                    isSelf: true)
    }

    /// Placement around the circumference. **An ellipse, not a circle** — the canvas is tall, so a circle leaves the top and bottom empty.
    private func nodes(for elder: Elder) -> [Node] {
        let items = facts(of: elder)
        guard !items.isEmpty else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day,
                                           value: -Self.activeWindowDays, to: .now) ?? .distantPast

        return items.enumerated().map { index, fact in
            let angle = (Double(index) / Double(items.count)) * 2 * .pi - .pi / 2
            let center = CGPoint(
                x: Space.center.x + cos(angle) * (Space.width / 2 - 76),
                y: Space.center.y + sin(angle) * (Space.height / 2 - 92)
            )
            let active = fact.lastMentionedAt >= cutoff
            return Node(
                center: center,
                radius: active ? 70 : 62,
                title: fact.subject,
                subtitle: fact.mentionCount > 1 ? "\(fact.mentionCount) mentions" : nil,
                active: active
            )
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.ink
            if let elder {
                headerRow(for: elder)
                graph(for: elder)
                    .frame(width: Space.width, height: Space.height)
                    .offset(x: Space.origin.x, y: Space.origin.y)
                legend
            } else {
                emptyState
            }
        }
        .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .topLeading)
        .clipped()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No memory map yet")
                .font(.kr(36, .bold))
                .foregroundStyle(Theme.faceText)
            Text("The map is drawn from what the elder has told the robot. "
                 + "It fills in as sessions record facts.")
                .font(.kr(20))
                .foregroundStyle(Theme.cream(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Layout.sideMargin)
        .padding(.top, 40)
    }

    private func headerRow(for elder: Elder) -> some View {
        let counts = Dictionary(grouping: elder.facts, by: \.kind)
            .mapValues(\.count)
        let summary = FactKind.allCases
            .compactMap { kind -> String? in
                guard let n = counts[kind], n > 0 else { return nil }
                return "\(n) \(kind.rawValue)\(n > 1 ? "s" : "")"
            }
            .joined(separator: " · ")

        return HStack(alignment: .firstTextBaseline) {
            Text("\(elder.name)'s memory map")
                .font(.kr(36, .bold))
                .foregroundStyle(Theme.faceText)
            Spacer()
            Text(summary.isEmpty ? "Nothing on file yet" : summary)
                .font(.kr(19))
                .foregroundStyle(Theme.cream(0.45))
        }
        .padding(.horizontal, Theme.Layout.sideMargin)
        .padding(.top, 40)
    }

    private func graph(for elder: Elder) -> some View {
        let center = selfNode(for: elder)
        let ring = nodes(for: elder)
        return ZStack {
            ForEach(Array(ring.enumerated()), id: \.offset) { _, node in
                edge(from: center.center, to: node.center,
                     color: node.active ? Theme.blue.opacity(0.7) : Theme.cream(0.22),
                     width: node.active ? 5 : 3)
            }
            ForEach(Array(ring.enumerated()), id: \.offset) { _, node in
                nodeView(node)
            }
            nodeView(center)
        }
    }

    private func edge(from a: CGPoint, to b: CGPoint, color: Color, width: CGFloat) -> some View {
        Path { p in
            p.move(to: a)
            p.addLine(to: b)
        }
        .stroke(color, lineWidth: width)
    }

    @ViewBuilder
    private func nodeView(_ node: Node) -> some View {
        ZStack {
            Circle()
                .fill(fill(for: node))
                .overlay(Circle().strokeBorder(stroke(for: node).0, lineWidth: stroke(for: node).1))
                .frame(width: node.radius * 2, height: node.radius * 2)

            VStack(spacing: node.isSelf ? 4 : 2) {
                Text(node.title)
                    .font(.kr(node.isSelf ? 30 : 24, node.isSelf || node.active ? .bold : .regular))
                    .foregroundStyle(node.isSelf ? Theme.ink : (node.active ? .white : Theme.cream))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
                    .frame(width: node.radius * 1.8)
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(.kr(node.isSelf ? 20 : 17))
                        .foregroundStyle(node.isSelf ? Theme.gray6B : Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
        }
        .position(node.center)
    }

    private func fill(for node: Node) -> Color {
        if node.isSelf { return Theme.cream }
        return node.active ? Theme.blue.opacity(0.25) : Theme.cream(0.12)
    }

    private func stroke(for node: Node) -> (Color, CGFloat) {
        if node.isSelf { return (.clear, 0) }
        return node.active ? (Theme.blue, 4) : (Theme.cream(0.35), 2)
    }

    private var legend: some View {
        HStack(spacing: 26) {
            Text("● Told before")
            Text("● Came up this week").foregroundStyle(Theme.blue)
        }
        .font(.kr(19))
        .foregroundStyle(Theme.cream(0.5))
        .padding(.leading, Theme.Layout.sideMargin)
        .frame(width: DesignSpec.width, height: DesignSpec.height - 36, alignment: .bottomLeading)
    }
}
