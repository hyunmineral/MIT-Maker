# August 28, 2026 · Review Checkpoint

**RobotForElders — elder conversation robot iPad app**

Review basis: a snapshot of the files in the current working folder. This folder isn't a Git repository, so no review based on commit history was possible.

---

## 1. Current assessment

This project is a SwiftUI-based, iPad-only app. The product direction is clear.

- Tests, scores and timers aren't shown on the elder screen.
- Natural conversation proceeds with a robot face and large lines.
- Staff handle choices, metrics, settings and measurement tools on a separate screen/panel.
- The memory store is SwiftData-based and on-device only.
- The OpenAI path remains, but without overseas-transfer consent it reverts to the Apple on-device voice.

The current stage is closest to **a prototype ready to prepare pilot sessions 0–1**. It isn't a real deployment app.

---

## 2. Build check

### Command that succeeded

```bash
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/RobotForElders-build-analyze \
  build CODE_SIGNING_ALLOWED=NO
```

Result: **BUILD SUCCEEDED**

### Command that failed

```bash
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build-analyze \
  build CODE_SIGNING_ALLOWED=NO
```

Result: failed at the last step after the app bundle was created.

```text
accessing build database ".../build-analyze/Build/Intermediates.noindex/XCBuildData/build.db": disk I/O error
```

It isn't a compile error; it looks like a problem accessing the build DB in the project-internal DerivedData path. It succeeded under `/tmp`.

---

## 3. Code state

Swift source size: about **6,008 lines**.

Main structure:

| Area | Files |
|---|---|
| App entry point | `Sources/App/RobotForEldersApp.swift` |
| Mode switching | `Sources/App/RootView.swift`, `Sources/App/AppMode.swift` |
| Session state machine | `Sources/Models/SessionViewModel.swift` |
| Fixed script | `Sources/Models/SessionScript.swift` |
| Memory store | `Sources/Memory/MemoryModels.swift`, `Sources/Memory/MemoryStore.swift` |
| Elder session UI | `Sources/Elder/SessionView.swift` |
| Voice output | `Sources/Elder/SpeechEngine.swift` |
| STT measurement | `Sources/Speech/SpeechProbe.swift`, `Sources/Staff/SpeechProbeView.swift` |
| Staff screens | `Sources/Staff/` |

---

## 4. Done

- 16 SwiftUI screens.
- Design system based on the iPad Air 5 portrait canvas `820 × 1180`.
- Session flow based on a fixed script.
- Skipping the `Gentle recovery` step on successful recall.
- SwiftData store: `Elder`, `Session`, `Utterance`, `Fact`, `FactRevision`, `RecallAnchor`, `MetricSample`, `SpeechSample`.
- Session opener lookup: promised topic → last topic → long-term memory.
- Saving delayed recall anchors and excluding verdicts under 6 minutes.
- Apple/OpenAI TTS engine choice, OpenAI voice cache.
- Blocking OpenAI use without overseas-transfer consent.
- On-device STT recognition-accuracy measurement tool.
- Deployment mode: staff panel, English and switch button removed.

---

## 5. Main risks

### High — no input to advance the session in deployment mode

Related files:

- `Sources/App/AppMode.swift`
- `Sources/Elder/SessionView.swift`

In `deployment` mode the staff panel disappears. But currently the session can only be advanced with the choice buttons on the staff panel. STT, Vision and remote control aren't attached yet, so deployment mode is closer to a pure display mode than a real operating mode.

Response:

- During the pilot, use `pilot` mode as the canonical mode.
- Don't use `deployment` mode for on-site placement until STT input or remote staff control is attached.

### High — the session is created as soon as the app appears

Related files:

- `Sources/Elder/SessionView.swift`
- `Sources/Models/SessionViewModel.swift`

`attach()` is called in `SessionView.onAppear`, and `beginSession()` immediately creates a new `Session`. That isn't the moment an elder actually sits down or staff make the first choice.

If the app quits or crashes without `endSession()` or `discard()` being called, an empty in-progress session can be left behind. In that case it may show as `In conversation` on the roster screen.

Response:

- Delay creating the session until the first real event occurs.
- Add a routine that cleans up old unfinished empty sessions at app start.

### High — session records are saved even without self/guardian consent

Related files:

- `Sources/App/ConsentStore.swift`
- `Sources/Models/SessionViewModel.swift`

The docs and settings text say session records can't be kept without `personal` consent. But the current `record(_:)` path has no `Consent.isGranted(.personal)` check.

Response:

- Enforce `.personal` consent at session start or right before recording.
- Without consent, block saving of utterances, anchors and metrics entirely, and direct staff to settings.

### Medium — most save failures are swallowed

Related files:

- `Sources/Models/SessionViewModel.swift`

`try? store.save()` appears in several places. If save failures don't surface in the UI, utterances, recall rates and the next opener can be silently lost.

Response:

- Keep save-failure state in `SessionViewModel` and show it on the staff panel.
- Failing to save the next opener directly affects session quality, so at least log it.

### Medium — there's no flow to start a session by choosing an elder from the roster

Related files:

- `Sources/Staff/RosterView.swift`
- `Sources/Models/SessionViewModel.swift`

The docs and comments describe staff choosing the elder from the roster until Vision. But the session subjects are currently hard-coded as `Kim Sunja`/`Park Malsun`, and roster cards have no select action.

Response:

- Tap a `RosterView` card → pass the selected `Elder` → `SessionViewModel` starts a session with that elder.
- Reorganise the state around a real `Elder` or a new-enrolment candidate model instead of `Person.known/stranger`.

### Medium — measured metrics and scripted metrics are mixed

Related files:

- `Sources/Models/SessionScript.swift`
- `Sources/Models/SessionViewModel.swift`
- `Sources/Memory/MemoryStore.swift`

The recall rate is close to a store-based measurement, but long-term memory consistency, speech amount and mood still have many values baked into `Choice.metricUpdates`. Wired into reports, mock values and measured values could get mixed.

Response:

- Give `MetricSample` a source: `scripted`, `measured`, `manual`.
- Compute the report screens from `measured` only.

---

## 6. Order of next tasks

1. Pin pilot operation to `pilot` mode, and seal off `deployment` mode until there's a real input path.
2. Add code-level protection so no session records are kept without `.personal` consent.
3. Add a routine that cleans up empty unfinished sessions.
4. Build the flow to start a session by choosing an elder from the roster.
5. Collect 3–5 minutes of STT measurement samples.
6. Separate metric sources, and replace the hard-coding in reports/memory map with store-based data.

---

## 7. Operating notes

- The current folder isn't a Git repository. Before the next code change, initialise Git or make a separate backup.
- Xcode outputs like `build`, `build-device`, `build-analyze` don't go into the repository.
- The canonical docs are `Docs/00`–`05`; past figures aren't quoted directly from `Docs/Backup/`.
- Treat the OpenAI API key path as pilot-only, and never leave the key in the client app in real deployment.
