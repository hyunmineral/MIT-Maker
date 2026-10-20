# Face Detection · Matching Measurement

**RobotForElders** — on-device identity recognition research for academic and volunteer purposes

Written: 2026-08-30 · Updated: 2026-08-30 (reflecting the app's English conversion)
Device: iPad Air 5 (M1) · portrait mount · eye-to-screen about 70 cm

> **The app screens are English-only.** Buttons and verdict text quoted in this document are written
> exactly as the English appears on screen. (The document body was originally in Korean and has been translated.)

Stage 1 (detection) **is treated as stable and we move on**. If boxes jitter or the detection rate collapses,
come back to this document and fix the mounting and lighting. Session identity isn't wired up yet.

This is a volunteer app and academic research, so if Feature Print can't separate people,
it may move on to non-commercial research weights such as InsightFace buffalo_sc.
For now only Apple Vision is used.

---

## Stage 1 — is a face visible

**Premise: passed.** Air 5 front camera + `VNDetectFaceRectanglesRequest`.

| Independent | Dependent |
|---|---|
| Distance (70 cm, 85 cm, 40 cm) | Number of faces |
| Frontal / slightly to the side | Confidence |
| Lighting (daylight / indoor lights) | Capture quality 0…1 |
| One person / two people | Detection rate relative to frames |

Photos aren't saved.

Staff settings → Consent on file → **Biometric (face) consent** → Probes → **Face detection probe**.

Pass criteria (provisional): detection rate ≥ 90% over 10 seconds frontal at 70 cm, quality not stuck at 0, two boxes for two people.

Code: `Sources/Vision/FaceProbe.swift`, `Sources/Staff/FaceProbeView.swift`

---

## Stage 2 — can numbers tell who it is

Runs Apple's `VNGenerateImageFeaturePrintRequest` revision 2 on the detected face crop.
No extra model. Enrolments live only in this screen's memory and are not written to `Elder.faceEmbeddings`
or the session.

### Research question

Are same-person distances smaller than different-person distances, **without overlapping**?

### Values shown on screen

| Display | Meaning |
|---|---|
| Distance | Smaller means the same. iOS 17 Feature Print. Roughly, same person below ~0.3 and different people above ~0.8 are common, but **settle it by measurement on this device** |
| `Closest: <name>` | First-place distance &lt; 0.55, and at least 0.15 ahead of second place |
| `Too close to call — not guessing` | Difference between first and second place under 0.15. So as not to call the wrong name |
| `No enrolled face is close (unknown)` | Even first place is 0.55 or above |

0.55 / 0.15 are starting values. They move once the table comes in.

### Procedure

1. Staff settings → Consent on file → turn on **Biometric (face) consent**
2. Probes → **Face matching probe**
3. Person A at 70 cm, frontal. Enter a name → **Enroll**. 2–3 more with the head turned slightly
4. Switch to person B and enrol the same way. **Two or more people** are needed for the table to mean anything
5. A sits again → **Compare now**. Write down the distance
6. B sits → **Compare now**. Write down the distance
7. Change only one of glasses · mask · profile at a time and fill the same table

Pressing **Done** clears the enrolments. Nothing stays on disk.

### Record table

| Probe | Min distance to enrolled A | Min distance to enrolled B | Verdict (screen) |
|---|---|---|---|
| A (same person) | | | |
| B (same person) | | | |
| A, glasses | | | |
| Unenrolled person | | | |

### Pass criteria (provisional)

- Same-person distance is **always** smaller than different-person distance
- The two values are at least 0.15 apart
- An unenrolled person gets `unknown` or `Too close to call`, never confidently another name

If they overlap, Feature Print alone isn't enough. Then move to buffalo_sc / InspireFace.
Even if they don't overlap, it doesn't go straight into the session — `resting → matching → opener` is wired up
after looking at the table. When in doubt, don't guess a name.

Code: `Sources/Vision/FaceMatch.swift`, `Sources/Staff/FaceMatchView.swift`

---

## Synthetic test (without a camera)

3 generated portraits of non-existent people (Margaret Walsh · Dorothy Miller · Robert Hayes) × frontal · side · lighting.
Staff settings → Probes → Face matching probe → **Run on virtual people**. Works in the simulator too.

Frontal and side are enrolled, with only lighting kept as the probe. Values run on a Mac with the same crop and Feature Print revision 2 as the app (2026-08-30):

| Probe | First place | Second place | Verdict |
|---|---|---|---|
| Dorothy lighting | Dorothy 0.225 | Margaret 0.610 | `Closest: Dorothy Miller` |
| Margaret lighting | Margaret 0.264 | Dorothy 0.554 | `Closest: Margaret Walsh` |
| Robert lighting | Robert 0.275 | Dorothy 0.662 | `Closest: Robert Hayes` |

Same-person distances 0.212…0.383 (mean 0.278).
Different-person distances 0.554…0.776 (mean 0.673).
Gap (different min − same max) **+0.171 — separates**. Enrol/probe protocol 3/3.
The CLI prints this line as `Gap (other min − same max)  0.171  separates`.

The portraits were redrawn as fictional Americans (2026-08-30, second set).

**This table doesn't replace the Air 5 at 70 cm.** Generated portraits are in focus with simple backgrounds, so they separate more easily than a real kiosk. Feature Print isn't a face-specific embedding but the whole cropped image, so clothing and hairstyle also mix into the distance.

Fixtures: `Resources/FaceFixtures/`. Recompute: `swiftc Tools/featureprint.swift -o /tmp/featureprint -framework Vision -framework ImageIO && /tmp/featureprint Resources/FaceFixtures`

---

## Not done yet

3. Wire into the session's `resting → matching → opener` (save to `Elder.faceEmbeddings`)
4. A face-specific embedding (buffalo_sc etc.) only if Feature Print overlaps
