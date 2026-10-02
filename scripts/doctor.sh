#!/usr/bin/env bash
# Prints what is needed to work out why MacIsland won't build or run: the Mac, the selected toolchain, the checkout, the
# built app, and the newest crash report. Changes nothing. Paste the output when asking for help.
set -uo pipefail

cd "$(dirname "$0")/.."
APP="build/MacIsland.app"

echo "== Mac"
echo "macOS     $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"

echo "== Toolchain"
echo "xcode-select -p   $(xcode-select -p 2>&1)"
echo "Swift             $(swift --version 2>&1 | head -n 1)"
echo "macOS SDK         $(xcrun --show-sdk-version 2>&1 | head -n 1)"
echo "Command Line Tools  $(pkgutil --pkg-info com.apple.pkg.CLTools_Executables 2>/dev/null | sed -n 's/^version: //p')"
if check="$(./scripts/check-toolchain.sh 2>&1)"; then
    echo "check-toolchain   ok"
else
    echo "check-toolchain   FAILED"
    printf '%s\n' "$check" | sed 's/^/  /'
fi

echo "== Checkout"
echo "commit    $(git log -1 --format='%h %s' 2>&1)"
echo "changes   $(git status --short 2>/dev/null | wc -l | tr -d ' ') file(s) changed or untracked"

echo "== Built app"
if [ -d "$APP" ]; then
    echo "bundle    $APP, built $(stat -f '%Sm' "$APP/Contents/MacOS/MacIsland")"
    echo "minos     $(otool -l "$APP/Contents/MacOS/MacIsland" | awk '/LC_BUILD_VERSION/ {f=1} f && /minos/ {print $2; exit}')"
    echo "signed    $(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p; s/^Signature=//p' | head -n 1)"
    echo "adapter   $([ -d "$APP/Contents/Frameworks/MediaRemoteAdapter.framework" ] && echo present || echo MISSING)"
else
    echo "bundle    not built yet (make bundle)"
fi
echo "running   $(pgrep -x MacIsland >/dev/null && echo yes || echo no)"

echo "== Newest crash report"
crash="$(ls -t "$HOME"/Library/Logs/DiagnosticReports/MacIsland* 2>/dev/null | head -n 1)"
echo "${crash:-none}"
