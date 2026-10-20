import SwiftData
import SwiftUI

/// **Staff decide what the robot calls this person.**
///
/// `FormOfAddress` had the rules exactly right, but **nobody was feeding it values.**
/// Enrolling during a session only called `addElder(name:)`, leaving honorific and surname empty, so
/// the robot called her by the full name `Margaret Walsh` instead of `Mrs. Walsh`
/// (found 2026-09-10). This screen fills that gap.
///
/// ## Why not ask during the session
///
/// Enrolment happens in front of the elder. Having staff ask "Are you married?" right there
/// to choose between `Mrs.` and `Ms.` means the elder hears that conversation. The form of address should be decided
/// **later, quietly** (`Docs/03_product-design.md` section 3).
struct ElderDetailView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let elder: Elder

    @State private var honorific: Honorific?
    @State private var familyName: String
    @State private var invitedFirstName: Bool
    @State private var birthYear: String
    @State private var hometown: String
    @State private var isApproved: Bool

    init(elder: Elder) {
        self.elder = elder
        _honorific = State(initialValue: elder.honorific)
        _familyName = State(initialValue: elder.familyName
            ?? FormOfAddress.derivedFamilyName(from: elder.name) ?? "")
        _invitedFirstName = State(initialValue: elder.invitedFirstName)
        _birthYear = State(initialValue: elder.birthYear.map(String.init) ?? "")
        _hometown = State(initialValue: elder.hometown ?? "")
        _isApproved = State(initialValue: elder.isApproved)
    }

    /// The name the robot would call with the current settings. **Shown before saving.**
    private var preview: String {
        FormOfAddress.spoken(
            fullName: elder.name,
            honorific: honorific,
            familyName: familyName.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : familyName,
            invitedFirstName: invitedFirstName
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                addressSection
                factsSection
                approvalSection
            }
            .navigationTitle(elder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private var previewSection: some View {
        Section {
            HStack {
                Image(systemName: "quote.bubble")
                    .foregroundStyle(Theme.blue)
                Text("“\(preview)”")
                    .font(.headline)
            }
        } header: {
            Text("The robot will say")
        } footer: {
            if honorific == nil && !invitedFirstName {
                Text("No title is set, so the robot falls back to the full recorded name. "
                     + "That is safe but formal — set a title, or record that they asked "
                     + "for their first name.")
                .foregroundStyle(Theme.amber)
            }
        }
    }

    private var addressSection: some View {
        Section {
            Picker("Title", selection: $honorific) {
                Text("None").tag(Honorific?.none)
                ForEach(Honorific.allCases) { item in
                    Text(item.title).tag(Honorific?.some(item))
                }
            }
            if let honorific {
                Text(honorific.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.gray6B)
            }
            TextField("Family name", text: $familyName)
                .textInputAutocapitalization(.words)
            Toggle("They asked me to use their first name", isOn: $invitedFirstName)
        } header: {
            Text("How to address them")
        } footer: {
            Text("**Mrs. only when we actually know** they are married or widowed; "
                 + "otherwise Ms. Using a first name is a fact we record, not a default — "
                 + "in this generation it is an invitation, and skipping it reads as rude.")
        }
    }

    private var factsSection: some View {
        Section {
            TextField("Birth year", text: $birthYear)
                .keyboardType(.numberPad)
            TextField("Where they grew up", text: $hometown)
        } header: {
            Text("On file")
        } footer: {
            Text("The birth year only shows the age on the staff screen. "
                 + "The robot never asks for it — that is an orientation question, "
                 + "and this app does not test.")
        }
    }

    private var approvalSection: some View {
        Section {
            Toggle("Recognize automatically", isOn: $isApproved)
        } footer: {
            Text("Off means the camera will not greet them by name even if their face "
                 + "is on file. Turn it off while something looks wrong.")
        }
    }

    private func save() {
        elder.honorific = honorific
        let family = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        elder.familyName = family.isEmpty ? nil : family
        elder.invitedFirstName = invitedFirstName
        elder.birthYear = Int(birthYear.trimmingCharacters(in: .whitespaces))
        let town = hometown.trimmingCharacters(in: .whitespacesAndNewlines)
        elder.hometown = town.isEmpty ? nil : town
        elder.isApproved = isApproved
        try? context.save()
        dismiss()
    }
}
