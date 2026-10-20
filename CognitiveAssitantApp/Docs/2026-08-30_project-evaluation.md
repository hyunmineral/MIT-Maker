# August 30, 2026 · Project Evaluation

**RobotForElders — elder conversation robot iPad app**

Written: 2026-08-30
Scope: the whole working folder (Swift source · `Docs/00`–`05` · settings · outputs)
Basis: the current snapshot. It isn't a Git repository, so commit history couldn't be examined.

The English conversion task list written the same day is `2026-08-30_english-conversion-work.md`.
This document records **how far the product has come right now**. For the scope and order of the English conversion, see that one.

---

## 1. One-line assessment

This project is **not a care robot for on-site deployment but a Wizard-of-Oz prototype that can make it to pilot session 0**.

The product judgement and design docs are unusually solid for an app at this stage, and the code largely follows that judgement. But **the abilities to listen, think and recognise don't exist yet**, and there are holes in the wiring, measurement and consent protection needed for operation.

| Question | Answer |
|---|---|
| What is being built | A portrait-mounted iPad face for adult day care. It plants memories in conversation and brings them back, showing cognitive change only to staff |
| Current stage | **Stage 0.5 done · right before the pilot.** Roadmap stages 1 (STT) · 2 (LLM) · 3 (Vision) not started |
| On-site demo | **Possible** in `pilot` mode with staff pressing choices |
| Unattended operation with elders | **Not possible.** `deployment` mode is a screen with its input cut off |
| Is it a medical/diagnostic product | The design consciously avoids it. But there's a risk that fake figures on staff screens look like a diagnosis |

Size: Swift **36 files · 6,008 lines**. No tests. Not a Git repository. The canonical docs are `Docs/00`–`05`.

---

## 2. What the product got right

The 4 principles are actually enforced as code constraints.

1. **Don't test, converse** — no scores, timers or progress on the elder screen. Measurement jargon only on the staff side.
2. **Old memories are the fuel** — `MemoryStore.opener(for:)` picks the opener in the order promise → last topic → long-term memory.
3. **Missing an answer isn't failure** — the recovery step is skipped on successful recall. The robot never says "who are you again?".
4. **Elders don't touch the screen** — choices are 20pt on the bottom staff panel, hidden by size so they're unreadable at 70 cm.

Physical design:

- Deployment device **iPad Air 5 (M1) 10.9″ portrait**
- Canvas **820 × 1180 native**
- Lines **62pt**, eye centre **y = 280 (deployment) / 240 (pilot)**

Finding and correcting the error of treating pt as character height in the legibility calculation is the most valuable judgement in this project. The 0.72 factor hasn't been measured with a ruler yet, so it rightly is the first measurement item of the pilot.

The personal-data direction is clear too.

- SwiftData `cloudKitDatabase: .none`
- STT pinned with `requiresOnDeviceRecognition = true`
- Without overseas-transfer consent, OpenAI TTS reverts to Apple at both the UI and the engine
- The API key is in the Keychain. The docs note it must move to a server for deployment

---

## 3. Completeness

With the current goal set as **"a staff-operated pilot app"** it scores well; set as **"a care robot product"**, the score drops.

| Area | Score | Basis |
|---|---|---|
| Product definition · principles | **9 / 10** | Even what it doesn't do is pinned down. Medical devices, diagnosis and touch operation are explicitly out of scope |
| Design docs | **8.5 / 10** | `00`–`05` are canonical and Backup is kept separate. Only the README is outdated |
| Design system · face | **8.5 / 10** | Even the CSS `border-radius` scaling rule was ported, so expression interpolation is seamless |
| Session state machine | **7 / 10** | Fixed script + branches work. Subjects fixed to Kim Sunja/Park Malsun |
| Memory store | **7 / 10** | Schema, opener and recall rate are real implementations. Consistency · TTR · mood are still script values |
| Voice output | **8 / 10** | Apple/OpenAI, cache, rate, consent gate, fallback instead of silence |
| Voice input | **3 / 10** | Only the measurement tool exists. STT isn't attached to the session |
| Staff operations UI | **5 / 10** | The roster reads the DB but can't go to a session. 14 · 15 · 16 are dummies |
| Personal-data protection | **6.5 / 10** | Overseas transfer and recording are blocked. **Self consent isn't checked on the save path** |
| Engineering hygiene | **3 / 10** | No Git, no tests, build outputs in the working folder |

**Pilot session 0 readiness: 7 / 10.**
**On-site deployment: 2 / 10.** No input path, consent enforcement, MDM, retention period or spare unit.

---

## 4. What actually works vs what's screen-only

### Works

- Gallery of 12 elder screens + 4 staff screens
- Fixed-script sessions (`SessionScript.known` / `stranger`)
- Apple on-device TTS (Yuna) · OpenAI TTS cache
- SwiftData: `Elder` · `Session` · `Utterance` · `Fact` · `FactRevision` · `RecallAnchor` · `MetricSample` · `SpeechSample`
- Opener lookup, anchor +8 minutes, verdicts under 6 minutes excluded from the recall rate
- Empty sessions are discarded rather than closed (`discard`)
- 3 modes (gallery / pilot / deployment), persisting across device restarts
- STT measurement: record → on-device recognition → transcribe the correct answer → word edit distance
- Two fingers 1.5 s → staff settings

### Screen-only

| Feature | Current | What the docs say |
|---|---|---|
| Face recognition | Staging + a staff "recognition complete" button | Stage 3 Vision embeddings |
| Voice input | Staff tap choices | Stage 1 STT |
| Conversation generation | Fixed Kim Sunja/Park Malsun script | Stage 2 LLM, 40-character line limit |
| Memory map · cognitive report · weekly digest | Hard-coded demo data | Aggregation of `Fact` / `MetricSample` |
| Roster → session | No tap action on cards, and "+ New elder" is decorative too | Staff choose from the roster until Vision |
| Speech amount TTR · mood | Numbers baked into the script's `metricUpdates` | Computed from utterances and voice |
| 18-minute delay | There's a countdown. It doesn't stop asking back | The delay is the essence |

The session subject is still looked up only by name.

```swift
let name = (person == .known) ? "Kim Sunja" : "Park Malsun"
elder = (try? store.allElders())?.first { $0.name == name }
```

The seed comment says "enrolled 8 months · 74 sessions total", but only **1** finished session is actually inserted. The roster meta shows "1 session total". The memory map's "12 people · 7 places · 23 events" has nothing to do with the DB either.

---

## 5. Structure

The layers are the same in the docs and the code.

```
App           entry · modes · consent
DesignSystem  820×1180 · typography · face shapes
Models        script state machine
Memory        SwiftData + opener/recall queries
Elder         stage · TTS
Staff         settings · roster · reports · STT measurement
Speech        on-device recognition measurement
Gallery       catalogue of the 16 screens
```

Contracts done well:

- `SessionStep` is fixed in advance as the stage-2 LLM output schema, and fields aren't added casually.
- Memory cards are store lookup only. No nonexistent utterance is attached to a promised topic (`.promised`).
- Colours aren't stored with metrics. Colour is applied on screen.
- The docs separate the side that makes conversation from the side that grades it.

Weaknesses:

- `SessionViewModel` handles session lifetime, script injection, recording and metric UI in one class (366 lines). Once stage-1 STT is attached, this is what grows first.
- `Person.known/stranger` and `Elder` are duplicated. The docs say "choose from the roster until Vision", but the code toggles between two people.
- `try? store.save()` is on every save path. Failures don't show on the staff screen. If the next opener is silently lost, principle 2 breaks.
- There are no app lifecycle hooks. The session opens in `onAppear`, and on a crash or force quit, empty/incomplete sessions with `endedAt == nil` can remain. The roster shows them as "In conversation".

---

## 6. Points where the product stops if they get stuck

### High — input cut off in deployment mode

Once the staff panel disappears there's no way to advance the session. No STT, Vision or remote control yet. The pilot must stay in `pilot`, and `deployment` should only be used to check the display.

Related: `App/AppMode.swift`, `Elder/SessionView.swift`

### High — self/guardian consent not enforced

The settings text says "without it, session records can't be kept", but `Consent.isGranted(.personal)` **is defined but never called.** Recording consent is enforced by `SpeechProbe` and overseas transfer by `SpeechEngine`. Only saving conversations and metrics is left open.

Related: `App/ConsentStore.swift`, `Models/SessionViewModel.swift`

### High — the session is created as soon as the screen appears

`SessionView.onAppear` → `attach()` → `beginSession()` creates a new `Session`. If the app quits or crashes without `endSession()` / `discard()` being called, an empty in-progress session can remain.

Related: `Elder/SessionView.swift`, `Models/SessionViewModel.swift`

### Product gate — STT failing to understand dialect

Korean · elderly pronunciation · the South Jeolla Boseong dialect overlap. The measurement tool is ready, and **the stage-1 schedule must not be set before the table comes in.**

### Ethics — fake cognitive figures looking real

`Metric.baseline` already shows consistency 92% and mood 70% before the session starts. The report screen has a fixed 8-week decline graph. If staff and guardians start using these numbers as grounds for consultation, the principle of "no diagnosis" collapses on screen. There's no source tag (`scripted` / `measured`).

### Later stages — 8GB RAM · cloud LLM

No problem in stages 0–1. In stage 2, when the on-device LLM + Vision + audio overlap, responses stutter as the docs warned. The moment it goes to the cloud, overseas-transfer consent is needed again, ending the current "nothing leaves the device" state.

### The hardware hypotheses are still hypotheses

Whether 62pt is readable at 70 cm, whether the built-in speakers are enough, whether elders look at the bottom panel, whether mood drops after a recall failure — all of these are answered only by **on-site observation**, not code. Even settling on the Air 5 is "final if it passes the pilot" (`01` section 8).

---

## 7. Mismatches between docs and code

The canonical docs are `Docs/00`–`05`. The problem is that **the entry-point doc is outdated**.

`README.md` still says **landscape 1194 × 834**, "iPad only · locked to landscape", "choice buttons stand in for STT/TTS", and no memory store. The real app is portrait 820 × 1180, has TTS attached, and has SwiftData. Someone new who reads only the README assumes the wrong device.

Others:

| Item | Status |
|---|---|
| `project.yml` version `0.1.0` vs `Info.plist` `1.0` | Mismatch |
| `.gitignore` | No `build-analyze/`. `build/` · `build-device/` · `build-analyze/` take about 458MB in the working folder |
| Git | Not a repository. Only `.gitignore` exists |
| `03` section 10 | Still says "delayed recall timer comes later", while the code has implemented up to the countdown |
| `HANDOFF.md` | Dated 2026-08-17. The 8-28 review came after. The root handoff isn't the latest |

Comments mostly point to doc sections, and traps (the SwiftUI `Anchor` clash, `FitToHeight`'s default centre alignment, SourceKit false diagnostics) are written right next to the code. This density is worth keeping.

---

## 8. Code quality

Easy to read, with consistent domain language. Like `RecallAnchor.isValidProbe`, `openerCard(for:)`, `enforceOverseasConsent()`, **why the line exists** is in the function name.

Notable technical choices:

- Merging eyes and mouth into one Shape for expression interpolation (`CSSShapes`)
- Keeping the "lines are always at the same y" invariant with `FitToHeight(alignment: .top)`
- Keeping the voice cache in `Application Support`, not `Caches`
- Settings as a full screen rather than a sheet, avoiding it being left half-open on the kiosk

Engineering gaps:

- No unit tests. `opener` priority, excluding under 6 minutes, WER and discarding empty sessions are pure logic that's easy to test
- The Korean word count is a whitespace split. The seed sentences have spaces so it works, but if STT results run words together, speech amount collapses to 1
- No SwiftData migration strategy. Changing the schema can break existing device data, and a `ModelContainer` failure is `fatalError`
- No storage encryption. Even on-device, this is biometric and health data that should assume loss or resale of used devices
- Accessibility (VoiceOver) matters little on elder screens, but it's absent on staff screens

---

## 9. How to view this project

Its strength is **product judgement, not technology**.

- Judging that "valid overseas-transfer consent" is hard to obtain from someone with cognitive decline, and choosing **not to send anything out** instead of obtaining consent
- Removing the choices from the elder screen so staff don't block the elder's view
- Taking anchors only from **the elder's speech**, not words the robot presents
- Stating explicitly that an LLM inventing memory cards would plant memories that never existed

Its weakness is that **the demo looks like a product**. With a face, big lines, 92% consistency and an 8-week decline graph, the demo goes well. If staff who don't know those numbers come from the seed and script use them in consultations, it does harm.

The roadmap order is right. Putting the store (0.5) before STT is right too. What to continue with the current code is not a new engine but **the wiring that makes the pilot run**.

---

## 10. Order of what to touch next on the code side

It's almost the same as `05` section 6 and the 8-28 review. Re-sorted on the 2026-08-30 code alone:

1. **Initialise Git** and exclude `build*` from tracking. 6,000 lines with no history is an accident waiting to happen.
2. **No saving without `personal` consent.** A double gate, like overseas transfer.
3. **Clean up empty unfinished sessions** + delay the session until the first real event.
4. **Roster card → start that Elder's session.** The operating path until Vision.
5. Attach a **source** to metrics, and have the staff overlay/reports show only measured values. Demo graphs only in the gallery.
6. Fix the `README` to match 820 × 1180 · portrait · stage-0.5 status.
7. A few tests for `opener` / `recallRate` / WER.
8. **Pilot session 0** — glyph 8.59 mm, 70 cm, gaze to the bottom, Yuna volume.
9. **STT measurement, 3–5 minutes.** No stage-1 schedule without this table.

Beyond stage 1 is for measurement to decide. If on-device Korean falls short of 75%, narrowing the topics while keeping staff assistance (WoZ), or going to remote control (option B), is safer than rushing to attach an LLM.

Switching to an English runtime is **a separate task** from the list above. Scope, order and verification follow `2026-08-30_english-conversion-work.md`.

---

## 11. Related documents

| Document | Relationship |
|---|---|
| `00`–`05` | The canonical design. This evaluation doesn't replace it |
| `2026-08-28_review-checkpoint.md` | The code review from two days earlier. The three High risks are unchanged on 8-30 |
| `2026-08-28_project-structure-and-improvements-analysis.md` | Structure summary. This document updates its judgement |
| `2026-08-30_english-conversion-work.md` | Task list for converting language and system to English |
| `HANDOFF.md` | Session record from August 17. The figures are valid; for later changes see this document and 8-28 |
