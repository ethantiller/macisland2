#!/usr/bin/env bash
# Builds MacIsland and wraps the binary in build/MacIsland.app (ad-hoc signed).
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [ ! -d build/adapter/MediaRemoteAdapter.framework ]; then
    ./scripts/build-adapter.sh
fi

APP="build/MacIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/MacIsland" "$APP/Contents/MacOS/MacIsland"
cp Support/Info.plist "$APP/Contents/Info.plist"
for resource_bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$resource_bundle" ] || continue
    cp -R "$resource_bundle" "$APP/Contents/Resources/"
done
# The adapter framework is loaded by /usr/bin/perl at runtime, not linked into the app.
cp -R build/adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp build/adapter/mediaremote-adapter.pl "$APP/Contents/Resources/"

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
