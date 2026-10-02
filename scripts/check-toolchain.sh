#!/usr/bin/env bash
# Fails with one plain message when the selected Swift toolchain is too old to build MacIsland, instead of the confusing
# Package.swift errors an old one gives ("reference to member 'v26' cannot be resolved"). Prints nothing when all is well.
# Keep MIN_SWIFT in step with swift-tools-version in Package.swift.
set -euo pipefail

cd "$(dirname "$0")/.."
MIN_SWIFT=6.2
MIN_SDK=26
MIN_MACOS=15

fix() {
    cat >&2 <<MSG
MacIsland needs Command Line Tools 26 or later (Swift $MIN_SWIFT+, macOS $MIN_SDK SDK).

Fix:
  xcode-select --install        (or Software Update -> Command Line Tools for Xcode 26)
  sudo xcode-select -s /Library/Developer/CommandLineTools    (if an older Xcode is still selected, or was deleted)
  swift --version               (must say $MIN_SWIFT or later)
MSG
    exit 1
}

if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt "$MIN_MACOS" ]; then
    echo "MacIsland needs macOS $MIN_MACOS or later." >&2
    exit 1
fi

if ! command -v swift >/dev/null 2>&1 || ! version_text="$(swift --version 2>&1)"; then
    echo "No working Swift toolchain is selected (xcode-select -p: $(xcode-select -p 2>&1 || true))." >&2
    fix
fi

swift_version="$(printf '%s\n' "$version_text" | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -n 1)"
sdk_version="$(xcrun --show-sdk-version 2>/dev/null || echo 0)"

# True when $1 (a dotted version) is at least $2.
at_least() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]; }

if [ -z "$swift_version" ] || ! at_least "$swift_version" "$MIN_SWIFT" || [ "${sdk_version%%.*}" -lt "$MIN_SDK" ]; then
    {
        echo "The selected toolchain is too old:"
        echo "  xcode-select -p   $(xcode-select -p 2>&1 || true)"
        echo "  Swift             ${swift_version:-unknown} (need $MIN_SWIFT or later)"
        echo "  macOS SDK         $sdk_version (need $MIN_SDK or later)"
        echo
    } >&2
    fix
fi
