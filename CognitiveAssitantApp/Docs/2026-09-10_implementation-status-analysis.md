# September 10, 2026 · Implementation Status

**RobotForElders — what was read from the app source, and what was closed that day**

Written: 2026-09-10 (analysis)
Revised: 2026-09-10 (reflecting implementation — sections 2 · 4 · 5 are new)
Scope: all of `Sources/`. As of commit `d9926a5` at the time of analysis
Method: **verified by reading the code** rather than trusting the docs. Where docs and code disagreed, the code was recorded.

> **One-line summary.** The ladder has climbed to the *listening and understanding* rung and has a foot
> on the *responding* rung. Lines the robot picks still go out only when staff press them. **The remaining gaps were closed that day,
> and 88 tests hold them in place.**

---

## 0. How to use this document

It's split three ways. **The boundary is "does it actually happen in front of the elder"**.

| Category | Meaning |
|---|---|
| **Works** | It actually happens on a real device |
| **Half done** | The code exists but isn't wired to that place, or it only happens when a person presses something |
| **Missing** | It doesn't happen. Only a screen exists, or there's no check |

Each item has its **source file** attached. Without a source, the next person has to read it all again.

---

## 1. What works

### 1-1. Session flow — fixed-script state machine

`Sources/Models/SessionScript.swift` · `Sources/Models/SessionViewModel.swift`

There are two scripts. **10 steps for an enrolled person**, **7 steps for someone met for the first time**. Each step has an expression ·
status · line · choices, and pressing a choice moves to the next step.
When delayed recall succeeds, the 'gentle recovery' screen is skipped — saying "that's all right" when nothing was missed
creates a failure that never happened.

The script is no longer completely fixed. There are four slots the store fills.

| Slot | What fills it |
|---|---|
| Greeting | The `spokenName` of the person recognised by face |
| Opener | The last session's promise → last topic → long-term memory, in that order |
| Recall | The fact mentioned most often. If something is still unknown, **plant instead of recalling** |
| Farewell | A topic that actually came up this time |

### 1-2. Speaking — Apple on-device is the default

`Sources/Elder/SpeechEngine.swift` · `Sources/Elder/Voice/`

There are two engines, and **the OpenAI path is locked in code without overseas-transfer consent.**
Received audio is cached, and on failure it quietly falls back to the Apple voice. The fallback
is left in red text on the staff screen — **you can't tell which engine it is from the sound alone.**

### 1-3. Listening — transcribes at every listening step

`Sources/Speech/NameListener.swift` · `Sources/Speech/SpeechEcho.swift`

**Silence and limits differ by purpose.**

| | Name · first story | Free answer |
|---|---|---|
| Staff confirmation | Required | None |
| If it didn't catch it | The robot asks again (up to 2 times) | **Doesn't ask again** |
| Silence / limit | 2.5 s / 15 s | 5 s / 90 s |

**Not answering a recall question isn't a recognition failure but something to observe in itself.**

The robot transcribing its own voice is blocked in two layers. `.voiceChat` turns on system
echo cancellation, and if something still gets in, `SpeechEcho` discards it **only when everything heard is contained
in the line**. Blocking partial matches too would discard normal answers like
`"What did I have? Soup."`.

### 1-4. Understanding — extracting facts from what was said

`Sources/Understanding/FactExtractor.swift`

Apple on-device `FoundationModels`. No network, no API key.
It takes about 10 seconds on a device, so **it runs in the background without blocking the lines.**

| Gate | Value | Why |
|---|---|---|
| Confidence floor | 0.5 | Turning something vague into a fact makes the next session open with a wrong memory |
| Per-session cap | 3 | If ten pile up at once, the robot suddenly remembers every trivial detail |

### 1-5. Memory — 8 SwiftData types

`Sources/Memory/`

**CloudKit sync is off.** Face embeddings are biometric data and conversation transcripts are health-related
data, so they aren't sent off the device.

There's a three-step order for choosing the opener — **promise → last topic → long-term memory.**

### 1-6. Recognition — never decided from a single frame

`Sources/Vision/`

It collects a sample every 0.5 seconds and decides a person has come **only when a majority of a 5-second window is a face**.
If first and second place aren't far enough apart (`margin 0.15`), **no name is called.**
If it still can't tell, it takes one more look while asking about the weather — answering means looking at the screen,
so a frontal frame is captured.

**What's said before enrolment isn't thrown away.** The moment the name is settled, it's attached with its original timestamps.

### 1-7. Suggestions — only choosing, with sentences written by people

`Sources/Understanding/ReplyPlanner.swift`

The model only chooses **what to do from a closed list and which numbered topic to talk about**. The sentence
is built by `Move.line(subject:)` and was written by people. It's safe even when an unknown value arrives —
an unknown `move` becomes `acknowledge`, and an out-of-range index is treated as absent.

### 1-8. Recall anchors — verifying the delay

When an anchor is planted, **8 minutes later** is the time to ask back, and **verdicts short of 6 minutes are excluded from the recall rate.**
When something couldn't be measured, no number is made up.

---

## 2. What was closed that day

Every gap found in the analysis was filled the same day. **Each item has a test holding it in place.**

### 2-1. Three metrics come from records

`Sources/Models/MetricEngine.swift` (new file)

Previously only the recall rate was really computed, and the rest were constants baked into `Choice.metricUpdates`.
Whichever choice staff pressed was the "measurement".

**That channel was removed.** The `MetricUpdate` type itself was deleted, so **there's no way for the script to produce
numbers.** Metrics come only from stored records.

| Metric | Where it comes from | When it can't be measured |
|---|---|---|
| Short-term recall rate | Anchor verdicts that met a valid delay | `—` · records why it couldn't be measured |
| Long-term memory consistency | Drifted facts / all facts | `—` if there are no facts |
| Speech amount · vocabulary | This session's average words ÷ **the person's own** baseline | `—` if there are no utterances |
| Mood · affect | **No method yet** | Always `—` |

Mood doesn't even have a function. The design names voice tone and lexical sentiment as sources, but neither is
implemented. **Instead of inventing a number, it records that it couldn't measure** — staff must never look at the screen and
tell the family "her mood was 68% today".

### 2-2. Recall verdicts split into four

`AnchorOutcome` defines four — exact · partial · after a hint · failed — and even has weights, yet
only exact and failed were being recorded. **Partial recall, the most common form in early decline,
was being recorded as failure.**

The script was fixed. At the ask-back slot it splits into exact · partial · doesn't know, and if they say they don't know, the robot
fills in the answer and then **at the recovery slot it splits into recall after a hint and failure.** The verdict is now carried
not by the step index but **by the choice itself** (`Choice.recall`).

### 2-3. The screen enforces the 8-minute delay

The planting slot and the ask-back slot are two steps apart, so in practice it was pressed before expiry almost every time.
A countdown was shown, but **pressing wasn't blocked.**

Now the verdict choices are locked before expiry. But **just locking them would stall the session
mid-pilot**, so staff can skip with `Probe now · not counted`, and the skip is
left in the log.

### 2-4. Staff set the form of address

`Sources/Staff/ElderDetailView.swift` (new file)

`FormOfAddress` had the rules exactly right, but **nobody was feeding it values.**
Enrolling during a session left both honorific and surname empty, so the robot called people by their full name instead of `Mrs. Walsh`.

Pressing a card in the roster sets honorific · surname · first-name permission · year of birth · hometown · automatic recognition.
**It shows "the robot will call them this" before saving.** People whose form of address isn't set
stand out on the roster card and in the weekly digest.

There's a reason it isn't asked during the session. Enrolment happens in front of the elder, and they would hear
the conversation choosing between `Mrs.` and `Ms.` right there.

### 2-5. Self/guardian consent really locks things

The consent screen's description says *"without it, no session can be recorded"*, yet **the code didn't have a single
line checking it.** The other three really were locking features, so only this item behaved differently
from its description.

Now without consent **the session itself isn't opened.** None of utterances, facts, metrics or enrolment
are written, and a red `Not recording` appears at the top of the staff panel.
**Reading isn't blocked** — records already saved remained under the consent at that time,
and deleting them is a separate decision.

### 2-6. Three staff screens read the store

| Screen | Before | Now |
|---|---|---|
| 14 Memory map | 5 nodes with fixed coordinates and names | Generated from `Fact`s · recent topics in blue |
| 15 Cognitive report | Dorothy's 8-week values as constants | Folding `MetricSample`s into weeks |
| 16 Weekly digest | Three items as constants | Generated from records · doesn't appear if there's nothing |

**All three screens were fixed to Dorothy Miller.** Seat someone else and those screens still appeared.

The report's closing paragraph follows the data too. It used to always say "8 consecutive weeks of decline" —
it read that way even when things were improving. **A single point isn't called a trend.**

The weekly digest merges the same request into one line instead of repeating it once per person, and changes come
above requests. **If requests pile up on top, the changes that actually matter get pushed down out of sight.**

### 2-7. When a fact drifts, **the first statement is kept**

`FactRevision` was stacking **the new value**. `Fact.detail` is already the latest, so
stacking the new value again **leaves nothing to compare against** — when that pair is exactly what
the consistency card is meant to show.

Now revision records keep **the value from before the change**.

> ⚠️ **Existing device data still has revision records with the old meaning.** The `FactRevision`s already
> stored on the device are 'new values', so the report shows them as 'previous values'.
> Before the pilot, delete those few entries, or read the first session's report with that in mind.

### 2-8. The line-width check covers the planner too

`Tools/check-captions.swift` scanned only `SessionScript.swift`. **Lines the planner builds
also appear as is on the elder screen, yet were outside the check.**

The check was widened and also moved into tests (with the UIKit-measured font). On the spot it **caught three defects.**

| Place | Problem | Fix |
|---|---|---|
| Name re-ask, 2nd round | The first line was **725.1pt**, 1pt over the 724 width, and silently wrapped | Dropped `quite`, made it 3 lines |
| Farewell | `\(topic) next time.` — the topic shared a line with other text | Topic on its own line |
| First meeting · hometown | `grow up, \(name)?` — the name shared a line with other text | Name on its own line |

**The build still passes when it overflows.** `FitToHeight` quietly shrinks the block, so the tier-A legibility
secured at 74pt silently disappears. A failure the eye can't catch.

### 2-9. Session length is visible

The design is 18 minutes per session, with the 8-minute delayed recall fitting within it. The code had no notion of time
at all. Now `12 / 18 min` shows on the staff panel and changes colour once it passes the target.

### 2-10. 88 tests — they run remotely too

`Tests/` (new directory · 11 suites)

**Only verdicts that need no device, person or model** live here.

| Suite | What it holds in place |
|---|---|
| `ReplyPlannerResolveTests` | **The safety claim itself.** Whatever the model spits out, does it avoid inventing topics |
| `MetricEngineTests` | Does it distinguish unmeasured from 0 |
| `MemoryStoreTests` | Opener priority · fact drift · average word count |
| `RecallAnchorTests` | The 6-minute rule · weights of the four verdicts |
| `CaptionBudgetTests` | 724pt width · row-count budget · do interpolations get their own row |
| `SessionScriptTests` | Do the index constants point at the actual steps |
| `SessionRecordingTests` | Does it really write nothing without consent |
| `ProbeGateTests` | Locking before expiry and staff skipping |
| `ReportDataTests` | Does it avoid inventing trends · merging notices |
| `FormOfAddressTests` · `SpeechEchoTests` | Form-of-address rules · echo detection |

```bash
xcodegen generate
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug -destination "id=3362262C-775F-4E60-9512-7A2A93ACE640" \
  -derivedDataPath build test
```

`3362262C…` is the **`iPad Air 5 (deployment unit)` simulator**. It has to run on the same model as the deployment device
for the screen calculations to come out the same.

### 2-11. Opening a single screen with a launch argument

The four staff screens live inside the gallery, and reaching them requires a person to tap menus.
**Remotely, nothing could be confirmed except that the build passed.**

```bash
xcrun simctl launch <device> com.tictechtoe.RobotForElders -screen 15
xcrun simctl io <device> screenshot /tmp/s.png
```

Lives only in `DEBUG`. Left in a release build, the kiosk would open a staff screen with a single launch argument.

---

## 3. What remains

### 3-1. Responses still go through staff's fingers

The robot listens, understands and picks its next move. **But it doesn't speak on its own.**

That isn't a defect but **an intentional step**. Unverified sentences never reach the elder, and
a quality metric comes for free. What stands in the way of going autonomous is latency — choosing takes 7 seconds,
and **the first token arrives at 78–100% of the total, so streaming can't hide it.**
The only remaining path seems to be choosing ahead while the elder is speaking.

### 3-2. There's no way to measure mood

Neither voice tone nor lexical sentiment is implemented. Recording that it couldn't be measured is the right answer for now, but
**one of the report's four cells can't stay empty forever.** What to measure it with is a product decision.

### 3-3. The `ask_known` path has never run

The planner has never chosen the move that brings up a stored topic in the probe. Whether the samples were all just
`follow_up` situations or the path really doesn't run **won't be known until real use.**

---

## 4. What must be checked on a device

**Tests can't stand in for anything here.** It needs people, a microphone, a camera and the real model.
Look at them one by one and report the results, and fixes will follow.

| # | What | How | What to look for |
|---|---|---|---|
| 1 | **Second-person face matching** | Enrol B and alternate A and B in front of it | Does it avoid calling B "A"? This is where `.ambiguous` runs for the first time |
| 2 | **Does the suggestion make sense there** | Answer aloud at the free-answer step | Does the sentence on the blue dashed button fit into the conversation |
| 3 | **Can staff put up with 7 seconds** | Watch a clock at the same point | If not, move to choosing ahead |
| 4 | **Does `ask_known` run** | Run a session with someone who has two or more facts | Does `ask_known` appear in the log |
| 5 | **Is the form of address actually used** | Set it in the roster and open a session | Does the robot say `Mrs. Walsh` |
| 6 | **Does the consent lock engage** | Turn off self/guardian consent for one session | Does the red `Not recording` appear and the store stop growing |
| 7 | **Is the 8-minute gate bearable** | Watch the countdown at the recall slot | Do staff wait, or skip every time |
| 8 | **Does 74pt read as tier A** | Hold a ruler to the screen and measure character height | The measurement of the 0.72 factor. The basis for every legibility figure |
| 9 | **Does the cognitive report make sense** | Accumulate sessions and `-screen 15` | Do the bars match the actual sessions |

**Items 1 and 2 decide whether the product works.** The rest come after.

---

## 5. When rewriting this

**Read the code first and the docs after.** Half of this document came from places where the docs and code
disagreed. In particular, re-check these four.

- `record(_:spokenOverride:)` in `Sources/Models/SessionViewModel.swift` —
  everything about what goes into the store is here
- `Sources/Models/MetricEngine.swift` — where the numbers on screen come from
- `opener(for:)` in `Sources/Memory/MemoryStore.swift` — what the next session opens with
- `resolve(move:subject:)` in `Sources/Understanding/ReplyPlanner.swift` —
  **where safety actually lives.** Here, not in the prompt
