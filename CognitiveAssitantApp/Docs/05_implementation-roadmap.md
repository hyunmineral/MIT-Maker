# Implementation Roadmap

**Elder Conversation Robot (RobotForElders)**

Written: August 17, 2026
Premise: all of documents `01`–`04`

---

## 0. What this document decides

If section 10 of `03_product-design.md` **listed** the stages, this document decides **order · dependencies · blockers**.
What has to be done first, what is blocking what, and what must be answered
before entering each stage.

> ### ⚠️ The order changes
>
> `03` section 10 set it as **stage 0 → stage 1 (STT) → stage 2 (LLM)**. But measuring the code showed
> **there's no persistence layer at all.** The only storage is the voice cache files and the voice settings
> in `UserDefaults`.
>
> This product's principle 2 is **"old memories fuel the conversation"**, and the session opener always
> starts with 'that story from last time'. **Without a store there is no last time.**
> However well STT and the LLM are wired up, everything vanishes the moment the session ends.
>
> **So `stage 0.5 — memory store` goes in before STT.**

---

## 1. Where things stand

### Done

| Area | Contents | Files |
|---|---|---|
| Design system | Native 820 × 1180 canvas · type scale · colour tokens | `DesignSystem/` |
| 16 screens | 12 elder + 4 staff. Rearranged with top alignment · 62pt lines | `Elder/Screens/` · `Staff/` |
| Session flow | Fixed-script state machine · branches · skipping the recovery step on successful recall | `Models/SessionViewModel.swift` |
| Voice output | Two engines, Apple / OpenAI · cache first · automatic fallback | `Elder/SpeechEngine.swift` · `Elder/Voice/` |
| Staff settings | Mode switching + voice. Per-voice preview · cache progress | `Staff/StaffSettingsView.swift` |
| Staff entry | Two-finger long press for 1.5 s (for deployment mode) | `DesignSystem/TwoFingerLongPress.swift` |
| Device deployment | Installed and running on iPad Air 5 (M1) · app icon | `Tools/make_app_icon.py` |
| **Memory store** | 7 SwiftData types · opener lookup · anchor delay verification | `Memory/` |
| **3 modes** | Gallery · pilot · deployment. Saved on the device, persists across reboots | `App/AppMode.swift` |

### Not implemented — all hard-coded

| Area | Current | What's actually needed |
|---|---|---|
| 4 metrics | ✅ **Done 2026-09-10** — recall rate · consistency · speech amount are computed from records. The `MetricUpdate` channel itself was removed, so **the script has no way to produce numbers** (`Models/MetricEngine.swift`) | Only mood remains — there's no way to measure it |
| Memory map (14) | ✅ **Done 2026-09-10** — nodes are built from `Fact`s | — |
| Personal cognitive report (15) | ✅ **Done 2026-09-10** — folds `MetricSample`s into weeks and draws them | — |
| Weekly digest (16) | ✅ **Done 2026-09-10** — generated from records. Doesn't appear if there's nothing to report | — |
| Face recognition | ✅ **Done** — detection, matching and enrolment really run (`Vision/`). The table's "staging only" was an outdated description | Second-person matching **unverified** |
| Form-of-address input | ✅ **Done 2026-09-10** — set by pressing a card in the roster (`Staff/ElderDetailView.swift`) | — |
| Self/guardian consent lock | ✅ **Done 2026-09-10** — no session opens without consent | — |
| Automated tests | ✅ **Done 2026-09-10** — 88 tests · 11 suites. Run without a device (`Tests/`) | — |
| Voice input | ✅ **Done 2026-09-01** — on-device STT at every listening step. When staff press a choice, what was actually said is saved as the transcript instead of the script label | Stage 1 done (`Speech/`) |
| Conversation **understanding** | ✅ **Done 2026-09-01** — extracts `Fact`s from what was said. Apple on-device `FoundationModels` | `Understanding/FactExtractor.swift` |
| Conversation **generation** | Fixed script. **This is the remaining slot** — the robot listens and understands but doesn't respond to the answer | LLM (stage 2) |

> The permission strings (`NSCameraUsageDescription` · `NSMicrophoneUsageDescription` ·
> `NSSpeechRecognitionUsageDescription`) are **already in** `Resources/Info.plist`.
> Only the frameworks haven't been attached yet.

---

## 2. Stages

Dependencies decide the actual order. Sizes are estimates, and stage 1 in particular can't be trusted until measured.

| Stage | Contents | Size | Blocking |
|---|---|---|---|
| **0** | The robot speaks | — | ✅ Done |
| **0.5** | **Memory store + deployment mode** | M | ✅ Done |
| **1** | The robot listens (STT) | **L · uncertain** | Stage 2 |
| **2** | The robot thinks (LLM) | L | — |
| **3** | The robot recognises (Vision) | M | — |

```
0 ─── 0.5 ─┬─ 1 ─── 2
           └─ 3          (3 is independent of 1 · 2. It can be attached later)
```

### Stage 0.5 — memory store + deployment mode ✅ Done

| Task | Result |
|---|---|
| Storage schema | `Memory/MemoryModels.swift` — `Elder` · `Session` · `Utterance` · `Fact` · `FactRevision` · `RecallAnchor` · `MetricSample` |
| Storage technology | **SwiftData**, `cloudKitDatabase: .none` — on-device only |
| Roster (13) wiring | `RosterView` reads with `@Query`. Cards show even the next opener |
| Session records | `SessionViewModel` records utterances · metrics · anchors |
| **Opener lookup** | `MemoryStore.opener(for:)` — promise → last topic → long-term memory, in that order |
| Deployment mode | 3 `AppMode`s. In deployment the staff panel, switch button and English all disappear |
| Delayed recall timer | `RecallAnchor.probeDueAt` + countdown on the staff panel. **Verdicts under 6 minutes excluded from the recall rate** |

> **Two things corrected during implementation.**
> 1. Removed the `"delay 8 min 12 s"` hard-coded in the script. It showed that even when asked back after 30 seconds
>    — it was a prop, not a measurement. Now the measurement module produces it from the measured value.
> 2. Sessions with no utterances are discarded rather than closed. Left as is, they inflate the cumulative count
>    and overwrite the next opener with `nil`, **breaking the link of principle 2.**

> **Stage 0.5 holds up even without face recognition.** Staff just pick from the roster at session start.
> That's why Vision could be deferred to stage 3.

### Stage 1 — the robot listens (STT)

> ### ⚠️ This is the real gate. Don't take it lightly.
>
> **Elderly English · regional accents · speech scattered by cognitive decline.** All three overlap.
> Get stuck here and stage-2 LLM quality is meaningless — wrong input, wrong output.
> **The size isn't pinned down.** Measure first, then decide.
>
> (Revised 2026-08-30: the app changed to `en-US`, so the gate was rewritten. The previous edition was Korean · the South Jeolla Boseong dialect.)

**What breaks recognition.** Lumping it all into "accent" gets the measurement design wrong.

| Cause | Especially for this audience |
|---|---|
| **Ageing voice** | Breathy low tones · tremor · quiet speech. The spectrum differs from the middle-aged adult voices the acoustic model learned |
| **Regional accents** | Asheville (southern Appalachia) · Des Moines (Midwest). US day care also commonly has **first-generation immigrants from non-English-speaking countries** |
| **Hearing loss** | Not hearing themselves, volume and intonation flatten and consonants smear |
| **Dentures** | `s` · `z` · `th` break down first. Common in this generation, yet rarely covered in the ASR literature |
| **Word-finding pauses · self-correction** | Breaking off and backtracking, like "that… um… peach orchard" |

The last row is this product's weak spot. **An app built to measure cognitive decline fails to understand because of that very symptom.**
Ordinary VAD reads long pauses as the end of speech and cuts people off, and self-corrections insert words
not in the reference sentence, lowering accuracy. It's the same problem as the "end-of-speech detection" item below.

| Task | Details |
|---|---|
| **Measure recognition accuracy** | **Do this first**, before anything else. Separate item below |
| Engine selection | On-device `Speech` vs cloud. Decided by measurement results |
| End-of-speech detection | Elders pause longer between words. An ordinary VAD threshold cuts them off |
| Retry flow | Asking again when it didn't catch something — **without making the failure look like the elder's fault** |
| Anchor extraction | Extract one fact from speech (`03` 4-1) |

**Measurement that must happen before starting — one day is enough**

1. Record 3–5 minutes of speech from the target elders — consent obtained (2026-08-17).
   **There's a measurement tool inside the app**: Staff settings → Probes → `STT accuracy probe`
2. The tool **shows the on-device recognition result immediately.** When staff transcribe the correct answer,
   word accuracy is computed automatically
3. Recording files stay in `Application Support/SpeechSamples`, so
   the same audio can be fed to 1–2 cloud candidates for offline comparison
4. Record **what breaks, by type** — proper nouns (names · places) · numbers and dates ·
   words following a pause · smeared consonants. With only a single lump-sum accuracy, there's nothing to act on

> **Don't set the pass criterion as overall accuracy.**
>
> What this product actually needs from recognition is **the one-word anchor answer** —
> catching `"tomato soup"` again 8 minutes later is enough for a recall verdict (`03` 4-1).
> Even at 70% overall word accuracy, measurement works if the anchor word isn't missed,
> and conversely even at 90%, getting only the proper nouns wrong breaks the product.
> So the measurement table records **overall accuracy and anchor-word recall separately**.
>
> The app's `Word accuracy` is **word-level edit distance** split on whitespace (close to `1 − WER`).
> In English whitespace is the word boundary, so this approach fits better than for Korean.

> **Recognition is pinned to on-device** (`requiresOnDeviceRecognition = true`).
> `SFSpeechRecognizer` defaults to sending to Apple's servers, so left as is the elder's voice
> would leave the device. Certainly without overseas-transfer consent, and even with it,
> measuring on-device performance is the right thing for measurement purposes.
>
> The first paragraph of the iOS permission prompt ("voice data is sent to Apple") is **fixed Apple wording**
> and can't be changed. We corrected it in our own explanatory text.

Until this table exists, neither the engine nor the schedule can be decided.

### Stage 2 — the robot thinks (LLM)

The contract is `SessionStep` (`03` section 8).

| Task | Details |
|---|---|
| Via a server | **Don't keep the key in the client** (section 4) |
| Output constraints | Lines **40 characters** · 5 expressions · memory cards **never generated** |
| Separate measurement | Metrics come from the measurement module, not the LLM. It must not grade its own conversation |
| Memory budget | Measure whether on-device runs in 8GB RAM (`01` 3-1) |
| Fallback | On response failure or delay, fall back to the fixed script. Never go silent in front of the elder |

### Stage 3 — the robot recognises (Vision)

| Task | Details |
|---|---|
| Face detection · embedding | `Vision` RGB-based. No TrueDepth (`01` 5-3) |
| On-device storage | Embeddings are **biometric data**. Never exported (`03` section 9) |
| Enrolment flow | Screen 06 — captured automatically mid-conversation with no shutter sound |
| Performance | Stop detection while speaking. Avoids 8GB memory pressure (`01` 3-1) |

---

## 3. Pilot — can be done right now

Stage 0 is finished, so **there's no need to wait for stage 0.5.**

### What's needed

- [ ] iPad Air 5 (✅ owned) · portrait mount — **eye-to-screen 70 cm, max 85 cm** (`01` 4-1)
- [ ] External speaker (also check whether the built-in one is enough)
- [ ] Settle the voice — pick a voice and **`Pre-generate all`** (13 lines)
- [x] **Self/guardian consent — done** (2026-08-17)
- [x] **Voice recording consent — done** (2026-08-17)
- [x] **Voice engine settled — Apple on-device** (2026-08-17).
      **Decided not to obtain overseas-transfer consent** — instead of obtaining it, make sure nothing leaves
- [ ] **Install an Apple English premium voice** —
      Settings → Accessibility → Spoken Content → Voices → English.
      ~~Yuna premium installed (2026-08-17)~~ **Invalid — it's a Korean voice.**
      The app lists only `en*` voices, so until an English one is downloaded, only default quality is available.
      **Once downloaded, the app picks it on its own** — `refreshVoices()` sorts by quality, descending, and
      takes the first (= best) if there's no saved choice. The simulator picking `Albert · Default`
      is because only default-quality voices exist there
- [ ] Observation record sheet — items below

### Session plan

| Session | Participants | Purpose |
|---|---|---|
| 0 | 1 staff member | Check device · voice · controls. No elders |
| 1–2 | 1 elder | Observe reactions. Whether the script is completed |
| 3–5 | 3 elders | Individual differences. Variation in legibility and hearing |

### Observation items

Separates what's answered by measurement from what's answered by eye.

| Item | Method | What changes |
|---|---|---|
| **Glyph factor 0.72** | Hold a ruler to the screen and measure the height of 62pt text | **The basis for every legibility figure** (`02` section 1) |
| 62pt line legibility | Ask them to read it | If not, 72pt or 13″ |
| Built-in speakers | Number of times they ask again | External speaker budget |
| **Do they look at the bottom of the screen** | Gaze observation | If so, switch to remote control (option B) (`03` section 5) |
| Does the conversation break off when staff reach out | Observation | 〃 |
| Do they respond to the robot face | Observation | The product's premise itself |
| Does the opener work | Observation | Principle 2 |
| **Does mood drop after a recall failure** | Expression · speech | If it does, **rewrite the recovery lines** (`03` 4-4) |

> The last item matters most. It's the only way to see whether principle 3 actually works,
> and if it failed, that's not the elder's problem but **this product's problem**.

---

## 4. Pre-deployment blockers

**If even one remains, don't deploy.** These don't apply to the pilot.

| Item | Why | Source |
|---|---|---|
| Move the API key to a server | **Not applicable right now, but it's in the code.** The layers handling the elder's words (STT · understanding · face) are all Apple on-device and need no key. But `Elder/Voice/OpenAITTSClient.swift` has a path that produces **the robot's voice** with OpenAI — **an idea for a later stage, not the current track.** The default is `.apple`, and without a key or overseas-transfer consent the code reverts to `.apple` on its own (`SpeechEngine.swift:40·104·116`). The moment this path is actually switched on, key management and overseas transfer come back to life with it | `01` · `03` section 9 |
| **Consent procedures complete** | Self/guardian ✅ · voice recording ✅ (both 2026-08-17) / **separate biometric ⬜** (at stage 3 Vision) / overseas transfer — **not needed** on the current track, but `Consent.overseas` is alive in the code and serves as the lock on the TTS path above. The app locks features item by item (`App/ConsentStore.swift`) | `03` section 9 |
| **Rewrite the voice recording consent wording** | On 2026-09-01 **the microphone was changed to stay on for the whole session.** The duration of use differs from when it only took a single name — the wording is based on that time and must be rewritten. Recording files are still not kept | `03` section 9 |
| **MDM Single App Mode** | Used devices aren't eligible for ABM automatic enrolment. They must be **supervised manually with a Mac + Apple Configurator**; validate the procedure on one unit before deployment | `01` 3-2 |
| **Decide the retention period for conversation transcripts** | Health-related personal data isn't kept indefinitely | `03` section 9 |
| **1 spare unit** | Used, so there's no warranty path. On failure, swap first and repair after | `01` 3-2 |

### Items with a deadline

| Item | Deadline | Why |
|---|---|---|
| **Decide whether TrueDepth is needed** | **End of 2026** | Only the current development device (iPad Pro 11″ 1st gen) has TrueDepth. Once it retires with iPadOS 27, verifying would mean buying a new iPad Pro (`01` 5-3 · section 6) |

---

## 5. Risks

| Risk | Impact | Response |
|---|---|---|
| **STT can't understand elderly English** | The whole product is stuck | Measure before starting stage 1. If it fails, narrow it to recognising only the anchor word, or deploy while keeping staff assistance |
| **The on-device LLM stutters in 8GB RAM** | Stage-2 path changes | Go to the cloud or a 12GB device (`01` section 8). **Going cloud means overseas-transfer consent is needed again** |
| **Apple English premium isn't good enough for elders** | Re-examine the voice path | Judge in session 0. **No alternatives are kept open for now** — go with premium. If it's actually judged insufficient, reopen then. OpenAI remains in the code only for development and demo convenience, and isn't the product path |
| **62pt can't be read** | Re-select the device | In the order 72pt → 13″ (`01` section 8) |
| **Can't source 10 or more used devices** | Limits deployment scale | Go to the new-product lineup (`01` 3-2) |
| **Consent can't be obtained** | The pilot itself is impossible | Agree with the centre early. **Start this first** |
| Battery swelling | Safety issue in a care facility | Procure only 85% or above · visual check every 6 months (`01` 3-2) |

---

## 6. What to do next (in order)

1. ~~Agree consent procedures with the centre~~ — self/guardian ✅ **done (2026-08-17)**
2. **Pilot session 0** — set up the mount and measure the glyph factor first (section 3).
   **Download an Apple English enhanced or premium voice first** — without overseas-transfer consent OpenAI can't be used.
   In the same session, also measure **English 62pt 3 rows** with a ruler (the outdated-figures warning in `00_doc-map.md`)
3. ~~Start stage 0.5~~ — ✅ done
4. **Measure STT recognition accuracy** (`STT accuracy probe`) — with the in-app tool. Once 3–5 minutes are collected, decide the stage-1 engine
5. Pilot sessions 1–5 → settle the open figures in `01`·`02` from the results

> **There's no more consent to obtain.** For overseas transfer, the choice was **to make sure nothing leaves** instead of obtaining it.
> The app already has an item for biometric (face) consent, and **the two face measurement screens are locked behind this consent** —
> it's needed now to do the measurements, not something waiting for stage 3.
