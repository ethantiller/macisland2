#!/usr/bin/env bash
# Compiles the vendored mediaremote-adapter into build/adapter/ (no cmake needed).
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="Vendor/mediaremote-adapter"
OUT="build/adapter"
FW="$OUT/MediaRemoteAdapter.framework"

rm -rf "$OUT"
mkdir -p "$FW/Versions/A/Resources"

clang -fobjc-arc -fvisibility=default -dynamiclib \
    -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -I"$SRC/include" -I"$SRC/src" \
    "$SRC"/src/adapter/*.m "$SRC/src/private/MediaRemote.m" "$SRC"/src/utility/*.m \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/MediaRemoteAdapter \
    -o "$FW/Versions/A/MediaRemoteAdapter"

cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
    <key>CFBundleName</key><string>MediaRemoteAdapter</string>
    <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
</dict>
</plist>
PLIST

ln -s A "$FW/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FW/Resources"
codesign --force --sign - "$FW" >/dev/null

# Test client: lets `mediaremote-adapter.pl ... test` check the adapter still works.
clang -fobjc-arc -Wno-gnu-folding-constant -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -I"$SRC/src/test" "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m" \
    -framework Foundation -framework MediaPlayer \
    -o "$OUT/MediaRemoteAdapterTestClient"

cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/"
echo "Built $OUT"
