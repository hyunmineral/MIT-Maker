# August 30, 2026 · English Conversion Task List

**RobotForElders — what's needed before switching the language and system to English**

Written: 2026-08-30 · Updated: 2026-08-30 (after executing C·D·E·F)
Premise: snapshot of the working folder. The product evaluation is in `2026-08-30_project-evaluation.md`.

It started as a task list and is now **an execution log**. Look at the progress status below first.

---

## Progress status (as of 2026-08-30)

| Stage | Status | Notes |
|---|---|---|
| A Decisions | ✅ | Locale `en-US` · app name `Companion` · English-speaking personas · **form of address settled** |
| B Typography recalculation | ❌ **Not done** | English glyph arcminutes · whether to keep 62pt · the 3-row limit are unchanged. See section 2-1 — **the riskiest of what remains** |
| C System locale | ✅ | TTS `en` · STT `en-US` · dates `en_US` · Info.plist · `CFBundleLocalizations` |
| D Script · seed | ✅ | 18 statuses · 14 log tags · metric labels |
| E UI | ✅ | 12 elder screens · all staff screens · settings · 3 probes · 16-screen catalogue · CLI |
| F Remove bilingual display | ✅ | Deleted `captionEn` · `statusEn` · `showsEnglish` · `titleEn` |
| G Docs | ⚠️ Policy changed | **Docs stay in Korean.** Only quoted UI labels are aligned to English (section 6) |
| H Comments | ❌ **Not doing** | Settled as staying in Korean (section 7) |
| I Verification | ✅ | Confirmed by running on a Korean (`ko-KR`) device. Section 10 |

Execution result: **0 Korean strings visible to users** (full scan, excluding comments). 29 files changed.

---

## 0. Premise — translation alone won't do

This app is tuned to **Hangul text size · a Korean voice · Korean law · Korean personas**. Changing only the strings breaks the screens or leaves the voice in Korean.

The goal of the work is **replacing it with a single runtime language, English**. No Korean–English bilingual display. `captionEn` already exists, but it's an abridged version and mustn't be promoted as is.

~~There are about 280+ lines of Korean strings in Swift.~~ → **All replaced with English.** The only Korean left is
comments, kept intentionally (section 7).

---

## 1. What to decide before coding

| Decision | Options | Why it comes first |
|---|---|---|
| Locale | `en-US` / `en-GB` / `en-AU` | STT model, TTS voices, date format and spelling all diverge |
| Form of address | `Ms. Kim` / first name / `Mrs.` | There's no English counterpart to `eoreusin` (respected elder), and script, roster and TTS all follow it |
| Demo personas | Keep Korean personas vs replace with English-speaking ones | Names, hometowns, topics and lunch menus repeat across the script, seed and 12 gallery screens |
| Comments · docs | Convert to English / keep in Korean | If screens and system are English, leaving only comments in Korean is possible. "Everything" would include docs and comments |
| Existing device data | Delete the app and reseed / migrate | If SwiftData already has Korean names and topics, `seedIfEmpty` won't run |

**Settled (2026-08-30):**

- Locale **`en-US`** — STT · dates · TTS filter all use this value
- App name **`Companion`** (`CFBundleDisplayName`)
- Demo personas **English-speaking** — Dorothy Miller / Margaret Walsh / Robert Hayes. Applied across script, seed and staff UI
- **Comments and canonical docs stay in Korean.** Only screens and system are English
- `Docs/Backup/` isn't touched

**Form of address settled (2026-08-30) — `Mr.` / `Mrs.` / `Ms.` + surname.** First name only when the person allows it.
The traditional American form of address; the rules themselves are in `03_product-design.md` section 3.

- Someone met for the first time → `Ms. Walsh` · men → `Mr. Hayes`
- `Mrs.` **only when** marriage or widowhood is known. Otherwise `Ms.`
- Dorothy Miller is set up as having asked to be called by her first name over 8 months and 74 visits, so `Dorothy`
- Implemented in one place, `Sources/Models/FormOfAddress.swift`. Three fields added to `Elder`: `honorific` ·
  `familyName` · `invitedFirstName` (within SwiftData lightweight migration)

The permission strings (`Info.plist`) **weren't changed.** Form of address is about how the robot *calls* people,
and the permission descriptions are third-person narration, so `the person in front of the screen` still fits.

---

## 2. What has to be recalculated, not translated

### 2-1. Typography · legibility — ❌ **not done yet**

The 62pt · 40 characters · about 11 characters per line in `02_design-criteria.md` are based on **the Hangul glyph factor 0.72**.

| Item | Now (Hangul) | After switching to English |
|---|---|---|
| Glyph height | ~0.72 em (Hangul) | Lowercase x-height ~0.5. **The same 62pt looks smaller** |
| One line | About 11 characters | 6–8 words in the 724pt width. Line-break points change |
| Line limit | 40 characters / 3 rows | 40 characters is too short for English. **Keep the 3-row invariant** and re-measure the character count |
| `Font.kr` | System font → SD Gothic | SF Pro / New York. No reason for the function to still be named `kr` |
| `letterSpacing(-0.02)` | For Hangul | Re-examine tracking for English lines |

To do:

1. Recalculate the arcminutes using English capital and x-height.
2. Decide whether to keep 62pt or **raise it to 72pt** for tier A at 70 cm.
3. Check on every screen that `Theme.speechMaxHeight`, `openerStep` line breaks and `FitToHeight` don't shrink with 3 English rows.
4. Revise the glyph table and mounting-distance table in `Docs/02` on an English basis.

### 2-2. Removing the bilingual structure — ✅ done

Pilot mode shows the Korean line + a 20pt `captionEn` together (`AppMode.showsEnglish`). With English as the main text:

- `SessionStep.caption` = the English line (what TTS reads)
- `captionEn` / `statusEn` **deleted**
- `AppMode.showsEnglish` **deleted**
- The English subtitle `Text` in `SessionView` **deleted**

~~`captionEn` is currently a short subtitle, so swapping Korean and English would leave the lines thin.~~

In practice no swap was done. **The `statusEn` values were promoted to `status`** and `captionEn` was
dropped — because `caption` was already the canonical English. Without this, an English subtitle would have been
laid under the English line, and the same English would have appeared twice in the staff panel status row.

---

## 3. System locale (behaviour, not strings) — ✅ done

This group is the core of "converting the system to English". Even with the strings changed, **TTS reads English in a Korean voice**, and STT stays `ko-KR`.

### 3-1. TTS — `Sources/Elder/SpeechEngine.swift`

| Now | Change to |
|---|---|
| `language.hasPrefix("ko")` | `"en"` (to match the settled locale) |
| Yuna premium guidance | Settings → Spoken Content → Voices → **English** |
| Default rate 78% | Needs retuning for English. Keep the number for now and re-measure in the pilot |
| OpenAI `instructions` | "Slowly, for elders" → rewrite in a respectful English tone |
| Korean `statusLabel` | English / Enhanced / Premium |
| Preview `"Mrs. Sunja, you're here!"` | A new English greeting line |

Execution result: `instructions` was already English. Rather than writing a new greeting, the preview sentence
is picked from `SessionScript.allSpokenLines` — hearing actual script lines is the only way to know how it will
sound on site. The default rate of 78% was kept and will be re-measured in the pilot.

Cache: the sentence is part of the `VoiceCache` key. **The lines (`caption`) didn't change this time, so
existing caches remain valid** — only devices with mp3s left over from the Korean-line days need clearing.

### 3-2. STT — `Sources/Speech/SpeechProbe.swift` + measurement tool

| Now | Change to |
|---|---|
| `Locale(identifier: "ko-KR")` | `en-US` (or the settled locale) |
| "No Korean on-device model" | Guidance for the English dictation model |
| Settings path (Keyboard → Dictation → Korean) | Replace the wording with the English path |
| Stage-1 gate = Boseong dialect | **Elderly English · regional accents · hearing-impaired pronunciation**. Rewrite the gate sentence in the `05` roadmap itself |
| Word (eojeol) edit distance | Whitespace splitting is right for English. Only change the comment from "eojeol" → "word" |

The `SpeechSample.wordAccuracy` algorithm fits English even better. Only the locale and guidance text were changed.

Execution result: the guidance path is **Settings → General → Keyboard → Dictation**. The consent description's
"dialect recognition rate" was rewritten as **older, accented speech**.

The stage-1 gate in the `05` roadmap was also **rewritten for English on 2026-08-30** — ageing voice ·
regional accents · hearing loss · dentures · word-finding pauses. The pass criterion was changed to look at
**anchor-word recall** separately rather than overall accuracy.

### 3-3. Dates · formats

- `SessionViewModel` `Locale(identifier: "ko_KR")` + a Korean "month M, day d" date format
- `RosterView` the same
- `durationLabel` `"3 min 12 sec"` in Korean → `"3 min 12 sec"`
- `personName` `"Mrs. Kim Sunja (85)"` → the settled form-of-address rules

Execution result: dates are `en_US` + `"MMM d"` (`Jul 20`), and `durationLabel` is `3 min 12 sec`.
`personName` **was left in the `name (age)` form because the form of address was undecided** — fix it here first once the form of address is settled.

### 3-4. Info.plist · app name

**Both** `project.yml` and `Resources/Info.plist` were changed. `project.yml` was edited first,
generated with `xcodegen generate`, then diffed against the hand-written plist to confirm they're identical —
so even if the next person runs `xcodegen`, it won't revert to Korean.

| Key | Now | Work |
|---|---|---|
| `CFBundleDisplayName` | `Conversation Robot` (in Korean) | ✅ **`Companion`** |
| `NSCameraUsageDescription` | Korean | ✅ English · "kept on this device only — no photos leave the iPad" |
| `NSMicrophoneUsageDescription` | Korean | ✅ English |
| `NSSpeechRecognitionUsageDescription` | Korean | ✅ English · "Recognition runs on this device" |
| `CFBundleDevelopmentRegion` | Development language | ✅ `en` |
| `CFBundleLocalizations` | None | ✅ `[en]` — the key that **pins it to English regardless of the device language** |

### 3-5. Permission pop-ups

Apple's fixed wording follows the OS language. **The device language has to be English** for the OS part of the pop-up to be English.
Changing only the app's strings isn't enough. Setting the pilot device language to English goes on the operations checklist.

However, **everything the app draws is pinned**: `CFBundleLocalizations: [en]` declares
English as the only supported language, and `.environment(\.locale, Locale(identifier: "en_US"))` is injected at the root
so date and number formats don't follow the device region. Confirmed by running on a `ko-KR` device.

---

## 4. Product copy · personas — ✅ done

The script, seed, gallery and staff mock-ups were aligned to one set of personas. The policy that hard-coding is the contract stays
(no String Catalog — section 8).

### 4-1. Script — must be rewritten

File: `Sources/Models/SessionScript.swift`

- `caption` · `status` · `choices` · `log` · `metricUpdates.note` for every step of `known` / `stranger`
- The `openerStep(topic:)` template `"the \(topic) you mentioned last time"` (in Korean)
- The choice quote-mark rule `"…"` — `SessionViewModel.record()` tells utterances apart with `hasPrefix("\"")`, so **the quote-mark rule must be kept in English**

Tone: `aigo` (oh dear), `yeojjwo` (humble "ask"), `seongham-i eotteoke doeseyo` (honorific "what is your name") sound awkward translated literally. Re-read whether principle 3 (not making failure look like a test) holds in the English recovery lines too.

### 4-2. Seed · staff mock-up data

| Now (applied in the app) | Where it's used |
|---|---|
| Dorothy Miller · 1941 · Asheville, NC | `SeedData`, script, roster, memory map, report |
| Margaret Walsh · Des Moines, Iowa | Script stranger, seed |
| Robert Hayes · Betty Clark · Frank Sullivan | Seed, weekly digest |
| Granddaughter Emma · finals | Opener, memory card |
| peach orchard · twenty / eighteen | Recall, consistency comparison |
| tomato soup | Anchor answer |
| your sister | `nextOpenerTopic` |

`SessionViewModel.beginSession()` looks people up by `DemoPeople.known` / `.stranger`. **On already-installed apps, Korean names remain in SwiftData and `seedIfEmpty` won't run — the app must be deleted and reinstalled.**

### 4-3. The 12 elder gallery screens

File: `Sources/Elder/Screens/ElderScreens.swift`

They must be **the same sentences** as the script. Including prop text such as `PhotoPlaceholder(text: "Face photo")` (in Korean).

### 4-4. Staff UI · settings · catalogue

| File | Contents |
|---|---|
| `App/AppMode.swift` | Mode names and descriptions |
| `App/ConsentStore.swift` | Labels and descriptions for the 3 consents. **Rewrite the legal wording for an English-speaking jurisdiction too** (section 5) |
| `App/RootView.swift` | Menu |
| `Elder/SessionView.swift` | Mute voice, say again, metrics, switch person, start over, countdown |
| `Models/SessionViewModel.swift` | Meta text, toggle labels, recall log |
| `Models/SessionModels.swift` | Korean labels for the 4 metrics |
| `Memory/MemoryModels.swift` | `AnchorOutcome.label` |
| `Staff/RosterView.swift` | Status · opener source |
| `Staff/StaffOverlayView.swift` | Header. Some already in English (`NOT SHOWN TO ELDER`) |
| `Staff/StaffSettingsView.swift` | The entire settings screen |
| `Staff/SpeechProbeView.swift` | Measurement UI |
| `Elder/Voice/APIKeySheet.swift` | Key entry sheet |
| `Staff/MemoryMapView.swift` | Nodes · legend |
| `Staff/CognitiveReportView.swift` | Report cards |
| `Staff/WeeklyDigestView.swift` | 3 notices |
| `Gallery/ScreenCatalog.swift` | Titles and notes for the 16 screens. `titleEn` is already English → merge into `title` and delete `titleEn` |
| `Gallery/ScreenGalleryView.swift` | Gallery chrome |

### 4-5. Identifier names (low priority)

Not needed for behaviour. If going "all English", do it after the copy.

- `Font.kr` → `Font.app` / `Font.ui`
- The type `Elder` is already English
- `// MARK: - Elder` (in Korean) etc.

---

## 5. Personal data · consent wording

⚠️ **The labels became English, but the legal rewrite wasn't done.** The current wording is the Korean original
carried over into English (`International transfer consent` etc.), and the per-jurisdiction rewrite below **remains to be done**.
As promised, `rawValue`s weren't changed, so existing UserDefaults are preserved.

No copy-pasting. `Consent.Kind.overseas` means "overseas transfer of personal data". For an English-speaking market, typically:

- US: HIPAA (health information) · state biometric laws · the OpenAI row is international transfer
- EU/UK: GDPR special category (health, biometric)

To do:

1. Rewrite the 3 consent labels for the English-speaking jurisdiction.
2. **Don't change the `personal` / `recording` / `overseas` rawValues.** They're storage keys, so existing UserDefaults would reset.
3. Replace the Personal Information Protection Act sentences in `03` section 9 with the law of the target market.
4. Make sure the English camera/microphone/speech permission text and the settings screen descriptions don't contradict each other.

Behaviour (on-device, CloudKit off, OpenAI gate) stays the same regardless of language.

---

## 6. Docs — ⚠️ the policy changed

**Canonical docs stay in Korean.** The reader is one Korean speaker, and the purpose of the English conversion is
the **screens** that elders and staff see, not the design docs. The table below is the original plan;
only the following two items are currently in effect.

1. **UI labels quoted in docs are written exactly as the English on screen.** (Done —
   replaced the button and verdict text in `2026-08-30_face-detection-measurement.md` with English)
2. When a `.md` is edited, produce the `.pdf` too.

### Original plan (converting all docs to English) — on hold

> Below is a plan that **was not executed**. Kept only as a record.


| Output | Work |
|---|---|
| `README.md` | English. The current README is the old landscape-1194 edition, so **don't translate it; rewrite it on the current (portrait 820×1180) basis** |
| `Docs/00`–`05` | File names in English too (`00_document-map.md` etc.). Body in English |
| `HANDOFF.md` | An English handoff for the next session |
| Dated review · evaluation docs | Translate or move to Backup |
| `Docs/Backup/` | **Not translated.** Kept as the Korean originals |
| `Design/…dc.html` | The original prototype. Doesn't need to be synced with the app. Touching it is a lot of effort |
| `Tools/make_app_icon.py` | Comments only. The icon itself is a face, so it has no language |

Content in the docs that must be fixed (beyond translation):

- Glyph 0.72 · 40 characters · 11 characters per line
- Yuna · Korean STT · the Boseong dialect gate
- Overseas transfer consent
- Demo personas · place names

---

## 7. Comments — ❌ not doing it (settled)

Almost all 36 Swift files have Korean comments. **They have nothing to do with runtime, so they stay in Korean.**

- If screens and system are English, the behaviour is complete. Comments aren't visible to users.
- The people reading this code are Korean speakers, so translating comments into English would only lose the nuance
  of the long comments that carry the design rationale.
- The same goes for `project.yml` comments and Python docstrings.

The exception is **comments whose facts are wrong**. If the code changed and a comment describes the old behaviour,
rewrite it then, in Korean (e.g. `project.yml`'s "only declared for now" → Vision
actually uses the camera).

---

## 8. What not to do

- Mechanically swap `caption` and `captionEn`
- Bring String Catalog / `Localizable.strings` into this scope. For now hard-coding is the contract. Do it when multiple languages are needed
- Change the `Consent.Kind` rawValues (`personal`, `recording`, `overseas`)
- Change the UserDefaults keys (`AppMode.current`, `SpeechEngine.*`)
- Translate `Docs/Backup/`
- Deploy with the Korean OpenAI cache left in place

---

## 9. Order of work

Dependency order. Skip section 2 and just swap strings, and the layout and TTS break.

```
A. Decisions   locale · form of address · demo personas · docs scope
B. Design      English glyph arcminutes · line pt · re-settle the 3-row limit → Theme
C. System      TTS en-* · STT en-* · Info.plist · date formats · clear caches
D. Script      SessionScript + openerStep + SeedData (one set of personas)
E. UI          12 gallery screens + staff screens + settings + probes + catalogue
F. Structure   remove captionEn / statusEn / showsEnglish / titleEn
G. Docs        rewrite README + Docs 00–05 in English + PDF
H. Comments    (optional) an English pass over Swift comments
I. Verify      section 10 checklist
```

In practice **C → D → E → F were done in one go**. With no Git they couldn't be split into commits,
and splitting them breaks compilation in intermediate states — deleting `statusEn` breaks `SessionView` immediately,
so F had to happen in the same breath as E. **There's still no repository. It would be good to create one before the next big task.**

Verification was a simulator build at the end of each batch, and finally running on a `ko-KR` device.

### Size

| Batch | Estimate | Actual |
|---|---|---|
| C System | Half a day | ✅ Done |
| D+E Copy | 1–2 days | ✅ Done. 29 files |
| B Typography | Half a day + device ruler | ❌ **Remaining** |
| F Remove bilingual display | Half a day | ✅ Done |
| G Docs + PDF | 1 day | ⚠️ Policy changed — keep in Korean, replace quoted labels only |
| H Comments | Half a day – 1 day | ❌ Not doing (settled) |

Two of the three key risks are closed.

1. **English 62pt unreadable at 70 cm** — ❌ **open.** Stage B wasn't done
2. ~~TTS keeps using a `ko` voice~~ — ✅ the list itself is filtered to `en`
3. ~~Korean seed left on the device so the opener opens in Korean~~ — ✅ the seed is English. **But already-installed
   devices must delete and reinstall the app** (`seedIfEmpty` doesn't overwrite existing data)

---

## 10. Verification checklist

Checking only whether the app is in English misses things. **[x] marks what was actually confirmed on 2026-08-30.**

- [x] `xcodebuild` simulator build — 0 errors, 0 new warnings
- [x] Screens are all English **even with the device language set to `ko-KR`** (confirmed by running in the simulator)
- [x] No Korean–English bilingual display in deployment mode — the bilingual structure itself was deleted
- [x] The home-screen name is English — iOS reports `CFBundleDisplayName = Companion`
- [x] Roster dates are in the `Jul 20` format (`en_US` + `MMM d`)
- [x] 0 user-facing Korean strings in the code (full scan, excluding comments)
- [ ] Across a whole pilot session: on-screen line = sentence TTS reads = English — **needs walking through on a device**
- [ ] The Apple voice list shows only English. The Korean Yuna doesn't remain as the default
- [ ] OpenAI previews go out as English sentences
- [ ] STT measurement uses the English on-device model
- [ ] 62pt English 3 rows aren't shrunk by `FitToHeight` — **together with stage B**
- [ ] The opener opens with the seed's English `nextOpenerTopic`
- [ ] Camera/microphone/speech permission pop-ups are in English (device language English)
- [ ] Existing devices: delete and reinstall the app. No Korean seed remains

---

## 11. Full list of files touched

Everything below **has been applied** (2026-08-30). The only exception is `Sources/DesignSystem/Theme.swift`,
which wasn't touched because stage B (typography recalculation) wasn't done. 29 files were actually changed, with
`Tools/featureprint.swift` (CLI output), `Sources/Vision/*` and `Sources/Gallery/*` added on top.

### System

- `Sources/Elder/SpeechEngine.swift`
- `Sources/Speech/SpeechProbe.swift`
- `Sources/Speech/SpeechSample.swift` (comments · guidance)
- `project.yml`
- `Resources/Info.plist`

### Script · data

- `Sources/Models/SessionScript.swift`
- `Sources/Models/SessionModels.swift`
- `Sources/Models/SessionViewModel.swift`
- `Sources/Memory/SeedData.swift`
- `Sources/Memory/MemoryModels.swift` (`AnchorOutcome.label`)

### UI

- `Sources/Elder/SessionView.swift`
- `Sources/Elder/Screens/ElderScreens.swift`
- `Sources/Elder/Voice/APIKeySheet.swift`
- `Sources/App/AppMode.swift`
- `Sources/App/ConsentStore.swift`
- `Sources/App/RootView.swift`
- `Sources/Staff/RosterView.swift`
- `Sources/Staff/StaffOverlayView.swift`
- `Sources/Staff/StaffSettingsView.swift`
- `Sources/Staff/SpeechProbeView.swift`
- `Sources/Staff/MemoryMapView.swift`
- `Sources/Staff/CognitiveReportView.swift`
- `Sources/Staff/WeeklyDigestView.swift`
- `Sources/Gallery/ScreenCatalog.swift`
- `Sources/Gallery/ScreenGalleryView.swift`
- `Sources/DesignSystem/Theme.swift` (typography · `Font.kr`)

### Docs (stage G) — on hold due to the policy change

- `README.md` · `Docs/00`–`05` · `HANDOFF.md` — **kept in Korean** (section 6).
  However, the problem of `README.md` being the old landscape-1194 edition remains regardless of language.

---

## 12. Related documents

| Document | Relationship |
|---|---|
| `2026-08-30_project-evaluation.md` | The product state before the English conversion |
| `02_design-criteria.md` | Basis for glyph · 40 characters · 62pt. To be revised in the English conversion |
| `03_product-design.md` | Principles · consent · line contract. Legal wording and 40-character limit to be revised |
| `05_implementation-roadmap.md` | STT gate (Boseong dialect · Yuna). To be rewritten as an English gate |
