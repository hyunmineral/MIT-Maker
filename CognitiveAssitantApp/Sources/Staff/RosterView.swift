import SwiftData
import SwiftUI

/// 13 Today's elder roster · Roster
///
/// Only people with an enrolled face are recognised automatically. Warning signs are shown only by the card border —
/// the principle of not diagnosing and only making 'change' noticeable holds in the list too.
///
/// **Reads from the memory store.** It used to be a Swift array literal (stage 0.5).
/// Until stage 3 (Vision), staff choosing here also stands in for starting a session.
struct RosterView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Elder.name) private var elders: [Elder]
    /// The person whose honorific/surname is being edited. Opens when the card is pressed.
    @State private var editing: Elder?

    struct Entry: Identifiable {
        var id: PersistentIdentifier
        var name: String
        /// The name the robot actually calls. **Staff must check it before starting** —
        /// whether to use the first name or surname is the elder's choice, and getting it wrong is rude.
        var spoken: String
        var status: String
        var statusColor: Color
        /// What to open this elder's session with. Staff check before starting —
        /// nobody is seated without knowing what the robot will ask first.
        var opener: String?
        var emphasized: Bool = false
        var alert: Bool = false
        /// **The form of address hasn't been set.** Left like this, the robot calls the full name.
        var needsAddress: Bool = false
    }

    // At the 820 portrait width, 3 columns narrow each card to 232pt and the name and status overlap. Use 2 columns.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 2)

    private var entries: [Entry] {
        let store = MemoryStore(context: context)
        return elders.map { elder in
            Entry(id: elder.persistentModelID,
                  name: elder.name,
                  spoken: elder.spokenName,
                  status: status(for: elder, store: store),
                  statusColor: statusColor(for: elder, store: store),
                  opener: openerLabel(for: elder, store: store),
                  emphasized: store.todaySession(for: elder) != nil,
                  needsAddress: elder.honorific == nil && !elder.invitedFirstName)
        }
    }

    /// One line for the opener. Also shows what it's based on —
    /// "promise" means it was previewed last time, and that's a topic that must be kept.
    private func openerLabel(for elder: Elder, store: MemoryStore) -> String? {
        guard let opener = store.opener(for: elder) else { return nil }
        let source: String
        switch opener.source {
        case .promised:       source = "promised"
        case .lastTopic:      source = "last topic"
        case .longTermAnchor: source = "long-term"
        }
        return "\(opener.topic) · \(source)"
    }

    /// One status line. **No diagnosis** — it only records what was done today.
    private func status(for elder: Elder, store: MemoryStore) -> String {
        if let today = store.todaySession(for: elder) {
            if today.endedAt == nil {
                let minutes = max(1, Int(Date.now.timeIntervalSince(today.startedAt) / 60))
                return "In session · \(minutes) min"
            }
            return "Done today · \(today.durationMinutes) min"
        }
        if store.lastCompletedSession(for: elder) == nil {
            return "First session · baseline"
        }
        return "Not seen today"
    }

    private func statusColor(for elder: Elder, store: MemoryStore) -> Color {
        guard let today = store.todaySession(for: elder) else { return Theme.gray6B }
        return today.endedAt == nil ? Theme.blue : Theme.gray6B
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .firstTextBaseline) {
                Text("Here today · \(todayLabel)")
                    .font(.kr(38, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("Oak Street Adult Day")
                    .font(.kr(20))
                    .foregroundStyle(Theme.gray6B)
            }

            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(entries) { entry in
                    Button {
                        editing = elders.first { $0.persistentModelID == entry.id }
                    } label: {
                        card(entry)
                    }
                    .buttonStyle(.plain)
                }
                addCard
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Layout.sideMargin)
        .padding(.vertical, 40)
        .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .topLeading)
        .background(Theme.staffPaper)
        .sheet(item: $editing) { ElderDetailView(elder: $0) }
    }

    private func card(_ entry: Entry) -> some View {
        HStack(spacing: 16) {
            DiagonalStripes(base: Color(hex: 0xE7E2D6), stripe: Color(hex: 0xF2EDE2), band: 8)
                .frame(width: 76, height: 76)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name)
                    .font(.kr(26, .bold))
                    .foregroundStyle(Theme.ink)
                // If the prefix is long, **the name itself gets cut off** (`Mr. Silliva…`).
                // The speech-bubble icon already signals "speaks", so keep the prefix short,
                // and allow shrinking so long surnames don't get cut.
                Label("Says “\(entry.spoken)”", systemImage: "quote.bubble")
                    .font(.kr(15))
                    .foregroundStyle(Theme.gray6B)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(entry.status)
                    .font(.kr(18, entry.emphasized ? .semibold : .regular))
                    .foregroundStyle(entry.statusColor)
                if let opener = entry.opener {
                    Label(opener, systemImage: "arrow.turn.down.right")
                        .font(.kr(15))
                        .foregroundStyle(Theme.blue)
                        .lineLimit(1)
                }
                if entry.needsAddress {
                    // **The name to call hasn't been set.** For now it calls the full name.
                    Label("Set what to call them", systemImage: "exclamationmark.circle")
                        .font(.kr(15, .semibold))
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(entry.alert ? Theme.red : Theme.cardBorder,
                              lineWidth: entry.alert ? 2 : 1)
        )
    }

    private var addCard: some View {
        Text("+ Enroll someone new")
            .font(.kr(22, .semibold))
            .foregroundStyle(Theme.gray6B)
            .frame(maxWidth: .infinity)
            .padding(22)
            .background(Color(hex: 0xEFEBE1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.ink(0.22),
                                  style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            )
    }
}
