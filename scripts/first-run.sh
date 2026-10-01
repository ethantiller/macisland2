#!/usr/bin/env bash
# Puts this Mac back to a first run, to test the welcome guide and its permission steps: quits MacIsland, resets every permission it
# was given, marks the install as fresh and the guide and tour as never seen, forgets which permissions were asked for, and opens the
# app. Dev only. The order matters: the preferences daemon caches, so the app must be quit before the preferences change, and the
# preferences must be written (not deleted) before it launches.
set -euo pipefail

cd "$(dirname "$0")/.."
ID="com.ethantiller.MacIsland"
APP="build/MacIsland.app"

[ -d "$APP" ] || { echo "No $APP: run 'make bundle' first." >&2; exit 1; }

# 1. Quit it, so nothing rewrites the preferences behind us.
pkill -x MacIsland 2>/dev/null || true
for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x MacIsland >/dev/null || break; sleep 0.3; done

# 2. Forget every permission the system gave it.
tccutil reset All "$ID" >/dev/null 2>&1 || true

# 3. Write the first-run state. `fresh` is written, not the key deleted: a deleted key would be read as an existing install.
defaults write "$ID" onboarding.install fresh
defaults write "$ID" onboarding.guide -int 0
defaults write "$ID" onboarding.settingsTour -int 0
# The guide's own record of what it asked: Downloads and Automation can't be read back, so it is remembered here.
defaults delete "$ID" access.asked 2>/dev/null || true

# 4. Launch it.
open -n "$APP"
echo "MacIsland reset to a first run and opened."
