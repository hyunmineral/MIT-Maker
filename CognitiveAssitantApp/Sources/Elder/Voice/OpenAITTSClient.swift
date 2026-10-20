import Foundation

/// One OpenAI speech-synthesis call.
///
/// `POST https://api.openai.com/v1/audio/speech` → mp3 bytes.
/// A single line never exceeds 4096 characters, so there's no splitting logic.
struct OpenAITTSClient {

    var apiKey: String
    var model: String
    var voice: String
    var instructions: String
    var speed: Double

    enum Failure: LocalizedError {
        case api(status: Int, message: String)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .api(let status, let message):
                // If the body is long, only the start. Shows as one line in the top bar.
                "OpenAI \(status) · \(message.prefix(120))"
            case .emptyAudio:
                "The OpenAI response contained no audio"
            }
        }
    }

    func synthesize(_ text: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body: [String: Any] = [
            "model": model,
            "voice": voice,
            "input": text,
            "response_format": "mp3",
            "speed": speed
        ]
        // `instructions` is ignored by tts-1 · tts-1-hd (stated in the API docs).
        if Self.supportsInstructions(model), !instructions.isEmpty {
            body["instructions"] = instructions
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Failure.api(status: status,
                              message: String(data: data, encoding: .utf8) ?? "no body")
        }
        guard !data.isEmpty else { throw Failure.emptyAudio }
        return data
    }

    static func supportsInstructions(_ model: String) -> Bool {
        !model.hasPrefix("tts-1")
    }

    // MARK: - Choices

    /// Selectable voices. OpenAI recommends `marin` · `cedar` when quality comes first.
    static let voices = [
        "marin", "cedar", "coral", "alloy", "ash", "ballad", "echo",
        "fable", "nova", "onyx", "sage", "shimmer", "verse"
    ]

    static let models = ["gpt-4o-mini-tts", "tts-1-hd", "tts-1"]
}
