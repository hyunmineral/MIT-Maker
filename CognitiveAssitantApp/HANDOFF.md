# HANDOFF — 2026-09-10

**RobotForElders** — a conversation robot on an iPad Air 5 (M1), mounted in portrait

Previous handoff: 2026-09-01 (the day the robot started listening). This file overwrote it.

> **Today we read the code, filled the gaps, and pinned it down with tests.** Rewriting the status
> from the source rather than the docs showed that **half the places had docs and code disagreeing**. The
> resulting list was closed the same day, and **88 tests** hold it in place.
>
> **Switched to a remote-work assumption.** Everything that can be judged without a device became a test;
> only what needs a person, microphone or camera is left on the checklist (9 items).
>
> **The source is uploaded to Google Drive.** It was unzipped and verified through build and tests.

---

## 0. Do this first tomorrow

### ① Merge the branch into `main` — 30 seconds

All of today's work is on **`implementation-final`**. There is no remote and everything so far
has piled up on `main`, so just pull it in.

```bash
git checkout main && git merge --ff-only implementation-final
```

**If you skip this, the next session starts from `main` and won't see today's work.**

### ② Second-person face match — carried over for the 3rd day, still top priority

**It can't be done alone, and it decides whether the product works at all.** 30 minutes is enough.

The `.ambiguous` branch of `FaceGallery.match` **has never run even once.**
With only one face in the gallery there is no runner-up. With one person enrolled, **if someone else
comes and the distance is under 0.55, the robot calls them by that person's name.**

| # | | Status |
|---|---|---|
| 1 | Does it recognise June as June? | ✅ 2026-08-31 |
| 2 | **Enrol B — does it recognise B as B?** | Unverified |
| 3 | **When B comes, does it avoid calling them June?** | **Unverified — the key one** |
| 4 | Does it call an unenrolled third person by no name at all? | Unverified |

Setup: two fingers for 1.5 s → Staff settings → Probes → turn on `Greet automatically at Resting`,
check the three consents, portrait mount · eye-to-screen 70 cm.
Thresholds are `unknown = 0.55` · `margin = 0.15` in `Sources/Vision/FacePrinting.swift`.
**Do not fix this by raising the threshold** — it brings the risk of calling someone else by that person's name.

> **New condition as of today.** If the self/guardian consent is off, **enrolment itself is blocked.**
> Turn it on in staff settings before starting. When off, a red `Not recording` shows at the top of the screen.

### ③ Real-use check of suggestions — carried over. The `ask_known` path has never run

It only appears after speech. Answer aloud in the free-answer step → `thinking…` → blue dashed button.
`ask_known` can only come up **with someone who has two or more saved topics**.

---

## 1. What was done this session

3 commits (`1bdc0fc` · `c50a266` · `2d88d91`), all on `implementation-final`.

### Set up a docs site (port 4337)

Built an Astro site in `Docs/site` that reads `Docs/*.md` **without copies**.
Edit the Markdown and the site follows immediately. The file names were Korean and couldn't be used in URLs, so
`src/data/docs.ts` sets the slugs — **when you add a doc, add one line here.**

It is started by a **Claude Code session-start hook**, not an always-on daemon
(`.claude/settings.json` → `Docs/site/scripts/ensure-dev-server.sh`).

### Read the code and rewrote the status

`Docs/2026-09-10_implementation-status-analysis.md`. **Read the source instead of trusting the docs.**
The roadmap's "face recognition — staged only" was an outdated description, and conversely "consent locks per item"
was **not true** for the self/guardian item.

### Implemented everything that was designed

| What | Why it was a problem |
|---|---|
| **Compute the three metrics from records** | Constants were baked into the options, so **what staff tapped was the measurement**. Deleted the `MetricUpdate` type to remove the channel itself |
| **Leave mood as `—`** | There is no way to measure it. A made-up 68% in the cognitive report would be a false record |
| **Four recall verdicts** | `AnchorOutcome` even had weights but only 0 and 1 were used. **Partial recall was recorded as failure** |
| **8-minute gate** | It only showed a countdown without blocking, so it was pressed before expiry almost every time. Now it locks, can be skipped, and the skip is recorded |
| **Form-of-address input** | `FormOfAddress` had the rules but **nobody fed it a value**, so it used the full name |
| **Consent lock** | The description said "no recording without it" but **there was not a single check** |
| **Three staff screens** | Memory map · cognitive report · weekly digest were **all hard-coded to Dorothy** |
| **Fact drift** | Revision records stacked the new value, so **the pair to compare against disappeared.** Now the previous value is kept |

### 88 tests — run without a device

`Tests/` · 11 suites. **Only verdicts that need no device, person or model** went in.
The most valuable is `ReplyPlannerResolveTests` — this project's safety claim
hangs on that one function and nothing was verifying it.

**The tests caught three real defects.** The name-asking line was **725.1pt**, 1pt over the 724 width,
and was silently wrapping; in the farewell and hometown questions an interpolation shared a line with other text.

### Two docs for the recipient

- `Docs/06_build-guide.md` — from receiving it to running it. A table of the **12 most common snags**
- `Docs/07_project-reference.md` — module map · data model · session flow ·
  **7 places where safety is at stake** · **what changes when you edit where**

Also fixed the repository `README.md`. **The doc the recipient reads first was the most outdated.**

### Uploaded the source to Google Drive

`RobotForElders/SourceCode/` — the archive + four docs to read.
**Unzipped and confirmed `xcodegen generate` → build → all 88 tests.**

https://drive.google.com/drive/folders/1ijTUNuyD5PrM_DGCohUqSgGH70-fIfHM

---

## 2. Current state

| | |
|---|---|
| Build | Simulator `BUILD SUCCEEDED` · tests **88/88 passing** |
| Git | 3 commits on the **`implementation-final`** branch. `main` is still `d9926a5`. 0 uncommitted |
| Device | **Not touched today.** The latest code is not on it |
| TestFlight | `0.1.0 (2608311425)` — today's work was not uploaded |
| Simulator | `iPad Air 5 (deployment unit)` `3362262C-775F-4E60-9512-7A2A93ACE640` booted |
| Docs site | Running at http://localhost:4337 (15 pages) |
| Drive | Archive + `06`·`07` docs in `SourceCode/` |

### Status of the four questions

| Question | Status |
|---|---|
| ① Does it recognise faces? | ✅ Confirmed on device |
| ② **Does it tell people apart?** | ⚠️ **Unverified — decides whether the product works** |
| ③ Does it remember conversations? | ✅ Confirmed with real voice |
| ④ What conversation does it hold? | 🟡 Half — it listens, understands and chooses, but **staff must press to send it** |

---

## 3. What to pick up next

1. **Section 0 ① merge the branch** — before anything else
2. **Section 0 ② second-person face match** — whether the product works
3. **Section 0 ③ real use of suggestions · `ask_known`**
4. **Put today's code on the device** — the new screens, gate and address input run on a device for the first time
5. **Clean up existing device data** — see the traps below. Before the pilot
6. **Decide how to measure the mood metric** — right now it is blank forever. A product decision
7. **Autonomous lines** — the last remaining box. Hide the 7 s latency by choosing ahead while the elder is speaking
8. **Rewrite the consent wording for an English-speaking jurisdiction** — a pilot blocker (carried over)

---

## 4. Traps that will block the next person if they don't know

### Newly found today

- **It's on `implementation-final`, not `main`.** Until merged, nothing shows up
  on `main`
- **Old `FactRevision`s on the device mean the opposite.** They used to stack the 'new value'; now they
  keep the 'value before the change'. For entries already stored, the report **shows them as the previous value.**
  There are only a few — delete them before the pilot
- **Fake metric samples created by the old script remain in the store.** They get mixed into the 8-week report
- **Self/guardian consent now really locks.** When off, none of sessions, utterances, facts or enrolment
  are saved. The red text at the top of the screen is the only signal
- **If you add a test file, run `xcodegen generate` again.** Otherwise the new test
  isn't added to the target and **it passes with the count unchanged** (actually happened today)
- **Swift Testing's second argument is a `Comment`.** Passing a `String` variable directly
  won't compile. Wrap it as `"\(value)"`
- **To add a doc to the docs site, add one line to `Docs/site/src/data/docs.ts`.**
  If it points at a missing file, the build stops and names it
- **Upload to Drive with rclone (the `gdrive:` remote).** Uploading files one by one via MCP
  takes **up to 90 seconds each**, which is unusable

### Carried over (still valid)

- **Don't use `.measurement` on `AVAudioSession`** — it turns off echo cancellation too
- **Don't reuse `LanguageModelSession`** — 6.9 → 6.7 → **9.9 s**
- **Don't stack `fullScreenCover`s** — the third one silently fails to open
- **Don't trust model latency in the simulator** — it uses the Mac's model
- **The 74pt vertical slack is only 4.15pt** — overflow doesn't error, the text just shrinks
- **`.xcodeproj` and `Info.plist` are generated files**
- **A TestFlight install overwrites the development-signed build and wipes enrolled faces.** Between development-signed builds
  data is preserved

---

## Re-check commands

```bash
git checkout main && git merge --ff-only implementation-final

xcodegen generate
swift Tools/check-captions.swift          # line budget

SIM=3362262C-775F-4E60-9512-7A2A93ACE640  # iPad Air 5 (deployment unit)
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug -destination "id=$SIM" -derivedDataPath build test

xcrun simctl launch $SIM com.tictechtoe.RobotForElders -screen 15   # cognitive report
```

Device · TestFlight procedures and common snags are in **`Docs/06_build-guide.md`**.
When opening the code for the first time, start with **`Docs/07_project-reference.md`**.
