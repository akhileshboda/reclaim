#!/usr/bin/env bash
# Runs a command inside the Reclaim write sandbox (Scripts/reclaim-test.sb), but only after a
# canary check proves the sandbox actually blocks writes to $HOME and ~/.Trash.
#
# Usage: Scripts/run-sandboxed.sh <command> [args...]
#        Scripts/run-sandboxed.sh --canary-only
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SANDBOX_DIR="${RECLAIM_SANDBOX_DIR:-${TMPDIR:-/tmp}/reclaim-sandbox}"
mkdir -p "$SANDBOX_DIR" "$ROOT/.build" "$ROOT/build"
SANDBOX_DIR="$(cd "$SANDBOX_DIR" && pwd -P)"

SB=(sandbox-exec -f "$ROOT/Scripts/reclaim-test.sb"
    -D "HOME=$HOME"
    -D "REPO_BUILD=$ROOT/.build"
    -D "APP_BUILD=$ROOT/build"
    -D "SANDBOX_DIR=$SANDBOX_DIR")

fail() { echo "canary: FAIL - $*; aborting" >&2; exit 70; }

canary() {
  local probe="$HOME/.reclaim-sandbox-canary-$$"
  if "${SB[@]}" /usr/bin/touch "$probe" 2>/dev/null; then
    rm -f "$probe"; fail "sandbox allowed a write to \$HOME"
  fi
  echo "canary: write to \$HOME denied"

  probe="$HOME/.Trash/.reclaim-sandbox-canary-$$"
  if "${SB[@]}" /bin/mkdir "$probe" 2>/dev/null; then
    rmdir "$probe"; fail "sandbox allowed a write to ~/.Trash"
  fi
  echo "canary: write to ~/.Trash denied"

  probe="$ROOT/Sources/.reclaim-sandbox-canary-$$"
  if "${SB[@]}" /usr/bin/touch "$probe" 2>/dev/null; then
    rm -f "$probe"; fail "sandbox allowed a write to the repo sources"
  fi
  echo "canary: write to repo sources denied"

  probe="$SANDBOX_DIR/.reclaim-sandbox-canary-$$"
  "${SB[@]}" /usr/bin/touch "$probe" || fail "sandbox blocked its own scratch directory"
  rm -f "$probe"
  echo "canary: write to sandbox dir allowed"

  if [ -d /Volumes/RTEST-SSD ]; then
    probe="/Volumes/RTEST-SSD/.reclaim-sandbox-canary-$$"
    "${SB[@]}" /usr/bin/touch "$probe" || fail "sandbox blocked the RTEST-SSD test volume"
    rm -f "$probe"
    echo "canary: write to /Volumes/RTEST-SSD allowed"
  fi
}

canary
[ "${1:-}" == "--canary-only" ] && exit 0

export RECLAIM_SANDBOXED=1 RECLAIM_SANDBOX=1 RECLAIM_SANDBOX_DIR="$SANDBOX_DIR"
exec "${SB[@]}" "$@"
