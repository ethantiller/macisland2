# Scripts, config, and file map

Every script, every config file, and what every file in the repo contains. Back to the [README](../README.md). How the pieces
fit: [ARCHITECTURE.md](ARCHITECTURE.md).

**Contents:** [Cheat sheet](#cheat-sheet) · [Scripts](#scripts) · [Config files](#config-files) · [Source map](#source-map) ·
[Tests](#tests) · [Vendored code](#vendored-code) · [Generated and ignored](#generated-and-ignored) ·
[Files outside the repo](#files-outside-the-repo)

---

## Cheat sheet

| Want to | Run |
| --- | --- |
| Build and restart the app | `./scripts/bundle.sh && pkill -x MacIsland; open build/MacIsland.app` |
| Build a release bundle | `./scripts/bundle.sh release` |
| Run the tests | `./scripts/test.sh` |
| Run some tests | `./scripts/test.sh --filter PaletteModelTests` |
| Render every state to PNG | `ISLAND_SNAPSHOT_DIR=/tmp/island ./scripts/test.sh --filter IslandSnapshots` |
| Refresh the pictures in the docs | `./scripts/docs-images.sh` |
| Check style (reports only) | `./scripts/lint.sh` |
| Fail on any style finding | `./scripts/lint.sh --strict` |
| Format the code in place | `./scripts/format.sh` (see the warning below) |
| Rebuild the Now Playing adapter | `./scripts/build-adapter.sh` |
| Forget the app's macOS permissions | `tccutil reset All com.ethantiller.MacIsland` |
| Measure idle CPU | `ps -o cputime= -p $(pgrep -x MacIsland)`, ten seconds apart |
| Read a crash report | `ls -t ~/Library/Logs/DiagnosticReports \| grep MacIsland` |

---

## Scripts

All are Bash with `set -euo pipefail`, run from anywhere (each `cd`s to the repo root), and live in `scripts/`.

### `bundle.sh`

Builds the app and wraps the binary in a bundle you can open.

```
./scripts/bundle.sh [debug|release]      # default: debug
```

1. `swift build -c <config>`, then finds the built binary with `--show-bin-path`.
2. If `build/adapter/MediaRemoteAdapter.framework` does not exist, runs `build-adapter.sh` first.
3. Recreates `build/MacIsland.app/Contents/{MacOS,Resources,Frameworks}`.
4. Copies in the binary, `Support/Info.plist`, the adapter framework (into `Frameworks/`), and `mediaremote-adapter.pl` (into
   `Resources/`).
5. Ad-hoc signs the bundle (`codesign --sign -`).

Output: `build/MacIsland.app`. Because signing is ad hoc, macOS treats each build as a new app and asks for permissions again.
Launch at Login only works from this bundle.

### `test.sh`

Runs `swift test`. With only the Command Line Tools installed, Swift Testing lives outside the default search path, so when
`Testing.framework` is found under `xcode-select -p`, the script adds the framework, linker, and rpath flags (`-F`, `-rpath`)
for the compiler and linker. Extra arguments pass through to `swift test` (`--filter`, `--parallel`, and so on). Output: pass/fail
lines; 321 tests, about a second.

The **snapshot test** (`IslandSnapshots`) only runs when `ISLAND_SNAPSHOT_DIR` is set, and then writes one PNG per island state to
that folder.

### `build-adapter.sh`

Compiles the vendored `mediaremote-adapter` (Objective-C) into `build/adapter/` without cmake:

- `clang -dynamiclib` for arm64 and x86_64, macOS 14 minimum, linking Foundation, AppKit, and UniformTypeIdentifiers, into a real
  `MediaRemoteAdapter.framework` (versioned folders, symlinks, an `Info.plist`, ad-hoc signed);
- a small test client, `MediaRemoteAdapterTestClient`, for the perl script's `test` command;
- copies `Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl` next to them.

Run it by hand only after changing the vendored source; `bundle.sh` runs it once if the framework is missing. To force a rebuild,
delete `build/adapter/`.

### `docs-images.sh`

Regenerates the pictures used in the README and the docs. It runs the snapshot test into a temp folder, then copies a fixed list of
states into `docs/images/`. Run it after a UI change so the docs still match the app. The list of images is at the top of the
script; add a name there (and a state in `Tests/MacIslandTests/IslandSnapshots.swift`) to add a picture.

The pictures are `ImageRenderer` output: exact layout, type, and color, but no Liquid Glass, text fields, or horizontal scroll
views, and the sound bars are frozen at rest.

### `lint.sh`

Reports style findings with Swift's built-in formatter (`swift format lint`, part of the Swift 6 toolchain; nothing to install).
Rules are in [`.swift-format`](#config-files). It changes nothing.

```
./scripts/lint.sh              # print findings and a count; exit 0
./scripts/lint.sh --strict     # exit 1 if there are any
```

The code was written before there was a formatter: at the time of writing there are about **490 findings** (mostly continuation-line
indentation, blank lines, and long lines), so `--strict` fails today. Use the plain form to see them.

### `format.sh`

Formats in place with `swift format format`, using [`.swift-format`](#config-files).

```
./scripts/format.sh                 # all of Sources/ and Tests/
./scripts/format.sh path/to/File.swift ...    # only these files
```

> It has **never been run over the whole codebase**, so the first run will make a large diff. Commit first, run it, read the
> result, run `./scripts/test.sh`, then commit the formatting on its own.

---

## Config files

| File | Contains |
| --- | --- |
| `Package.swift` | Tools version 6.2, `platforms: [.macOS(.v26)]`, an executable target `MacIsland` (`Sources/MacIsland`) and a test target `MacIslandTests` (`Tests/MacIslandTests`), both in **Swift 5 language mode**. No dependencies |
| `Support/Info.plist` | The bundle's identity (`com.ethantiller.MacIsland`, version 0.1.0), `LSUIElement` (no Dock icon), `LSMinimumSystemVersion`, and the permission reasons: Calendars, Reminders, Bluetooth, Focus status, Downloads folder, Apple Events, Camera, Microphone, Speech recognition, and the `macisland` URL scheme |
| `.swift-format` | 4-space indent, 120-column lines, at most one blank line, existing line breaks respected; rules that would fight this codebase's style (force unwraps, naming, doc comments) are off; imports must be ordered |
| `.gitignore` | `.build/`, `.swiftpm/`, `build/`, Xcode user data, `.DS_Store`, secrets files, and `.claude` |
| `CLAUDE.md` | Instructions Claude Code loads in this repo: read the design doc first, tokens and components only, where things live, the commands |
| `DESIGN.md` | The design system and per-module design notes |

There is no CI, no linter config other than `.swift-format`, and no dependency manager.

---

## Source map

Every Swift file in `Sources/MacIsland/` (75 files, about 10,000 lines). One folder per feature: a model plus its view.

### `App/`

| File | Contains |
| --- | --- |
| `MacIslandApp.swift` | The `@main` `App` (menu-bar capsule, Settings, module menu bars), `AppDelegate` (builds `IslandFeatures`, wires every monitor to the view model, the hotkeys, the panel), `ModuleMenuBars`, `MenuBarModuleView` |
| `URLCommand.swift` | `URLCommand` (the `macisland://` parser and its limits) and `URLCommandRunner` (runs them, rate-limits banners) |
| `FloatingPanels.swift` | `FloatingPanels` (torn-off windows, one per module, Keep on Desktop), `DetachedPanelState`, `DetachedModuleView` (the glass window's chrome) |

### `Island/` (panel, input, state, drawing)

| File | Contains |
| --- | --- |
| `IslandPanel.swift` | The always-there `NSPanel`: borderless, non-activating, over everything, click-through by default, first-click-acts hosting view |
| `ScreenGeometry.swift` | Notch detection and sizes; `panelSize` (560 x 260); `islandRect(for:)` |
| `MouseTracker.swift` | Global and local event monitors: hover, click-through, file-drag detection, swipes, click-outside |
| `SwipeRecognizer.swift` | Turns one gesture's scroll deltas into down, up, left, or right, once |
| `IslandViewModel.swift` | `IslandModule`, `ClockMode`, `IslandAlert`, `IslandBanner`, `CompactActivity`, `IslandFeatures`, the view model itself, and `TrailingStrip` (what fits right of the notch) |
| `IslandView.swift` | The island's content: the tab strip, compact layers and pair, banners, the file drop target, the settings and pencil buttons |
| `IslandContainer.swift` | `IslandPresentation`, `IslandSurface`, and the container that draws the outline, surface, size, and swell |
| `NotchShape.swift` | The island outline (flat top, concave flares, continuous bottom corners) |
| `PeekContent.swift` | What each peek shows, and the idle peek |
| `ModuleContent.swift` | The one module-to-view switch used everywhere |
| `Theme.swift` | All design tokens: `Palette`, `SurfaceInk`, `Tint` (with `Tint.airDrop`, the AirDrop half of the drop target), `Typography`, `Metrics`, `Timing`, `Motion`, `BlurFade`, the `\.islandSurface` key |
| `Components.swift` | Shared controls: `IconButton`, `ChipButton`, `SegmentedChoice`, `IslandSlider`, `ArtworkView`, `ProgressRing`, `ChargingBadge`, `AirDropGlyph`, `Glyph`, `IslandButtonStyle`, `formatTime` |
| `FloatingGlass.swift` | The `floatingGlass()` modifier (padding plus Liquid Glass) |
| `FloatingGlassPanel.swift` | The floating window class (palette and window styles) and the `\.isFloatingWindow` key |

### `Home/`

| File | Contains |
| --- | --- |
| `HomeView.swift` | The Home module: two rows of widgets, and the month calendar it opens |
| `HomeWidgets.swift` | The boxes: `TimeWidget`, `MediaWidget`, `QuickActionsGrid`, `HomeAction` and `HomeActionPill` |
| `HomeCards.swift` | Pieces the idle peek reuses: `DateInline`, `UpNextLabel`, `QuickToolsRow`, `QuickToolButton`, `QuickTimerChips`, `MacBatteryGlance` |
| `MonthGrid.swift` | Six-week month layout and its view |

### `NowPlaying/`

| File | Contains |
| --- | --- |
| `NowPlayingModel.swift` | State, artwork, accent color, transport (direct to Music/Spotify, else the adapter), shuffle, repeat, Favorite, app volume |
| `NowPlayingState.swift` | The state struct, `RepeatMode`, and the parser for the adapter's JSON lines |
| `MediaRemoteAdapter.swift` | Runs the perl adapter: the `stream` process (restarted if it exits) and one-shot commands |
| `NowPlayingView.swift` | The player layout, scrubber, volume, output picker, lyric line, `EqualizerView`, the compact play control, and the shared `mediaNamespace` |
| `PlayerScripting.swift` | `ScriptablePlayer` (Music, Spotify), `PlayerCommand`, and AppleScript for volume, Favorite, transport, seek |
| `Lyrics.swift` | LRC parsing and `LyricsModel` (LRCLIB lookup, per-track cache) |
| `ArtworkAccent.swift` | Picks the most vivid color in the art and lifts it to read on black |

### `Timer/`

| File | Contains |
| --- | --- |
| `TimerModel.swift` | Countdown with pause, add-minutes, an end date |
| `StopwatchModel.swift` | Drift-free stopwatch with laps, and `formatStopwatch` |
| `PomodoroModel.swift` | Phases, chaining, the session history and streak |
| `TimerView.swift` | The Clock tab (rings, presets, laps, the Pomodoro chart), the compact readouts, and the timer, Pomodoro, and stopwatch peeks |

### `Shelf/`

| File | Contains |
| --- | --- |
| `ShelfModel.swift` | The files on the Shelf (paths only) and AirDrop |
| `ShelfView.swift` | The Files and Clipboard views, drop tiles, item and card views with their menus |
| `ClipboardHistory.swift` | The pasteboard poller and the ten-item, memory-only history, and `matches` for the palette |
| `SmartAction.swift` | Detects a lone link, address, or `#hex` color and names the action |
| `FileTools.swift` | Zip, unzip, and the Shelf jobs (convert, combine, resize, compress, Copy Text), unique names |
| `Converters.swift` | `FileKind`, `ConversionTarget`, and every converter: images, documents, PDF, video, audio, plus `MarkdownText` |
| `TextRecognizer.swift` | `RecognizedText`, `TextRecognizing`, and the Vision recognizer |
| `ScreenshotWatcher.swift` | A Spotlight query for new screenshots |

### `Tools/`

| File | Contains |
| --- | --- |
| `ToolID.swift` | The eleven tools and the default pins |
| `ToolCatalog.swift` | What each tool is and does (shared by the Tools tab, Home, the peek, and the palette) |
| `ToolsView.swift` | The Tools tab: row (or the Mirror), grid, Ring Light sliders, Keep Awake chips; `ControlButton` |
| `CameraMirror.swift` | `CameraMirror`, `CameraSessionProviding`, the AVFoundation provider, and the preview layer view |
| `MirrorView.swift` | The Mirror: preview, Ring Light, Done |
| `ScreenRecorder.swift` | `ScreenRecorder` (30-minute cap), the ScreenCaptureKit recorder, and `RegionPicker` |
| `KeepAwake.swift` | The power assertion, with durations |
| `LowPowerMode.swift` | Reads Low Power Mode and toggles it (admin prompt) |
| `RingLight.swift` | The screen-edge glow (a click-through window) |
| `MicrophoneMute.swift` | Mutes the default input device |
| `KeyboardCleaner.swift` | The event tap that swallows keys for 30 seconds |
| `AudioOutputs.swift` | Output devices and the default one |
| `SystemActions.swift` | Eyedropper, hex strings, clipboard, area screenshot, Lock Screen |

### `Agenda/`

| File | Contains |
| --- | --- |
| `AgendaMonitor.swift` | EventKit: next event or reminder, announcements, the reminder list, adding and completing; `ReminderRow`; meeting-link finding; timing rules |
| `AgendaView.swift` | `IdleView` (the agenda row) and `AgendaAction` |
| `RemindersView.swift` | The Reminders tab |

### `Notes/`, `Weather/`, `Launch/`, `Palette/`

| File | Contains |
| --- | --- |
| `Notes/NotesModel.swift` | Notes and snippets, saved as one JSON file after a pause in typing |
| `Notes/VoiceRecorder.swift` | `VoiceRecorder` (10-minute cap), `Transcribing`, the level meter, and the on-device Speech transcriber |
| `Notes/NotesView.swift` | The Notes tab: lists, editors, the Prompter |
| `Weather/WeatherModel.swift` | Open-Meteo geocoding and forecast (with quarter-hour rain), WMO code names, `WeatherGlance` |
| `Weather/RainRule.swift` | `RainSample`, `RainRule` (dry now, 0.2 mm within 30 minutes), `RainSpell` (once per spell) |
| `Launch/AppIndex.swift` | Scans app folders for the palette |
| `Launch/ShortcutsCLI.swift` | `shortcuts list` and `shortcuts run` |
| `Launch/LaunchModel.swift` | Holds the app index and the Shortcuts list for the palette |
| `Palette/PaletteModel.swift` | Builds and ranks the rows; translation states; answer rows (define, units, currency, calculate) and `clip` rows |
| `Palette/Answers.swift` | `DictionaryLookup`, `DictionaryText`, `UnitConversion`, `Calculator`, `CurrencyRequest` |
| `Palette/ExchangeRates.swift` | The Frankfurter rates, cached 12 hours per base |
| `Palette/PaletteSearch.swift` | Match scoring, the timer parser, the translation parser |
| `Palette/SearchEngine.swift` | The nine engines, custom ones, URL building, keyword matching |
| `Palette/PaletteView.swift` | The panel's content on Liquid Glass |
| `Palette/PaletteController.swift` | Shows and hides the panel; reads Esc, Return, and arrows |

### `System/` and `Transfers/`

| File | Contains |
| --- | --- |
| `System/BatteryMonitor.swift` | Charger, 20% and 10%, and the full-charge level; the battery glyph |
| `System/VolumeMonitor.swift` | External drive mounts, and eject |
| `System/AudioAccessoryMonitor.swift` | Bluetooth headphones connecting, and their battery |
| `System/PrivacyMonitor.swift` | Which app is using the microphone |
| `System/NetworkMonitor.swift` | Personal Hotspot detection |
| `System/FocusMode.swift` | Whether a Focus is on; switching through Shortcuts |
| `System/DiskSpace.swift` | `DiskRule` (warn under 10 GB, re-arm above 15 GB) and `DiskSpace`, checked on events |
| `System/BluetoothDevices.swift` | Paired audio devices, connecting, and `IOBluetoothProvider` behind `BluetoothDeviceProviding` |
| `System/WorkTracker.swift` | The "in progress" job list |
| `Transfers/TransferMonitor.swift` | Progress of files arriving in Downloads |

### `Settings/`

| File | Contains |
| --- | --- |
| `AppSettings.swift` | Every setting, its storage, the tab sides, menu-bar modules, search engines, pinned tools |
| `SettingsView.swift` | The Settings window and its tab lists |
| `GlobalHotkey.swift` | Carbon hotkeys with ids |
| `LaunchAtLogin.swift` | Start at login (bundle only) |

---

## Tests

`Tests/MacIslandTests/`: 18 files, about 3,700 lines, **321 tests**. Swift Testing.

| File | Covers |
| --- | --- |
| `TestSupport.swift` | `makeViewModel()`: a view model from test doubles |
| `KeyboardTests.swift` | Hotkey pinning, arrow tabs, banners |
| `PresentationTests.swift` | Hover, peek, expanded, banner widths, drag target, the hidden pill, swipes |
| `SettingsTests.swift` | Hotkey, tabs |
| `FeatureTests.swift`, `ToolsTests.swift` | Timer, stopwatch, tools, clipboard |
| `NowPlayingStateTests.swift`, `ArtworkAccentTests.swift` | The stream parser, elapsed time, accent color |
| `Phase2Tests.swift` | Minimal pairs, full charge, Keep Awake, drives, screenshots |
| `PlanFeatureTests.swift` | Agenda rules, meeting links, pinned tools, drop tiles |
| `MediaTests.swift` | LRC, lyrics, transport, shuffle and repeat, players |
| `Phase4Tests.swift` | Pomodoro, month grid, weather, smart actions, file tools, notes, Clean Keys, reminders, the strip, the tab sides |
| `Phase5Tests.swift` | Search engines, ranking, parsers, apps, Shortcuts, the palette model, menu bar and windows, the player layout, transport routing |
| `ShelfToolsTests.swift` | File kinds and targets, Copy Text, document, PDF, image, audio, and video conversions |
| `ClipboardTests.swift` | History search, plain-text copy, Save as Snippet, the `clip` palette rows |
| `AnswersTests.swift` | Definitions, units, the calculator, currency parsing and rates, the answer rows, `macisland://` links, Lock Screen |
| `AmbientTests.swift` | Rain rules and forecast, disk space rules, the Bluetooth device list |
| `CaptureTests.swift` | The Mirror, two-action banners, screen and voice recording, the recording activity, the new tools |
| `IslandSnapshots.swift` | Opt-in: renders states to PNG |

---

## Vendored code

`Vendor/mediaremote-adapter/` is [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) at `73f14ab`
(BSD-3-Clause; `LICENSE`, and `VENDORED.txt` says how it was taken):

| Path | Contains |
| --- | --- |
| `bin/mediaremote-adapter.pl` | The perl entry point: `stream`, `get`, `send`, `seek`, `shuffle`, `repeat`, `speed`, `test` |
| `src/adapter/` | The Objective-C that talks to MediaRemote (state, commands, streaming, diffs) |
| `src/private/` | The private MediaRemote declarations |
| `src/utility/`, `src/test/`, `include/` | Helpers, the test client, the public header |

---

## Generated and ignored

| Path | What | Made by |
| --- | --- | --- |
| `.build/` | SwiftPM build products | `swift build`, `swift test` |
| `build/adapter/` | The compiled adapter framework, perl script, test client | `build-adapter.sh` |
| `build/MacIsland.app` | The app bundle | `bundle.sh` |
| `docs/images/` | Pictures for the docs (committed) | `docs-images.sh` |

---

## Files outside the repo

These matter to the project but are **not** in git.

| File | What |
| --- | --- |
| `~/Library/Application Support/MacIsland/notes.json` | Your notes and snippets (the app's data) |
| `~/Library/Preferences/com.ethantiller.MacIsland.plist` | Settings (UserDefaults) |
| `~/.claude/projects/-Users-ethantiller-git-mac-island/memory/` | Claude's saved notes about how you like to work (minimal Apple design; rebuild and relaunch after UI changes), the project status, and how you like plans written |
