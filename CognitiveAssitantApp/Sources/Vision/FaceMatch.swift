import CoreGraphics
import Foundation
import Observation
import Vision

/// Stage-2 measurement — **can numbers tell who it is.**
///
/// Runs Apple's `VNGenerateImageFeaturePrintRequest` on the detected face crop.
/// Uses only Vision, no extra model. If same-person distances are smaller than different-person ones,
/// this can be attached to the session; if they overlap, move to a face-specific embedding like buffalo_sc.
@Observable
final class FaceMatch {

    struct Person: Identifiable {
        let id = UUID()
        var label: String
        var samples: Int
        fileprivate var prints: [VNFeaturePrintObservation]
    }

    struct Score: Identifiable {
        var id: UUID { personID }
        var personID: UUID
        var label: String
        var distance: Float
    }

    private(set) var people: [Person] = []
    private(set) var lastScores: [Score] = []
    private(set) var lastError: String?

    func enroll(label: String, image: CGImage) {
        lastError = nil
        lastScores = []
        guard let print = FacePrinting.print(from: image) else {
            lastError = "No face found. Please look straight at the camera."
            return
        }
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let i = people.firstIndex(where: { $0.label == name }) {
            people[i].prints.append(print)
            people[i].samples += 1
        } else {
            people.append(Person(label: name, samples: 1, prints: [print]))
        }
    }

    func fail(_ message: String) {
        lastError = message
        lastScores = []
    }

    func compare(image: CGImage) {
        lastError = nil
        lastScores = []
        guard let probe = FacePrinting.print(from: image) else {
            lastError = "No face found. Please look straight at the camera."
            return
        }
        guard !people.isEmpty else {
            lastError = "Enroll a face first."
            return
        }

        lastScores = people.compactMap { person in
            let distances = person.prints.compactMap {
                FacePrinting.distance(probe, $0)
            }
            guard let best = distances.min() else { return nil }
            return Score(personID: person.id, label: person.label, distance: best)
        }
        .sorted { $0.distance < $1.distance }
    }

    func clear() {
        people = []
        lastScores = []
        lastError = nil
    }

    struct PairDistance: Identifiable {
        let id = UUID()
        var labelA: String
        var labelB: String
        var samePerson: Bool
        var distance: Float
    }

    /// Every pair among enrolled samples. Used for the synthetic test summary.
    func pairDistances() -> [PairDistance] {
        var rows: [PairDistance] = []
        for i in 0..<people.count {
            let a = people[i]
            for x in 0..<a.prints.count {
                for y in (x + 1)..<a.prints.count {
                    guard let d = FacePrinting.distance(a.prints[x], a.prints[y]) else { continue }
                    rows.append(PairDistance(labelA: a.label, labelB: a.label,
                                             samePerson: true, distance: d))
                }
            }
            for j in (i + 1)..<people.count {
                let b = people[j]
                for pa in a.prints {
                    for pb in b.prints {
                        guard let d = FacePrinting.distance(pa, pb) else { continue }
                        rows.append(PairDistance(labelA: a.label, labelB: b.label,
                                                 samePerson: false, distance: d))
                    }
                }
            }
        }
        return rows.sorted { $0.distance < $1.distance }
    }

    /// Thresholds are set in only one place, `FacePrinting.Threshold` —
    /// **the measurement screen and the real session must use the same criteria** for this measurement to mean anything.
    var verdict: String? {
        guard lastScores.count >= 1 else { return nil }
        let best = lastScores[0]
        let second = lastScores.dropFirst().first
        if let second, best.distance + FacePrinting.Threshold.margin > second.distance {
            return "Too close to call — not guessing"
        }
        if best.distance < FacePrinting.Threshold.unknown {
            return "Closest: \(best.label)"
        }
        return "No enrolled face is close (unknown)"
    }
}
