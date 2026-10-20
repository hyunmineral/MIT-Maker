import AVFoundation
import Speech

/// Requests iOS permissions **at the moment a consent is switched on**.
///
/// ## Why not at app launch
///
/// Asking for camera, microphone and speech recognition back to back right after launch pops up three system dialogs.
/// This device is **a kiosk placed in front of elders**. An elder must never meet those screens.
///
/// There is a more important reason. In this app **the centre's consent form comes first and features come after**
/// (`Docs/03_product-design.md` section 9). Requesting OS permissions before the consent is recorded reverses
/// that order. So the relevant permission is requested **at the very moment staff switch the consent on** —
/// it's inside staff settings, so no dialog appears on the elder screen, and the order is preserved.
///
/// ## Why it's needed
///
/// iOS permission prompts appear only when the app **asks directly**. If the asking code sits deep inside a feature,
/// then when an earlier condition blocks it, **the OS is never even asked** and nothing quietly happens.
/// From outside, "permission denied", "never asked" and "broken" all look the same.
enum SystemPermissions {

    /// Requests the OS permissions needed by the features this consent unlocks. Does nothing if already granted.
    static func request(for kind: Consent.Kind) async {
        switch kind {
        case .recording:
            _ = await speechRecognition()
            _ = await microphone()
        case .biometric:
            _ = await camera()
        case .personal, .overseas:
            // An item that has no OS permission attached.
            break
        }
    }

    @discardableResult
    static func camera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    @discardableResult
    static func microphone() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    @discardableResult
    static func speechRecognition() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }
}
