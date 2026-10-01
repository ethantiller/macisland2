# MacIsland

A Dynamic Island for the MacBook notch: a borderless `NSPanel` hosting SwiftUI, built as a Swift
package (Command Line Tools only, no Xcode project).

## Design

**Read `DESIGN.md` before any UI change and follow it.** The island is black and white, and the
only color is the color of what's live. All colors, fonts, and sizes come from
`Sources/MacIsland/Island/Theme.swift`, and controls come from `Island/Components.swift`. Keep
the island clean: prefer removing or reusing over adding. The tab strip shows up to five tabs left of the notch and one right of it (arranged in Settings); don't raise that.

## Docs

Start with `README.md`, then `docs/ROADMAP.md` (status, what is next, what has not been hand-tested) and `docs/ARCHITECTURE.md` (how it
works, and the gotchas). `docs/FEATURES.md` is the feature reference; `docs/SCRIPTS.md` maps every script and file. Keep them in step
with changes, and run `./scripts/docs-images.sh` after a UI change.

## Commands

- Build and run: `make build-and-restart`
  (UI changes are only visible after this).
- Tests: `./scripts/test.sh`
- Visual review: `ISLAND_SNAPSHOT_DIR=/tmp/island ./scripts/test.sh --filter IslandSnapshots`
- Refresh the docs pictures: `./scripts/docs-images.sh`
- Style: `./scripts/lint.sh` (reports; `--strict` fails) and `./scripts/format.sh` (never run over the whole codebase yet)

## Layout

- `App/`: entry point, menu bar item, wiring.
- `Island/`: panel, geometry, hover and click-through tracking, view model, theme, shared components.
- One folder per feature (`NowPlaying/`, `Shelf/`, `Timer/`, `Tools/`, `System/`, `Agenda/`, `Home/`, `Weather/`, `Notes/`, `Widgets/`): a model plus its view.
- `Settings/`: the Settings window (an `NSWindow` made by `App/SettingsWindowController.swift`), its tour, and `AppSettings`.
- `Onboarding/`: the first-run guide (state, steps and copy, model, view, permission requests); its window is `App/OnboardingWindowController.swift`.
- `Vendor/mediaremote-adapter`: Now Playing access via `/usr/bin/perl` (Apple restricts MediaRemote since macOS 15.4).

## Working style

When the user asks for ideas, options, or a plan, give them that and stop. Don't start building or changing anything until they say to go ahead.

Use RTK commands first before others 
Command:   rtk hook claude
RTK.md:    /Users/ethantiller/.claude/RTK.md (awareness: default)
CLAUDE.md: @RTK.md reference added