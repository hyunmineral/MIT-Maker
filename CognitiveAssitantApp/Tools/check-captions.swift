#!/usr/bin/env swift
// Checks that lines fit within the vertical budget.
//
// **The build still passes when it overflows.** `FitToHeight` quietly shrinks the whole block,
// and then the tier-A legibility secured at 74pt (35.8 arcminutes) silently disappears.
// A script made to catch that failure with numbers rather than the eye.
//
//   swift Tools/check-captions.swift            # exit code 0 if it passes
//
// Rationale: Docs/04_screen-design.md sections 2 and 3 · Sources/DesignSystem/Theme.swift

import AppKit
import Foundation

// MARK: - Budget (must match the values in Theme.swift)

let speech: CGFloat = 74
let lineHeightMultiple: CGFloat = 1.35
let contentWidth: CGFloat = 724          // 820 − 48 × 2
let belowSpacing: CGFloat = 16
let waveHeight: CGFloat = 44
let cardHeight: CGFloat = 160
let stageHeightPilot: CGFloat = 980
let captionTopPilot: CGFloat = 460

/// UIKit-measured line height. **Computing with AppKit `NSFont` comes out 1.35pt small, so it isn't used**
/// (at 74pt, AppKit 87.0 vs UIKit 88.35). Derived from the simulator line pitch of 95.75pt.
let lineHeight: CGFloat = 88.35
let lineSpacing: CGFloat = speech * (lineHeightMultiple - 1.25)   // 7.4

let budget = stageHeightPilot - captionTopPilot                   // 520

func captionHeight(lines: Int) -> CGFloat {
    lineHeight * CGFloat(lines) + lineSpacing * CGFloat(lines - 1)
}

/// The allowed number of lines depends on what's attached below the line.
func maxLines(wave: Bool, card: Bool) -> Int {
    let below = (wave ? belowSpacing + waveHeight : 0) + (card ? belowSpacing + cardHeight : 0)
    var n = 1
    while captionHeight(lines: n + 1) + below <= budget { n += 1 }
    return n
}

// MARK: - Width measurement

let font = NSFont.systemFont(ofSize: speech, weight: .semibold)
func width(_ s: String) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: font, .kern: -0.02 * speech]).width
}

// MARK: - Reading the script

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// **Lines are built in two places.** The script, and the sentences for moves the planner chooses.
// Planner lines also appear as is on the elder screen, yet were outside the check for a long time (2026-09-10).
let sourceURLs = [
    root.appendingPathComponent("Sources/Models/SessionScript.swift"),
    root.appendingPathComponent("Sources/Understanding/ReplyPlanner.swift"),
]

/// Interpolations (`\(...)`) have **unknown length.** If alone on their own line they're treated as passing;
/// sharing a line with other text triggers a warning by itself — because long names and topics wrap.
let interpolation = try! NSRegularExpression(pattern: #"\\\((?:[^()]|\([^()]*\))*\)"#)

var failures = 0, warnings = 0

// The script writes lines with `caption:`, the planner with the string after `case .move:`.
// Both break lines with `\n` inside double quotes, so **multi-line string literals** are all read.
let captionPattern = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*\\n(?:[^"\\]|\\.)*)""#)

for scriptURL in sourceURLs {
guard let source = try? String(contentsOf: scriptURL, encoding: .utf8) else {
    FileHandle.standardError.write(Data("File not found: \(scriptURL.path)\n".utf8))
    exit(2)
}
let ns = source as NSString
for m in captionPattern.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
    let raw = ns.substring(with: m.range(at: 1))
    let line = source[..<source.index(source.startIndex, offsetBy: m.range.location)]
        .filter { $0 == "\n" }.count + 1
    let lines = raw.components(separatedBy: "\\n")

    for text in lines {
        let r = NSRange(location: 0, length: (text as NSString).length)
        let holes = interpolation.matches(in: text, range: r)
        let stripped = interpolation.stringByReplacingMatches(in: text, range: r, withTemplate: "")

        if !holes.isEmpty {
            // Lines with interpolation: measure only the fixed part, and warn if not alone
            let fixedOnly = stripped.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?—-"))
            if !fixedOnly.isEmpty {
                print("⚠️  \(scriptURL.lastPathComponent):\(line)  interpolation shares a line with other text — will wrap on long values")
                print("        \(text)")
                warnings += 1
            }
            continue
        }
        let w = width(text)
        if w > contentWidth {
            print("✗  \(scriptURL.lastPathComponent):\(line)  \(Int(w))pt > \(Int(contentWidth))pt")
            print("        \(text)")
            failures += 1
        }
    }
}
}

// MARK: - Summary

print("")
print("Lines \(speech)pt · width \(Int(contentWidth))pt · pilot budget \(Int(budget))pt")
print("Allowed lines — caption only \(maxLines(wave: false, card: false)) · "
      + "+waveform \(maxLines(wave: true, card: false)) · "
      + "+waveform+card \(maxLines(wave: true, card: true))")
print("")

if failures > 0 {
    print("\(failures) over width. Lines need re-breaking.")
    exit(1)
}
print("None over width\(warnings > 0 ? " (\(warnings) warnings)" : "")")
