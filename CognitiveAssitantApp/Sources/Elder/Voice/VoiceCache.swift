import Foundation
import CryptoKit

/// Stores generated audio on the device.
///
/// The stage-0 script is fixed, so there's no reason to generate the same sentence twice. Once fetched, it means
/// **0 s latency · no extra billing · works even when the network drops**.
/// Press 'Pre-generate all' before the pilot starts and no network is used for the whole session.
///
/// Kept in `Application Support`, not `Caches` — iOS clears `Caches` at will.
/// If the cache vanished mid-session in front of an elder, it would show up directly as latency.
enum VoiceCache {

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Voice", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Audio is a regenerable derivative. Keep it out of backups.
        var url = dir
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return dir
    }()

    /// If any of sentence, model, voice, instructions or rate differs, it's a different file.
    /// When comparing voices, the previous voice must not play back.
    static func signature(text: String,
                          model: String,
                          voice: String,
                          instructions: String,
                          speed: Double) -> String {
        let seed = "\(model)|\(voice)|\(instructions)|\(String(format: "%.2f", speed))|\(text)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func url(for signature: String) -> URL {
        directory.appendingPathComponent("\(signature).mp3")
    }

    static func has(_ signature: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: signature).path)
    }

    @discardableResult
    static func store(_ data: Data, for signature: String) throws -> URL {
        let target = url(for: signature)
        try data.write(to: target, options: .atomic)
        return target
    }

    static func clear() {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    static var fileCount: Int {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "mp3" }.count
    }
}
