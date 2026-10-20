# Design Criteria

**Elder Conversation Robot (RobotForElders) — redesign for the iPad Air 5 (M1)**

Written: August 17, 2026
Premise: `01_hardware-spec.md` settled the deployment device as the **iPad Air 5 (M1) 10.9″**

---

## 0. Where this document sits

With the device settled, **we stop designing "something that looks more or less fine on any iPad"
and start again with a design fitted exactly to this one device.**

This document is that baseline. The layout of each screen (`04_screen-design.md`) and the product definition
(`03_product-design.md`) are all derived from the values set here.

| Document | Contents |
|---|---|
| `01_hardware-spec.md` | Which device and why |
| **`02_design-criteria.md`** | **← This document.** Canvas · legibility · typography · gaze · colour · layout skeleton |
| `03_product-design.md` | What the product does — screen list · conversation flow · cognitive measurement |
| `04_screen-design.md` | Per-screen layout spec |

> The previous edition (834 × 1194 canvas, based on the iPad Pro 11″ 1st gen) is in `Docs/Backup/`.

---

## 1. ⚠️ First — correcting the legibility calculation in the previous documents

This is the most important change in this redesign. **The calculation has to be fixed before the design changes.**

Previous specs **treated the font size (pt) as the physical height of the characters**.
As in "a 52pt line = 9.8 mm". **That's wrong.**

Font size is the size of the em box, and the actual glyph leaves margins above and below within it.
Hangul has no upper/lower case distinction like Latin, so it fills the em box fairly fully,
but still **about 0.72× the em size** is the actual character height (based on Apple SD Gothic Neo).

### What changes

| | Previous calculation (wrong) | After correction |
|---|---|---|
| Physical height of a 52pt line | 9.8 mm | **7.2 mm** |
| Visual angle at 70 cm | 48 arcmin | **35 arcmin** |
| Visual angle at 100 cm | 34 arcmin | **25 arcmin** |
| Distance maintaining 30 arcmin (presbyopia floor) | 1.12 m | **83 cm** |

**In other words, the previous spec's "1 m or less is fine" was optimistic.**
With the current 52pt lines, **83 cm is the limit**, and even that sits on the floor.

> **The mounting distance table in section 4 of `01_hardware-spec.md` must be updated to reflect this correction.**
> The conclusion (Air 5 settled) doesn't change, but **the mounting distance requirement tightens from 1 m → 85 cm.**

### Corrected formula — use this from now on

```
1pt = 25.4 / 132 = 0.19242 mm          (264ppi @2x → 132pt per inch)
glyph height (mm) = pt × 0.19242 × 0.72 = pt × 0.13854
visual angle (arcmin) = glyph height (mm) ÷ distance (mm) × 3437.75
```

Conversion factors by distance (arcmin = pt × factor):

| Mounting distance | Factor |
|---|---|
| 50cm | × 0.9526 |
| **70 cm (recommended)** | **× 0.6804** |
| 85 cm (maximum) | × 0.5604 |
| 100cm | × 0.4763 |

> **Settle 0.72 by measurement.** In the pilot, measure the character height directly on screen with a ruler and
> calibrate this factor. Bundling Noto Sans KR as the font changes the factor.

### ⚠️ Corrected again 2026-08-31 — the 0.72 factor above can't be used for the English screen

**On 2026-08-30 the interface switched to English only. At that moment the 0.72 in this section became invalid.**
The arcminutes in the table above and the typography table in section 4 **were all calculated assuming Hangul glyphs.**

Unlike Hangul, Latin script has different heights for upper and lower case. Measured values for SF Pro
(the `.system(size:weight:)` the code uses) at 62pt semibold:

| Glyph | em ratio | Physical at 62pt |
|---|---|---|
| Hangul (this section's assumption) | 0.72 | 8.59 mm |
| English capital `H` (cap height) | **0.7046** | 8.41 mm |
| English lowercase `x` (x-height) | **0.5176** | **6.18 mm** |

**Capitals are effectively the same as Hangul. Lowercase is the problem.** Most of each line is lowercase,
and the x-height is only 0.52 em. **The same 62pt looks 28% smaller than Hangul.**

#### What changes — 62pt lines

| Distance | Hangul 0.72 (previous description) | English lowercase 0.5176 | Verdict |
|---|---|---|---|
| **70 cm (recommended)** | 42.2 arcmin | **30.3 arcmin** | **Sits on the absolute floor of 30. Short of tier A (35)** |
| **85 cm (maximum)** | 34.7 arcmin | **25.0 arcmin** | **Doesn't hold** |

The maximum distance at which 62pt lowercase holds the standard is **tier A 35 arcmin → 60.7 cm**,
**absolute floor 30 arcmin → 70.8 cm**.

> **So in English, 70 cm isn't "a target with headroom" but the absolute floor.**
> The 1.2× headroom that `01` 4-1 put on 70 cm no longer exists, and the 85 cm maximum is invalid.

#### English factors by distance (arcmin = pt × factor)

These don't replace the Hangul factors but are **listed alongside, on a lowercase basis.** When judging whether something is readable,
look at **the lowercase column**, not capitals — when it's unreadable, lowercase breaks down first.

| Distance | Hangul 0.72 (previous) | English `H` 0.7046 | **English `x` 0.5176** |
|---|---|---|---|
| 50cm | × 0.9526 | × 0.9322 | **× 0.6848** |
| **70 cm (recommended)** | × 0.6804 | × 0.6659 | **× 0.4891** |
| 85cm | × 0.5603 | × 0.5483 | **× 0.4028** |
| 100cm | × 0.4763 | × 0.4661 | **× 0.3424** |

#### Recovering it takes 72pt → **measured with a ruler, it was 74pt (settled 2026-09-01)**

| Line size | Physical `x` | 70 cm | 85 cm | Distance holding tier A (35) | Distance holding floor (30) |
|---|---|---|---|---|---|
| **62pt (current)** | 6.18 mm | 30.3 arcmin | 25.0 arcmin | 60.7 cm | 70.8 cm |
| **72pt** | **7.17 mm** | **35.2 arcmin** | 29.0 arcmin | **70.4 cm** | 82.2 cm |
| 74pt | 7.37 mm | 36.2 arcmin | 29.8 arcmin | 72.4 cm | 84.5 cm |

~~**72pt is the value that exactly recovers tier A at 70 cm.**~~

> **The "not settled yet" item below was closed by measurement on 2026-08-31, and the conclusion flipped.**
> Measured with a ruler on the device, the 62pt lowercase `x` was **6.1 mm** (versus the SF Pro theoretical 6.18 mm in the table above).
> The factor drops `0.4891 → 0.4832`, and then **72pt is 34.8 arcmin, short of tier A.**
>
> | | Theoretical 0.4891 | **Measured 0.4832** |
> |---|---|---|
> | 62pt | 30.3 | 30.0 |
> | 72pt | 35.2 (passes) | **34.8 (short)** |
> | **74pt** | 36.2 | **35.8 (passes)** |
>
> **72 versus 74 falls exactly into this 1.2% gap.** The ruler measurement is the conservative one and is grounded
> in the physical object, so we follow it and **settled on 74pt.** For the same reason section 4 rejected 52pt,
> we don't round up to clear the floor.

#### The reason section 4 rejected 72pt doesn't apply to English

Section 4 rejected 72pt because *"only 10 characters fit per line in the 724pt width, so lines become 4 rows and `FitToHeight`
shrinks everything"*. **That rationale came from the width of Hangul characters (≈1 em).**
English glyphs are much narrower. The 23 caption lines in the current script were actually measured in SF Pro semibold:

| Size | Longest line | Lines over 724pt |
|---|---|---|
| 62pt | 670pt (54pt of slack) | **0** |
| **72pt** | 773pt | **2** — `I loved the orchard story.` · `Tell me about your sister` |
| 74pt | 794pt | 2 (the same lines) |

**The two overflowing lines are both in a single wrap-up line, and rewording it resolves them.**
In English there's no structural reason preventing a move to 72pt.

#### Not settled yet — needs measuring with a ruler

The em ratios above are **proxy values from measuring SF Pro on macOS**. They haven't been confirmed against iOS device rendering
or the optical size switch (SF Pro Text ↔ Display).

> ~~**Measure the mm of `H` and `x` directly with a ruler on the device and settle this table.**~~
> **✅ Done 2026-08-31.** `H` 8.4 mm · `x` **6.1 mm** (at 62pt). Three methods agreed —
> SF Pro calculation 8.41 / 6.18, ruler measurement 8.4 / 6.1, screen pixels 8.27 / 6.25.
> **It came out 6.1, not 6.2, which is why the conclusion became 74 instead of 72** (see above).

~~**Until then, don't cite the arcminute values in this document or `01`·`04` as evidence for the English screen.**~~

**✅ `04_screen-design.md` was corrected on 2026-09-01 too.** All three documents are English-based.
One item remains, newly exposed by `04` — **the memory card title 40pt · body 34pt are
19.3 / 16.4 arcmin on an English basis, short of tier B (22).** Recovering it needs 46pt, but
the pilot vertical budget is 17.85pt short. See "remaining problems" in the `04` preamble.


---

## 2. Canvas — 820 × 1180 native

```
iPad Air 5 (M1)   2360 × 1640 px @2x   →   logical resolution 820 × 1180 pt (portrait)
DesignSpec        820 × 1180 pt                 →   scale 1.000 · no letterboxing
```

The previous 834 × 1194 canvas was the resolution of the iPad Pro 11″ 1st gen (development device),
and on the Air 5 it ran scaled down to 0.983. **What switching to native gains:**

- **Scale 1.0** — 1pt is exactly 2px. Lines and borders don't land on half pixels
- **Zero letterboxing** — the 3pt black bands top and bottom disappear
- **Text is 1.7% larger** — at 52pt, 7.08 mm → 7.20 mm
- Calculations get simpler. Screen coordinates are real coordinates

**The cost:** on the development device (Pro 11″ 1st gen) it now appears scaled down to 0.983.
That device retires with iPadOS 27 at the end of 2026, so it's accepted.

### Base grid

| Item | Value |
|---|---|
| Canvas | 820 × 1180 |
| Base unit | **8pt** — every spacing is a multiple of 8 |
| Side margins | **48pt** |
| Content width | **724pt** |
| Corner radius | card 24pt · button 16pt · chip 999pt |

> `DesignSpec` is an absolute coordinate system. **Write new screens in 820 × 1180 absolute values too.**
> A responsive layout throws the scale out of line with existing screens.

---

## 3. Legibility tiers — what elders must "read"

Make every character big and nothing fits. **Requirements are split by role.**

The basic premise of this product is that **sound is primary and text is secondary**.
The robot speaks, and the text on screen is a secondary means of confirming that speech by eye.
So among text aimed at elders, **the only thing that must be read is the robot's line**.

| Tier | Requirement | Minimum at 70 cm | Applies to |
|---|---|---|---|
| **A — must be read** | **≥ 35 arcmin** | **52pt** | Robot lines |
| **B — must be recognisable** | ≥ 22 arcmin | 33pt | Memory card title, elder's name |
| **C — staff only** | ≥ 12 arcmin at a staff distance of 40 cm | 11pt | Status · metrics · logs · controls |

**Tier A's 35 arcminutes is the presbyopia floor (30 arcmin) plus 5 arcminutes of headroom.**
It reflects the clinical rule of thumb that 30 arcminutes isn't enough once low vision such as cataracts or macular degeneration is mixed in.

---

## 4. Type scale

The canvas scale is 1.0, so **pt values are the real size**.

| Role | Size | Weight | Glyph | 70 cm | 85 cm | Tier |
|---|---|---|---|---|---|---|
| **Robot line** | **74pt** | Semibold | 7.37 mm | **35.8 arcmin** | 29.4 arcmin | **A** |
| Elder's name (greeting) | 74pt | Bold | 7.37 mm | 35.8 arcmin | 29.4 arcmin | A |
| Memory card title | 40pt | Semibold | 3.99 mm | **19.3 arcmin** | 15.9 arcmin | **Short of B** |
| Memory card body | 34pt | Regular | 3.39 mm | **16.4 arcmin** | 13.5 arcmin | **Short of B** |
| Memory card category | 22pt | Medium | 2.19 mm | 10.6 arcmin | — | C |

> **This table was recalculated on 2026-09-01 on an English lowercase `x` basis (factor 0.4832).**
> The old Hangul-based values (line 42.2 · card 27.2 / 23.1 / 15.0 arcmin) aren't evidence.
| Staff control button | 20pt | Medium | 2.77 mm | — | — | C |
| Staff metric value | 18pt | Semibold | 2.49 mm | — | — | C |
| Staff status label | 13pt | Medium | 1.80 mm | — | — | C |
| Staff log | 11pt | Regular | 1.52 mm | — | — | C |

### Why 62pt lines were chosen

Raised **19%** from the earlier 52pt. With the corrected calculation, 52pt is 35.4 arcmin at 70 cm —
sitting exactly on the tier-A floor. No headroom at all.

Raising to 62pt **holds tier A out to 85 cm**, reaching the absolute floor (30 arcmin) at 98 cm.
It tolerates some wobble in the mounting position.

| Line size | Distance holding tier A (35 arcmin) | Distance at absolute floor (30 arcmin) |
|---|---|---|
| 52pt (before) | 70 cm | 83 cm |
| **62pt (settled)** | **85 cm** | **98 cm** |
| 72pt | 98cm | 1.14m |

> **Why not raise it further to 72pt:** only 10 characters fit per line in the 724pt width.
> Most lines would become 4 rows and eat the vertical budget, and `FitToHeight` would shrink everything,
> **actually making it smaller** (see section 7).

### Line length and line-count budget

Hangul characters are almost as wide as the em. **About 11 characters per line at 62pt** (724 ÷ 62 = 11.7).

```
"Your granddaughter Jimin you mentioned last week — how did her exam go?"   26 Korean characters → 3 lines
"Mrs. Sunja, you're here!"                                                    12 Korean characters → 2 lines
"What did you have for lunch today?"                                          13 Korean characters → 2 lines
```

**The line budget is at most 3 rows.** Line spacing 1.35 → block height `62 × 1.35 × 3 = 251pt`.

> **When the conversation engine (stage 2) is attached, this budget becomes the contract.**
> If LLM output exceeds 3 rows the screen breaks. **Constrain it to 40 characters at generation time**, or
> split it by sentence and show it in sequence when it overflows. The current fixed script all fits within 3 rows.

---

## 5. Gaze alignment — only possible on the Air 5

**The front camera is at the centre of the portrait edge.** Mounted in portrait, that's the **top centre** of the screen.
Among currently sold models only the iPad mini has this, so it's a key gain from choosing the Air 5
(`01_hardware-spec.md` 5-1).

Elders look not at the centre of the screen but at **the robot's eyes**. So **the vertical position of the eyes
determines the gaze error**.

```
gaze error (°) = atan( eye centre y (pt) × 0.19242mm ÷ mounting distance (mm) )
```

| Eye centre y | Distance from camera | Gaze error at 70 cm |
|---|---|---|
| 200pt | 38.5mm | 3.1° |
| **280pt (settled)** | **53.9 mm** | **4.4°** |
| 318pt | 61.2 mm | **5.0° ← limit** |
| 400pt | 77.0mm | 6.3° |
| 590pt (dead centre of screen) | 113.5 mm | 9.2° |

**The limit at which people feel "it's looking at me" is roughly 5°.** Beyond that the gaze
is perceived as looking past you.

> ### Design rule: the eye centre's y coordinate **never exceeds 318pt.** The settled value is **280pt**.

This rule forces the layout order — **the robot face has to be at the very top of the screen.**
Putting a staff status bar at the top as in the earlier design pushes the face down and throws the gaze off.

> **So all staff UI moves to the bottom of the screen** (section 6).
> In the previous edition (834 canvas) the camera was on the side anyway, so this optimisation was meaningless.
> **It's design room that exists because the device changed.**

---

## 6. Two modes

The same screens are used in two contexts. **The layouts aren't lumped into one.**

### Deployment mode

A kiosk placed in front of the elder. **No staff elements on screen at all.**
The physical implementation of design principle 1 (don't test, converse).

```
┌──────────────────────────────┐  y=0    ← camera (top centre)
│                              │
│         Robot face            │  60 – 520   eye centre y=280
│                              │
├──────────────────────────────┤
│         Robot line            │  560 – 811  62pt · max 3 rows
├──────────────────────────────┤
│      Memory card (optional)   │  860 – 1080
└──────────────────────────────┘  y=1180
```

### Pilot mode (Wizard of Oz)

The current approach: fixed script + TTS + staff tapping the next step.
**The bottom 200pt is given over to the staff panel.**

```
┌──────────────────────────────┐  y=0
│         Robot face            │  40 – 460   eye centre y=240
│         Robot line            │  500 – 751
│      Memory card (optional)   │  790 – 950
├══════════════════════════════┤  y=980   ← divider
│  Status · metrics · log · controls │  980 – 1180  (200pt)
└──────────────────────────────┘  y=1180
```

The elder stage has variable height, so it's wrapped in `FitToHeight`. The eye centre moves up a little
to 240pt, but the gaze error of 3.8° is actually better.

### ⚠️ Open — where pilot-mode controls are operated from

**There's a physical problem. The iPad stands facing the elder, so for staff to tap the screen
they have to block the elder's view.** Besides, if a choice label ("She did great")
is visible to the elder, it becomes the strange situation of **what they'll say being written out in advance**.

| Option | Details | Problem |
|---|---|---|
| A. Bottom panel (current) | The current approach | In the elder's field of view · staff block the view |
| B. Staff iPhone remote | Send control signals over the same Wi-Fi | Needs implementing (1–2 days) |
| C. Bluetooth remote | Only "next" with a page-turner remote | Can't choose branches |

**A decision is needed.** The point of the pilot is to see how natural the elders' responses are, so
**B is recommended** — with A, what's being observed gets contaminated.
To be settled in `03_product-design.md`.

---

## 7. ⚠️ The FitToHeight trap — always check when enlarging fonts

`FitToHeight` **shrinks everything as a whole** when content exceeds the stage height.
If you enlarge the line font and the stage overflows, **the container shrinks everything and the effect cancels out.**
At worst the lines stay the same and only the face gets smaller, making it worse.

That's why the vertical budget was reworked when going to 62pt.

**Vertical budget (pilot mode, tightest case — 3-row line + memory card present):**

| Element | Height |
|---|---|
| Top margin | 40 |
| Robot face | 420 |
| Gap | 40 |
| 3-row line (62 × 1.35 × 3) | 251 |
| Gap | 39 |
| Memory card | 160 |
| Gap | 30 |
| **Elder stage total** | **980** |
| Staff panel | 200 |
| **Grand total** | **1180 ✓** |

**It fits exactly. There's no slack.** Hold to the following:

- The moment a line **becomes 4 rows it overflows** → constrain conversation engine output to 40 characters (section 4)
- To put a photo in the memory card, solve it **within 160pt**
- **Don't put a `Spacer` inside `FitToHeight`** — the height is then always measured as the available height and
  shrinking stops working. Give spacing with `VStack(spacing:)`

---

## 8. Colour and contrast

The existing palette is kept. **Checked against presbyopia contrast criteria, there's no problem.**

| Token | Value | Use |
|---|---|---|
| `cream` | `#F2EBDC` | Text on elder screens |
| `ink` | `#0F1115` | Elder screen background · staff screen text |
| `paper` | `#EDE9E1` | Canvas background |
| `staffPaper` | `#F7F5F0` | Staff screen background |
| `blue` | `#2864F0` | Emphasis · information |
| `green` | `#1F8A5B` | Success · good |
| `amber` | `#E8C24A` | Caution |
| `red` | `#C8442E` | Warning · failure |

### Contrast ratio check

| Combination | Contrast ratio | Criterion |
|---|---|---|
| cream on ink (elder lines) | **15.9 : 1** | Passes WCAG AAA (7:1) by a wide margin |
| ink on staffPaper (staff screens) | **17.4 : 1** | Passes |
| blue on cream | 4.2 : 1 | Use only for large text (≥24pt) |

> **Elder screens are light text on a dark background (dark mode).** For presbyopia the opposite is usually
> recommended, but in this product **the robot face is the screen itself**, so a dark background is essential.
> The 15.9:1 contrast ratio compensates enough.

### Information is never conveyed by colour alone

Metric colours (green/amber/red) are **always used together with a value or wording**.
Colour vision deficiency is more prevalent among older people, and cataracts reduce discrimination of blue hues.

---

## 9. Touch targets

| Target | Minimum size |
|---|---|
| Things elders press | **None** — in this product elders don't touch the screen |
| Staff control buttons | 44 × 44pt (Apple HIG minimum) · **56pt height** recommended in practice |
| Staff screen list items | 64pt tall |

> **Not requiring touch from elders is a design premise.**
> With trembling hands and dry skin, capacitive touch commonly fails to register.
> All elder input comes only through **voice and face**.

---

## 10. Code mapping

Where the values in this document live in the code.

| Criterion | Code location |
|---|---|
| Canvas 820 × 1180 | `DesignSystem/DesignCanvas.swift` → `DesignSpec` |
| Type scale | `DesignSystem/Theme.swift` → `Theme.Type` |
| Colour tokens | `DesignSystem/Theme.swift` → `Theme` |
| Grid · spacing | `DesignSystem/Theme.swift` → `Theme.Layout` |
| Eye centre 280pt | `DesignSystem/FaceStyle.swift` · each screen |
| Mode branching | `Models/SessionViewModel.swift` → `AppMode` |

**Don't edit `.xcodeproj` directly.** `project.yml` + XcodeGen is the single source of truth.

---

## 11. Settled in this document / open

### Settled

- Canvas **820 × 1180** native, scale 1.0
- **Glyph factor 0.72** applied to legibility calculations (previous calculation corrected)
- Robot lines **62pt** — tier A held out to 85 cm
- Eye centre **y = 280pt** — gaze error 4.4°
- Staff UI goes to the **bottom**. The face takes the top
- Elders **don't touch the screen**

### Open

| Item | Where it's decided |
|---|---|
| Pilot-mode staff control method (A/B/C) | `03_product-design.md` |
| Calibrating the 0.72 glyph factor by measurement | Pilot |
| Final mounting distance (target 70 cm · max 85 cm) | Mount design |
| Whether to bundle Noto Sans KR | When the font is settled — the factor changes |
