#!/usr/bin/env bash
# Signs each path given as "MacIsland Dev", making that identity the first time (make-signing-cert.sh), so every build is the
# same app to macOS and permissions survive rebuilds. Falls back to ad hoc when the identity can't be made or used (no login
# keychain, the keychain prompt was denied), so a build never fails over signing. MACISLAND_ADHOC=1 signs ad hoc and leaves the
# keychain alone.
set -euo pipefail

cd "$(dirname "$0")/.."

identity="-"
if [ "${MACISLAND_ADHOC:-}" != 1 ]; then
    identity="$(./scripts/signing-identity.sh)"
    if [ "$identity" = "-" ]; then
        echo "First build on this Mac: making the \"MacIsland Dev\" signing identity (see scripts/make-signing-cert.sh)" >&2
        if ./scripts/make-signing-cert.sh >&2; then
            identity="$(./scripts/signing-identity.sh)"
        else
            echo "Couldn't make it; signing ad hoc, so permissions are asked again after each rebuild" >&2
        fi
    fi
fi

for path in "$@"; do
    if [ "$identity" != "-" ]; then
        if error="$(codesign --force --sign "$identity" "$path" 2>&1 >/dev/null)"; then
            continue
        fi
        echo "Couldn't sign $path as \"MacIsland Dev\" ($error); signing it ad hoc" >&2
    fi
    if ! error="$(codesign --force --sign - "$path" 2>&1 >/dev/null)"; then
        echo "$error" >&2
        exit 1
    fi
done
