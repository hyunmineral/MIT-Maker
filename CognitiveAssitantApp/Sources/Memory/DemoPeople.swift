import Foundation

/// American people for demos. They don't exist.
///
/// The script, seed and synthetic face fixtures share these names. In a pilot deployment
/// `SeedData` isn't loaded, so these values remain only in the demo.
enum DemoPeople {
    static let known = "Dorothy Miller"
    static let stranger = "Margaret Walsh"
    static let rosterExtra = ["Robert Hayes", "Betty Clark", "Frank Sullivan"]

    // MARK: - Form of address (`FormOfAddress`)

    /// Widowed — there's a `husband` record, so there's grounds to use `Mrs.`.
    static let knownHonorific: Honorific = .mrs
    static let knownFamilyName = "Miller"
    /// Over 8 months and 74 visits **she asked to be called by her first name.** So the robot calls her "Dorothy".
    static let knownInvitedFirstName = true

    /// Someone met for the first time today. Marital status is unknown, so `Ms.`, and the first name isn't used until permitted.
    static let strangerHonorific: Honorific = .ms
    static let strangerFamilyName = "Walsh"

    /// The name the robot actually calls. The rules live only in `FormOfAddress`.
    static var knownSpoken: String {
        FormOfAddress.spoken(fullName: known, honorific: knownHonorific,
                             familyName: knownFamilyName,
                             invitedFirstName: knownInvitedFirstName)
    }
    static var strangerSpoken: String {
        FormOfAddress.spoken(fullName: stranger, honorific: strangerHonorific,
                             familyName: strangerFamilyName, invitedFirstName: false)
    }

    static let knownBirthYear = 1941
    static let knownHometown = "Asheville, North Carolina"
    static let strangerHometown = "Des Moines, Iowa"

    static let granddaughter = "Granddaughter Emma"
    static let son = "Son Michael"
    static let husband = "Late husband"
    static let orchard = "the peach orchard"
    static let sister = "your sister"
    static let lunch = "tomato soup"
}
