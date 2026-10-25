#!/usr/bin/env bash
# Builds the test bundles outside the sandbox, then runs them inside it.
#
# Usage: Scripts/test.sh [--integration] [extra swift-testing args, e.g. --filter Trash]
#
# The bundles are executed directly (not through `swift test`) because SwiftPM wraps manifest
# evaluation in its own sandbox-exec, and macOS does not allow nesting sandboxes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"
source Scripts/toolchain.sh

if [ "${1:-}" == "--integration" ]; then
  shift
  export RECLAIM_INTEGRATION=1
  set -- --filter Integration "$@"
fi

swift build --build-tests "${SWIFT_TEST_FLAGS[@]}"
BIN_DIR="$(swift build --show-bin-path "${SWIFT_TEST_FLAGS[@]}")"

if [ -z "$TESTING_HELPER" ]; then
  # Full Xcode toolchain: swift test can run the bundles itself.
  exec Scripts/run-sandboxed.sh swift test --skip-build --disable-sandbox "$@"
fi

status=0
for bundle in "$BIN_DIR"/*Tests.xctest; do
  name="$(basename "$bundle" .xctest)"
  binary="$bundle/Contents/MacOS/$name"
  echo "== $name"
  Scripts/run-sandboxed.sh "$TESTING_HELPER" --test-bundle-path "$binary" "$binary" \
    --testing-library swift-testing "$@" || status=$?
done
exit $status
