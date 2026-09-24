#!/bin/bash
# Selects the Xcode every macOS job builds with, and says which.
#
# The audit asked for Xcode 27 rather than whatever `macos-latest` happens to
# map to. GitHub's runner images ship several Xcodes side by side; this picks
# the newest Xcode 27 if the image has one, otherwise the newest installed,
# and writes the choice to the job summary so a toolchain change is visible
# rather than silent. Set ZOON_REQUIRE_XCODE_MAJOR to make a missing major
# version fail instead of falling back.
set -euo pipefail

pick() {
  ls -d /Applications/Xcode_"$1"*.app 2>/dev/null \
    | grep -E 'Xcode_[0-9]+(\.[0-9]+)*\.app$' \
    | sort -t_ -k2 -V | tail -1
}

CHOSEN="$(pick 27 || true)"
if [ -z "$CHOSEN" ]; then
  if [ -n "${ZOON_REQUIRE_XCODE_MAJOR:-}" ]; then
    echo "Xcode ${ZOON_REQUIRE_XCODE_MAJOR} is not installed on this runner image." >&2
    ls -d /Applications/Xcode*.app >&2 || true
    exit 1
  fi
  CHOSEN="$(pick '' || true)"
fi
if [ -z "$CHOSEN" ]; then
  echo "No versioned Xcode found under /Applications; keeping the default." >&2
  xcodebuild -version
  exit 0
fi

sudo xcode-select -s "$CHOSEN/Contents/Developer"
{
  echo "### Toolchain"
  echo ""
  echo "Selected \`$(basename "$CHOSEN")\` (Xcode 27 preferred; installed: $(ls -d /Applications/Xcode_*.app 2>/dev/null | xargs -n1 basename | tr '\n' ' '))"
  echo '```'
  xcodebuild -version
  echo '```'
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
