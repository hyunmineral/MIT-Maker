# Screen Design

**Elder Conversation Robot (RobotForElders) — 820 × 1180 absolute coordinates**

Written: August 17, 2026
Revised: September 1, 2026 — **arcminute values corrected throughout** (Hangul → English basis) · lines 62 → 74pt ·
pilot vertical skeleton rearranged · 2 errors in the face-bottom table fixed
Premises: `02_design-criteria.md` (canvas · legibility · gaze) · `03_product-design.md` (UI boundary · screen scope)

---

## ⚠️ Corrected 2026-09-01 — every arcminute value in this document was Hangul-based

When the screen switched to **English only** on 2026-08-30, every arcminute figure in this document lost its basis.
`01`·`02` were corrected on 2026-08-31, but this document had been carried over. Below is the corrected edition.

### Conversion factors

| Basis | arcmin/pt (70 cm) | 62pt | 72pt | 74pt |
|---|---|---|---|---|
| Hangul glyph 0.72 (this document's old premise) | 0.6804 | 42.2 | 49.0 | 50.3 |
| SF Pro theoretical x-height (em × 0.5176) | 0.4891 | 30.3 | 35.2 | 36.2 |
| **On-device ruler measurement (62pt → 6.1 mm)** | **0.4832** | **30.0** | **34.8** | **35.8** |

**The design basis is the measured value `0.4832`.** It differs from the theoretical value by 1.2%, and **72pt versus 74pt falls exactly
into that gap** (theoretically it passes at 35.2; measured, it falls short at 34.8). The ruler measurement is the conservative one and
is grounded in the physical object, so we followed it and **settled on 74pt**.

> arcmin = pt × 0.19242 × (x-height ÷ em) × 3437.75 ÷ 700
> `0.19242 mm/pt` comes from the iPad Air 5's 264 ppi.

### Corrected values

| Item | pt | Old value (Hangul) | **Corrected (English)** | Tier |
|---|---|---|---|---|
| Robot line | 62 → **74** | 42.2 | 30.0 → **35.8** | **A** — only at 74pt |
| Memory card title | 40 | 27.2 | **19.3** | **Short of B (22)** |
| Memory card body | 34 | 23.1 | **16.4** | **Short of B** |
| Memory card category | 22 | 15.0 | 10.6 | C — staff-facing, so irrelevant |
| 05 · 11 notice text | 26 | 17.7 | 12.6 | Deleted (section 7 ②) |
| 12 notice text | 30 | 20.4 | 14.5 | Lowered to C (section 7 ②) |

### Remaining problem — the memory card isn't tier B

**Title 40pt · body 34pt are 19.3 / 16.4 arcmin on an English basis, short of the tier-B floor of 22 arcmin.**
On a Hangul basis (27.2 / 23.1) they passed, but the switch broke that.

Recovering tier B needs **46pt for both title and body** (22 ÷ 0.4832 = 45.5), and the card height
grows from **160 → about 182pt**. But **the pilot vertical budget has only 4.15pt of slack, so
it's 17.85pt short.** Raising just the constants makes `FitToHeight` shrink the lines too,
undoing 74pt — see section 2.

**Left open.** One of three must be chosen, and it's a product decision.

1. **Drop the card from tier B** — redefine the tier so the card isn't something to "recognise" but a **secondary visual cue**
   for what the robot says aloud. No code change
2. **Find more vertical budget** — shrink the 200pt staff panel, or move the listening waveform (44 + gap 16)
   inside the card
3. **Don't put the card and a 3-row line on the same screen** — shorten lines to 2 rows at the 3 overlapping steps

---

## 0. Where this document sits

If `02` was the rules and `03` the product decisions, this document is **the coordinates**.
Every value is an absolute pt on the 820 × 1180 canvas, drawn at scale 1.0 on the deployment device.

> Checking the existing 12 screens against the new criteria in this document turned up **5 principle violations**.
> They're gathered in section 7. Of them, **the touch buttons on screen 06** are the biggest.

---

## 1. The biggest change — every elder screen becomes top-aligned

Currently `ElderScreen` places its content **vertically centred**.

```swift
VStack(spacing: spacing) { content }   // centred inside a ZStack
```

As a result the eyes land at the middle of the screen (y ≈ 400–500). By the calculation in `02_design-criteria.md` section 5,
that's **a gaze error of 7–9°** — when the elder looks at the robot's eyes, the robot is perceived as looking elsewhere.

> ### Rule: eye centre y = **280** (deployment) / **240** (pilot). Maximum 318.

The front camera sits at the top centre of the screen, so the higher the eyes, the better the gaze lines up.
**Pin the face to the very top of the screen and let the rest flow below.** Drop centre alignment.

This is room that exists because the Air 5 was chosen — if the camera were on the side (landscape edge),
however high the eyes went, the gaze would still miss to the side.

---

## 2. Vertical skeleton

### Deployment mode

```
y=0     ┌──────────────────────────────┐  ← camera (top centre)
        │                              │
  60    │         Robot face            │   eye centre y=280 · bottom at most 493
 493    │                              │
        ├──────────────────────────────┤
 560    │         Robot line            │   74pt · max 3 rows · 279.85pt
 840    │         (gap 16)              │
 856    │   Listening waveform (optional) │   44pt
 900    │         (gap 16)              │
 916    │    Memory card (optional)     │   160pt
1076    ├──────────────────────────────┤
        │         (margin 104)          │
y=1180  └──────────────────────────────┘
```

In deployment mode the stage is the full 1180, so there's **104pt of slack**. The vertical budget is only a problem in the pilot.

### Pilot mode (Wizard of Oz)

The stage is squeezed to 980 and the bottom 200pt becomes the staff panel. The eyes move up to **232**
and the gaze error actually improves to **3.7°** — there's no loss in this direction, so
this value was used first when winning back vertical budget below.

```
y=0     ┌──────────────────────────────┐
  32    │         Robot face            │   eye centre y=232 · bottom at most 445
 445    │                              │
 460    │         Robot line            │   74pt · max 3 rows · 279.85pt
 740    │         (gap 16)              │
 756    │   Listening waveform (optional) │   44pt
 800    │         (gap 16)              │
 816    │    Memory card (optional)     │   160pt
 976    │         (slack 4.15)          │
 980    ├══════════════════════════════┤  ← divider 1pt · cream 9%
        │       Staff panel 200pt       │
y=1180  └──────────────────────────────┘
```

### Pilot vertical budget — only 4.15pt of slack

The worst step is **3-row line + listening waveform + memory card**, and there are three of them
(`Continuity opener` · `Reminiscence` · `openerStep`).

| Item | Height |
|---|---|
| 3-row line | 279.85 (`88.35 × 3 + 7.4 × 2`) |
| Gap | 16 |
| Listening waveform | 44 |
| Gap | 16 |
| Memory card | 160 |
| **Required** | **515.85** |
| Budget (`980 − 460`) | 520 |
| **Slack** | **4.15** |

**Overflow doesn't fail with an error but by the lines silently getting smaller.** That's because `FitToHeight`
shrinks the whole block. In fact, when `captionTop` was 500 (budget 480) it was
shrunk to 0.914 and **74pt rendered as 67.6pt (32.7 arcmin)** — raising just the constant cancels out the net effect.

> **Don't compute line height with AppKit `NSFont`.** At 74pt it gives 87, but
> the UIKit measurement is **88.35**, 1.35pt larger. Over 3 rows that's 4pt, eating the whole slack.
> Whenever you edit around here, re-measure the **line pitch** in the simulator (measured 95.75pt on 2026-09-01).

The reason `captionTop` can't go lower than 460 is the face. The bottom of the largest expression,
`surprise`, is **445**, leaving 15pt of slack (measured 445.0 in the simulator on 2026-09-01).

### Allocation of the 200pt staff panel

| y | Height | Contents | Size |
|---|---|---|---|
| 980 | 1 | Divider `cream(0.09)` | — |
| 996 – 1024 | 28 | Step status · progress `n/N` · (right) voice status button | 13pt |
| 1040 – 1096 | 56 | **Choice buttons** (gap 12) | 20pt |
| 1112 – 1160 | 48 | Secondary control pills — `Say again` · `Start over` · `Show metrics` · `Switch to new person` | 13pt |

**The 4 metrics and the log aren't in this panel.** Pressing `Show metrics` expands them as an overlay covering the stage
(currently `StaffOverlayView`). During a session staff should be watching the elder, not graphs.

---

## 3. Shared component specs

### Robot face

The `FaceStyle` presets are used as is; this document decides **only the placement**.

```
eye centre y   = 280 (deployment) / 232 (pilot)
eye top y      = eye centre − eye height ÷ 2
mouth top y    = eye bottom + 34          (RobotFaceView's VStack spacing)
horizontal     = always centred on the canvas

face bottom y  = eye centre + eye height ÷ 2 + 34 + mouth height
```

| Expression | Eyes | Mouth | Bottom y (deployment) | Bottom y (pilot) |
|---|---|---|---|---|
| `sleep` | 120 × 16 · gap 150 · 40% | None | 288 | 240 |
| `neutral` | 110 circle · gap 140 | 120 × 22 capsule | 391 | 343 |
| `happy` | 120 × 60 ∩ · gap 140 | 170 × 80 U | 424 | 376 |
| **`surprise`** | 118 circle · gap 140 | 120 circle | **493** | **445** |
| `soft` | 120 × 46 ∩ · gap 140 | 150 × 26 capsule | 363 | 315 |

> **Corrected 2026-09-01.** This table listed `surprise` as 523 and `soft` as 372.
> Computed with the formula above and the `FaceStyle` presets they're 493 / 363, and the simulator measurement
> of the `surprise` pilot bottom, **445.0** (= 493 − 48), matched the calculation.
> **Using the wrong 523 as the basis would set the pilot `captionTop` 30pt off.**

`surprise` is the largest. In deployment the line starts at 560, leaving **67pt**; in the pilot it starts at 460, leaving
**15pt** — there's no slack, so don't make the face any bigger in this expression.

### Robot line

| Item | Value |
|---|---|
| Size | **74pt Semibold** — no exceptions (2026-09-01, previously 62pt) |
| Visual angle at 70 cm | **35.8 arcmin — tier A** (62pt fell short at 30.0) |
| Colour | `Theme.faceText` (#F7F2E7) · contrast 15.9:1 |
| Line spacing | 1.35 → line pitch **95.75pt** (measured) |
| Alignment | Centre |
| Width | 724 (side margins 48) |
| **Characters per line** | **About 21** (English. Measured 31.2–34.1pt per character) |
| **Maximum rows** | **3 rows** (block 279.85pt) |
| Required | `.fixedSize(horizontal: false, vertical: true)` — without it, it's cut to one line |

**Characters per line replaces the old "about 11 characters" (Hangul at 62pt).** Measuring English at 74pt,
`Last time you told me` (21 characters) is 655.5pt and `How did she do?` (15 characters) is 511.5pt,
or 31.2–34.1pt per character, so **21–23 characters** fit in the 724pt width. Conservatively, 21 is used.

The longest line in the current script fits within 3 rows. Stage-2 LLM output must be constrained to **63 characters** (21 × 3)
to keep this budget (`03` section 8).

#### The allowed number of rows depends on what's attached below the line

"At most 3 rows" is the value **when a memory card is attached**. Computed with the 520pt pilot budget:

| Below the line | Allowed rows |
|---|---|
| Nothing | **5 rows** |
| Listening waveform only (seed questions etc.) | **4 rows** |
| **Listening waveform + memory card** | **3 rows** |

#### The 724pt width — a wall that wasn't hit at 62pt is hit at 74pt

**Even with lines broken by `\n`, if a single row exceeds 724pt it automatically wraps once more.**
At 62pt the whole script passed, but **going to 74pt, 4 rows exceeded the width.**

| Location | Old wording | Width | Fix |
|---|---|---|---|
| Demo farewell | `I loved the orchard story.` | 755.6 | `I loved that story.` |
| Demo farewell | `Tell me about your sister` | 749.3 | `Tell me about` / `your sister next time.` |
| Hometown seed | `I'd like to know you better,` | 797.4 | `I'd like to know you.` |
| Hometown seed | `Where did you grow up?` | 753.1 | `Where did you` / `grow up?` (4 rows, no card) |
| Store opener | `Last time you mentioned` | 766.6 | `You mentioned` |

> **Interpolations (`\(name)` · `\(topic)`) must always sit alone on their own row.**
> Attached like `better, \(name).`, `Margaret Walsh` comes to 716.8pt with **only 7pt of slack**,
> and a slightly longer name wraps and exceeds the budget. Topics come from the store, so they're even riskier.

#### Checking tool

**Exceeding the width still lets the build pass; on screen it only shows up as smaller text.**
The eye can't catch it, so it's caught with numbers.

```bash
swift Tools/check-captions.swift     # exit code 1 if anything exceeds the width
```

It measures every `caption:` in the script row by row and warns when an interpolation shares a row with other text.
**If you've touched the line size or margins, run this first.**

### English subtitle

`captionEn` appears below the line at 20pt `cream(0.42)` **only in pilot and gallery modes**.
**Hidden in deployment mode** — for elders English is noise, and it eats 40pt of vertical budget.

### Memory card

Height fixed at **160**, width at most 724.

```
┌────────────────────────────────────────┐
│ ┌──────┐  Category 22pt · blue           │  Photo 112 × 112
│ │Photo │  Title 40pt · faceText          │  Side padding 24 · top/bottom 24
│ └──────┘  Body 34pt · cream(0.55)       │  Background cream(0.07) · radius 24
└────────────────────────────────────────┘  Border cream(0.15) 1pt
```

~~Title 40pt · body 34pt are **tier B** (27.2 / 23.1 arcmin at 70 cm).~~
**⚠️ Those values were Hangul-based. In English they're 19.3 / 16.4 arcmin, short of the tier-B floor of 22.**
The sizes are for **recognising** rather than reading, and the robot speaks the content aloud (`02` section 3) —
whether that premise holds is open. See "remaining problem" in the "Corrected 2026-09-01" section above.

> The current `SessionMemoryCard` has a 22pt title · 15pt body. 15pt is **10 arcmin** at 70 cm,
> completely invisible to elders. It was not a size for anything placed on an elder screen.

### Listening

`ListeningWave`, 5 bars. On elder screens, **bars 9 × 44 · gap 10**,
placed **right below the line** (gap `Theme.Layout.belowCaptionSpacing` = 16) — placed above the line it would push the line's start y,
breaking the invariant that "lines are always in the same place". **No accompanying text** (section 7 violation ②).

---

## 4. The 12 elder screens

Based on deployment-mode coordinates. In pilot mode everything shifts up by 60, and the bottom 200 is cut off.

| # | Screen | Background | Expression | Line (74pt) | Extras |
|---|---|---|---|---|---|
| 1 | Resting | `idle` | `sleep` | — | `Resting` 30pt `cream(0.28)` · y 560 |
| 2 | Face recognition | `standard25` | `neutral` | **Hello?** | **Progress bar removed** · recognition happens inwardly (section 7 ⑤) |
| 3 | Greeting | `standard25` | `happy` | Mrs. Sunja,<br>you're here! | — |
| 4 | First meeting | `standard25` | `surprise` | We haven't met.<br>Nice to meet you! | — |
| 5 | Asking the name | `standard22` | `neutral` | May I ask<br>your name? | `ListeningWave` below the line · **text removed** |
| 6 | Name confirmation · enrolment | `standard22` | `happy` | Mrs. Park Malsun,<br>is that right? | Face photo circle 220 · **buttons removed** |
| 7 | Picking up the last conversation | `standard22` | `happy` | Your granddaughter Jimin<br>you mentioned last week —<br>how did her exam go? | Memory card |
| 8 | Subtle short-term memory check | `standard22` | `neutral` | Oh, what did you say<br>you had for lunch? | **Measurement text removed** |
| 9 | Recall conversation | `standard20` | `happy` | Tell me about the<br>Boseong tea fields again | Memory card (photo) |
| 10 | Gentle recovery | `warm` | `soft` | Oh dear, I shouldn't<br>have asked.<br>It was seaweed soup. | — |
| 11 | Wrap-up | `standard22` | `happy` | I enjoyed the tea field<br>story today.<br>See you tomorrow! | **Preview moved into the line** (section 7 ④) |
| 12 | Anomaly detected | `alert` | `surprise` | I've asked a carer<br>to come. Just a moment! | `Calling staff` badge → **tier C 13pt** |

### Screen 6 — the flow after removing the touch buttons

| Who | Action |
|---|---|
| Robot | "Mrs. Park Malsun, is that right?" (74pt) + face photo circle 220 |
| Elder | **Answers by voice** — "Yes, that's right" / "No, it's Park Mansun" |
| Staff | In stage 0, presses one of the two choices in the bottom panel on the elder's behalf |

There's **no confirm button** on screen. Principle 4 (`03` section 2).

---

## 5. The 4 staff screens

Unlike the elder canvas, these are based on **a staff distance of 40 cm**, so ordinary iPadOS sizes are used.
Background `staffPaper` (#F7F5F0), text `ink` — contrast 17.4:1.

| # | Screen | Status | Layout |
|---|---|---|---|
| 13 | Today's elder roster | ✅ Pilot | **2-column** card grid. Card width (820−48×2−24)/2 = **350** · height 200 |
| 15 | Personal cognitive report | 🔶 Later | 1 column. 4 metric cards + trend graph + consultation recommendation |
| 14 | Memory map | ⬜ Stage 2 | Coordinate system **724 × 940**, origin (48, 150) — see below |
| 16 | Weekly change digest | ⬜ After deployment | 1-column list. Good news and requests alternating |

### 14 Memory map — recalculating node coordinates

The coordinate system changes from 746 × 900 → **724 × 940**, so the nodes have to move
(`x × 0.9705`, `y × 1.0444`).

| Node | Old | **New** |
|---|---|---|
| Kim Sunja (self) | (373, 430) | **(362, 449)** |
| Husband · late | (168, 165) | **(163, 172)** |
| Tea field | (582, 200) | **(565, 209)** |
| Son Sangcheol | (160, 700) | **(155, 731)** |
| Granddaughter Jimin | (572, 730) | **(555, 762)** |

`selfNode`'s x of 362 is exactly half of 724.

---

## 6. Vertical budget check

The tightest case — **pilot mode · `surprise` expression · 3-row line · memory card present.**

| Element | Height | Cumulative |
|---|---|---|
| Top margin | 40 | 40 |
| Face (`surprise` eyes 118 + 34 + mouth 120) | 272 | 312 |
| Gap | 40 | 352 |
| 3-row line (62 × 1.35 × 3) | 251 | 603 |
| English subtitle (pilot only) | 40 | 643 |
| Gap | 39 | 682 |
| Memory card | 160 | 842 |
| Slack | 138 | **980** |
| Staff panel | 200 | **1180 ✓** |

**138pt of slack.** No current screen combines the `surprise` expression with a memory card, so
in practice there's even more room. But `FitToHeight` is still needed as a safety net —
**don't put a `Spacer` inside it.**

---

## 7. Five principle violations found

The result of checking the current 12 screens against the principles in `03_product-design.md`.

### ① Screen 06 has touch buttons for elders — violates principle 4

```swift
Text("Yes, that's right").font(.kr(34, .bold)) … .background(Theme.cream)
Text("No")  .font(.kr(34, .bold)) … .strokeBorder(...)
```

It asks the elder to press the screen. **With trembling hands and dry skin, capacitive touch often
fails, and a failed touch becomes an experience of "I did something wrong".** Confirming a name is part of the conversation,
not form entry.

**Fix: delete.** The elder answers by voice; in stage 0 the staff panel choices stand in.

### ② Notice text in sizes elders can't read — pointless

| Screen | Text | Size | Visual angle at 70 cm (Hangul basis, old) | **English basis** |
|---|---|---|---|---|
| 05 | `I'm listening · Listening` | 26pt | 17.7 arcmin | **12.6 arcmin** |
| 11 | `To ask about next time · her sister's story` | 26pt | 17.7 arcmin | **12.6 arcmin** |
| 12 | `Calling staff · Staff notified` | 30pt | 20.4 arcmin | **14.5 arcmin** |

Far short of the 30-arcminute presbyopia floor. **Re-measured on an English basis it's even worse** —
this section's judgement (delete them all or move them down to staff use) still stands, and only its basis got stronger. **If they were meant for elders, they failed;
if they're for staff, there's no reason for them to be in the middle of the elder screen.**

**Fix:**
- 05 — delete the text. The `ListeningWave` waveform alone is enough (which was also the original intent)
- 11 — see section 7 ④
- 12 — make its nature as a staff/bystander display explicit and lower it to **tier C 13pt** at the bottom

### ③ Measurement jargon is exposed on the elder screen — violates principle 1

```swift
// 08 SubtleRecallScreen
Text("8 min since anchor planted · delayed recall probe")
```

The comment says "not shown on the actual elder screen", but **it actually renders.**
A case of text meant for the gallery description getting into the screen.

**Fix:** delete it from the screen and move it to the `note` in `ScreenCatalog`.

**For the same reason, the progress bar on screen 02** is removed too. A bar filled to 62% is a progress indicator,
which principle 1 forbids. The comment says "elders only read it as 'thinking'", but
then there's no reason for it to be a bar. **Replace it with the eyes' brightness breathing.**

### ④ The next-session preview exists only on screen — principle 2 doesn't work

`To ask about next time · her sister's story` on `11 Wrap-up` is **a device for building a sense of connection** and
where principle 2 is carried out. But at 26pt elders can't read it. **The intent doesn't get across.**

**Fix: the robot says it.** Remove the on-screen text and put it in the line.

```
Current  "I enjoyed the tea field story today. See you tomorrow!"        24 Korean characters
New      "I enjoyed the tea field story today.
       Next time, tell me about your sister!"                               32 Korean characters → 3 rows ✓
```

~~It fits within the 62pt 3-row budget (33 characters).~~ **The 74pt 3-row budget is 63 characters on an English basis** (section 3).

### ⑤ The robot says out loud that it didn't recognise someone — against the spirit of principle 3

The line on screen 02 was **"Uh… who are you again?"**.

It was prototype wording meant to show the flow, but if it actually came out in front of an elder,
**the robot would be telling the elder about its own recognition failure.** For someone living with memory problems,
"who are you again?" is especially sensitive, and puts pressure on them to explain themselves.

Principle 3 said recall failures are never exposed to the elder. **The same goes for the robot's own failures.**

**Fix:** change the line to **"Hello?"**. Recognition runs inwardly, and `status` ("Recognising face")
tells only staff. The result shows on the next screen by **calling the name (03) or being glad to meet them (04)**
— which also fits the original design, where calling the name doubles as feedback that recognition succeeded.

---

## 8. Code change list

| File | Change |
|---|---|
| `DesignSystem/DesignCanvas.swift` | ✅ Done — 820 × 1180 |
| `DesignSystem/Theme.swift` | ✅ Done — `Layout` · `Size` |
| `Elder/Screens/ElderScreens.swift` | Make `ElderScreen` **top-aligned + fixed eye y**. All lines use `Theme.Size.speech`. Apply the 4 violations |
| `Elder/SessionComponents.swift` | `SessionMemoryCard` to 160pt · 40/34pt. `ChoiceButton` to **staff-facing 20pt · height 56** |
| `DesignSystem/Theme.swift` | ✅ 2026-09-01 — `Size.speech` 74 · `captionTopPilot` 460 · `eyeCenterYPilot` 232 · `belowCaptionSpacing` 16 |
| `Models/SessionScript.swift` | ✅ 2026-09-01 — rewrote the 4 lines that exceeded the 724 width (section 3) |
| `Tools/check-captions.swift` | ✅ 2026-09-01 — checks line width and row-count budget |
| `Elder/SessionView.swift` | Separate stage and staff panel. Panel fixed at 200pt |
| `Models/SessionScript.swift` | Replace the 11 wrap-up line (section 7 ④) |
| `Gallery/ScreenCatalog.swift` | Move the 08 description text to `note` |
| `Staff/MemoryMapView.swift` | Coordinate system 724 × 940 · rearrange the 5 nodes |
| `Staff/RosterView.swift` | Card width 350 (2 columns) |
| `Staff/StaffOverlayView.swift` | A **toggle overlay** instead of an always-on panel |

---

## 9. Settled / open

### Settled

- Elder screens are **top-aligned.** Eye centre y = 280 (deployment) / **232** (pilot)
- Robot lines **74pt · max 3 rows · no exceptions** — 35.8 arcmin at 70 cm, tier A
- Line start y = 560 (deployment) / **460** (pilot). The pilot has only **4.15pt** of slack
- A single row of a line **never exceeds 724pt.** Interpolations sit alone on their own row (section 3)
- Allowed rows — caption only 5 · +waveform 4 · **+waveform+card 3**
- Memory card **160pt · title 40 · body 34** — ⚠️ **short of tier B on an English basis.** Open (see preamble)
- Staff panel **200pt** — status + choices only. Metrics and log are a toggle overlay
- The English subtitle is **hidden in deployment mode**
- All 4 violations applied (section 7)

### Open

| Item | When it must be decided |
|---|---|
| Session start trigger — automatic face recognition vs staff choosing from the roster | When implementing the 13 roster screen |
| Budget if a screen ever combines the `surprise` expression with a memory card | Conversation engine stage 2 |
| Automatic trigger conditions for 12 Anomaly detected | After reviewing separate sensing (on hold per `03` section 7) |
