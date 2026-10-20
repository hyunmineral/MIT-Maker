import SwiftUI

/// The list of 16 screens from the design document.
/// Numbers, titles and descriptions were taken from the original `figcaption`s and rewritten in English.
struct ScreenSpec: Identifiable {
    let id: Int
    let title: String
    let note: String
    let audience: Audience

    enum Audience {
        case elder   // the robot face display the elder sees
        case staff   // staff/guardian screens reached by turning the iPad and unlocking
    }

    @ViewBuilder
    var view: some View {
        switch id {
        case 1:  IdleScreen()
        case 2:  RecognizingScreen()
        case 3:  GreetingKnownScreen()
        case 4:  FirstMeetingScreen()
        case 5:  AskingNameScreen()
        case 6:  ConfirmEnrollScreen()
        case 7:  ContinuityScreen()
        case 8:  SubtleRecallScreen()
        case 9:  ReminiscenceScreen()
        case 10: GentleAssistScreen()
        case 11: FarewellScreen()
        case 12: StaffAlertScreen()
        case 13: RosterView()
        case 14: MemoryMapView()
        case 15: CognitiveReportView()
        default: WeeklyDigestView()
        }
    }

    var numberLabel: String { String(format: "%02d", id) }
}

enum ScreenCatalog {

    /// Opens a single screen by number. Used by the launch argument (`-screen 15`).
    @ViewBuilder
    static func view(number: Int) -> some View {
        if let spec = all.first(where: { $0.id == number }) {
            spec.view
        } else {
            Text("No screen \(number)")
                .font(.kr(24))
                .foregroundStyle(Theme.gray6B)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.staffPaper)
        }
    }

    static let all: [ScreenSpec] = [
        ScreenSpec(id: 1, title: "Idle",
                   note: "Eyes closed, low power when no one is there. Wakes on sound or motion", audience: .elder),
        ScreenSpec(id: 2, title: "Recognizing",
                   note: "Greets out loud, **recognizes silently**. Never says out loud that it failed to recognize someone — a sensitive thing to say to a person living with memory loss", audience: .elder),
        ScreenSpec(id: 3, title: "Greeting (known)",
                   note: "Saying the name *is* the success feedback. No separate confirmation step", audience: .elder),
        ScreenSpec(id: 4, title: "First meeting",
                   note: "An unenrolled face is a new acquaintance, not an error. Switches to a surprised expression", audience: .elder),
        ScreenSpec(id: 5, title: "Asking name",
                   note: "No keyboard. Voice only. The waveform is what says \"listening\"", audience: .elder),
        ScreenSpec(id: 6, title: "Confirm & enroll",
                   note: "Captured quietly during the conversation with no shutter sound; only the name is confirmed", audience: .elder),
        ScreenSpec(id: 7, title: "Continuity",
                   note: "The session opener always starts from that story from last time", audience: .elder),
        ScreenSpec(id: 8, title: "Subtle recall",
                   note: "The delayed recall probe, 8 minutes after the anchor was planted. Phrased as small talk "
                       + "opening with \"By the way\", and nothing on screen refers to a measurement",
                   audience: .elder),
        ScreenSpec(id: 9, title: "Reminiscence",
                   note: "Stimulates long-term memory while quietly comparing how the same story changes", audience: .elder),
        ScreenSpec(id: 10, title: "Gentle assist",
                   note: "After 3 seconds of silence the robot fills in the answer itself and moves the topic on", audience: .elder),
        ScreenSpec(id: 11, title: "Farewell",
                   note: "Announces the next session's opener on the spot = a sense of being connected", audience: .elder),
        ScreenSpec(id: 12, title: "Staff alert",
                   note: "On signs of confusion, pain, or a fall. The elder sees only a reassuring line", audience: .elder),
        ScreenSpec(id: 13, title: "Roster",
                   note: "Only enrolled faces are recognized automatically. Attention flags show as a card border", audience: .staff),
        ScreenSpec(id: 14, title: "Memory map",
                   note: "Tapping a node opens the original utterances on that topic and how the facts have changed", audience: .staff),
        ScreenSpec(id: 15, title: "Cognitive report",
                   note: "Does not diagnose. Shows change only, and recommends a consultation", audience: .staff),
        ScreenSpec(id: 16, title: "Weekly digest",
                   note: "Puts good news and requests next to the alerts so warnings do not just pile up", audience: .staff)
    ]

    static var elderScreens: [ScreenSpec] { all.filter { $0.audience == .elder } }
    static var staffScreens: [ScreenSpec] { all.filter { $0.audience == .staff } }
}
