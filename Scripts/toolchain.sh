#!/usr/bin/env bash
# Sourced by the other scripts. Works around Command Line Tools installs where a stale
# PackageDescription *.private.swiftinterface (older than libPackageDescription.dylib) breaks
# manifest linking, and where Swift Testing's macro plugin and runtime aren't on the default
# search paths. With full Xcode none of this applies and SWIFT_TEST_FLAGS stays empty.
#
# Exports: SWIFTPM_CUSTOM_LIBS_DIR (when needed), SWIFT_TEST_FLAGS (array), TESTING_HELPER

TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
SWIFT_TEST_FLAGS=()
TESTING_HELPER=""

if [[ "$DEVELOPER_DIR_PATH" == */CommandLineTools ]]; then
  CLT="$DEVELOPER_DIR_PATH"
  PM_LIBS="$CLT/usr/lib/swift/pm"

  if ls "$PM_LIBS"/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface >/dev/null 2>&1; then
    CLEAN_LIBS="$TOOLCHAIN_ROOT/.build/pm-libs"
    if [ ! -d "$CLEAN_LIBS/ManifestAPI" ] || [ "$PM_LIBS/ManifestAPI/libPackageDescription.dylib" -nt "$CLEAN_LIBS/ManifestAPI/libPackageDescription.dylib" ]; then
      rm -rf "$CLEAN_LIBS"
      mkdir -p "$CLEAN_LIBS"
      rsync -a --exclude '*.private.swiftinterface' "$PM_LIBS/ManifestAPI" "$PM_LIBS/PluginAPI" "$CLEAN_LIBS/"
    fi
    export SWIFTPM_CUSTOM_LIBS_DIR="$CLEAN_LIBS"
  fi

  SWIFT_TEST_FLAGS=(
    -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing"
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/Frameworks"
    -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib"
  )
  TESTING_HELPER="$CLT/usr/libexec/swift/pm/swiftpm-testing-helper"
fi
