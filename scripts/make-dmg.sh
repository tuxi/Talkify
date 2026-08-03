#!/bin/bash
#
# make-dmg.sh — package a notarized Talkify.app into a distributable .dmg.
#
# Usage:
#   ./scripts/make-dmg.sh [path/to/Talkify.app]
#
# If the app path is omitted, the newest Talkify.app under
# ~/Library/Developer/Xcode/DerivedData is used.
#
# Version strings are read from Configurations/TalkifyMacCommon.xcconfig so the
# DMG name always matches the current build. Output goes to dist/Talkify-<v>.dmg
# inside the workspace.
#
# Example (after exporting from Xcode Organizer):
#   ./scripts/make-dmg.sh ~/Desktop/Talkify-2.0.0/Talkify.app
#
# Notes:
# - The .app must already be signed with a Developer ID and notarized (Xcode
#   Organizer -> Distribute App -> Direct Distribution does this for you).
# - The resulting DMG is unsigned; that is fine for direct distribution as long
#   as the .app inside is signed + notarized.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCCONFIG="$ROOT/Configurations/TalkifyMacCommon.xcconfig"
APP_NAME="Talkify"

# --- Read version from the single source of truth ---------------------------

MARKETING_VERSION="$(sed -n 's/^MARKETING_VERSION *= *//p' "$XCCONFIG" | head -1)"
BUILD_NUMBER="$(sed -n 's/^CURRENT_PROJECT_VERSION *= *//p' "$XCCONFIG" | head -1)"

if [ -z "$MARKETING_VERSION" ]; then
    echo "error: could not read MARKETING_VERSION from $XCCONFIG" >&2
    exit 1
fi

# --- Locate the .app ---------------------------------------------------------

if [ $# -ge 1 ]; then
    APP_PATH="$1"
elif [ -d "$ROOT/dist/$APP_NAME.app" ]; then
    APP_PATH="$ROOT/dist/$APP_NAME.app"
else
    APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 8 \
        -name "$APP_NAME.app" -type d 2>/dev/null | sort | tail -1 || true)"
fi

if [ -z "${APP_PATH:-}" ] || [ ! -d "$APP_PATH" ]; then
    echo "error: no .app found; pass the path explicitly, e.g." >&2
    echo "  $0 /path/to/$APP_NAME.app" >&2
    exit 1
fi

# --- Sanity checks on signature / notarization ------------------------------

echo "==> Verifying code signature"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Verifying notarization (Gatekeeper)"
if spctl -a -vv --type execute "$APP_PATH" 2>&1; then
    echo "    notarization OK"
else
    echo "    warning: Gatekeeper check failed — the app may not be notarized yet." >&2
    echo "    Notarize it in Xcode Organizer (Distribute App -> Direct Distribution) first." >&2
fi

# --- Build the DMG -----------------------------------------------------------

OUT_DIR="$ROOT/dist"
OUT_DMG="$OUT_DIR/$APP_NAME-$MARKETING_VERSION.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "==> Staging $APP_NAME.app (build $BUILD_NUMBER, v$MARKETING_VERSION)"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
echo "==> Creating $OUT_DMG"
hdiutil create -volname "$APP_NAME $MARKETING_VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$OUT_DMG" >/dev/null

echo "==> Verifying DMG"
hdiutil verify "$OUT_DMG" >/dev/null

echo "Done: $OUT_DMG"
echo "Upload this file to the GitHub release (https://github.com/tuxi/Talkify/releases/new)."
