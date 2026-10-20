# Product Design

**Elder Conversation Robot (RobotForElders)**

Written: August 17, 2026
Premises: `01_hardware-spec.md` (iPad Air 5 settled) · `02_design-criteria.md` (820 × 1180 canvas)

---

## 0. What this document decides

If `02_design-criteria.md` was **"how it should look"**, this document is **"what the product
does"**.

The current code already contains 16 screens · a session script · 4 metrics. But those are
**the result of porting the original prototype HTML to SwiftUI**, not a design that has been reviewed.
This document re-judges them.

> Of the decisions made in this document, **section 6 (elder UI · staff UI boundary) is the biggest.**
> The choice buttons the prototype put on the elder screen move to the staff UI.

---

## 1. Product definition

> **A robot face display installed in an adult day care centre or senior centre that recognises elders as they approach, calls them by name
> and continues the previous conversation.** Cognitive change is observed not through tests but **within conversation**
> and reported only to staff.

### Where this app came from

There's a kind of volunteering where students visit nursing homes and adult day care centres to talk with elders and
**spend an enjoyable time together**. This product is an extension of that volunteering — people can't go every day,
so the robot sits in that seat and naturally strikes up conversation.

The starting point governs the whole design.

- **The primary goal is an enjoyable time.** Cognitive measurement is **layered onto** that conversation, not the other way
  round. That's why principle 1 ("don't test, converse") isn't a preference but the product's identity
- What the volunteers did — calling people by name, remembering last time's story, laughing it off when someone can't remember —
  became the feature list as is (principles 2 · 3)
- **The robot doesn't replace people.** It fills the days volunteers can't come, not removes the days they do.
  The condition that staff are nearby during sessions means the same thing

### The line between early detection and diagnosis

The purpose of this app includes **noticing early signs of dementia quickly**. Yet "what it doesn't do" below
states firmly that it doesn't diagnose. That's not a contradiction but a division of roles.

| | |
|---|---|
| **What the app does** | Makes change noticeable. Recall has dropped compared with 8 weeks ago, the facts of the same story are drifting — the kind of change most easily missed by those who see the person every day |
| **What the app doesn't do** | **Put a name on** that change. The end point is always "recommend a consultation" |

> **The word "dementia" is never used in the code** (checked 2026-08-30: 0 hits for `dementia` or the Korean word for it
> across all of `Sources/`). It doesn't appear on screens or in reports either.
> It's also a condition for avoiding medical device certification, but before that it's **so that wrong words
> never reach the family**.

> The cognitive report screen (`15`) **always ends with this paragraph** (added 2026-08-30):
> *"This is not a diagnosis. The app watches for change; it does not name it. …
> Share this with the family and suggest a visit to their doctor."*
>
> **The recommendation is made in this one place only.** The `suggest a screen` on the recall card was removed —
> it read as if the card were issuing a prescription, and with recommendations coming from two places it's unclear
> which is the conclusion. **The card observes; the closing recommends.**

### Audience and environment

| Item | Value |
|---|---|
| Elders | 65 and over, including suspected mild cognitive impairment through early dementia. Presbyopia and hearing loss assumed |
| Place | **Adult day care.** Elders come during the day and go home. It's noisy and several elders take turns in the seat (settled 2026-08-30) |
| One session | **About 18 minutes** (time allocation in section 5) |
| Per day | 4–6 elders × 1 session |
| Device | Portrait mount, constant power, eye-to-screen **70 cm** (max 85 cm) |
| Facilitation | **Centre staff** are nearby during sessions (settled 2026-08-30). Neither robot nor app replaces staff |

### What it doesn't do — explicitly out of scope

- **No diagnosis.** It produces scores but not clinical diagnoses, and the screen only goes as far as "recommend a consultation".
  This is also the line that keeps it from becoming subject to medical device certification.
- **No treatment.** It isn't a cognitive rehabilitation programme.
- **Elders aren't left alone.** Fall and emergency detection aren't this product's responsibility
  (the `12 Anomaly detected` screen only goes as far as calling staff).
- **No operation is asked of elders.** No touch, buttons or menus.

---

## 2. Four principles

The first three were set by the original design document; the fourth was added in this redesign.

### 1. Don't test, converse

Questions, scores, timers and progress are **never shown on the elder screen.**
All metrics appear only on staff screens and in after-the-fact reports.

> This principle gives rise to the UI boundary in section 6. It accepts the grey zone of **"a size visible to elders but not readable"**,
> but pins that line down with the legibility tiers in `02_design-criteria.md`.

### 2. Old memories fuel the conversation

The session opener always starts with **'that story from last time'**.
Well-preserved long-term memory (hometown · children · occupation) is the key to opening conversation.

### 3. Missing an answer isn't failure

When recall fails, the robot fills in the answer and moves on. The failure is only recorded quietly.
**The moment the elder perceives the failure, this product becomes a test.**

### 4. Elders don't touch the screen

Trembling hands and dry skin often make capacitive touch fail. A failed touch
becomes an experience of "I did something wrong". All elder input comes only through **voice and face**.

---

## 3. Session structure

### Form of address — what to call people

English has no word equivalent to the Korean "eoreusin" (respected elder). With the app becoming English-only, this decision became necessary.

**Rule: `Mr.` / `Mrs.` / `Ms.` + surname. The first name only after the person allows it.**

| Situation | How to address | Basis |
|---|---|---|
| Someone met for the first time | `Ms. Walsh` | The traditional first form of address for someone born in the 1940s |
| Men | `Mr. Hayes` | Regardless of marital status |
| Women **known** to be married or widowed | `Mrs. Miller` | If unknown, keep `Ms.`. No guessing |
| Someone who asked to be called by first name | `Dorothy` | Changes only when staff record it |
| Surname unknown | The recorded full name as is | A wrong form of address is worse than none |

**Calling someone by first name is a recorded fact, not a default.** In American culture "Call me Dorothy" is
**the person's own permission** marking a closer relationship, and the app skipping that step would be rude.
For this generation in particular, being called by first name on first meeting reads as impolite.

The roster (screen `13`) shows **the name the robot actually calls** on each card —
staff must check it before seating someone. In stage 3 (face recognition) calling the name doubles as feedback that recognition
succeeded (item 3 in the table below), so if the form of address is wrong, the greeting itself fails.

Implementation: `Sources/Models/FormOfAddress.swift` · `Elder.honorific` · `.familyName` ·
`.invitedFirstName`. The rules live in this one place only.

> **Trap.** If the surname isn't entered separately, the last word of the full name is inferred as the surname.
> `Mary Van Dyke` becomes `Ms. Dyke`. When building the enrolment screen, **have staff enter the surname directly.**

When referring in the third person, both docs and code keep using `elder`. Only **direct (second-person) address** changed.

### Enrolled elders (main flow)

| # | Step | What it does | Measurement |
|---|---|---|---|
| 1 | **Resting** | Eyes closed, power saving. Reacts only to sound and movement | — |
| 2 | **Face recognition** | A 'opening its eyes and looking' effect, with no scanning UI | Recognition similarity |
| 3 | **Greeting** | Calling the name doubles as feedback that recognition succeeded | — |
| 4 | **Picking up the last conversation** | Opener from the last session's topic. Memory card shown | Continuity · speech amount |
| 5 | **Planting the anchor** | Plants one fact from today | Anchor saved |
| 6 | **Recall conversation** | Long-term memory topics. **The delay is filled here** | Consistency · speech amount |
| 7 | **Delayed recall check** | Brings back the anchor in a chatty tone | **Short-term recall rate** |
| 8 | **Gentle recovery** | Only on failure. The robot fills in the answer and moves on | Whether mood is maintained |
| 9 | **Wrap-up** | Previews the next session's opener right there | — |

**8 appears only when 7 fails.** On success it's skipped
(`SessionViewModel.pick` already behaves this way).

### Time allocation — 18 minutes

```
0:00  Recognition · greeting              1 min
1:00  Picking up the last conversation (opener)  3 min
4:00  Planting the anchor                 1 min
5:00  Recall conversation (long-term memory)  8 min   ← the stretch that fills the delay
13:00 Delayed recall check                1 min 30 s
14:30 (on failure) Gentle recovery        1 min
15:30 Wrap-up                             1 min 30 s
17:00 End · tidy up records
```

> ### ⚠️ The current script has no delay
>
> In `SessionScript.known`, planting the anchor (4) → recall conversation (5) → delayed recall (6) are **consecutive
> screens**, so in practice it asks back within seconds. That's right for a prototype meant to show
> the flow, but **delayed recall is all about the delay.** Recall before 8 minutes have passed
> isn't a short-term memory measurement.
>
> **Scheduling was implemented in stage 0.5.** Planting an anchor sets `probeDueAt = +8 min` and
> a countdown appears on the staff panel. Asking back isn't blocked, but **verdicts under 6 minutes are
> excluded from the recall rate** — values from demos or operator mistakes must not pollute the metric.

### Someone met for the first time

| # | Step | What it does |
|---|---|---|
| 1 | Resting | 〃 |
| 2 | Face recognition | Judged as not enrolled |
| 3 | **First meeting** | Not an error but a new acquaintance. Switches to a surprised expression |
| 4 | Asking the name | No keyboard. Voice only |
| 5 | Name confirmation · face enrolment | Captured automatically mid-conversation with no shutter sound; only confirmation is asked |
| 6 | Collecting a first story | Seeds of long-term memory like hometown. **Collecting the personal baseline** |
| 7 | Wrap-up | Previews hearing more of that story next time |

**No metrics are produced in the first session.** There's no earlier record to compare against.
This session's values become **that elder's baseline**.

---

## 4. Cognitive measurement — how to measure through conversation alone

This is the heart of the product. It defines how each of the four metrics is produced.

### 4-1. Short-term recall rate — anchor · delayed recall

The structure itself is the same as the MMSE's delayed recall. What differs is **what is to be remembered**.

| | MMSE | This product |
|---|---|---|
| Target | 3 words the examiner presents ("tree · car · hat") | **A fact the elder said themselves** ("seaweed soup for lunch") |
| Elder's perception | Explicitly asked to memorise | They just answered a question |
| On failure | Failed the test | **Nothing happened** |

> **An anchor must come from the elder's own speech.**
> The moment the robot says "please remember these three words", this product becomes a test,
> and principles 1 · 3 collapse together.

**Scoring**

| Verdict | Condition |
|---|---|
| Exact recall | Answers the anchor fact as is |
| Partial recall | Right category but different details ("it was some kind of soup…") |
| Recall after a hint | Recalls after the robot gives a cue |
| Not recalled | Can't recall even after a hint → **to gentle recovery** |

The delay is recorded too (`anchor #1 exact recall · delay 8 min 12 s`).
**The same verdict is worth something different if the delay is short.**

**1–2 anchors per session.** With 3 or more, asking back happens more often and the elder notices the pattern.

### 4-2. Long-term memory consistency — comparing fact drift

When the same topic recurs across several sessions, **how the facts change** is compared.

```
Existing record  "Worked in the Boseong tea fields at twenty"   (mentioned 3 times)
Today            "I worked there at eighteen"
→ 1 fact drift · comparison saved
```

**It isn't recorded as 'wrong'. It's recorded as 'changed'.**
Autobiographical memory in later life is naturally reconstructed, and the same goes for young people. What matters is
not individual mismatches but **the trend of the accumulated drift ratio**.

**Failures to recognise people are counted separately.** Not recognising a person mentioned in a recent session
("Jimin… who's that?") is a signal of a different nature from drift in old facts.
It's weighted more heavily and shown separately on the staff screen.

### 4-3. Speech amount · vocabulary

| Value | Contents |
|---|---|
| Average word count | Per response |
| TTR | type-token ratio — lexical diversity |
| Distribution by topic | Which topics make them talk more |

> **Absolute values are never compared with other elders.** Some people are naturally quiet.
> **Only change against the personal baseline** is looked at. That's why the first session collects the baseline.

Speech amount rising on recall topics is **a good sign** — it means long-term memory is alive and
motivation to converse is maintained.

### 4-4. Mood · emotional tone

Produced by combining voice tone (pitch · rate · energy) + lexical valence.

**The most important observation point is right after a recall failure.** If principle 3 actually worked,
mood shouldn't drop even after the failure. **If it did, the recovery line failed**,
and that's not the elder's problem but this product's.

### 4-5. What isn't measured

- Response speed (answer latency) — mixed up with hearing loss, pronunciation and device latency, it can't be interpreted
- A combined accuracy score — a single score soon gets used like a diagnosis
- Absolute rankings across sessions — elders aren't lined up against each other

---

## 5. Elder UI · staff UI boundary — the biggest change in this redesign

### The problem

The prototype put **the choice buttons in the middle of the elder screen** as big cream pills.
They were for staff to press on the elder's behalf in the pilot (Wizard of Oz).

This breaks two things at once.

1. **What the elder would say is written on screen in advance.** With `"She did great"` showing in large text,
   natural conversation can't be observed.
2. **Staff physically have to block the elder's view.** The iPad stands facing the elder.

### Decision

> **The choices are staff UI, not elder UI.** They move down to the bottom staff panel and are drawn at
> **tier C size (20pt or less)** from `02_design-criteria.md`.

The basis for this lies in the legibility tiers themselves.

| | Size | Elder (70 cm) | Staff (40 cm) |
|---|---|---|---|
| Robot line | 62pt | **42 arcmin — readable** | Readable |
| Staff controls | 20pt | **13.6 arcmin — not readable** | 23.8 arcmin — readable |
| Staff log | 11pt | 7.5 arcmin — not readable | 13.1 arcmin — readable |

The presbyopia floor is 30 arcminutes, so **20pt is physically unreadable at the elder's distance.**
"Visible but not readable" is how principle 1 is upheld.
The same judgement already exists in the code — see the comment on the top-bar voice menu.

### Where staff operate from

| Option | Details | Cost | Verdict |
|---|---|---|---|
| **A. Bottom panel** | Tier C size, bottom 200pt of the screen | 0 | **Adopted for pilot stage 0** |
| B. Staff iPhone remote | Send control signals over the local network | 1–2 days | **Reserve** |
| C. Bluetooth remote | "Next" only. Can't choose branches | Cheap | Rejected — branches are needed |

**Start with A.** Text size already solves the exposure problem, and staff sitting beside the elder is
a natural arrangement in adult day care. It costs nothing, so trying it first is right.

> **Condition for moving to B:** if in the pilot the elder is seen **looking at the bottom of the screen**,
> or **the elder's gaze or speech breaks off** when staff reach out, switch immediately.
> This must be observed in the pilot (section 11).

---

## 6. Three modes

```swift
enum AppMode { case gallery, pilot, deployment }
```

| Mode | Screen | User | Status |
|---|---|---|---|
| **Gallery** | Catalogue of 16 screens | Development · demos | Implemented (`ScreenGalleryView`) |
| **Pilot** | Elder stage + 200pt staff panel at the bottom | Staff (WoZ) | Implemented |
| **Deployment** | Elder stage only. **No staff UI** | Elders | Implemented (`App/AppMode.swift`) |

**The only way for staff to get in from deployment mode** is **a two-finger long press for 1.5 seconds**
anywhere on screen (`TwoFingerLongPress`). For now it opens **staff settings** (mode · consent · voice),
and session start · roster · reports will be added here later.

The mode is saved on the device. **The kiosk is switched off and on every day and also restarts for OS updates**, so
if staff had to switch back to deployment mode each time, one day it would sit in front of an elder
still on the pilot screen.

---

## 7. Reviewing the 16 screens

Separates what pilot stage 0 actually needs from what comes later. **Nothing is deleted** —
they stay in the gallery to preserve the design intent.

### Elder screens

| # | Screen | Pilot stage 0 | Notes |
|---|---|---|---|
| 1 | Resting | ✅ | |
| 2 | Approach detected · face recognition | ✅ | Stage 0 is staging only. Real Vision is stage 1 |
| 3 | Greeting — someone known | ✅ | |
| 4 | First meeting | ✅ | |
| 5 | Asking the name | ✅ | In stage 0 staff enter it on their behalf |
| 6 | Name confirmation · face enrolment | ✅ | |
| 7 | Picking up the last conversation | ✅ | **Opener — the heart of principle 2** |
| 8 | Subtle short-term memory check | ✅ | |
| 9 | Recall conversation — memory card | ✅ | |
| 10 | Gentle recovery | ✅ | **The heart of principle 3** |
| 11 | Wrap-up | ✅ | |
| 12 | Anomaly detected · call staff | ⬜ **On hold** | Fall and pain detection need separate sensing. Keep the screen only, with no automatic trigger |

### Staff screens

| # | Screen | Pilot stage 0 | Notes |
|---|---|---|---|
| 13 | Today's elder roster | ✅ | Choose who it is at session start |
| 15 | Personal cognitive report | 🔶 **Later** | There's something to see only after sessions end |
| 14 | Memory map | ⬜ **After stage 2** | Only meaningful once nodes accumulate |
| 16 | Weekly change digest | ⬜ **After deployment** | Needs several weeks of data |

---

## 8. Data contract — the slots the stage-2 conversation engine will fill

`SessionStep` is currently one line of the fixed script, but **in stage 2 it becomes the schema for LLM output.**
So fields aren't added casually now.

| Field | Type | Stage-2 constraint |
|---|---|---|
| `face` | `FaceStyle` | One of 5 presets. No free generation |
| `caption` | `String` | **40 characters or fewer.** Beyond that it becomes 4 lines and the screen breaks (`02` section 4) |
| `captionEn` | `String` | For bilingual display. Hidden in deployment mode |
| `speaks` | `Bool` | Status displays (`Resting`) aren't read aloud |
| `listening` | `Bool` | Waveform display |
| `card` | `MemoryCard?` | Only what's looked up from the memory store. **No generation** |
| `choices` | `[Choice]` | Stage 0 only. From stage 1, STT results replace them |

`metricUpdates` · `log` inside `Choice` are **measurement results**, not lines.
In stage 2 they're filled **by the measurement module, not the LLM.** Keeping the side that makes conversation separate from
the side that measures it means the model never grades the conversation it produced itself.

> ### ⚠️ Memory cards must not be generated
> `card` comes only from past session records and enrolled photos. If an LLM invented a plausible memory,
> it would **plant a memory the elder never had**. That kind of accident can't be undone.

---

## 9. Personal data

What this product handles is **sensitive data**. It's settled at the design stage.

| Data | Nature | Principle |
|---|---|---|
| Face embeddings | **Biometric data** (sensitive data under the Personal Information Protection Act) | **On-device only.** No external transfer |
| Elder names · family relationships | Personal data | On-device. Exception: mixed into lines and sent out via TTS |
| Conversation transcripts | Personal data + health-related | On-device. Retention period to be decided |
| Cognitive metrics | **Health data** | On-device. Only to staff and guardians |

**Three consents required**

1. **Self consent** — the very process of obtaining valid consent from someone with cognitive decline is contentious.
   Guardian consent is obtained alongside it.
2. **Separate biometric (face) consent** — must be separated from general personal-data consent.
3. **Overseas transfer consent** — needed as long as cloud TTS · LLMs are used.
   **On 2026-08-17 it was decided not to obtain it.** Instead the voice was settled as **Apple on-device (Yuna premium)**,
   removing the need for anything to go out at all. Making sure nothing leaves beats obtaining consent —
   especially when obtaining valid consent from someone with cognitive decline is itself contentious.
   **If a cloud LLM is used in stage 2, this judgement has to be made again.**

### Right now this product sends nothing off the device

| Data | Where it goes |
|---|---|
| Line speech synthesis | Apple on-device TTS — no transfer |
| Speech recognition (measurement) | Pinned with `requiresOnDeviceRecognition = true` — no transfer |
| Face embeddings · conversation transcripts · metrics | SwiftData, `cloudKitDatabase: .none` — no transfer |

**No API key is used either, so the "move the key to a server" blocker is gone too.**
This holds until the conversation engine is attached in stage 2.

**The app holds the consent state item by item** (`App/ConsentStore.swift`). Only checked items
unlock features — without overseas-transfer consent, choosing the OpenAI engine is locked outright, and even if bypassed
it reverts to Apple right before synthesis. The original consent forms are kept on paper by the centre, and the app holds only
a record of that fact.

> **Required before deployment:** move the API key to a server. A key embedded in a client app can in principle be extracted.
> Accept it for 1 pilot unit, but not in deployment.

---

## 10. Scope by stage

| Stage | Contents | Status |
|---|---|---|
| **Stage 0 — the robot speaks** | Fixed script + TTS + staff tap the next step | Implemented. Voice settings done too |
| **Stage 1 — the robot listens** | STT. **Korean · elderly pronunciation · South Jeolla Boseong dialect** | Not started |
| **Stage 2 — the robot thinks** | Connect the conversation engine (LLM). `SessionStep` is the contract | Not started |
| Later | Face recognition (Vision) · persisting the memory map · real metric computation · delayed recall scheduling timer | |

> **Stage 1 is the real gate.** If elderly pronunciation and dialect can't be recognised, stage-2 LLM quality
> is meaningless. Get stuck here and the whole product is stuck. **Don't take stage 1 lightly.**

---

## 11. What the pilot must answer

Measurement items deferred from `01`·`02` are gathered here too.

| Question | What changes | Source |
|---|---|---|
| **Is the 0.72 glyph factor right** | The basis for every legibility figure | `02` section 1 |
| Are 62pt lines readable | If not, 72pt or 13″ | `01` section 8 |
| Are the built-in speakers enough | External speaker budget | `01` 5-2 |
| **Do elders look at the bottom of the screen (staff panel)** | If so, switch to option B (remote) | Section 5 |
| Does the conversation break off when staff reach out | 〃 | Section 5 |
| Do they respond to the robot face | The product's premise itself | — |
| Does the opener ("last week, granddaughter Jimin…") work | Verifies principle 2 | — |
| **Does mood drop after a recall failure** | If it does, rewrite the recovery lines | 4-4 |

---

## 12. Settled / open

### Settled

- The choices are **staff UI**. Bottom panel · tier C 20pt (section 5)
- Pilot operation starts with **option A (bottom panel)**, option B (remote) in reserve
- Anchors are taken only from **the elder's own speech** (4-1)
- Metrics look only at **change against the personal baseline**. Elders aren't compared with each other (4-3)
- Memory cards are **lookup only.** No LLM generation (section 8)
- Pilot stage-0 screens are **1–11 + 13**. 12 · 14 · 15 · 16 on hold (section 7)
- Face embeddings are **on-device only** (section 9)
- The form of address is **`Mr.`/`Mrs.`/`Ms.` + surname**. First name only after the person allows it (section 3)

### Open

| Item | When it must be decided |
|---|---|
| How to implement the delayed recall scheduling timer | Stage 1 |
| Retention period for conversation transcripts | Before deployment |
| Wording of the consent procedures (self · guardian · biometric · overseas transfer) | Before the pilot — **needs agreement with the centre** |
| STT engine choice (dialect recognition) | When stage 1 starts |
| Who triggers session start (automatic recognition vs staff choice) | `04_screen-design` |
