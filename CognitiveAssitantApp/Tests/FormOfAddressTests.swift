import Testing
@testable import RobotForElders

/// A wrong form of address is worse than none (`Docs/03_product-design.md` section 3).
@Suite("FormOfAddress — no guessing")
struct FormOfAddressTests {

    @Test("With an honorific and surname, that's what is used")
    func titleAndFamilyName() {
        let spoken = FormOfAddress.spoken(fullName: "Dorothy Miller", honorific: .mrs,
                                          familyName: "Miller", invitedFirstName: false)
        #expect(spoken == "Mrs. Miller")
    }

    @Test("If the surname wasn't recorded, it's taken from the full name")
    func derivesFamilyName() {
        let spoken = FormOfAddress.spoken(fullName: "Robert Hayes", honorific: .mr,
                                          familyName: nil, invitedFirstName: false)
        #expect(spoken == "Mr. Hayes")
    }

    @Test("Without an honorific, the full name is used as is — nothing invented")
    func noHonorificKeepsFullName() {
        let spoken = FormOfAddress.spoken(fullName: "Margaret Walsh", honorific: nil,
                                          familyName: "Walsh", invitedFirstName: false)
        #expect(spoken == "Margaret Walsh")
    }

    @Test("The first name is used only when she asked to be called by it")
    func firstNameOnlyWhenInvited() {
        let formal = FormOfAddress.spoken(fullName: "Dorothy Miller", honorific: .mrs,
                                          familyName: "Miller", invitedFirstName: false)
        let invited = FormOfAddress.spoken(fullName: "Dorothy Miller", honorific: .mrs,
                                           familyName: "Miller", invitedFirstName: true)
        #expect(formal == "Mrs. Miller")
        #expect(invited == "Dorothy")
    }

    @Test("A one-word name yields no surname")
    func singleWordName() {
        #expect(FormOfAddress.derivedFamilyName(from: "Betty") == nil)
        let spoken = FormOfAddress.spoken(fullName: "Betty", honorific: .ms,
                                          familyName: nil, invitedFirstName: false)
        #expect(spoken == "Betty")
    }

    @Test("Two-word surnames can't be caught by the fallback — staff must enter them")
    func compoundFamilyNameNeedsStaff() {
        // The fallback only looks at the last word. Leave it with this limitation known, and let it be fixed on screen.
        #expect(FormOfAddress.derivedFamilyName(from: "Maria de la Cruz") == "Cruz")
        let recorded = FormOfAddress.spoken(fullName: "Maria de la Cruz", honorific: .ms,
                                            familyName: "de la Cruz", invitedFirstName: false)
        #expect(recorded == "Ms. de la Cruz")
    }
}
