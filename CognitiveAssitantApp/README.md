# Elder Conversation Robot · iPad Face Display

An iPad app designed for an adult day care centre, where several elders take turns sitting
in the same seat. The robot recognises the face that approaches, calls the person by name, then opens that person's memory store
and **continues the previous conversation.**

Cognitive checks happen only by **planting one fact in the conversation and naturally bringing it back
a few minutes later**, with no separate test screen. The elder's screen has no questions, scores or timers.

The deployment device is fixed as an **iPad Air 5 (M1) 10.9″ · mounted in portrait**, and the screen
is drawn in absolute coordinates on an **820 × 1180** canvas.

---

## Where things stand

| Stage | Status |
|---|---|
| Stage 0 — 16 screens · fixed-script session | ✅ |
| Stage 0.5 — memory store (SwiftData, on-device) | ✅ |
| Stage 1 — STT · extracting facts from what was said | ✅ on-device (`Speech/` · `Understanding/`) |
| Stage 2 — conversation engine | 🟡 **Half.** It picks the next line, but **staff must press to send it** |
| Stage 3 — face recognition | ✅ Detection, matching and enrolment are wired to session identity. **Second-person matching is unverified** |

The robot listens, understands and picks its next move. **But it doesn't speak on its own** —
the chosen line appears as a blue dashed button on the staff panel and goes out only when staff press it.
Unverified sentences never reach the elder, and **the rate at which staff press becomes the quality metric**.
Going autonomous is the last box left for this product.

**Lines are chosen, never generated.** Free generation was pulled after three out of six on-device runs broke the safety
rules (inventing a shared past that never happened). The model only chooses a `move` and a topic
index from a closed list, and the sentence comes from a human-written template — **safety comes not from the prompt but from
the bounds checks in `ReplyPlanner.resolve`.**

---

## Four principles (constraints that run through the code)

1. **Don't test, converse** — never show questions, scores or timers on the elder's screen.
   All metrics appear only in `StaffOverlayView` and in after-the-fact reports.
2. **Old memories fuel the conversation** — the session opener always starts with 'that story from last time'.
   Without a store there is no last time. That's why stage 0.5 came before STT.
3. **Missing an answer isn't failure** — when recall fails, the robot fills in the answer and moves on
   (the Gentle assist step in `SessionScript`). The failure is only recorded quietly.
4. **Elders don't touch the screen** — trembling hands and dry skin often make capacitive touch fail.
   All elder input comes only through **voice and face**.

---

## Language — everything is in English

This is the first thing newcomers get confused about.

- **The app interface is English-only** and shows in English **regardless of the device language**
  (`CFBundleLocalizations: [en]` + the `en_US` locale pinned at the root). The home-screen name is `Companion`
- **Design docs and code comments are in English too.** (They were originally written in Korean and have been translated)
- When a doc quotes an on-screen button or phrase, it is written exactly as it appears

The form of address is **`Mr.` / `Mrs.` / `Ms.` + surname**. The first name is used only when the person has allowed it,
and that permission is a fact recorded in `Elder.invitedFirstName`, not a default
(`Sources/Models/FormOfAddress.swift`).

---

## Running

The `.xcodeproj` is not in the repository. **XcodeGen generates it from `project.yml`.**

**Requirements:** Xcode 26 or later · macOS 26 · [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The deployment target is iPadOS 17; on-device understanding and line selection
use `FoundationModels`, so **only those features run on iPadOS 26 or later** (without it, the script runs).

```bash
xcodegen generate          # project.yml → RobotForElders.xcodeproj
open RobotForElders.xcodeproj
```

To launch straight into the simulator from the command line:

```bash
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -destination 'id=<simulator UDID>' -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
xcrun simctl install <UDID> build/Build/Products/Debug-iphonesimulator/RobotForElders.app
xcrun simctl launch  <UDID> com.tictechtoe.RobotForElders
```

> **To change permission strings or the app name, edit `project.yml`.** `Resources/Info.plist` is
> a generated file that XcodeGen overwrites. Edit both, run `xcodegen generate`, and confirm with a diff.

### Tests — run without a device

88 tests · 11 suites. **Only verdicts that need no device, person or model** live here.

```bash
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPad Air (5th generation)' \
  -derivedDataPath build test

swift Tools/check-captions.swift    # check line width and line-count budget
```

**Run on the same model as the deployment device (iPad Air 5).** Screen calculations are tied to the model.

### Opening a single screen directly (DEBUG only)

The four staff screens live inside the gallery, so a person has to tap through menus. To check remotely:

```bash
xcrun simctl launch <UDID> com.tictechtoe.RobotForElders -screen 15
xcrun simctl launch <UDID> com.tictechtoe.RobotForElders -probe plan
```

---

## Three modes

The same screens are used in three contexts (`AppMode`). Switch with the small button at the bottom left.

| Mode | What |
|---|---|
| **Gallery** | Catalogue of the 16 screens. For design review — never put in front of an elder |
| **Pilot** | 980pt elder stage on top + 200pt staff panel below. Staff tap the next step |
| **Deployment** | A kiosk in front of the elder. **No staff elements on screen at all** |

The only way back from deployment mode is **pressing anywhere on the screen with two fingers for 1.5 seconds**
(`TwoFingerLongPress` → staff settings).

The 16 screens: 12 elder (resting · face recognition · greeting · first meeting · name · enrolment · last conversation ·
subtle recall check · recall conversation · gentle recovery · wrap-up · call staff) + 4 staff (roster ·
memory map · cognitive report · weekly digest).

---

## Measurement tools (Staff settings → Probes)

Screens for **measuring the numbers in the docs directly on the device**. Each consent item applies its own lock.

| Tool | What it measures | Required consent |
|---|---|---|
| `STT accuracy probe` | On-device recognition vs a human transcription. Word accuracy computed automatically | Voice recording |
| `Face detection probe` | Whether a face is caught at 70 cm · detection rate · quality | Biometrics (face) |
| `Face matching probe` | Feature Print distance to enrolled faces. Can also run against 9 synthetic people | Biometrics (face) |

**Recognition is pinned to on-device** (`requiresOnDeviceRecognition = true`).
`SFSpeechRecognizer` defaults to sending audio to Apple's servers, so left as is the elder's voice
would leave the device.

---

## Source layout

```
Sources/
├── App/                RobotForEldersApp · RootView · AppMode (3 modes) · ConsentStore (4 consents)
├── DesignSystem/
│   ├── Theme           colour · type · layout tokens (74pt lines, eye centre y=232 …)
│   ├── CSSShapes       Shapes that reproduce CSS border-radius / border-top·bottom exactly
│   ├── FaceStyle       5 robot expressions (sleep·neutral·happy·surprise·soft)
│   ├── CSSKeyframes    blink · breathe · wavebar as functions of time
│   ├── Backdrop        per-screen radial-gradient presets
│   ├── DesignCanvas    container that fits the 820×1180 canvas to the device size
│   └── TwoFingerLongPress   the only door into staff settings from deployment mode
├── Models/             SessionScript (script) · SessionViewModel (state machine) · FormOfAddress (address)
│                       MetricEngine (metric calculation — pure functions)
├── Memory/             SwiftData store — Elder · Session · Utterance · Fact · RecallAnchor
├── Speech/             STT (NameListener) · echo detection (SpeechEcho) · recognition-rate measurement
├── Understanding/      FactExtractor (what was said → facts) · ReplyPlanner (choosing the next move)
├── Vision/             face detection · Feature Print matching · resting-screen watcher (PresenceWatcher)
├── Elder/              session screen · 12 elder screens · SpeechEngine (TTS) · Voice/ (OpenAI)
├── Staff/              staff overlay · 4 staff screens · settings · 7 probes
│                       ElderDetailView (address entry) · ReportData (report calculation)
└── Gallery/            screen list (ScreenCatalog) and thumbnail gallery

Tests/                  88 tests. Run without a device
Tools/                  check-captions (line budget) · archive (TestFlight) · icon generation
```

| Folder | Link |
|---|---|
| App shell · modes · consent | [`Sources/App/`](Sources/App/) |
| Design tokens · face shapes · canvas | [`Sources/DesignSystem/`](Sources/DesignSystem/) |
| Script · state machine · metrics · form of address | [`Sources/Models/`](Sources/Models/) |
| SwiftData memory store | [`Sources/Memory/`](Sources/Memory/) |
| Speech recognition · echo detection | [`Sources/Speech/`](Sources/Speech/) |
| Fact extraction · next-move selection | [`Sources/Understanding/`](Sources/Understanding/) |
| Face detection · matching · presence | [`Sources/Vision/`](Sources/Vision/) |
| Elder screens · voice | [`Sources/Elder/`](Sources/Elder/) |
| Staff screens · settings · probes | [`Sources/Staff/`](Sources/Staff/) |
| Screen catalogue | [`Sources/Gallery/`](Sources/Gallery/) |
| Tests | [`Tests/`](Tests/) |
| Tools | [`Tools/`](Tools/) |
| Design docs | [`Docs/`](Docs/) (start with [`00_doc-map.md`](Docs/00_doc-map.md)) |

### Metrics come only from records

Three of the four metrics (recall rate · consistency · speech amount) are computed from stored records (`MetricEngine`).
**The channel through which the script could produce numbers has been removed** — previously constants were baked into the options,
so whatever staff tapped was the "measurement".

Mood is **recorded as not measurable.** Neither voice tone nor lexical sentiment is implemented.
A made-up number in the cognitive report would be a false record about a person's memory.

`Design/` is the Claude Design handoff bundle this app started from.
**It is not kept in sync with the app** — it remains only as the original prototype from before the portrait redesign.

### Why the eyes and mouth are drawn with a single shape

The original prototype draws an open eye with `background` and a smiling eye (∩) with only `border-top`.
Those are different CSS properties, so porting them as is makes expression changes jump.

`CSSBorderShape` merges the two using the property that **once the border is at least as thick as the height, the hole disappears and the shape becomes solid**.
Thanks to that, the 8 radii + 2 borders are bundled into an `AnimatableVector`
and "closed eye → open eye → smiling eye" interpolates seamlessly.

### Delayed recall is all about the delay

Asking back one minute after planting an anchor measures working memory, not delayed recall.
`RecallAnchor` records the real elapsed time, and **verdicts that fall short of 6 minutes — 75% of the standard interval (8 minutes) —
are recorded but excluded from the recall rate.**
The remaining time shows as a countdown on the staff panel, so nobody needs to watch a clock.

### On-device only

Face embeddings are biometric data, and conversation transcripts and cognitive metrics are health-related data.
`ModelContainer` is opened with `cloudKitDatabase: .none`, and for OpenAI TTS,
**engine selection itself is locked without overseas-transfer consent.** If consent is turned off while the engine is still
OpenAI, `enforceOverseasConsent()` reverts to the Apple voice.

---

## Docs

`Docs/00_doc-map.md` is the starting point. If you're new, read `01` → `02` → `03` → `04` in order,
and see `05` for what to do first. When you edit a `.md`, also produce a `.pdf` at the same path.

> ⚠️ **The legibility figures in `02`–`05` are based on Hangul glyphs (factor 0.72) and don't fit the English screen.**
> English lowercase x-height is about 0.5 em, so **the same 62pt looks smaller.**
> Don't cite 62pt · 40 characters · 11 characters per line as English evidence — measuring with a ruler on the device is
> the riskiest item among the remaining work.

## Fonts

No font files are bundled; the system font is used. Changing only `Font.kr(_:_:)` in `Theme.swift`
switches to a bundled font (the `kr` in the name is a leftover from the Korean-language days).
