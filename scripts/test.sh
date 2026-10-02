#!/usr/bin/env bash
# Runs unit tests. With only the Command Line Tools installed, Swift Testing lives
# outside the default search path, so point the compiler and linker at it.
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/check-toolchain.sh
DEV="$(xcode-select -p)/Library/Developer"
FW="$DEV/Frameworks"
if [ -d "$FW/Testing.framework" ]; then
    swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$DEV/usr/lib" \
        "$@"
else
    swift test "$@"
fi
