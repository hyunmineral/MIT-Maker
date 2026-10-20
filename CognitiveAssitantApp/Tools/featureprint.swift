#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Same path as the app's `FaceMatch`: face crop → Feature Print revision 2 → distance.
/// Prints a same-person / different-person table for the synthetic-person JPEGs.
///
///   swift Tools/featureprint.swift Resources/FaceFixtures

struct Sample {
    var person: String
    var variant: String
    var file: String
    var print: VNFeaturePrintObservation
}

func loadCGImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func cropFace(_ image: CGImage, box: CGRect) -> CGImage? {
    let w = CGFloat(image.width)
    let h = CGFloat(image.height)
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
    return image.cropping(to: CGRect(
        x: pixel.origin.x.rounded(.down),
        y: pixel.origin.y.rounded(.down),
        width: pixel.width.rounded(.up),
        height: pixel.height.rounded(.up)
    ))
}

func facePrint(from image: CGImage) -> VNFeaturePrintObservation? {
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let detect = VNDetectFaceRectanglesRequest()
    do { try handler.perform([detect]) } catch { return nil }
    guard let face = detect.results?.max(by: {
        $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }) else { return nil }
    guard let crop = cropFace(image, box: face.boundingBox) else { return nil }

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

func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
    var d: Float = 0
    do {
        try a.computeDistance(&d, to: b)
        return d
    } catch {
        return nil
    }
}

func parseName(_ file: String) -> (String, String)? {
    // dorothy-front.jpg → (Dorothy Miller, front)
    let stem = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
    let parts = stem.split(separator: "-", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { return nil }
    let person: String
    switch parts[0] {
    case "margaret": person = "Margaret Walsh"
    case "dorothy": person = "Dorothy Miller"
    case "robert": person = "Robert Hayes"
    default: person = parts[0]
    }
    let variant: String
    switch parts[1] {
    case "front": variant = "front"
    case "turn": variant = "side"
    case "dim": variant = "light"
    default: variant = parts[1]
    }
    return (person, variant)
}

let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/FaceFixtures")
let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
let files = urls
    .filter { $0.pathExtension.lowercased() == "jpg" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !files.isEmpty else {
    fputs("No JPEG found: \(dir.path)\n", stderr)
    exit(1)
}

var samples: [Sample] = []
print("Detection")
for url in files {
    guard let names = parseName(url.lastPathComponent) else {
        print("  skip \(url.lastPathComponent)")
        continue
    }
    guard let image = loadCGImage(url) else {
        print("  FAIL load \(url.lastPathComponent)")
        continue
    }
    guard let fp = facePrint(from: image) else {
        print("  FAIL face \(url.lastPathComponent)  \(image.width)x\(image.height)")
        continue
    }
    print("  OK \(names.0) \(names.1)  \(url.lastPathComponent)  \(image.width)x\(image.height)")
    samples.append(Sample(person: names.0, variant: names.1, file: url.lastPathComponent, print: fp))
}

print("\nPairwise distances (smaller = same person)")
print("A\tvar\tB\tvar\tdist\tsame")
var same: [Float] = []
var other: [Float] = []
for i in 0..<samples.count {
    for j in (i + 1)..<samples.count {
        let a = samples[i], b = samples[j]
        guard let d = distance(a.print, b.print) else { continue }
        let isSame = a.person == b.person
        if isSame { same.append(d) } else { other.append(d) }
        let mark = isSame ? "yes" : ""
        print("\(a.person)\t\(a.variant)\t\(b.person)\t\(b.variant)\t\(String(format: "%.3f", d))\t\(mark)")
    }
}

func stats(_ xs: [Float]) -> String {
    guard let mn = xs.min(), let mx = xs.max() else { return "none" }
    let mean = xs.reduce(0, +) / Float(xs.count)
    return String(format: "n=%d  min=%.3f  max=%.3f  mean=%.3f", xs.count, mn, mx, mean)
}

print("\nSame person       \(stats(same))")
print("Different person  \(stats(other))")

if let sMax = same.max(), let oMin = other.min() {
    let gap = oMin - sMax
    print(String(format: "Gap (other min − same max)  %.3f  %@", gap, gap > 0.15 ? "separates" : "overlaps"))
}

/// Same verdict as the app: enrol frontal+side, probe with lighting. Threshold 0.55 / margin 0.15
print("\nEnroll=front+side, probe=light (same as in-app virtual test)")
let people = Array(Set(samples.map(\.person))).sorted()
for probePerson in people {
    guard let probe = samples.first(where: { $0.person == probePerson && $0.variant == "light" }) else {
        print("  \(probePerson) missing light shot")
        continue
    }
    var scores: [(String, Float)] = []
    for person in people {
        let enrolled = samples.filter { $0.person == person && $0.variant != "light" }
        let ds = enrolled.compactMap { distance(probe.print, $0.print) }
        guard let best = ds.min() else { continue }
        scores.append((person, best))
    }
    scores.sort { $0.1 < $1.1 }
    let best = scores[0]
    let second = scores.dropFirst().first
    let verdict: String
    if let second, best.1 + 0.15 > second.1 {
        verdict = "Too close to call — not guessing"
    } else if best.1 < 0.55 {
        verdict = "Closest: \(best.0)"
    } else {
        verdict = "Unknown"
    }
    let ok = verdict.contains(probePerson) ? "hit" : "miss"
    let line = scores.map { "\($0.0) \(String(format: "%.3f", $0.1))" }.joined(separator: "  ")
    print("  probe \(probePerson)  →  \(verdict)  [\(ok)]  \(line)")
}
