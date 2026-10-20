import Foundation
import SwiftData

/// One STT recognition-accuracy measurement sample.
///
/// `Docs/05_implementation-roadmap.md` section 2 — raw data for **the table that must be built before starting stage 1 (STT)**.
/// Elderly English · regional accents · hearing-impaired pronunciation all overlap here, so
/// neither the engine nor the schedule can be decided before measuring recognition accuracy.
///
/// Recording files stay in `Application Support/SpeechSamples`. **Not `Caches`** —
/// if iOS cleared it at will, the originals for later comparison with cloud engines would be gone.
@Model
final class SpeechSample {
    var recordedAt: Date
    /// Recording file name. The directory is `SpeechSampleStore.directory`.
    var fileName: String
    /// On-device recognition result.
    var recognized: String
    /// The correct transcription a person listened to and wrote down. If empty, it hasn't been scored yet.
    var reference: String
    /// Speaker note — like "Dorothy · 85 · Asheville". Written with minimal personal identification.
    var note: String
    /// Time taken for recognition (seconds).
    var duration: TimeInterval

    init(fileName: String, recognized: String = "", reference: String = "",
         note: String = "", duration: TimeInterval = 0, recordedAt: Date = .now) {
        self.fileName = fileName
        self.recognized = recognized
        self.reference = reference
        self.note = note
        self.duration = duration
        self.recordedAt = recordedAt
    }

    var isScored: Bool { !reference.isEmpty && !recognized.isEmpty }

    /// Word-level accuracy (0…1).
    ///
    /// Uses edit distance over words split on whitespace, without morphological analysis. In Korean, space-separated words
    /// are close to units of meaning, so this is **enough to rank engines against each other.**
    /// It isn't trying to measure absolute accuracy to research-paper standard.
    var wordAccuracy: Double? {
        guard isScored else { return nil }
        let ref = SpeechSample.words(reference)
        let hyp = SpeechSample.words(recognized)
        guard !ref.isEmpty else { return nil }
        let distance = SpeechSample.editDistance(ref, hyp)
        return max(0, 1 - Double(distance) / Double(ref.count))
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Levenshtein distance over word arrays.
    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1,       // deletion
                                 current[j - 1] + 1,    // insertion
                                 previous[j - 1] + cost) // substitution
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Where recording files live.
enum SpeechSampleStore {
    /// **`Application Support`, not `Caches`.** These are the originals for later comparison
    /// with cloud engines, so iOS must not clear them at will.
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("SpeechSamples", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
