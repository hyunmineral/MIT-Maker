import SwiftUI

/// Screen for entering the OpenAI API key. A staff-only window, so it doesn't follow the elder-screen rules (large text).
///
/// The key is stored only in the Keychain via `APIKeyStore`. It is never shown on screen again.
struct APIKeySheet: View {
    /// After saving or deleting, the parent re-reads the state.
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typedKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $typedKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    if let masked = APIKeyStore.maskedKey {
                        Text("Stored key: \(masked)")
                    } else {
                        Text("No key saved yet.")
                    }
                }

                Section("Before you use this") {
                    Label("Spoken lines are sent to OpenAI. Those lines carry the elder's name and personal history.",
                          systemImage: "exclamationmark.triangle")
                    Label("A key shipped inside a client app can always be extracted. For real deployment, keep the key on a server and have the app call that server.",
                          systemImage: "lock.open")
                    Label("Each line is cached on the device once generated and never re-fetched. Tap \"Pre-generate all\" and the session needs no network at all.",
                          systemImage: "square.and.arrow.down")
                }
                .font(.footnote)

                if APIKeyStore.hasKey {
                    Section {
                        Button("Delete stored key", role: .destructive) {
                            APIKeyStore.clear()
                            typedKey = ""
                            onChange()
                        }
                    }
                }
            }
            .navigationTitle("Voice · OpenAI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        APIKeyStore.save(typedKey)
                        typedKey = ""
                        onChange()
                        dismiss()
                    }
                    .disabled(typedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
