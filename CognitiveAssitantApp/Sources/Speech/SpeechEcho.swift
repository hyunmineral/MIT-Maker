import Foundation

/// **Stops the robot from transcribing its own voice as the elder's speech.**
///
/// The device speaks through the speaker and listens with the same microphone, so this really happened (2026-09-01).
/// `"What did you have for lunch today?"` was saved verbatim as the elder's answer,
/// and junk like `Fact "She"` was produced from it.
///
/// Echo cancellation (`AVAudioSession`'s `.voiceChat`) is the first layer and this is the second.
/// One isn't enough — elders sometimes read the question back word for word.
///
/// **It sits outside `SessionViewModel` so it can be tested.** As a private function inside the view model,
/// this verdict couldn't be checked without spinning up a device and a session.
enum SpeechEcho {

    /// Below two words it isn't checked. It can't be told apart from normal short answers like `"yes"`.
    static let minimumWords = 2

    /// Whether what was heard is the robot's line.
    ///
    /// The verdict is based only on **whether everything heard is contained in the line**. Blocking partial matches too
    /// would discard normal speech that echoes the question while answering, like `"What did I have? Soup."`.
    static func isEcho(heard: String, caption: String) -> Bool {
        let said = flatten(heard)
        guard said.split(separator: " ").count >= minimumWords else { return false }
        return flatten(caption).contains(said)
    }

    /// Strips case, punctuation and line breaks, leaving only the words.
    static func flatten(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
