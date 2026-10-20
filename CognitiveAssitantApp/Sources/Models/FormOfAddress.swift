import Foundation

/// **What the robot calls** the elder.
///
/// `Docs/03_product-design.md` section 3. English has no word equivalent to the Korean "eoreusin" (respected elder).
/// The traditional first form of address for an American born in the 1940s is **`Mr.` / `Mrs.` / `Ms.` + surname**,
/// and **the first name is used only after the person allows it**. In American culture that permission itself
/// signals that the relationship has become closer, so the app skipping it on its own would be rude.
///
/// So calling someone by first name is **a recorded fact, not a default**
/// (`Elder.invitedFirstName`). It changes only when staff record "she asked to be called Dorothy".
enum Honorific: String, CaseIterable, Identifiable {
    case mr
    case mrs
    case ms

    var id: String { rawValue }

    /// The form that goes out as is to the screen and TTS. American style uses a period (British style doesn't).
    var title: String {
        switch self {
        case .mr:  "Mr."
        case .mrs: "Mrs."
        case .ms:  "Ms."
        }
    }

    /// Description of the option on the staff screen.
    var detail: String {
        switch self {
        case .mr:  "Any adult man"
        case .mrs: "Married or widowed — only when we actually know"
        case .ms:  "Default for a woman when we do not know"
        }
    }
}

/// The rules for building the form of address, gathered in one place. The script, roster and reports all use this.
///
/// **No guessing.** If the surname is unknown, call the recorded name as is — a wrong form of address is
/// worse than none. `Mrs.` is used **only when** marriage or widowhood is known;
/// otherwise it stays `Ms.`.
enum FormOfAddress {

    /// The name the robot calls out loud.
    ///
    /// - If `invited` is true, the first name (the person asked to be called that)
    /// - Otherwise the `Mrs. Miller` form
    /// - If the surname or honorific is unknown, the recorded full name as is
    static func spoken(fullName: String,
                       honorific: Honorific?,
                       familyName: String?,
                       invitedFirstName: Bool) -> String {
        if invitedFirstName {
            return givenName(from: fullName)
        }
        if let honorific, let family = familyName ?? derivedFamilyName(from: fullName) {
            return "\(honorific.title) \(family)"
        }
        return fullName
    }

    /// Just the first name from the full name. Returns it unchanged if there's no space.
    static func givenName(from fullName: String) -> String {
        fullName.split(separator: " ").first.map(String.init) ?? fullName
    }

    /// Infers the surname from the full name. **Only a fallback** —
    /// two-word surnames like `Van Dyke` · `de la Cruz` can't be caught this way.
    /// Once there's an enrolment screen, staff should enter `Elder.familyName` directly.
    static func derivedFamilyName(from fullName: String) -> String? {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[parts.count - 1])
    }
}
