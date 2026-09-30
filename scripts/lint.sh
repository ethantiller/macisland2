#!/usr/bin/env bash
# Reports style problems with Swift's built-in formatter (`swift format`, in the Swift 6 toolchain). Changes nothing.
# The rules are in .swift-format. The code was written before there was a formatter, so expect findings: this
# exits 0 unless you pass --strict, which fails on any finding.
set -euo pipefail

cd "$(dirname "$0")/.."
strict=false
[ "${1:-}" = "--strict" ] && strict=true

flags=(--configuration .swift-format --recursive)
$strict && flags+=(--strict)

output="$(swift format lint "${flags[@]}" Sources Tests 2>&1 || true)"
if [ -n "$output" ]; then
    echo "$output"
    echo
    echo "$(echo "$output" | grep -c 'warning:\|error:') findings. Fix them with ./scripts/format.sh"
    $strict && exit 1
    exit 0
fi
echo "No style findings."
