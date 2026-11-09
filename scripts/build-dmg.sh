#!/bin/bash
set -euo pipefail

RILLVIA_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RILLVIA_VERSION="${RILLVIA_VERSION:-1.0.0}"
RILLVIA_BUILD="${RILLVIA_BUILD:-1}"
RILLVIA_DERIVED_DATA="${RILLVIA_DERIVED_DATA:-$RILLVIA_ROOT/build/PackageDerivedData}"
RILLVIA_SIGNING_IDENTITY="${RILLVIA_SIGNING_IDENTITY:--}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) RILLVIA_VERSION="$2"; shift 2 ;;
    --build) RILLVIA_BUILD="$2"; shift 2 ;;
    --help)
      printf 'Usage: scripts/build-dmg.sh [--version 1.0.0] [--build 1]\n'
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [[ ! "$RILLVIA_VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || [[ ! "$RILLVIA_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Use a version such as 1.0.0 and a positive build number.\n' >&2
  exit 2
fi

mkdir -p "$RILLVIA_ROOT/build/dist"
RILLVIA_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/rillvia-dmg.XXXXXX")"
trap 'rm -rf "$RILLVIA_STAGE"' EXIT

xcodebuild build -project "$RILLVIA_ROOT/Rillvia.xcodeproj" -scheme Rillvia \
  -configuration Release -derivedDataPath "$RILLVIA_DERIVED_DATA" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$RILLVIA_VERSION" CURRENT_PROJECT_VERSION="$RILLVIA_BUILD"

RILLVIA_APP="$RILLVIA_DERIVED_DATA/Build/Products/Release/Rillvia.app"
RILLVIA_DMG="$RILLVIA_ROOT/build/dist/Rillvia-$RILLVIA_VERSION-universal.dmg"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$RILLVIA_APP/Contents/Info.plist" | /usr/bin/grep -qx 'com.rillvia.app'
RILLVIA_ARCHITECTURES="$(lipo -archs "$RILLVIA_APP/Contents/MacOS/Rillvia")"
if [[ " $RILLVIA_ARCHITECTURES " != *' arm64 '* || " $RILLVIA_ARCHITECTURES " != *' x86_64 '* ]]; then
  printf 'The app must contain both arm64 and x86_64. Found: %s\n' "$RILLVIA_ARCHITECTURES" >&2
  exit 2
fi

if [[ "$RILLVIA_SIGNING_IDENTITY" != '-' ]]; then
  codesign --force --options runtime --timestamp --sign "$RILLVIA_SIGNING_IDENTITY" "$RILLVIA_APP"
fi
codesign --verify --deep --strict "$RILLVIA_APP"
ditto "$RILLVIA_APP" "$RILLVIA_STAGE/Rillvia.app"
ln -s /Applications "$RILLVIA_STAGE/Applications"
cat > "$RILLVIA_STAGE/Read Me.txt" <<'TEXT'
Rillvia

Drag Rillvia to Applications, then open it from there.
Requires macOS 26 or later. Works on Apple silicon and Intel Macs.

The setup tour helps you choose a browser and add your first rule.
Settings > Updates checks for new versions. Download first, then choose
Install and restart. Your saved rules and shortcuts stay in place.

https://github.com/masterdisk/Rillvia
TEXT
if [[ -z "${RILLVIA_NOTARY_PROFILE:-}" ]]; then
  cat >> "$RILLVIA_STAGE/Read Me.txt" <<'TEXT'

First open: this copy isn't notarized by Apple, so macOS stops it the
first time. Click Done, open System Settings > Privacy & Security, and
click Open Anyway next to Rillvia.
TEXT
fi

hdiutil create -volname Rillvia -srcfolder "$RILLVIA_STAGE" -fs HFS+ -format UDZO \
  -imagekey zlib-level=9 -ov "$RILLVIA_DMG"
if [[ "$RILLVIA_SIGNING_IDENTITY" != '-' ]]; then
  codesign --timestamp --sign "$RILLVIA_SIGNING_IDENTITY" --identifier com.rillvia.app.dmg "$RILLVIA_DMG"
fi
if [[ -n "${RILLVIA_NOTARY_PROFILE:-}" ]]; then
  if [[ "$RILLVIA_SIGNING_IDENTITY" == '-' ]]; then
    printf 'Notarization requires a Developer ID signing identity.\n' >&2
    exit 2
  fi
  RILLVIA_NOTARY_ARGS=(--keychain-profile "$RILLVIA_NOTARY_PROFILE" --wait --output-format json)
  if [[ -n "${RILLVIA_NOTARY_KEYCHAIN:-}" ]]; then
    RILLVIA_NOTARY_ARGS+=(--keychain "$RILLVIA_NOTARY_KEYCHAIN")
  fi
  xcrun notarytool submit "$RILLVIA_DMG" "${RILLVIA_NOTARY_ARGS[@]}" > "$RILLVIA_STAGE/notarization.json"
  python3 - "$RILLVIA_STAGE/notarization.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    result = json.load(file)
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept this build for notarization.')
PY
  xcrun stapler staple "$RILLVIA_DMG"
  xcrun stapler validate "$RILLVIA_DMG"
fi
hdiutil verify "$RILLVIA_DMG"
(cd "$RILLVIA_ROOT/build/dist" && shasum -a 256 "$(basename "$RILLVIA_DMG")" > "$(basename "$RILLVIA_DMG").sha256")
printf '\nDMG ready: %s\n' "$RILLVIA_DMG"
