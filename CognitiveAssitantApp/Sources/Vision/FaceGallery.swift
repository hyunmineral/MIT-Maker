import CoreGraphics
import Foundation
import SwiftData
import Vision

/// The faces enrolled in the store. **The side used when the session asks "who is it".**
///
/// `FaceMatch` is for the measurement screen and lives only in memory. This one reads from
/// `Elder.faceEmbeddings`. Both use `FacePrinting.Threshold` for their thresholds.
struct FaceGallery {

    struct Entry {
        var elderID: PersistentIdentifier
        var name: String
        var prints: [VNFeaturePrintObservation]
    }

    enum Outcome {
        /// Narrowed down to one person with enough confidence.
        case recognized(elderID: PersistentIdentifier, name: String, distance: Float)
        /// Doesn't resemble anyone enrolled. **Treat as someone met for the first time.**
        case unknown(best: Float?)
        /// First and second place aren't far enough apart. **Don't call a name** — calling someone wrongly
        /// is worse than not recognising them (`Docs/03_product-design.md` section 3).
        case ambiguous(best: Float, second: Float)
        /// No face found in the image.
        case noFace

        /// One line to leave in the staff log.
        var logText: String {
            switch self {
            case let .recognized(_, name, d):
                String(format: "%@ · distance %.3f", name, d)
            case let .unknown(best):
                best.map { String(format: "No enrolled face is close · best %.3f", $0) }
                    ?? "Nobody is enrolled yet"
            case let .ambiguous(best, second):
                String(format: "Too close to call · %.3f vs %.3f — not guessing", best, second)
            case .noFace:
                "A face was detected but no print could be made"
            }
        }
    }

    var entries: [Entry] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Read from the store. People not approved (`isApproved == false`) aren't targets for automatic recognition.
    init(elders: [Elder]) {
        entries = elders.compactMap { elder in
            guard elder.isApproved else { return nil }
            let prints = elder.faceEmbeddings.compactMap(FacePrinting.decode)
            guard !prints.isEmpty else { return nil }
            return Entry(elderID: elder.persistentModelID, name: elder.name, prints: prints)
        }
    }

    func match(image: CGImage) -> Outcome {
        guard let probe = FacePrinting.print(from: image) else { return .noFace }
        guard !entries.isEmpty else { return .unknown(best: nil) }

        let scored = entries.compactMap { entry -> (Entry, Float)? in
            let best = entry.prints.compactMap { FacePrinting.distance(probe, $0) }.min()
            return best.map { (entry, $0) }
        }
        .sorted { $0.1 < $1.1 }

        guard let (top, best) = scored.first else { return .unknown(best: nil) }

        if let second = scored.dropFirst().first?.1,
           best + FacePrinting.Threshold.margin > second {
            return .ambiguous(best: best, second: second)
        }
        guard best < FacePrinting.Threshold.unknown else { return .unknown(best: best) }
        return .recognized(elderID: top.elderID, name: top.name, distance: best)
    }
}
