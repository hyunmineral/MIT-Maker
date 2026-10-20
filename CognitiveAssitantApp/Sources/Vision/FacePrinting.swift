import CoreGraphics
import Foundation
import Vision

/// Shared code for creating and comparing face prints (Feature Print).
///
/// **The measurement screen (`FaceMatch`) and the real session (`FaceGallery`) must use the same code.**
/// If a threshold that passed in measurement means something different in the product, the measurement itself is meaningless.
/// So print generation, thresholds and the storage format live here in one place only.
enum FacePrinting {

    /// Based on iOS 17 Feature Print Revision 2. **Smaller means the same person.**
    ///
    /// Same person below ~0.3 and different people above ~0.8 are common. **The two values below are provisional and
    /// must be settled by on-device measurement (`Docs/2026-08-30_face-detection-measurement.md`).**
    enum Threshold {
        /// Farther than this, it's considered not to resemble anyone enrolled.
        static let unknown: Float = 0.55
        /// If first and second place aren't at least this far apart, **no name is called.**
        /// Calling someone wrongly is worse than not recognising them (`Docs/03_product-design.md` section 3).
        static let margin: Float = 0.15
    }

    /// Crops the largest face in the image and makes a print. `nil` if there's no face.
    static func print(from image: CGImage) -> VNFeaturePrintObservation? {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let detect = VNDetectFaceRectanglesRequest()
        do { try handler.perform([detect]) } catch { return nil }
        guard let face = detect.results?.max(by: { $0.boundingBox.area < $1.boundingBox.area })
        else { return nil }
        guard let crop = image.croppingFace(normalizedBox: face.boundingBox) else { return nil }

        let printHandler = VNImageRequestHandler(cgImage: crop, options: [:])
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        do {
            try printHandler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }

    static func distance(_ a: VNFeaturePrintObservation,
                         _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do { try a.computeDistance(&d, to: b) } catch { return nil }
        return d
    }

    // MARK: - Storage format

    /// Builds the form that goes into `Elder.faceEmbeddings`.
    ///
    /// **It never leaves the device** (`Docs/03_product-design.md` section 9). SwiftData is
    /// a local store, and CloudKit isn't enabled on the container.
    static func encode(_ print: VNFeaturePrintObservation) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: print, requiringSecureCoding: true)
    }

    static func decode(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self,
                                                from: data)
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}

extension CGImage {
    /// Converts a Vision box (origin bottom left, 0…1) to pixels and crops just the face. With a little extra margin.
    func croppingFace(normalizedBox box: CGRect) -> CGImage? {
        let w = CGFloat(width)
        let h = CGFloat(height)
        var pixel = CGRect(
            x: box.minX * w,
            y: (1 - box.maxY) * h,
            width: box.width * w,
            height: box.height * h
        )
        let pad = pixel.width * 0.25
        pixel = pixel.insetBy(dx: -pad, dy: -pad)
        pixel = pixel.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard pixel.width > 8, pixel.height > 8 else { return nil }
        return cropping(to: CGRect(
            x: pixel.origin.x.rounded(.down),
            y: pixel.origin.y.rounded(.down),
            width: pixel.width.rounded(.up),
            height: pixel.height.rounded(.up)
        ))
    }
}
