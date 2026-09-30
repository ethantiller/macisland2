#!/usr/bin/env bash
# Formats Sources/ and Tests/ in place with `swift format`, using the rules in .swift-format.
# It has not been run over the whole codebase yet, so the first run makes a large diff: commit first, run it,
# review the result, and run ./scripts/test.sh before committing it. Pass paths to format only some files.
set -euo pipefail

cd "$(dirname "$0")/.."
if [ "$#" -gt 0 ]; then
    swift format format --configuration .swift-format --in-place "$@"
else
    swift format format --configuration .swift-format --recursive --in-place Sources Tests
fi
echo "Formatted."
