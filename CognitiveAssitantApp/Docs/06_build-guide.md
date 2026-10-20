# Build Guide

**RobotForElders — from receiving it to running it**

Written: September 10, 2026
Audience: someone receiving this source for the first time. Assumes you've used Xcode on macOS before.

> **One thing to know first.** The `.xcodeproj` isn't in the repository. **XcodeGen
> generates it from `project.yml`.** Without knowing this, you get stuck at "there's no project file".

---

## 0. The 5-minute path

```bash
brew install xcodegen
xcodegen generate
open RobotForElders.xcodeproj
```

In Xcode, choose the **iPad Air (5th generation) simulator** as the destination and run.
That's it. No signing or account needed.

---

## 1. Requirements

| | What | Why |
|---|---|---|
| Required | **Xcode 26** or later | Swift Testing · `FoundationModels` SDK |
| Required | **macOS 26** or later | Required by that Xcode |
| Required | **XcodeGen** (`brew install xcodegen`) | The `.xcodeproj` is a generated file |
| Optional | **Pillow** (`pip install pillow`) | Only when redrawing the app icon |
| Optional | A real iPad | For checks that need the microphone, camera or on-device model |

The deployment target is **iPadOS 17**. However, **on-device understanding and line selection
use `FoundationModels`, so they only run on iPadOS 26 or later.** Below that it builds
and runs, with only those features quietly switched off, proceeding on the fixed script
(`#if canImport(FoundationModels)` + `#available(iOS 26.0, *)`).

**iPad only.** It's `TARGETED_DEVICE_FAMILY: 2` and locked to portrait, so
it doesn't show up in the list for iPhone simulators.

---

## 2. Don't hand-edit generated files

Two files are generated. Edits disappear on the next `xcodegen generate`.

| Generated file | The real source |
|---|---|
| `RobotForElders.xcodeproj` | `project.yml` |
| `Resources/Info.plist` | `targets.RobotForElders.info.properties` in `project.yml` |

Permission strings (camera · microphone · speech recognition) and the app name are all in `project.yml` too.
**Edit both, run `xcodegen generate`, and confirm with a diff.**

**If you added a new test file, run `xcodegen generate` again.** Otherwise
the file isn't added to the target, and you write a new test but it passes **with the count unchanged**.

---

## 3. Building and running in the simulator

```bash
xcrun simctl list devices available | grep "iPad Air"

xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air (5th generation)' \
  -derivedDataPath build build

xcrun simctl boot <UDID>
xcrun simctl install <UDID> build/Build/Products/Debug-iphonesimulator/RobotForElders.app
xcrun simctl launch  <UDID> com.tictechtoe.RobotForElders
xcrun simctl io <UDID> screenshot /tmp/s.png
```

**Run on the same model as the deployment device (iPad Air 5).** Screens are drawn in 820 × 1180 absolute coordinates,
so with a different model, verifying the layout by eye becomes meaningless.

### Opening a single screen directly (DEBUG only)

The four staff screens live inside the gallery, and staff settings sit behind a **two-finger long press for 1.5 seconds**.
That gesture can't be reproduced in the simulator, so there's a path to open them via launch arguments.

```bash
xcrun simctl launch <UDID> com.tictechtoe.RobotForElders -screen 15   # cognitive report
xcrun simctl launch <UDID> com.tictechtoe.RobotForElders -screen 13   # today's roster
xcrun simctl launch <UDID> com.tictechtoe.RobotForElders -probe plan  # line-selection measurement
```

`-screen` takes 1–16, and `-probe` takes `understanding` · `reply` · `plan`.
**Release builds don't have this path** — the kiosk in front of the elder must not open a staff screen
from a single launch argument.

---

## 4. Running the tests

**88 tests · 11 suites. No device, person or model needed.**

```bash
xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air (5th generation)' \
  -derivedDataPath build test
```

Also measure the line budget once before building. **This doesn't even need the simulator.**

```bash
swift Tools/check-captions.swift
```

If a single row of a line exceeds 724pt it wraps, adding a row, and then the vertical budget bursts.
**The build still passes when it overflows and only the text gets smaller, so the eye can't catch it.**

---

## 5. Putting it on a device

**You have to change the signing settings to your own.** Two places in `project.yml`.

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: 3J58K2RH44          # ← your team ID
targets:
  RobotForElders:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.tictechtoe.RobotForElders   # ← your own
```

If you don't change the bundle ID, an app with the same ID is already registered to another team and provisioning fails.
After changing it, run `xcodegen generate` again.

```bash
xcrun devicectl list devices                     # device UDID

xcodebuild -project RobotForElders.xcodeproj -scheme RobotForElders \
  -configuration Debug -destination "id=<device UDID>" \
  -derivedDataPath build-device -allowProvisioningUpdates build

xcrun devicectl device install app --device <UDID> \
  build-device/Build/Products/Debug-iphoneos/RobotForElders.app
xcrun devicectl device process launch --device <UDID> \
  --terminate-existing com.tictechtoe.RobotForElders
```

### Pulling the store off the device

Rather than asking what was actually saved, **pulling it off and looking is faster and more accurate.**
Two defects were actually caught this way (the robot transcribing its own voice, and a pronoun becoming a fact).

```bash
D=<device UDID>
for f in default.store default.store-shm default.store-wal; do
  xcrun devicectl device copy from --device $D --domain-type appDataContainer \
    --domain-identifier com.tictechtoe.RobotForElders --user mobile \
    --source "Library/Application Support/$f" --destination "/tmp/store/$f"
done
sqlite3 /tmp/store/default.store "SELECT ZSUBJECT,ZKINDRAW,ZDETAIL FROM ZFACT;"
```

**You have to fetch the `-wal` file too** to see recent records. The utterance timestamp column is `ZUTTERANCE.ZAT`.

---

## 6. TestFlight

```bash
./Tools/archive.sh            # archive → .ipa → upload
./Tools/archive.sh --archive  # archive only
./Tools/archive.sh --export   # up to .ipa only
```

You need an App Store Connect **team API key**. `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
(`chmod 600`). **Never put it in the repository.**

The script injects the build number as UTC time (`YYMMDDHHmm`). Bumping it by hand gets forgotten,
and using the commit count collides when uploading twice from the same commit.

> **`UPLOAD SUCCEEDED` isn't the end.** Processing runs separately afterwards, and even if it fails the screen
> just shows "no builds". `archive.sh` watches it to the end with `--build-status`.

---

## 7. Common snags

| Symptom | Cause | What to do |
|---|---|---|
| There's no project file | The `.xcodeproj` is generated | `xcodegen generate` |
| Edits to `Info.plist` disappeared | It's generated too | Edit it in `project.yml` |
| Wrote a new test but the count didn't change | The new file wasn't added to the target | `xcodegen generate` again |
| Signing failure · provisioning error | Someone else's team ID · someone else's bundle ID | Change both as in section 5 |
| Signing error in a simulator build | There's no reason for signing to apply | Add `CODE_SIGNING_ALLOWED=NO` |
| Understanding and suggestions do nothing | `FoundationModels` is missing or switched off | Staff settings → Probes → `Understanding check` shows the reason |
| The simulator is too fast | The simulator uses **the Mac's model** | Measure latency only on a device (1.0 s vs 4.9 s) |
| Lines suddenly look smaller | Vertical budget exceeded → `FitToHeight` shrinking | `swift Tools/check-captions.swift` |
| TestFlight won't accept the build | Processing-stage failure such as an app name conflict (90129) | Match `CFBundleDisplayName` to the app name in App Store Connect |
| Faces enrolled on the device disappeared | A TestFlight install overwrote the development-signed build | Overwriting between development-signed builds preserves data |
| A red `Not recording` shows on screen | Self/guardian consent is off | Turn it on in Staff settings → Consent. **When off, nothing is saved** |
| The recall verdict button can't be pressed | 8 minutes haven't passed since the anchor | Wait, or skip with `Probe now · not counted` |

---

## 8. Redrawing the app icon

The icon is a rendering of the expression the app actually draws.

```bash
pip install pillow
python3 Tools/make_app_icon.py happy Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

The variants are `happy` · `neutral`. The coordinates in `Tools/make_app_icon.py` are
copied from `Sources/DesignSystem/FaceStyle.swift`, so **if you change an expression, the icon has to be
changed too.**

---

## 9. The order to check once before building

```bash
xcodegen generate                      # regenerate the project
swift Tools/check-captions.swift       # line budget
xcodebuild … test                      # 88 tests
xcodebuild … build                     # build
```

If all four pass, **it's safe within the scope that doesn't need a device.** Anything beyond that
(face matching · STT · model latency · legibility) follows the checklist in section 4 of
`Docs/2026-09-10_implementation-status-analysis.md`.
