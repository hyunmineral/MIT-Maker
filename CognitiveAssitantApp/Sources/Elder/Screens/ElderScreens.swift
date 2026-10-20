import SwiftUI

/// The common skeleton of the 12 screens elders see.
///
/// **Top-aligned, not centred.** The front camera sits at the top centre of the screen,
/// so the eyes' y coordinate determines the gaze error — with the eyes at screen centre (y≈450)
/// the error exceeds 7° and is perceived as "looking past you". Rationale in `Docs/02_design-criteria.md` section 5.
///
/// Lines start at **the same y every time**, regardless of expression. Face height varies by expression,
/// 288–523, so if lines flowed from the face they'd jump up and down at every step.
struct ElderScreen<Face: View, Below: View>: View {
    var backdrop: CSSRadialBackdrop
    /// Eye height. The face block is lowered so the eye centre lands on `Theme.Layout.eyeCenterY`.
    var eyeHeight: CGFloat
    var captionTop: CGFloat = Theme.Layout.captionTop
    /// Spacing between elements below the line.
    var belowSpacing: CGFloat = 28
    @ViewBuilder var face: Face
    @ViewBuilder var below: Below

    var body: some View {
        ZStack(alignment: .top) {
            backdrop
            face
                .padding(.top, Theme.Layout.eyeCenterY - eyeHeight / 2)
            VStack(spacing: belowSpacing) { below }
                .frame(width: Theme.Layout.contentWidth)
                .padding(.top, captionTop)
        }
        .frame(width: DesignSpec.width, height: DesignSpec.height, alignment: .top)
        .clipped()
    }
}

/// One face, with eyes and mouth stacked at the prescribed gap.
private struct FaceBlock: View {
    var style: FaceStyle
    var blinks: Bool = false

    var body: some View {
        VStack(spacing: Theme.Layout.faceStackGap) {
            EyesView(style: style, blinks: blinks)
            if style.mouth.width > 0 {
                FacePartView(part: style.mouth)
            }
        }
    }
}

/// Robot line. **Fixed at 62pt — no exceptions.**
///
/// 42 arcminutes at 70 cm, comfortably tier A (35 arcminutes), holding up to 85 cm.
/// It used to vary by screen from 40 to 62pt, and 48pt at 33 arcminutes fell short of tier A.
private struct Caption: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.kr(Theme.Size.speech, .semibold))
            .foregroundStyle(Theme.faceText)
            .multilineTextAlignment(.center)
            .cssLineHeight(Theme.speechLineHeight, Theme.Size.speech)
            // Without this it gets cut to one line.
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Auxiliary display for staff and bystanders. Tier C size, unreadable at the elder's distance (70 cm).
private struct StaffNote: View {
    var text: String
    var color: Color = Theme.cream(0.4)

    var body: some View {
        Text(text)
            .font(.kr(Theme.Size.staffLabel))
            .foregroundStyle(color)
    }
}

// MARK: - 01 Resting · Idle

struct IdleScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.idle, eyeHeight: 16) {
            EyesView(style: .sleep, blinks: false)
        } below: {
            // A status display, not the robot speaking. A size that doesn't need to be readable.
            Text("Resting")
                .font(.kr(30))
                .letterSpacing(0.3, 30)
                .foregroundStyle(Theme.cream(0.28))
        }
    }
}

// MARK: - 02 Approach detected · face recognition

struct RecognizingScreen: View {
    var body: some View {
        // Changed the line from "Uh… who are you again?" to **"Hello?"**.
        // The robot saying out loud that it didn't recognise someone is especially sensitive
        // for a person living with memory problems. **Recognise inwardly and only greet outwardly** —
        // if recognised, the next screen calls them by name (03); if new, it's glad to meet them (04).
        //
        // The progress bar was removed too. A bar filled to 62% is **a progress indicator**, which principle 1 (don't
        // test) forbids. Blinking eyes are enough to convey 'thinking'.
        ElderScreen(backdrop: Backdrop.standard25, eyeHeight: 110) {
            EyesView(style: .neutral, blinks: true)
        } below: {
            Caption(text: "Hello.\nCome on in.")
        }
    }
}

// MARK: - 03 Greeting — someone known

struct GreetingKnownScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.standard25, eyeHeight: 60) {
            FaceBlock(style: .happy)
        } below: {
            Caption(text: "\(DemoPeople.knownSpoken)!\nYou made it.")
        }
    }
}

// MARK: - 04 First meeting

struct FirstMeetingScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.standard25, eyeHeight: 118) {
            FaceBlock(style: .surprise)
        } below: {
            Caption(text: "Oh — we haven't met.\nNice to meet you!")
        }
    }
}

// MARK: - 05 Asking the name

struct AskingNameScreen: View {
    var body: some View {
        // Removed the "I'm listening · Listening" text. 26pt is 17.7 arcminutes at 70 cm, so
        // elders can't read it anyway. The waveform alone signals it — which was also the original intent.
        ElderScreen(backdrop: Backdrop.standard22, eyeHeight: 110) {
            FaceBlock(style: .neutral)
        } below: {
            Caption(text: "What's your name?")
            ListeningWave(barWidth: 9, barHeight: 44, spacing: 10)
        }
    }
}

// MARK: - 06 Name confirmation · face enrolment

struct ConfirmEnrollScreen: View {
    var body: some View {
        // Removed the "Yes, that's right / No" touch buttons — they violate principle 4.
        // With trembling hands and dry skin capacitive touch often fails, and a failed touch
        // becomes an experience of "I did something wrong". Confirming a name is a conversation, not form entry.
        // The elder answers by voice; in stage 0 the staff panel choices stand in.
        ElderScreen(backdrop: Backdrop.standard22, eyeHeight: 60) {
            FaceBlock(style: .happy)
        } below: {
            Caption(text: "Margaret Walsh —\nis that right?")
            PhotoPlaceholder(text: "Photo", fontSize: 22, band: 12)
                .frame(width: 200, height: 200)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.blue, lineWidth: 5))
        }
    }
}

// MARK: - 07 Everyday conversation — picking up the last conversation

struct ContinuityScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.standard22, eyeHeight: 60) {
            FaceBlock(style: .happy)
        } below: {
            Caption(text: "Last time you told me\nabout Emma's tests.\nHow did she do?")
        }
    }
}

// MARK: - 08 Subtle short-term memory check

struct SubtleRecallScreen: View {
    var body: some View {
        // Removed "8 min since anchor planted · delayed recall probe".
        // Measurement jargon was showing as is on the elder screen — a violation of principle 1.
        // The design explanation moved to the note in `ScreenCatalog`.
        ElderScreen(backdrop: Backdrop.standard22, eyeHeight: 110) {
            FaceBlock(style: .neutral)
        } below: {
            Caption(text: "By the way —\nwhat was lunch?")
        }
    }
}

// MARK: - 09 Recall conversation — memory card

struct ReminiscenceScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.standard20, eyeHeight: 60) {
            FaceBlock(style: .happy)
        } below: {
            Caption(text: "Tell me about\nthe peach orchard\nagain.")
            SessionMemoryCard(
                card: MemoryCard(kind: "Memory card · 1961",
                                 title: "Asheville · peach orchard",
                                 body: "Long-term anchor · mentioned 3 times")
            )
        }
    }
}

// MARK: - 10 When it's hard — gentle recovery

struct GentleAssistScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.warm, eyeHeight: 56) {
            VStack(spacing: Theme.Layout.faceStackGap) {
                HStack(spacing: 140) {
                    downwardEye
                    downwardEye
                }
                Capsule().fill(Theme.cream).frame(width: 150, height: 26)
            }
        } below: {
            Caption(text: "That's all right.\nIt was tomato soup.")
        }
    }

    /// Downward-curved eyes (∪) — an apologetic expression. A shape used only on this screen.
    private var downwardEye: some View {
        FacePartView(part: FacePart(width: 120, height: 56,
                                    radii: .bottom(120), borderBottom: 20))
    }
}

// MARK: - 11 Wrap-up

struct FarewellScreen: View {
    var body: some View {
        // The preview of the next session **moved into the line.** It used to be written at 26pt at the bottom of the screen,
        // 17.7 arcminutes at 70 cm, so elders couldn't read it — the device meant to build connection (principle 2)
        // wasn't getting across. It gets across only if the robot says it.
        ElderScreen(backdrop: Backdrop.standard22, eyeHeight: 60) {
            FaceBlock(style: .happy)
        } below: {
            Caption(text: "I loved the orchard story.\nTell me about your sister\nnext time.")
        }
    }
}

// MARK: - 12 Anomaly detected · call staff

struct StaffAlertScreen: View {
    var body: some View {
        ElderScreen(backdrop: Backdrop.alert, eyeHeight: 118) {
            FaceBlock(style: .surprise)
        } below: {
            Caption(text: "I asked someone to come.\nHang on a second.")
            // A display for staff and bystanders, not the elder. Lowered to tier C —
            // the line above already says what the elder needs to hear.
            StaffNote(text: "Staff notified", color: Theme.red)
        }
    }
}
