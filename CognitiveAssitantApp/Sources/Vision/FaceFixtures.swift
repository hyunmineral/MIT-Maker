import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// 3 synthetic elders × (frontal · side · lighting). Fixtures for checking Feature Print distances without a camera.
///
/// Not real people. Generated portraits, present only in `Resources/FaceFixtures/`.
/// Doesn't replace the 70 cm Air 5 measurement — it's for checking that the algorithm and verdict logic run.
enum FaceFixtures {

    struct Shot: Identifiable {
        var person: String
        var variant: String
        var file: String
        /// Frontal and side are enrolled; lighting is the held-out probe.
        var enroll: Bool
        var id: String { file }
    }

    static let shots: [Shot] = [
        Shot(person: DemoPeople.stranger, variant: "front", file: "margaret-front", enroll: true),
        Shot(person: DemoPeople.stranger, variant: "side",  file: "margaret-turn",  enroll: true),
        Shot(person: DemoPeople.stranger, variant: "light", file: "margaret-dim",   enroll: false),
        Shot(person: DemoPeople.known,    variant: "front", file: "dorothy-front",  enroll: true),
        Shot(person: DemoPeople.known,    variant: "side",  file: "dorothy-turn",   enroll: true),
        Shot(person: DemoPeople.known,    variant: "light", file: "dorothy-dim",    enroll: false),
        Shot(person: "Robert Hayes",      variant: "front", file: "robert-front",   enroll: true),
        Shot(person: "Robert Hayes",      variant: "side",  file: "robert-turn",    enroll: true),
        Shot(person: "Robert Hayes",      variant: "light", file: "robert-dim",     enroll: false),
    ]

    static func cgImage(_ file: String) -> CGImage? {
        let url = Bundle.main.url(forResource: file, withExtension: "jpg", subdirectory: "FaceFixtures")
            ?? Bundle.main.url(forResource: file, withExtension: "jpg")
        if let url,
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return image
        }
        return UIImage(named: file)?.cgImage
    }
}
