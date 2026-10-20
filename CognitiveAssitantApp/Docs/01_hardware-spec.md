# Hardware Specification

**Elder Conversation Robot (RobotForElders) — choosing the deployment device**

Written: August 2, 2026
Revised: August 17, 2026 — **deployment device settled as the iPad Air 5 (M1).** The conclusion changed, so sections 1–7 were completely rewritten
Revised again: August 17, 2026 — **legibility calculation corrected** (glyph factor 0.72) · switch to a native 820 × 1180 canvas ·
62pt lines settled · **mounting distance requirement 1 m → 85 cm.** Sections 4 and 8 changed

> **The previous edition's (August 2) conclusion was the iPad Air 13″ (M4) at ₩1,549,000.**
> If you were referring to that edition, replace it with this document. The rationale for the earlier conclusion and the reasons
> for overturning it are kept in section 2.

---

## 1. Conclusion

| Item | Settled spec |
|---|---|
| Device | **iPad Air 5th gen (M1, 2022) · 10.9″** |
| Storage | **64GB or 256GB** (the Air 5 has only these two — no 128GB option) |
| Connectivity | **Wi-Fi** (no cellular) |
| Procurement | **Used · refurbished** (discontinued May 2024) |
| Reference prices | 64GB **₩390,000–460,000** · 256GB **₩560,000–600,000** (Korean used market, 2026-08, excluding accessories) |
| Mounting | Fixed portrait, always powered |
| **Mounting distance** | **85 cm or less — 70 cm recommended.** Not optional; it's a condition of using this device (section 4) |
| Operating mode | MDM **Single App Mode** (kiosk) |

**Separate budget required:** USB-C external speaker and microphone. See 5-2. This is not optional.

### This decision is a trade — what was given and what was gained

Of the four baselines the previous edition set, **two are given up**. This is written down plainly.

| Baseline | Requirement | iPad Air 5 | Verdict |
|---|---|---|---|
| RAM | 12GB (on-device model + Vision + audio at once) | **8GB** | ✗ **Short** — mitigations in 3-1 |
| Display | LCD (avoid kiosk burn-in) | Liquid Retina IPS **LCD** | ✓ |
| Screen size | 13″ (40 arcminutes at a 1 m mount) | **10.9″** | ✗ **Short** — section 4, offset by mounting distance |
| Support lifespan | Currently sold model | **Discontinued May 2024** | ✗ **Short** — but OS lifespan is ample (3-3) |

In return, it gains four things that **couldn't be bought** in the previous edition.

| Gained | Value |
|---|---|
| **Front camera on the portrait edge** | The previous edition's biggest design constraint (old 4-1) **disappears entirely.** Mounted in portrait the camera sits at the top centre of the screen — the elder's gaze and the camera line up |
| **Apple Intelligence support** | M1 + 8GB meets the requirement. The on-device path is open |
| **Development device = deployment device** | The current development device (A12X) has to be replaced anyway (section 6). Developing on the same device as deployment changes how much the verification can be trusted |
| **About ₩1,100,000 saved per unit** | Compared with the Air 13″ (M4) at ₩1,549,000. For a 5-unit deployment, ₩5,500,000 |

**In short**, it gave up memory headroom, screen size and warranty, and bought **the right camera position, cost and development
consistency**. In this project the camera position is something money can't buy later
(in the current lineup only the iPad mini has a portrait-edge camera, and its screen is 8.3″), so the trade itself holds.

**But the three given up remain things to manage. Section 3 covers them.**

---

## 2. What overturned the previous conclusion (Air 13″ M4)

The previous edition chose "the option that holds up even when conditions get worse", because neither the mounting setup nor
the elders' vision distribution was known. That judgement was right given the information at the time.

This decision should be read as **a decision to resolve one of those unknowns by measurement**.
Run the pilot on the Air 5 to answer "can elders actually read 9.8 mm on 10.9″",
and if not, enlarge the screen then. If they can, ₩1,100,000 per unit has been saved.

**So this spec isn't "final" but "final if it passes the pilot".**
Always read the overturn conditions in section 8 alongside it.

---

## 3. How to manage the three given up

### 3-1. ⚠️ 8GB RAM — concurrency must be avoided by design

The Apple Intelligence requirement is 8GB, so **on-device "works"**.
The problem is that this app runs camera Vision · audio streaming · rendering **at the same time** as the model.
At 8GB, memory pressure pushes the model out and back in, and **responses stutter.**

That's why 12GB was the stable baseline, and that headroom is now gone.
**The only option is to make up for it by design.**

| Mitigation | Details |
|---|---|
| **Break up concurrency** | Stop Vision face recognition while the robot is speaking. Recognition results aren't needed then anyway |
| **Don't run Vision continuously** | Only at session start and topic changes, instead of every-frame detection. Face embeddings are cached |
| **Attach the on-device LLM last** | Pilot stages 0–1 (fixed script + STT) have no LLM. Memory pressure first appears in stage 2 |
| **Don't decide without measuring** | On entering stage 2, do memory profiling on this device first. If it doesn't work, go to the cloud |

> **Key point:** 8GB is no problem at all in pilot stages 0–1.
> The risk **first appears in stage 2 (conversation engine).** Until then this item can stay open.

### 3-2. ⚠️ Procuring a discontinued device — now accepting the risk the previous edition warned about

Section 3-3 of the previous edition ruled out used procurement as "the savings don't match the risk".
The Air 5 is **the best of** what that warning covered (M1 · 8GB · ample OS lifespan),
but the problems that come from being used remain.

| Risk | Response |
|---|---|
| **Battery swelling** — a safety issue in a care facility. It really happens after a few years of constant charging | **State battery health (maximum capacity) in the procurement terms.** Nothing below 85% is accepted. After deployment, visual check every 6 months (back lifting · screen raised) |
| **Spec mismatch across units** — even the same model varies unit to unit | If possible, **buy them all at once from one seller.** Apple certified refurbished takes priority if available |
| **No warranty path** — AppleCare not available | **Keep 1 spare unit in stock.** On failure, swap first and repair after, with no service interruption |
| **Activation Lock** | At purchase, confirming **iCloud signed out and reset** is mandatory. A locked device is a brick |
| **Whether MDM enrolment is possible** | Used devices aren't eligible for Apple Business Manager automatic enrolment. **Manual enrolment (Apple Configurator)** is needed, and the Single App Mode setup procedure differs in that case |

> **The last item is easy to miss.** Single App Mode is the core of running a kiosk,
> and used devices aren't in ABM, so they must be **supervised directly with a Mac + Apple Configurator**.
> Validate this procedure on one unit before deployment.

**At larger scale this calculation flips.** Up to 5 units, finding used devices of identical spec is realistic,
but matching 20 to the same condition is practically impossible. **Once a large deployment is confirmed, go back to
the new-product lineup.**

### 3-3. Support lifespan is actually not a problem

It's a discontinued device, but **with an M1 chip the OS lifespan is generous.** That's the decisive difference from the
used A13 · A14 devices reviewed in section 3-3 of the previous edition.

| Device | Chip | iPadOS 27 | Expected remaining lifespan |
|---|---|---|---|
| Current development device (Pro 11″ 1st gen) | A12X | **✗ Support ends** | **None — end of 2026** |
| iPad 9th gen (2021) | A13 | ✓ (possibly the last) | 1–2 years |
| **iPad Air 5 (2022)** | **M1** | **✓** | **At least 3–4 years** |

The floor for Apple Intelligence support is M1, so as long as Apple maintains on-device AI features
it will be hard to drop M1. **From a security-update standpoint the Air 5 is a safe bet.**

---

## 4. ⚠️ The screen is 10.9″ — mounting distance is now part of the spec

This section is the most important in this revision.

> **⚠️ Corrected 2026-08-17.** The first edition of this section **treated the font size (pt) as the physical height of the characters**.
> Actual Hangul glyphs are about **0.72×** the em box. The figures below reflect that factor and are
> **28% smaller** than the first edition. The calculation basis and verification method are in `02_design-criteria.md` section 1.
> **The conclusion (Air 5 settled) doesn't change, but the mounting distance requirement tightens from 1 m → 85 cm.**

> **⚠️ Corrected again 2026-08-31 — the English conversion invalidated this section's figures again.**
> The 0.72 above is **the Hangul glyph factor**. When the screen switched to English only on 2026-08-30,
> the arcminute values in 4-1 · 4-2 below all lost their basis. Latin lowercase x-height is
> only **0.5176** em, so **the same 62pt looks 28% smaller.**
>
> | 62pt line | 70 cm | 85 cm |
> |---|---|---|
> | Hangul 0.72 (table below) | 42.2 arcmin | 34.7 arcmin |
> | **English lowercase `x`** | **30.3 arcmin** | **25.0 arcmin** |
>
> **Result: in English, 70 cm isn't "1.2× the target with headroom" but the absolute lower bound,
> and the 85 cm maximum doesn't hold.** This isn't a matter of changing the mounting distance —
> keep 70 cm as is, but **raise lines from 62pt → 72pt** to restore the original design intent.
> The full calculation · English per-distance factors · line-length measurements are in **`02_design-criteria.md` section 1**.
>
> **The tables in 4-1 · 4-2 below are Hangul-based. Don't cite them as evidence for the English screen.**
> The em ratios are macOS-measured proxies, so they must be settled by measuring the mm of `H` · `x`
> with a ruler on the device (`HANDOFF.md` section 0 ①).


The canvas was switched to **a native 820 × 1180, 1:1 with the Air 5 logical resolution**, so the scale is 1.0 and
there's no letterboxing. **pt values are the real size.**

```
1pt = 25.4 ÷ 132 = 0.19242mm          (264ppi @2x → 132pt per inch)
glyph height = pt × 0.19242 × 0.72 = pt × 0.13854 mm
visual angle (arcmin) = glyph height (mm) ÷ distance (mm) × 3437.75
```

**Lines are settled at 62pt → glyph 8.59 mm.** That's 19% up from the earlier 52pt,
and the rationale is in 4-2 below.

### 4-1. Converted to visual angle — 85 cm is the limit

What the eye takes in isn't the physical height but **the visual angle**.
The comfortable reading floor for presbyopia is **30 arcminutes**, and the practical target for a group including low vision is **35 arcminutes**.

| Mounting distance | 62pt line (8.59 mm) | Verdict |
|---|---|---|
| 50 cm | 59 arcmin | Ample headroom |
| **70 cm** | **42 arcmin** | **Recommended — 1.2× the target** |
| **85 cm** | **35 arcmin** | **Practical limit** |
| 98 cm | 30 arcmin | Absolute floor |
| 150 cm | 20 arcmin | **Hard to read** |

**So the maximum mounting distance is 85 cm, and the target is 70 cm.**
It works when placed on a table right in front of a seated elder.
**Setups for standing conversation or placement across a bed don't work with this device.**

> The previous edition chose the 13″ that "holds up when things get worse" because the mounting setup was undecided.
> Having chosen the Air 5, **the mounting distance must be pinned down first and operated within.**
> State **"screen-to-eye distance 85 cm or less, target 70 cm"** in the mount design requirements.

### 4-2. Screen size compensated in code — lines raised to 62pt

The canvas is absolute, so **enlarging the line font enlarges the physical size directly.**
In the corrected calculation, the earlier 52pt is 35 arcminutes at 70 cm — **sitting exactly on the target line** with no headroom.
So it was **raised to 62pt and settled** (`02_design-criteria.md` section 4).

| Line font | Glyph height | Distance holding 35 arcmin | Distance holding 30 arcmin |
|---|---|---|---|
| 52pt (before) | 7.20 mm | 70 cm | 83 cm |
| **62pt (settled)** | **8.59 mm** | **85 cm** | **98 cm** |
| 72pt | 9.98mm | 98cm | 1.14m |

**Why not raise it further to 72pt:** only 10 characters fit per line in the 724pt usable width.
Most lines would become 4 lines, the vertical budget would overflow, and the trap below would **actually make it smaller.**

#### ⚠️ Enlarging only the font cancels out the effect

`FitToHeight` **shrinks everything as a whole** when content exceeds the stage height.
Enlarging the line font overflows the stage, then `FitToHeight` shrinks everything and **the net effect disappears.**
At worst the lines get bigger but the face gets smaller, making the screen worse.

That's why the vertical budget was reworked when going to 62pt
(`02_design-criteria.md` section 7 has the height allocation per element). **Lines to hold:**

1. **Lines are at most 3 rows.** The moment it becomes 4 it overflows → constrain the conversation engine output to 40 characters
2. Solve the memory card **within 160pt**
3. **Don't put a `Spacer` inside `FitToHeight`**

**Whether it needs to go bigger is for the pilot to answer.** Measure at 62pt first.

---

## 5. Constraints that come with the spec — apply before designing the mount

### 5-1. ✓ The front camera is on the portrait edge — the previous edition's constraint is resolved

Apple spec wording: `12MP Ultra Wide front camera, 122° field of view, Center Stage`
**Located on the portrait (short) edge** — the camera moved to the landscape edge only from the 2024 M2 Air.

Mounted in portrait, the camera sits at **the top centre of the screen**. When the elder looks at the robot's eyes,
gaze and camera nearly coincide. **An ideal arrangement for this project, and
a condition that can't be bought in currently sold models other than the iPad mini (8.3″).**

The "decide whether the camera goes left or right" · "correct face recognition framing" that section 4-1 of the previous edition required
**are no longer needed.** The mount design and the Vision code both get simpler.

### 5-2. ⚠️ Speakers and microphones are still not enough

Apple spec wording: `Landscape stereo speakers`, `Dual microphones`.

The stereo speakers are **landscape-oriented**, so mounted in portrait they split top and bottom.
For elders with reduced hearing + a noisy adult day care environment, they aren't enough.

**Always include a USB-C external speaker and microphone in a separate budget.** This stays the same even if the device changes.

> However, **confirm by measurement** in the pilot what the previous edition asserted as "required".
> If the built-in speakers are enough, the per-deployment cost drops again.

### 5-3. ⚠️ No TrueDepth — decide before retiring the development device

The Air 5 has **Touch ID (power button)** and **no TrueDepth camera.**
In the current lineup only the iPad Pro has TrueDepth.

If anti-spoofing (blocking photo tricks) or low-light robustness becomes a requirement, this device can't do it.
The current design assumes RGB-based face embeddings from `Vision`, so **it isn't needed now.**

> **⚠️ This item has a deadline.** The current development device (Pro 11″ 1st gen) has TrueDepth.
> Before retiring it, **decide whether depth data is needed**.
> After retirement, verifying it would mean buying a new iPad Pro.

### 5-4. Aspect ratio · brightness

- The canvas was switched to **native 820 × 1180**, so the aspect ratio matches exactly —
  **scale 1.0 · zero letterboxing.** Better than the previous edition (Air 13″, 35pt black bands on each side).
- Brightness **500 nits**. Enough under indoor lighting.
  **Avoid mounting by a window with direct sunlight** — less headroom than the latest models (600–1000 nits).

### 5-5. Operating conditions

- **Constant power** needed.
- The kiosk uses MDM **Single App Mode.** It returns to the app automatically after reboots, OS updates and battery drain.
  **But used devices need manual supervision — see the last item in 3-2.**
- Guided Access has to be set by hand every time, so it's unsuitable for continuous operation. It's enough for short demos.

---

## 6. The current development device — replacement gets solved

**Hojun's iPad** — `iPad8,1` (iPad Pro 11″ 1st gen, 2018, A12X), iPadOS 26.5

**iPadOS 27 drops all A12 · A12X devices.** Announced at WWDC in June 2026, due out at year end.
This development device is among them.

This decision **also solves the development device replacement.** Using the Air 5 as both deployment and development device:

- Verification happens under **exactly the same conditions** as deployment — screen size, RAM and camera position are all the same
- **Apple Intelligence on-device testing**, impossible on the A12X, opens up
- No separate development device budget is needed

### What can be done only on this device before it retires

Finish the following before the replacement point (iPadOS 27 release, end of 2026).

1. **Decide whether TrueDepth is needed** (5-3). After retirement the means to verify it is gone.
2. **Capture rendering snapshots at scale 1.0.** This device's canvas and resolution match exactly.
   It becomes the reference for telling whether something that looks odd on the Air 5 (0.983) is due to scaling or to code.

---

## 7. Purchase list

| Item | Spec | Quantity | Unit price |
|---|---|---|---|
| **iPad Air 5 (M1)** | **64GB or 256GB · Wi-Fi · used/refurbished** | As many as deployed | **₩390,000–600,000** |
| **iPad Air 5 (M1) — spare** | Same spec | **1** | Same |
| USB-C external speaker | For elders' hearing | 1 per device | Estimated separately |
| USB-C external microphone | Far-field pickup | 1 per device | Estimated separately |
| Portrait mount | Must guarantee **eye-to-screen 1 m or less** (4-1) | 1 per device | Estimated separately |
| Constant-power adapter | USB-C | 1 per device | — |
| MDM subscription | For Single App Mode | — | Estimated separately |
| **Mac for Apple Configurator** | Manual supervision of used devices (3-2) | 1 (existing equipment OK) | — |

### Storage — 64GB is enough

What the app uses is the voice cache (13 lines of mp3, a few MB) · face embeddings · memory graph · conversation logs,
**a few hundred MB all together**. The Apple Intelligence on-device model is provided by the OS,
so the app doesn't bundle it. **64GB doesn't block the on-device path.**

> **If you plan to keep original conversation audio long term, go with 256GB.**
> Unlike text logs, audio accumulates fast.
> The price difference is around ₩150,000, so if you can't decide, 256GB is the safe choice.

### Procurement checklist

- [ ] Battery maximum capacity **85% or higher**
- [ ] iCloud signed out · Activation Lock released
- [ ] No back lifting · screen raised (signs of battery swelling)
- [ ] Model number is `iPad13,16` or `iPad13,17` (Air 5) — beware of confusing it with the Air 4 (A14)
- [ ] USB-C charging and data work

> **The last item often goes wrong in practice.** The Air 4 and Air 5 look almost identical, but
> the Air 4's chip is the A14, so **no Apple Intelligence and only 4GB RAM**. Check in Settings > General > About.

---

## 8. Conditions that overturn this decision

**This spec becomes final only after passing the pilot.** If any of the following applies, it's reconsidered.

| Condition | Outcome |
|---|---|
| **62pt (8.59 mm) can't be read in the pilot** | First try raising to 72pt (9.98 mm). The vertical budget overflows, so the memory card has to shrink. If still not enough, **move up to 13″** |
| **The mounting distance can't be kept to 85 cm or less** | If standing conversation or distant placement is a requirement, this device doesn't work → **13″** |
| **Many elders have low vision (cataracts · macular degeneration)** | 30 arcminutes isn't enough → font enlargement required; if that still fails, **13″** |
| **The on-device LLM doesn't run in 8GB** (3-1) | Go cloud-only or **move up to a 12GB device (Air M4 or later)** |
| **Deployment exceeds 10 units** | Finding identical used devices becomes impossible → **new-product lineup** (3-2) |
| **TrueDepth becomes a requirement** (5-3) | The entire Air line is out → **iPad Pro** (+ code to handle OLED burn-in) |

### Reference — where to go when moving up

The glyph height of a 62pt line when the 820 × 1180 canvas is scaled to that device.

| Line | Model | Price | Canvas scale | Line glyph | Notes |
|---|---|---|---|---|---|
| iPad Air | **13″ (M4) 128GB** | ₩1,549,000 | 1.158 | **9.95 mm** | The previous edition's conclusion. 12GB · LCD |
| iPad Air | 11″ (M4) 128GB | ₩1,249,000 | 1.000 | 8.59 mm | **Same screen as the Air 5** — the only reason to move up is RAM |
| iPad Pro | 13″ (M5) 256GB | ₩2,499,000 | 1.166 | 10.01 mm | If TrueDepth is needed. **OLED burn-in handling required** |
| iPad | (A16) 128GB | ₩749,000 | 1.000 | 8.59 mm | **No Apple Intelligence** — only if cloud is confirmed |

> Moving up to 13″ makes the glyph **16% bigger**, 8.59 → 9.95 mm.
> The distance holding 35 arcminutes grows from 85 cm → 99 cm.

> **If RAM is the only problem, go to the Air 11″ (M4)** — the screen is the same 9.8 mm as the Air 5, so
> the mounting distance constraint in section 4 stays. To solve screen and RAM together it has to be 13″.
>
> **Don't buy the iPad Pro 11″.** At ₩1,999,000 its lines are 10.0 mm,
> smaller than the Air 13″ (11.5 mm, ₩1,549,000) — more expensive and harder to see.

### Apple Intelligence support requirements (reference)

**A17 Pro or M1 or later + 8GB RAM or more**, iPadOS 18.1 or later. Judging by chip generation alone gets it wrong.

| Line | Support starts | Notes |
|---|---|---|
| iPad Pro | M1 (2021) | All later models |
| **iPad Air** | **M1 (2022, 5th gen)** | **← the chosen device is the support floor** |
| iPad mini | A17 Pro (2024, 7th gen) | No earlier mini is supported |
| Standard iPad | **None** | Even the latest A16 (11th gen, 2025) has 6GB RAM and isn't supported |

---

## 9. Still undecided

| Open issue | Impact | When it gets resolved |
|---|---|---|
| **Mounting distance · setup** | **This device only works if pinned to 85 cm or less (target 70 cm)** (4-1) | At mount design — **most urgent** |
| **62pt (8.59 mm) legibility** | If unreadable, enlarge to 72pt or 13″ (section 8) | Pilot |
| **Measuring the 0.72 glyph factor** | The basis for every legibility figure. Changes if the font changes | Pilot (`02_design-criteria.md` section 1) |
| **Are the built-in speakers enough** | If so, drop the external speaker budget (5-2) | Pilot |
| **Conversation engine on-device vs cloud** | If on-device, 8GB is the bottleneck (3-1) | On entering stage 2 |
| **Whether TrueDepth is needed** | If needed, the entire Air line is out (5-3) | **Before the development device retires (end of 2026)** |
| **Number of units deployed** | Over 10 units, used procurement becomes impossible (3-2) | Agreement with the centre |

---

## Sources

- [Apple iPad model comparison](https://www.apple.com/ipad/compare/)
- [iPad Air (5th generation) tech specs — Apple Support](https://support.apple.com/en-us/111887)
- [iPad Air tech specs](https://www.apple.com/ipad-air/specs/)
- [iPad Pro tech specs](https://www.apple.com/ipad-pro/specs/)
- [iPad Air prices (South Korea)](https://www.apple.com/kr/shop/buy-ipad/ipad-air)
- [iPad Air 5th gen used prices — Danawa](https://m.danawa.com/product/product.html?code=18410876)
- [iPad Air 5 used market prices — Joongna](https://web.joongna.com/search/%EC%95%84%EC%9D%B4%ED%8C%A8%EB%93%9C%20%EC%97%90%EC%96%B45)
- [iPad Air 5 M1 256GB refurbished prices — DealNews](https://www.dealnews.com/Refurb-Apple-iPad-Air-5-M1-256-GB-Wi-Fi-10-9-Tablet-for-394-free-shipping/21969823.html)
- [Camera moves to the landscape edge from the 2024 iPad Air — TechCrunch](https://techcrunch.com/2024/05/07/apple-finally-places-front-camera-on-ipad-on-the-landscape-edge-like-it-should-be/)
- [How to use Apple Intelligence — Apple Support](https://support.apple.com/en-us/121115)
- [iPadOS 27 · Apple Intelligence compatibility list — iThinkDiff](https://www.ithinkdiff.com/ipados-27-supported-ipads-apple-intelligence/)
- [iPadOS 27 drops support for many iPads — MacRumors](https://www.macrumors.com/2026/06/08/ipados-27-drops-support-for-a-wave-of-ipads/)
- [RAM by iPad model](https://techyorker.com/ipad-ram-list-how-much-memory-for-every-model/)
- [The iPad 11 doesn't support Apple Intelligence — 9to5Mac](https://9to5mac.com/2025/03/04/ipad-11-no-apple-intelligence/)
- [iOS Single App Mode guide — SimpleMDM](https://simplemdm.com/blog/how-to-use-ios-single-app-mode/)
