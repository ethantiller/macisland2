#!/usr/bin/env bash
# Regenerates the pictures used in README.md and docs/: renders every island state to PNG with the snapshot test,
# then copies the ones the docs use into docs/images/. Run it after a UI change so the docs still match the app.
#
# The renders come from SwiftUI's ImageRenderer, so they show layout, type, and color, but not Liquid Glass, text
# fields, or horizontal scroll views. Check those in the running app.
set -euo pipefail

cd "$(dirname "$0")/.."
RENDERS="${TMPDIR:-/tmp}/island-docs"
rm -rf "$RENDERS"
ISLAND_SNAPSHOT_DIR="$RENDERS" ./scripts/test.sh --filter IslandSnapshots
ISLAND_SNAPSHOT_DIR="$RENDERS" ./scripts/test.sh --filter WidgetSizeSnapshots
ISLAND_SNAPSHOT_DIR="$RENDERS" ./scripts/test.sh --filter OnboardingSnapshots

mkdir -p docs/images
# Keep this list in step with the images the docs mention.
for name in \
    03-compact-media-playing 09b-compact-pair-timer-media 10-compact-alert 13-compact-charging \
    11-banner-airpods 12-banner-low-battery \
    03e-peek-idle-weather 03b-peek-media 03i-peek-choose-activity 03f-peek-timer-compact 03g-peek-pomodoro 03h-peek-stopwatch \
    04a-expanded-home 04a-expanded-home-calendar 04-expanded-media 04b-expanded-media-lyrics 04g-expanded-media-mixer 04h-expanded-media-mixer-needs-access \
    04c-expanded-reminders 04e-right-tab 05-expanded-shelf-empty 05d-expanded-shelf-downloads 06-expanded-timer 06b-expanded-pomodoro 06c-expanded-timer-setter 04f-home-preset-3-listening 04f-home-preset-5-dashboard 31-widget-sizes \
    07-expanded-stopwatch 08a-expanded-tools-more 08c-expanded-tools-eight 08d-expanded-notes \
    12b-banner-two-actions 14-compact-recording 14b-peek-voice \
    40-guide-01-welcome 40-guide-06-modules 40-guide-09-calendars 40-guide-19-finish 43-tour-03-shortcut; do
    cp "$RENDERS/$name.png" "docs/images/$name.png"
done
echo "Copied $(ls docs/images | wc -l | tr -d ' ') images to docs/images/"
