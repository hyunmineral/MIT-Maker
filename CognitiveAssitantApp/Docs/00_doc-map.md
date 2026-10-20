# Doc Map

**Elder Conversation Robot (RobotForElders)** — design document structure

Last updated: September 10, 2026

---

## What this document set is

Once the deployment device was settled as the **iPad Air 5 (M1)**, the design that "looks more or less fine on any iPad"
was dropped and **restarted as a design fitted exactly to this one device**.

The previous documents (landscape 1194 × 834 · portrait 834 × 1194 canvases, based on the iPad Pro 11″ 1st gen)
are kept in `Backup/`. **Only the numbered documents below are currently valid.**

---

## Document list

| Document | Contents | Status |
|---|---|---|
| **`00_doc-map.md`** | This document | — |
| **`01_hardware-spec.md`** | Which device and why · procurement · mounting conditions | ✅ Done |
| **`02_design-criteria.md`** | Canvas · legibility · typography · gaze alignment · colour · layout skeleton | ✅ Done |
| **`03_product-design.md`** | What the product does — session structure · cognitive measurement · UI boundaries · data contract | ✅ Done |
| **`04_screen-design.md`** | Per-screen layout spec (820 × 1180 absolute coordinates) | ✅ Done |
| **`05_implementation-roadmap.md`** | Stage order · dependencies · pilot execution · pre-deployment blockers | ✅ Done |
| **`06_build-guide.md`** | From receiving it to running it — requirements · device · TestFlight · common snags | ✅ Done |
| **`07_project-reference.md`** | A map connecting code and design — modules · data model · session flow · what changes when you edit where | ✅ Done |
| **`2026-08-28_review-checkpoint.md`** | Code review results · build check · main risks | Reference |
| **`2026-08-28_project-structure-and-improvements-analysis.md`** | Structure summary · improvement tasks | Reference |
| **`2026-08-30_project-evaluation.md`** | Current product completeness · what works / what's screen-only · next steps | Reference |
| **`2026-08-30_english-conversion-work.md`** | Converting language and system to English — **execution log**. What's done and what remains | Required |
| **`2026-08-30_face-detection-measurement.md`** | Face detection · Feature Print matching · synthetic-person test numbers | Reference |
| **`2026-09-10_implementation-status-analysis.md`** | Based on the app source — what works · what's half done · what's missing · the next step | **Latest** |

### Reading order

If you're new, read `01` → `02` → `03` → `04` in order, and see `05` for what to do first.
**If you need to open the code, `07` comes first** — the module map and session flow are there.
If the goal is to build, `06` alone is enough.
**`02_design-criteria.md` is the basis for physical and visual decisions, and `03_product-design.md` the basis for product decisions.**
When creating or changing a screen, read both first.

---

## ⚠️ The app is in English, and the docs are now in English too (2026-08-30)

**The app screens and system have switched to English only.** Even if the device language is Korean it shows in English
(`CFBundleLocalizations: [en]` + root locale pinned to `en_US`). The app name is `Companion`.

**The design docs and code comments were originally kept in Korean and have since been translated into English.**
When a doc quotes an on-screen button or phrase, it is written exactly as it appears.

For details and remaining work, see the progress table in `2026-08-30_english-conversion-work.md`.

### What this conversion hasn't cleaned up yet

**The figures below are all based on Hangul glyphs (factor 0.72), so they don't apply as is to the English screen.**
English lowercase x-height is about 0.5 em, so **the same 62pt looks smaller.**

| Document | Outdated basis |
|---|---|
| `02_design-criteria.md` | 62pt · about 11 characters per line · glyph factor 0.72 · mounting distance 85 cm |
| `03_product-design.md` | 40-character line length cap (too short for English) · Personal Information Protection Act wording |
| `04_screen-design.md` | Line-break points |
| `05_implementation-roadmap.md` | The STT stage-1 gate is the Boseong dialect (the app is `en-US`) |

**Keep the 3-line invariant, but the character counts must be re-measured.** Until measured with a ruler on the device,
don't cite the numbers in the table above as evidence for the English screen.

---

## Settled key figures

Values you need to know without reading every document.

| Item | Value | Basis |
|---|---|---|
| Deployment device | **iPad Air 5 (M1) 10.9″** · used/refurbished | `01` section 1 |
| Canvas | **820 × 1180** native (scale 1.0) | `02` section 2 |
| Robot line | **62pt** (glyph 8.59 mm) | `02` section 4 |
| Mounting distance | **Target 70 cm · max 85 cm** | `01` 4-1 · `02` section 1 |
| Eye centre y | **280pt** (gaze error 4.4°) | `02` section 5 |
| Side margins | 48pt (content width 724pt) | `02` section 2 |
| Base spacing unit | 8pt | `02` section 2 |
| One session | **18 minutes** (including 8-minute delayed recall) | `03` section 3 |
| Choice buttons | **Staff UI** · bottom panel · 20pt | `03` section 5 |
| Line length cap | **40 characters** (beyond that it becomes 4 lines and the screen breaks) | `03` section 8 |
| Form of address | **`Mr.`/`Mrs.`/`Ms.` + surname.** First name only after permission | `03` section 3 |
| Next to start | **Consent agreement with the centre → pilot session 0 → memory store** | `05` section 6 |

---

## ⚠️ What was corrected in this redesign

**The legibility calculations in the previous documents were wrong.** They treated the font size (pt) as the physical height
of the characters, but actual Hangul glyphs are about **0.72×** the em box.

| | Before (wrong) | After correction |
|---|---|---|
| Physical height of a 52pt line | 9.8 mm | **7.2 mm** |
| Distance maintaining 30 arcminutes | 1.12 m | **83 cm** |

Because of this correction, **lines were raised to 62pt and the mounting distance requirement tightened to 85 cm.**
Details in `02_design-criteria.md` section 1.

> **The 0.72 factor itself hasn't been measured yet.** It must be calibrated by measuring the screen with a ruler
> in the pilot, and bundling Noto Sans KR as the font would change the value.

---

## Three principles (these lines aren't crossed even if the docs change)

1. **Don't test, converse** — never show questions, scores or timers on the elder's screen.
   All metrics go only to staff screens and after-the-fact reports.
2. **Old memories fuel the conversation** — the session opener always starts with 'that story from last time'.
3. **Missing an answer isn't failure** — when recall fails, the robot fills in the answer and moves on.
   Failure is only recorded quietly.

This redesign added one more.

4. **Elders don't touch the screen** — trembling hands and dry skin often make capacitive touch fail.
   All elder input comes only through **voice and face**. (`02` section 9)

---

## Other records in the repository

There's more to read outside `Docs/`. If it isn't written down anywhere, the next person gets lost.

| Location | What | Status |
|---|---|---|
| `README.md` | Repository landing page · how to build · source layout | Current |
| `HANDOFF.md` | Session handover — current state and next steps | Current |
| `tts-eval/NOTES.md` | Exploration of local TTS models (Qwen3 · Chatterbox) | **Finished experiment.** The deployment voice is Apple premium |
| `tts-eval/analyze.py` | Tool for measuring acoustic metrics of voice clips | Reusable |
| `Design/` | The Claude Design prototype it started from | Not kept in sync with the app |
| `Docs/site/` | Local docs site for reading these documents (Astro · port 4337) | Start with `npm run dev` |

---

## Archived documents (`Backup/`)

| File | Contents |
|---|---|
| `2026-07-27_README_old-edition.md` | The README from the landscape 1194 × 834 days |
| `2026-08-02_HANDOFF.md` / `.pdf` | Session log of the portrait switch · device deployment · OpenAI TTS integration |
| `2026-08-02_hardware-spec_M4-edition.md` | **Abandoned conclusion** (iPad Air 13″ M4). The original of the per-line alternatives · used-device review · cloud cost analysis |
| `2026-08-17_hardware-spec_Air5-edition.md` / `.pdf` | Right after the Air 5 was settled · edition **before** the legibility correction |

> Don't cite figures from archived documents as is. In particular **all the legibility and mounting-distance figures are outdated.**
