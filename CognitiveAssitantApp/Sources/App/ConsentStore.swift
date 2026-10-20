import Foundation
import Observation

/// Which consents have been obtained.
///
/// The consents required by `Docs/03_product-design.md` section 9 **split into three that don't substitute for one another.**
/// Lumping them together as "consent was given" leads to obtaining only conversation-record consent and
/// then sending voice to an overseas server. So each item is recorded separately.
///
/// **This is not the legal consent itself but a record of that fact.** The actual consent forms are kept
/// on paper by the centre. The app only opens and closes features according to that state.
enum Consent {

    enum Kind: String, CaseIterable, Identifiable {
        /// Self/guardian consent — to record conversation content and cognitive metrics.
        case personal
        /// Voice-recording consent — needed to measure STT recognition accuracy.
        case recording
        /// Biometric (face) consent — face detection and identity matching. The Vision stage.
        case biometric
        /// Overseas personal-data transfer consent — a condition for using cloud TTS and LLMs.
        case overseas

        var id: String { rawValue }

        var label: String {
            switch self {
            case .personal:  "Participant & family consent"
            case .recording: "Voice recording consent"
            case .biometric: "Biometric (face) consent"
            case .overseas:  "International transfer consent"
            }
        }

        var detail: String {
            switch self {
            case .personal:
                "Records conversation content and cognitive measures on this device. Without it, no session can be recorded."
            case .recording:
                "Records what the elder says to measure speech recognition accuracy. "
                + "Without it we cannot measure accuracy on older, accented speech, and stage 1 cannot be scheduled."
            case .biometric:
                "Analyzes faces on this device only, to tell who is here. No photo goes to the cloud. "
                + "Without it, the face detection and matching probes cannot run."
            case .overseas:
                "Spoken lines leave for OpenAI servers abroad. Those lines carry the elder's name "
                + "and personal history. Without it, only Apple on-device voices are available."
            }
        }

        fileprivate var storageKey: String { "Consent.\(rawValue)" }
    }

    static func isGranted(_ kind: Kind) -> Bool {
        UserDefaults.standard.bool(forKey: kind.storageKey)
    }

    static func set(_ kind: Kind, _ granted: Bool) {
        UserDefaults.standard.set(granted, forKey: kind.storageKey)
    }
}

@Observable
final class ConsentStore {
    private(set) var granted: Set<Consent.Kind> = []

    init() { reload() }

    func reload() {
        granted = Set(Consent.Kind.allCases.filter(Consent.isGranted))
    }

    func isGranted(_ kind: Consent.Kind) -> Bool { granted.contains(kind) }

    func set(_ kind: Consent.Kind, _ value: Bool) {
        Consent.set(kind, value)
        reload()
    }
}
