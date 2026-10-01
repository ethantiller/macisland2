#!/usr/bin/env bash
# Prints the identity to sign builds with: "MacIsland Dev" (see make-signing-cert.sh) when it is in the keychain, or "-" (ad hoc) when not.
# Self-signed, so macOS calls it untrusted; codesign signs with it all the same, and that is all TCC needs to keep permissions.
set -euo pipefail

hash="$(security find-identity -p codesigning 2>/dev/null | awk '/"MacIsland Dev"/ { print $2; exit }')"
echo "${hash:--}"
