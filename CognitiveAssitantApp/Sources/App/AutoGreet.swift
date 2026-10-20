import Foundation

/// Whether the resting screen **waits for a person using the camera.**
///
/// When off, staff start as before by pressing `Someone walks up`. There are two reasons
/// for having an on/off switch.
///
/// 1. **Staff in the pilot must be able to take back control.** If it misbehaves they should
///    switch it off on the spot and proceed by hand, not have to close the session.
/// 2. **An always-on camera is not yet an agreed item** (`Docs/03_product-design.md` section 9).
///    It is something to settle with the centre separately from biometric consent, so the default is off.
///
/// Without biometric consent, `PresenceWatcher` never turns on regardless of this value.
enum AutoGreet {
    private static let key = "AutoGreet.enabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
