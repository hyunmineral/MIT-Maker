#!/bin/bash
#
# Builds an archive for TestFlight. The build number is decided and injected here.
#
#   ./Tools/archive.sh            # archive → .ipa → TestFlight upload
#   ./Tools/archive.sh --archive  # archive only
#   ./Tools/archive.sh --export   # up to .ipa only (no upload)
#
# ## Authentication
#
# Uses an App Store Connect API team key. **Keys are per team, not created per app** —
# there's no way to narrow permissions to a single app, so key management must not be loose.
#
#   ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8   (chmod 600)
#
# Never put it in the repository. The two values below aren't secret, but the `.p8` is.
#
# ## Why build the build number from UTC time
#
# Within the same marketing version, TestFlight accepts an upload only if **the build number always increases**.
# Of the three candidates, time is best.
#
# - Writing it in `project.yml` and bumping by hand → gets forgotten. And it's only rejected at the upload step,
#   after the archive is fully built, wasting time
# - Commit count (`git rev-list --count`) → uploading twice from the same commit collides
# - **UTC time (`YYMMDDHHmm`)** → always increases, never collides, and the number alone tells you
#   when the build was made. During the pilot you often need to ask what's installed on the device
#
# It's not written to the repository. `project.yml` holds the base value and it's only injected here —
# if the file got dirty on every build, the commits would get messy.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="RobotForElders"
PROJECT="RobotForElders.xcodeproj"
BUILD=$(date -u +%y%m%d%H%M)
OUT="build/archive"
ARCHIVE="$OUT/$SCHEME-$BUILD.xcarchive"

MARKETING=$(grep -m1 'MARKETING_VERSION:' project.yml | sed 's/.*"\(.*\)".*/\1/')

echo "▸ Version $MARKETING · build $BUILD"
# Under `set -e`, using `[ ] && echo` ends the script right there when the condition is false.
if [ -n "$(git status --porcelain)" ]; then
  echo "  ⚠︎ There are uncommitted changes — what gets uploaded differs from the repository"
fi

# The .xcodeproj isn't in the repository. Always regenerate it.
xcodegen generate >/dev/null

mkdir -p "$OUT"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" \
  | grep -E '^\*\*|error:|warning: .*Sources' || true

[ -d "$ARCHIVE" ] || { echo "✗ Archive failed"; exit 1; }

# The success signal is **the values inside the output**, not the exit code.
PLIST="$ARCHIVE/Products/Applications/$SCHEME.app/Info.plist"
echo "▸ Values baked into the archive:"
echo "    CFBundleShortVersionString $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
echo "    CFBundleVersion           $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
echo "    $ARCHIVE"

ASC_KEY_ID="${ASC_KEY_ID:-C6B2VTXZZW}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-69a6de72-6c07-47e3-e053-5b8c7c11a4d1}"

if [ "${1-}" = "--archive" ]; then
  echo "▸ Skipping export (--archive)"
  exit 0
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Tools/ExportOptions.plist \
  -exportPath "$OUT/$BUILD" \
  -allowProvisioningUpdates \
  | grep -E '^\*\*|error:' || true

IPA=$(ls "$OUT/$BUILD"/*.ipa 2>/dev/null | head -1)
[ -n "$IPA" ] || { echo "✗ Export failed — see $OUT/$BUILD"; exit 1; }
echo "▸ $IPA"

if [ "${1-}" = "--export" ]; then
  echo "▸ Skipping upload (--export)"
  exit 0
fi

if [ ! -f "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" ]; then
  echo "✗ No key — ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8"
  exit 1
fi

# **Validate first.** Uploads can't be undone, and processing failures arrive by email much later.
echo "▸ Validating"
xcrun altool --validate-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | grep -E 'SUCCEEDED|ERROR|error'

echo "▸ Uploading → App Store Connect"
UPLOAD=$(xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1)
echo "$UPLOAD" | grep -E 'SUCCEEDED|Delivery UUID|ERROR|error' || true

DELIVERY=$(echo "$UPLOAD" | sed -n 's/.*Delivery UUID: *\([0-9a-f-]*\).*/\1/p' | head -1)
if [ -z "$DELIVERY" ]; then
  echo "✗ Upload failed — no Delivery UUID"
  exit 1
fi

# **`UPLOAD SUCCEEDED` only means "the file arrived intact".**
# Processing runs separately afterwards, and even if it fails the screen just shows "no builds".
# It actually got silently rejected with 90129 (duplicate display name) and took ages to figure out. Watch it to the end.
echo "▸ Waiting for processing (up to 10 minutes)"
for _ in $(seq 1 14); do
  sleep 45
  STATUS=$(xcrun altool --build-status --delivery-id "$DELIVERY" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1)
  LINE=$(echo "$STATUS" | grep -E 'BUILD-STATUS|IS-ON-APP-STORE' | tr -d ' ' | tr '\n' ' ')
  echo "    $LINE"
  if echo "$LINE" | grep -q 'BUILD-STATUS:FAILED'; then
    echo "✗ Processing failed:"
    echo "$STATUS" | grep -E 'description :'
    exit 1
  fi
  if echo "$LINE" | grep -q 'IS-ON-APP-STORE-CONNECT:true'; then
    echo "✓ Build $BUILD — available in TestFlight"
    exit 0
  fi
done
echo "⚠︎ Still processing. Check later:"
echo "  xcrun altool --build-status --delivery-id $DELIVERY \\"
echo "    --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID"
