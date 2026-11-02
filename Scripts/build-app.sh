#!/usr/bin/env bash
# Builds build/Reclaim.app (universal by default), build/Reclaim-<version>.zip and, for release
# builds, build/Reclaim-<version>.dmg.
#
# Usage: Scripts/build-app.sh [--arch arm64|x86_64|universal] [--debug]
# No Xcode needed: SwiftPM builds the binary, this script assembles and ad-hoc signs the bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
source Scripts/toolchain.sh

ARCH="universal"
CONFIG="release"
while [ $# -gt 0 ]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2 ;;
    --debug) CONFIG="debug"; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
case "$ARCH" in
  universal) ARCHS=(arm64 x86_64) ;;
  arm64|x86_64) ARCHS=("$ARCH") ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

# Copy each slice out as soon as it's built: the newer SwiftPM build engine writes every
# architecture to the same output path.
SLICES="$ROOT/build/slices"
mkdir -p "$SLICES"
BINARIES=()
for arch in "${ARCHS[@]}"; do
  swift build -c "$CONFIG" --arch "$arch" --product Reclaim
  cp "$(swift build -c "$CONFIG" --arch "$arch" --show-bin-path)/Reclaim" "$SLICES/Reclaim-$arch"
  BINARIES+=("$SLICES/Reclaim-$arch")
done

APP="$ROOT/build/Reclaim.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

lipo -create -output "$APP/Contents/MacOS/Reclaim" "${BINARIES[@]}"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
# Where Report a Bug... sends feedback. It comes from the environment (a CI secret for releases), never
# from the repository, so the relay URL isn't published in the source. Without it the app offers
# only the GitHub issue route.
if [ -n "${RECLAIM_FEEDBACK_URL:-}" ]; then
  plutil -replace ReclaimFeedbackURL -string "$RECLAIM_FEEDBACK_URL" "$APP/Contents/Info.plist"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc ("-") by default. Set SIGN_IDENTITY to a stable certificate name so macOS keeps the
# Full Disk Access grant across rebuilds (an ad-hoc signature changes with every build).
codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$APP"
codesign --verify --strict "$APP"

ZIP="$ROOT/build/Reclaim-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "built $APP ($(lipo -archs "$APP/Contents/MacOS/Reclaim"), $CONFIG)"
echo "zipped $ZIP ($(du -h "$ZIP" | cut -f1))"

# The disk image holds the app next to an Applications shortcut, so installing is one drag. Debug
# builds skip it: it only matters for something you hand to other people.
if [ "$CONFIG" = "release" ]; then
  DMG="$ROOT/build/Reclaim-$VERSION.dmg"
  STAGING="$ROOT/build/dmg-staging"
  rm -rf "$STAGING" "$DMG"
  mkdir -p "$STAGING"
  ditto "$APP" "$STAGING/Reclaim.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -quiet -volname "Reclaim" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
  rm -rf "$STAGING"
  # A stable certificate signs the image too; an ad-hoc signature on a DMG adds nothing.
  if [ "${SIGN_IDENTITY:--}" != "-" ]; then
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$DMG"
  fi
  hdiutil verify -quiet "$DMG"
  echo "imaged $DMG ($(du -h "$DMG" | cut -f1))"
fi
