# Project Reference

**RobotForElders — what this code does, and what changes when you edit where**

Written: September 10, 2026
Audience: someone who has opened the source but doesn't know where to start. The *why* of the design is in `01`–`05`;
this document is **a map connecting code and design**.

---

## 1. One-page summary

An **iPad face display** set up in an adult day care centre, in a seat that several elders take turns sitting in.
The robot recognises the face that approaches, calls the person by name, then opens that person's memory store
and **continues the previous conversation.**

Cognitive state is observed only by **planting one fact in the conversation and naturally bringing it back
a few minutes later**, with no separate test screen. The elder's screen has no questions, scores or timers.

**It doesn't diagnose.** It only makes change noticeable; a doctor gives it a name.

---

## 2. Lines that aren't crossed (constraints running through the code)

1. **Don't test, converse** — metrics only in `StaffOverlayView` and after-the-fact reports.
2. **Old memories fuel the conversation** — the session opener always opens with 'that story from last time'.
3. **Missing an answer isn't failure** — when recall fails, the robot fills in the answer and moves on.
4. **Elders don't touch the screen** — all elder input comes only through voice and face.

The code holds two more lines on top of these.

5. **Missing values are never invented** — unmeasured metrics stay as `—` (`MetricEngine`).
6. **Conversations that never happened are never quoted** — memory cards use only what's in the store.

---

## 3. Where things stand

| Stage | Status | Where |
|---|---|---|
| 0 — 16 screens · fixed script | ✅ | `Models/SessionScript.swift` |
| 0.5 — memory store | ✅ | `Memory/` |
| 1 — listening · understanding | ✅ on-device | `Speech/` · `Understanding/FactExtractor.swift` |
| 2 — conversation generation | 🟡 **Up to choosing.** Staff must press to send it | `Understanding/ReplyPlanner.swift` |
| 3 — face recognition | ✅ Wired to session identity. **Second-person matching unverified** | `Vision/` |

**Going autonomous is the last box left for this product.**

---

## 4. Module map

| Folder | Role | Types to look at first |
|---|---|---|
| `App/` | App shell · 3 modes · 4 consents · OS permissions | `RootView` · `AppMode` · `ConsentStore` |
| `Models/` | Script · state machine · metric calculation · form-of-address rules | `SessionViewModel` · `SessionScript` · `MetricEngine` |
| `Memory/` | SwiftData store and queries | `MemoryStore` · `MemoryModels` |
| `Speech/` | Transcription · echo detection · recognition-rate measurement | `NameListener` · `SpeechEcho` |
| `Understanding/` | What was said → facts · choosing the next move | `FactExtractor` · `ReplyPlanner` |
| `Vision/` | Person detection · face prints · matching · enrolment | `PresenceWatcher` · `FaceGallery` · `FacePrinting` |
| `Elder/` | Session screen · 12 elder screens · voice output | `SessionView` · `SpeechEngine` |
| `Staff/` | Staff overlay · 4 staff screens · settings · 7 probes | `StaffSettingsView` · `ReportData` |
| `DesignSystem/` | Colour · type · layout tokens · expressions · canvas | `Theme` · `FaceStyle` · `CSSShapes` |
| `Gallery/` | Catalogue of the 16 screens | `ScreenCatalog` |

**Read `Models/` and `Understanding/` first.** The product's decisions are there, and
the rest connects those decisions to screens and storage.

---

## 5. Data model

```
Elder ─┬─ sessions  [Session] ─┬─ utterances [Utterance]   transcript
       │                       ├─ anchors    [RecallAnchor] delayed recall
       │                       ├─ metrics    [MetricSample] one set per session
       │                       ├─ topics     [String]       topics covered this time
       │                       └─ nextOpenerTopic           preview for the next session
       ├─ facts     [Fact] ──── revisions [FactRevision]    value before the change
       └─ faceEmbeddings [Data]  up to 5
```

| Model | What it holds | Watch out |
|---|---|---|
| `Elder` | Name · honorific · surname · first-name permission · hometown · approval · face prints | `spokenName` is the name the robot calls |
| `Session` | Start/end · topics · next opener | `discard`ed if there are no utterances |
| `Utterance` | Transcript · word count · topic · whether it's the elder | **What was actually said** goes in, not the choice label |
| `Fact` | Topic · kind · detail · mention count | Mentioning the same topic again raises the count |
| `FactRevision` | Detail **before the change** | The latest is `Fact.detail`. Putting the two side by side is the consistency metric |
| `RecallAnchor` | Question · answer · planted time · time to ask back · verdict | Under 6 minutes is excluded from the recall rate |
| `MetricSample` | Metric key · value · time | When a session closes, **only what was measured** is kept |

**On-device only.** `ModelContainer` is opened with `cloudKitDatabase: .none`.
Face embeddings are biometric data, and conversation transcripts and cognitive metrics are health-related data.

---

## 6. The order a session runs in

### 6-1. Someone arrives

```
PresenceWatcher  sample every 0.5 s → majority of a 5 s window is a face
      │ onPresence            "who it is isn't known yet" — greet right away
      ↓
SessionViewModel.presenceDetected()   resting → greeting
      │ (the camera keeps looking in the meantime)
      ↓
FaceGallery.match  →  recognized / ambiguous / unknown / noFace
      │ onIdentified
      ↓
SessionViewModel.identify(...)   opens that person's memories and rebuilds the script
```

If it couldn't tell, `stallWhileLooking()` **takes one more look while asking about the weather.**
It's not just buying time — answering means looking at the screen, so a frontal frame is captured.

### 6-2. The elder speaks

```
NameListener (STT)  →  SessionViewModel.noteHeard(text)
                          │ SpeechEcho.isEcho → discard if it's the robot's own voice
                          ↓ heardAnswer
Staff press a choice → pick(choice) → record(choice)
                          ├─ Save Utterance (transcript of what was said)
                          ├─ FactExtractor.extract   10 s in the background
                          └─ ReplyPlanner.plan       7 s in the background → suggestion on the staff panel
```

**There are only two places that need staff confirmation** — the name and the first story. In the remaining listening steps,
what was said becomes the transcript as is. Making staff type at every step means they can't watch the elder.

### 6-3. Planting a memory and bringing it back

```
[4] Plant anchor   "What did you have for lunch today?"  → RecallAnchor(probeDueAt = +8 min)
      … the conversation continues …
[6] Ask back       "By the way, what was lunch?"
      ├─ exact / partial        → verdict ends here
      └─ doesn't know → [7] recovery  → recall after a hint / failure
```

**If 8 minutes haven't passed, the verdict choices are locked.** Staff can skip with `Probe now · not counted`,
and the skip is left in the log.

### 6-4. The session closes

On reaching the last screen, `endSession()` **leaves one set of metrics** and previews
the last topic that came up as the next opener. This is where principle 2 carries on.

---

## 7. The 16 screens

| Elder (12) | Staff (4) |
|---|---|
| 1 Resting · 2 Face recognition · 3 Greeting · 4 First meeting | 13 Today's roster |
| 5 Asking the name · 6 Enrolment confirmation · 7 Last conversation | 14 Memory map |
| 8 Subtle recall check · 9 Recall conversation · 10 Gentle recovery | 15 Personal cognitive report |
| 11 Wrap-up · 12 Call staff | 16 Weekly digest |

All four staff screens **read from the store.** View them in gallery mode or
open them directly with `-screen 13`–`16`.

### 3 modes (`AppMode`)

| Mode | What |
|---|---|
| Gallery | Screen catalogue. **Never put in front of an elder** |
| Pilot | 980pt elder stage on top + 200pt staff panel below |
| Deployment | Kiosk. **No staff elements on screen at all** |

The only way back from deployment mode is **two fingers for 1.5 seconds**.

---

## 8. Figures that define the screens

| Item | Value | Basis |
|---|---|---|
| Canvas | 820 × 1180 (scale 1.0) | `02` section 2 |
| Lines | **74pt** · max 3 rows | 35.8 arcmin = tier A. `02` section 4 |
| Max row width | **724pt** (820 − 48 × 2) | Wraps if exceeded |
| Eye centre y | 280 (deployment) · **232** (pilot) | Gaze error 4.4° · 3.7° |
| Line start y | 560 (deployment) · **460** (pilot) | Pilot slack **4.15pt** |
| Staff panel | 200pt · buttons 20pt | Unreadable at the elder's distance |
| 1 session | **18 minutes** (including 8-minute delayed recall) | `03` section 3 |

> **There's only 4pt of vertical slack.** Touch the waveform or card heights or the line spacing and it overflows immediately,
> and **overflow doesn't fail with an error but by the lines silently getting smaller.**
> If you've edited around here, always run `swift Tools/check-captions.swift`.

**Interpolations sit alone on their own row.** Names and topics come from the store, so their length is unknown.

---

## 9. Where safety is actually at stake

Places where **the code blocks things**, not prompts or conventions. Take particular care when editing them.

| What it blocks | Where |
|---|---|
| The model inventing a topic that doesn't exist | `ReplyPlanner.resolve(move:subject:)` |
| The robot recording its own voice as the elder's words | `SpeechEcho.isEcho(heard:caption:)` |
| Calling an unrecognised person by someone else's name | `.ambiguous` in `FaceGallery.match` |
| Recording without consent | `SessionViewModel.isRecording` |
| The script producing metric numbers | `MetricEngine` (the channel itself was removed) |
| Counting recall with no delay in the recall rate | `RecallAnchor.isValidProbe` |
| Voice going overseas | `SpeechEngine.enforceOverseasConsent()` |

**Safety comes not from the model's compliance but from Swift's bounds checks.** That's why free generation was pulled
and replaced with choosing (the measurements from then remain in `ReplyComposer`).

---

## 10. What changes when you edit where

| What you want to do | Where to edit |
|---|---|
| The robot's line wording | `Models/SessionScript.swift` · `ReplyPlanner.Move.line` |
| Add actions the robot can take | Add a `case` to `ReplyPlanner.Move` + write the sentence |
| What to ask someone met for the first time | `SessionScript.SeedQuestion` |
| How metrics are calculated | `Models/MetricEngine.swift` (pure functions · has tests) |
| Delayed recall interval | `RecallAnchor.probeDelay` · `minimumValidDelay` |
| Face matching thresholds | `Vision/FacePrinting.Threshold` — **don't raise them to boost the recognition rate** |
| Silence and utterance limits | `Speech/NameListener.Purpose` |
| Colour · text size · layout | `DesignSystem/Theme.swift` |
| Expressions | `DesignSystem/FaceStyle.swift` (+ the icon too) |
| Permission strings · app name | `project.yml` (`Info.plist` is generated) |
| Staff report wording | `Staff/ReportData.swift` |
| Order of session steps | The `SessionScript` array + **index constants** (tests catch mismatches) |

---

## 11. Things that save you trouble if you know them first

- **`.xcodeproj` and `Info.plist` are generated.** `project.yml` is the source.
- **Don't reuse `LanguageModelSession`.** History accumulates and every call gets slower
  (measured 6.9 → 6.7 → **9.9 s**).
- **Don't use `.measurement` on `AVAudioSession`.** It turns off all system audio processing,
  **and that includes echo cancellation.** Only `SpeechProbe` is an exception — its purpose is to measure recognition accuracy
  on uncorrected input.
- **Don't stack several `fullScreenCover`s on one view.** With three, the third
  silently fails to open. No error, no log.
- **Don't trust model latency in the simulator.** The simulator uses the Mac's model.
- **The first token arrives at 78–100% of total latency.** Streaming can't hide it.
- **Always display the model's choice and the code's fallback distinctly** (`Plan.wasFallback`).
  Without it, when the same value comes out three times you don't know whether to fix the prompt or the code.
- **Don't raise thresholds to boost the recognition rate.** It brings the risk of calling someone else by that person's name.

---

## 12. Further reading

| Document | What |
|---|---|
| `00_doc-map.md` | Document structure · settled key figures · lines not crossed |
| `02_design-criteria.md` | Canvas · legibility · typography · gaze alignment |
| `03_product-design.md` | Session structure · cognitive measurement · UI boundary · consent |
| `04_screen-design.md` | Absolute coordinates per screen |
| `06_build-guide.md` | From receiving it to running it |
| `2026-09-10_implementation-status-analysis.md` | **What runs now and what doesn't** |
