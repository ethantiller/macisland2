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
| Check style | `make lint` |
| Format Swift sources in place | `make format` (see the warning below) |
| Build the app bundle | `make bundle` |
| Restart the built app | `make restart` |
| Build and restart the app | `make build-and-restart` |
| Build and restart the app | `make build-and-restart` |
| Build signed ad hoc, leaving the keychain alone | `MACISLAND_ADHOC=1 make bundle` |
| Build a release bundle | `./scripts/bundle.sh release` |
| Run the tests | `./scripts/test.sh` |
| Run some tests | `./scripts/test.sh --filter WidgetTests` |
| Render every state to PNG | `ISLAND_SNAPSHOT_DIR=/tmp/island ./scripts/test.sh --filter IslandSnapshots` |
| Refresh the pictures in the docs | `./scripts/docs-images.sh` |
| Check style (reports only) | `./scripts/lint.sh` |
| Fail on any style finding | `./scripts/lint.sh --strict` |
| Format the code in place | `./scripts/format.sh` (see the warning below) |
| Rebuild the Now Playing adapter | `./scripts/build-adapter.sh` |
| Show the first-run guide again | `open macisland://guide` |
| Test the guide on a dev Mac from a true first run | `make first-run` (after `make bundle`): quits MacIsland, `tccutil reset All`, writes `onboarding.install fresh` and the guide and tour as never seen, forgets which permissions were asked, the last Automation answers, and the step the guide stopped at, and opens the app |
| Open Settings on its tour | `open macisland://tour` |
| See the guide as a fresh install would (debug builds) | `open 'macisland://guide?reset=1'` |
| Forget the app's macOS permissions | `tccutil reset All com.ethantiller.MacIsland` |
| Measure idle CPU | `ps -o cputime= -p $(pgrep -x MacIsland)`, ten seconds apart |
| Read a crash report | `ls -t ~/Library/Logs/DiagnosticReports \| grep MacIsland` |

---

## Scripts

All are Bash with `set -euo pipefail`, run from anywhere (each `cd`s to the repo root), and live in `scripts/`.

### `first-run.sh` (`make first-run`)

Dev only. Puts this Mac back to a true first run, to test the guide's permission steps. In this order, because the preferences daemon caches: quits MacIsland, runs `tccutil reset All com.ethantiller.MacIsland`, **writes** `onboarding.install fresh` (writing, not deleting: a deleted key would be read as an existing install), `onboarding.guide 0`, and `onboarding.settingsTour 0`, deletes `access.asked` (what the guide asked), `access.automation` (the last answer for Music and Spotify), and `onboarding.resumeStep` (where the guide stopped), and opens `build/MacIsland.app`. Run `make bundle` first.

### `bundle.sh`

Builds the app and wraps the binary in a bundle you can open.

```
./scripts/bundle.sh [debug|release]      # default: debug
```

1. `swift build -c <config>`, then finds the built binary with `--show-bin-path`.
2. If `build/adapter/MediaRemoteAdapter.framework` does not exist, runs `build-adapter.sh` first.
3. Recreates `build/MacIsland.app/Contents/{MacOS,Resources,Frameworks}`.
4. Copies in the binary, `Support/Info.plist`, SwiftPM's resource bundle (into `Contents/Resources/`), the adapter framework (into
  `Frameworks/`), and `mediaremote-adapter.pl` (into `Resources/`).
5. Signs the bundle with `sign.sh`: as "MacIsland Dev", which the first build on a Mac makes, or ad hoc (`codesign --sign -`) when
  that identity can't be made or used.

Output: `build/MacIsland.app`. Signed as "MacIsland Dev", its designated requirement is the bundle ID and that certificate, so
Accessibility and the other permissions carry over from build to build. Ad hoc, the requirement is the build's hash: each build is a
new app to macOS, and a permission switch that still shows on in System Settings belongs to an old build (remove the entry, or
`tccutil reset Accessibility com.ethantiller.MacIsland`, and allow it again).
Launch at Login only works from this bundle.

### `sign.sh`

```sh
./scripts/sign.sh PATH...
```

Signs each path as "MacIsland Dev" (`signing-identity.sh` finds it). When there is none, it runs `make-signing-cert.sh` first, so
the first build on a Mac sets signing up with nothing to do by hand. If the identity can't be made (no login keychain) or used (the
keychain prompt was denied, or the keychain is locked, as over SSH), it says so and signs ad hoc: a build never fails over signing.
`MACISLAND_ADHOC=1` signs ad hoc without looking at the keychain (CI, or to keep the certificate off a Mac). `bundle.sh` signs the
app with it and `build-adapter.sh` the adapter framework.

### `make-signing-cert.sh`

Run by `sign.sh` on the first build; by hand only to make the identity ahead of time. Makes a self-signed code-signing
certificate, "MacIsland Dev" (ten years, RSA 2048, code signing only), with macOS's own `/usr/bin/openssl` (a Homebrew OpenSSL 3
writes PKCS#12 that `security import` can't read), and imports it and its key into the login keychain with `/usr/bin/codesign` allowed to use the key. Does nothing if it is
already there. macOS lists it as untrusted (`CSSMERR_TP_NOT_TRUSTED`), which does not matter: codesign signs with it, and TCC matches
on the certificate. After the first build signed with it, allow each permission once more; macOS may also ask once whether
codesign may use the key (choose Always Allow). To undo: delete "MacIsland Dev" in Keychain Access, and build with
`MACISLAND_ADHOC=1` so it isn't made again.

### `signing-identity.sh`

Prints the SHA-1 of the "MacIsland Dev" identity, or `-` when there is none. `sign.sh` uses it.

### `test.sh`

Runs `swift test`. With only the Command Line Tools installed, Swift Testing lives outside the default search path, so when
`Testing.framework` is found under `xcode-select -p`, the script adds the framework, linker, and rpath flags (`-F`, `-rpath`)
for the compiler and linker. Extra arguments pass through to `swift test` (`--filter`, `--parallel`, and so on). Output: pass/fail
lines; 789 tests, about a second.

The **snapshot test** (`IslandSnapshots`) only runs when `ISLAND_SNAPSHOT_DIR` is set, and then writes one PNG per island state to
that folder.

### `build-adapter.sh`

Compiles the vendored `mediaremote-adapter` (Objective-C) into `build/adapter/` without cmake:

- `clang -dynamiclib` for arm64 and x86_64, macOS 14 minimum, linking Foundation, AppKit, and UniformTypeIdentifiers, into a real
  `MediaRemoteAdapter.framework` (versioned folders, symlinks, an `Info.plist`, signed like the app);
- a small test client, `MediaRemoteAdapterTestClient`, for the perl script's `test` command;
- copies `Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl` next to them.

Run it by hand only after changing the vendored source; `bundle.sh` runs it once if the framework is missing. To force a rebuild,
delete `build/adapter/`.

### `docs-images.sh`

Regenerates the pictures used in the README and the docs. It runs the snapshot test into a temp folder, then copies a fixed list of
states into `docs/images/`. Run it after a UI change so the docs still match the app. The list of images is at the top of the
script; add a name there (and a state in `Tests/MacIslandTests/IslandSnapshots.swift`) to add a picture.

The pictures are `ImageRenderer` output: exact layout, type, and color, but no Liquid Glass, text fields, or horizontal scroll
views, and the sound bars are held still mid-bounce (`\.isSnapshot`: `ImageRenderer` can't draw their Core Animation layers).

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
| `Makefile` | Shortcuts for linting, formatting, bundling, restarting, and building then restarting the app |
| `Support/Info.plist` | The bundle's identity (`com.ethantiller.MacIsland`, version 0.1.0), `LSUIElement` (no Dock icon), `LSMinimumSystemVersion`, and the permission reasons: Calendars, Reminders, Bluetooth, Focus status, Downloads folder, Apple Events, Camera, Microphone, Speech recognition, and the `macisland` URL scheme |
| `.swift-format` | 4-space indent, 120-column lines, at most one blank line, existing line breaks respected; rules that would fight this codebase's style (force unwraps, naming, doc comments) are off; imports must be ordered |
| `.gitignore` | `.build/`, `.swiftpm/`, `build/`, Xcode user data, `.DS_Store`, secrets files, and `.claude` |
| `CLAUDE.md` | Instructions Claude Code loads in this repo: read the design doc first, tokens and components only, where things live, the commands |
| `DESIGN.md` | The design system and per-module design notes |

There is no CI, no linter config other than `.swift-format`, and no dependency manager.

---

## Source map

Every Swift file in `Sources/MacIsland/` (83 files, about 11,500 lines). One folder per feature: a model plus its view.

### `App/`

| File | Contains |
| --- | --- |
| `MacIslandApp.swift` | The `@main` `App` (menu-bar capsule, Settings, module menu bars), `AppDelegate` (builds `IslandFeatures`, wires every monitor to the view model, the hotkeys, the panel), `ModuleMenuBars`, `MenuBarModuleView` |
| `FeatureRunner.swift` | What a Features switch starts and stops (`apply`, `startAtLaunch`), and how settings read once features are taken into account |
| `URLCommand.swift` | `URLCommand` (the `macisland://` parser and its limits) and `URLCommandRunner` (runs them, rate-limits banners) |
| `FloatingPanels.swift` | `FloatingPanels` (torn-off windows, one per module, Keep on Desktop), `DetachedPanelState`, `DetachedModuleView` (the glass window's chrome) |
| `OnboardingWindowController.swift` | `OnboardingPanel` (the guide's window), `OnboardingContext` (what the guide needs from the app), `OnboardingWindowController` (shows, positions, and closes it) |
| `SettingsWindowController.swift` | The Settings window: an `NSWindow` hosting `SettingsView`, made when opened and gone when closed, with its frame remembered |

### `Onboarding/` (the first-run guide)

| File | Contains |
| --- | --- |
| `OnboardingState.swift` | `OnboardingState` (which guide and tour versions were seen, and the step to resume at; `onboarding.*` keys), `InstallEvidence` (existing or fresh) |
| `OnboardingFlow.swift` | `GuideStepID`, `PracticeGoal`, `GuideStep`, `OnboardingFlow`, `GuideSetup`, `GuideCopy` (every sentence) |
| `OnboardingModel.swift` | `OnboardingModel` (walks the steps, practice, Done, Open Settings, and where to resume) and `GuideEnding` |
| `OnboardingView.swift` | The guide's content (`OnboardingView`), the window's root on glass (`OnboardingRoot`), the permission step's status and the practice line |
| `SetupGate.swift` | `SetupGate`: whether setup is complete (the guide finished, every permission allowed), which shows or hides the island |
| `StageInput.swift` | `.stageInput(_:isOn:)`: makes the stage island answer to hover, a click, swipes, and a dragged file |
| `AccessRequests.swift` | `AccessKind` (the ten permissions), `AccessAsked`, `AccessProviding`, `LiveAccess` (every request), `AccessModel` (states, and a grant that stands while EventKit lags), `AccessCenter`, `AppRelaunch` |
| `BluetoothAccess.swift` | Asks for Bluetooth through `CBCentralManager` and returns the answer |

### `Island/` (panel, input, state, drawing)

| File | Contains |
| --- | --- |
| `IslandPanel.swift` | The always-there `NSPanel`: borderless, non-activating, over everything, click-through by default, first-click-acts hosting view |
| `ScreenGeometry.swift` | Notch detection and sizes; `panelSize` (560 x 276); `islandRect(for:)` |
| `MenuHoldObserver.swift` | Holds the island open while any AppKit menu is tracking |
| `MouseTracker.swift` | Global and local event monitors: hover, click-through, file-drag detection, swipes, click-outside (off until setup is complete) |
| `SwipeRecognizer.swift` | Turns one gesture's scroll deltas into down, up, left, or right, once |
| `Announcements.swift` | `AmbientEvent` (what can be muted) and the banners and alerts of each, built once for the island and the preview |
| `IslandViewModel.swift` | `IslandModule`, `ClockMode`, `IslandAlert`, `IslandBanner`, `CompactActivity`, `IslandFeatures`, the view model itself, and `TrailingStrip` (what fits right of the notch) |
| `IslandView.swift` | The island's content: the tab strip, compact layers and pair, banners, the file drop target, the settings and pencil buttons |
| `IslandContainer.swift` | `IslandPresentation`, `IslandSurface`, and the container that draws the outline, surface, size, and swell |
| `NotchShape.swift` | The island outline (flat top, concave flares, continuous bottom corners) |
| `PeekContent.swift` | What each peek shows, and the idle peek |
| `ModuleContent.swift` | The one module-to-view switch used everywhere |
| `Theme.swift` | All design tokens: `Palette`, `SurfaceInk`, `Tint` (with `Tint.airDrop` for the AirDrop target), `Typography`, `Metrics`, `Timing`, `Motion`, `BlurFade`, the `\.islandSurface` key |
| `Components.swift` | Shared controls: `IconButton`, `ChipButton`, `SegmentedChoice`, `IslandSlider`, `ArtworkView`, `ProgressRing`, `EdgeFade`, `ChargingBadge`, `AirDropGlyph`, `Glyph`, `IslandButtonStyle`, `formatTime` |
| `FloatingGlass.swift` | The `floatingGlass()` modifier (padding plus Liquid Glass) |
| `FloatingGlassPanel.swift` | The torn-off window class and the `\.isFloatingWindow` key |

### `Widgets/`

| File | Contains |
| --- | --- |
| `WidgetCatalog.swift` | `BuiltInWidget`, `WidgetID`, `WidgetDescriptor` (width, kind, height, source, refresh, tint, tap) |
| `HomeLayoutFeatures.swift` | `WidgetCatalog.feature(of:)`, and `removingWidgets` / `restoring`: widgets leave Home and return with their feature |
| `HomeLayout.swift` | `HomeLayout` (v2: an ordered list of sized `WidgetPlacement`), `WidgetOptions`, the presets, `frames`/`contentHeight`/`capacityText`, `normalized`, and the key-based decoder |
| `HomeGridSpec.swift` | `GridSize`, `GridCell`, `GridRect`, and `HomeGridSpec`: packing, geometry, and the drag-target maths (pure) |
| `SavedHomePreset.swift` | A layout saved under a name, and the rules for its name |
| `HomeLayoutMigration.swift` | Version 1 (rows) to version 2, once, on read (frozen) |
| `ShortcutsCLI.swift` | `shortcuts list` and `shortcuts run`, for Shortcut widgets |
| `CustomWidget.swift` | `CustomWidget` (four sources), `WebValue.extract`, and the catalog lookup that includes them |
| `CustomWidgetValues.swift` | `CustomWidgetValues` (in-memory values, freshness, one fetch at a time), `LiveWidgetFetcher`, `SampleWidgetFetcher` |
| `BoundedProcess.swift` | Runs one program with a time limit, an output cap, and a minimal environment |
| `HomeLayoutEditing.swift` | The editor's pure edits: `inserting`, `placing`, `moving`, `resizing`, `removing`, `adding`, `applying` |

### `Home/`

| File | Contains |
| --- | --- |
| `HomeView.swift` | The Home module: the widget grid, and the month calendar it opens |
| `HomeGrid.swift` | `HomeGrid` (the grid from a `HomeLayout`) and `HomeWidgetView` (a widget at a size) |
| `MoreWidgets.swift` | Weather, Battery, Reminders, Note, and custom widgets, each at its sizes |
| `HomeWidgets.swift` | The boxes: `TimeWidget`, `MediaWidget`, `QuickActionsGrid`, `HomeAction` and `HomeActionPill` |
| `HomeCards.swift` | Pieces the idle peek reuses: `DateInline`, `UpNextLabel`, `QuickToolsRow`, `QuickToolButton`, `QuickTimerChips`, `MacBatteryGlance` |
| `MonthGrid.swift` | Six-week month layout and its view |

### `NowPlaying/`

| File | Contains |
| --- | --- |
| `NowPlayingModel.swift` | State, artwork, accent color, transport (direct to Music/Spotify, else the adapter), shuffle, repeat, Favorite, app volume |
| `NowPlayingState.swift` | The state struct, `RepeatMode`, and the parser for the adapter's JSON lines |
| `MediaRemoteAdapter.swift` | Runs the perl adapter: the `stream` process (restarted if it exits) and one-shot commands |
| `NowPlayingView.swift` | The player layout, scrubber, volume, output picker, lyric line, the compact play control, and the shared `mediaNamespace` |
| `EqualizerView.swift` | The sound bars: a Core Animation loop (`EqualizerBarsView`), a still SwiftUI stand-in for snapshots, and `\.isSnapshot` |
| `PlayerScripting.swift` | `ScriptablePlayer` (Music, Spotify), `PlayerCommand`, and AppleScript for volume, Favorite, transport, seek |
| `Lyrics.swift` | LRC parsing and `LyricsModel` (LRCLIB lookup, per-track cache) |
| `ArtworkAccent.swift` | Picks the most vivid color in the art and lifts it to read on black |

### `Timer/`

| File | Contains |
| --- | --- |
| `TimerModel.swift` | Countdown with pause, add-minutes, an end date |
| `StopwatchModel.swift` | Drift-free stopwatch with laps, and `formatStopwatch` |
| `PomodoroModel.swift` | Phases, `PomodoroPlan` (the lengths), chaining, the session history and streak |
| `DialScrubber.swift` | The timer dial's pure math (`DialScrubber`) and scroll routing (`ScrollRouting`, `AxisLock`) |
| `TimerView.swift` | The Clock tab (rings, presets, the minute dial, laps, the Pomodoro chart), the compact readouts, and the timer, Pomodoro, and stopwatch peeks |

### `Shelf/`

| File | Contains |
| --- | --- |
| `ShelfModel.swift` | The files on the Shelf (paths only, plus the folder MacIsland owns for results) and AirDrop |
| `ShelfThumbnails.swift` | QuickLook thumbnails for Shelf files, cached in memory |
| `ShelfView.swift` | The Files and Clipboard views, drop tiles, item and card views with their menus |
| `ClipboardHistory.swift` | The pasteboard poller and the memory-only history (0, 10, 25, or 50 items) |
| `SmartAction.swift` | Detects a lone link, address, or `#hex` color and names the action |
| `FileTools.swift` | Zip, unzip, and the Shelf jobs (convert, combine, resize, compress, Copy Text): staged results and the choice of where they go, unique names |
| `Converters.swift` | `FileKind`, `ConversionTarget`, and every converter: images, documents, PDF, video, audio, plus `MarkdownText` |
| `TextRecognizer.swift` | `RecognizedText`, `TextRecognizing`, and the Vision recognizer |
| `ScreenshotWatcher.swift` | A Spotlight query for new screenshots |

### `Tools/`

| File | Contains |
| --- | --- |
| `ToolID.swift` | `ToolID` (a built-in tool or a Shortcut tool, stored by name), `ShortcutTool`, and the default pins |
| `ToolCatalog.swift` | What each tool is and does (shared by the Tools tab, Home, and the peek) |
| `ToolsView.swift` | The Tools tab: row (or the Mirror), grid, Ring Light sliders, Keep Awake chips; `ControlButton` |
| `CameraMirror.swift` | `CameraMirror`, `CameraSessionProviding`, the AVFoundation provider, and the preview layer view |
| `MirrorView.swift` | The Mirror: preview, Ring Light, Done |
| `ScreenRecorder.swift` | `ScreenRecorder` (30-minute cap), the ScreenCaptureKit recorder, and `RegionPicker` |
| `KeepAwake.swift` | The power assertion, with durations |
| `RingLight.swift` | The screen-edge glow (a click-through window) |
| `MicrophoneMute.swift` | Mutes the default input device |
| `KeyboardCleaner.swift` | The event tap that swallows keys for 30 seconds |
| `AudioOutputs.swift` | Output devices and the default one |
| `SystemActions.swift` | Eyedropper, hex strings, clipboard, area screenshot |

### `Agenda/`

| File | Contains |
| --- | --- |
| `AgendaMonitor.swift` | EventKit: next event or reminder, announcements, the reminder list, adding and completing; `ReminderRow`; meeting-link finding; timing rules |
| `AgendaView.swift` | `IdleView` (the agenda row) and `AgendaAction` |
| `RemindersView.swift` | The Reminders tab |

### `Notes/` and `Weather/`

| File | Contains |
| --- | --- |
| `Notes/NotesModel.swift` | Notes and snippets, saved as one JSON file after a pause in typing |
| `Notes/VoiceRecorder.swift` | `VoiceRecorder` (10-minute cap), `Transcribing`, the level meter, and the on-device Speech transcriber |
| `Notes/NotesView.swift` | The Notes tab: lists, editors, the Prompter |
| `Weather/WeatherModel.swift` | Open-Meteo geocoding and forecast (with quarter-hour rain), WMO code names, `WeatherGlance` |
| `Weather/RainRule.swift` | `RainSample`, `RainRule` (dry now, 0.2 mm within 30 minutes), `RainSpell` (once per spell) |

### `System/` and `Transfers/`

| File | Contains |
| --- | --- |
| `System/BatteryMonitor.swift` | Charger, 20% and 10%, and the full-charge level; the battery glyph |
| `System/VolumeMonitor.swift` | External drive mounts, and eject |
| `System/VolumeHUD.swift` | The volume HUD: the keys' math, CoreAudio volume, the media-key event tap, and the controller |
| `System/AudioAccessoryMonitor.swift` | Bluetooth headphones connecting, and their battery |
| `System/PrivacyMonitor.swift` | Which app is using the microphone, from CoreAudio property listeners (no polling) |
| `System/NetworkMonitor.swift` | Personal Hotspot detection |
| `System/FocusMode.swift` | Whether a Focus is on, read when needed or while the Focus button shows; switching through Shortcuts |
| `System/DiskSpace.swift` | `DiskRule` (warn under 10 GB, re-arm above 15 GB) and `DiskSpace`, checked on events |
| `System/BluetoothDevices.swift` | Paired audio devices, connecting, and `IOBluetoothProvider` behind `BluetoothDeviceProviding` |
| `System/WorkTracker.swift` | The "in progress" job list |
| `Transfers/TransferMonitor.swift` | Progress of files arriving in Downloads |

### `Settings/`

Note for `swift run`: without an app bundle there is no bundle identifier, so defaults live in another domain, and an existing developer install looks fresh there (the guide shows). Harmless.

| File | Contains |
| --- | --- |
| `AppSettings.swift` | Every setting, its storage, the tab sides, menu-bar modules, search engines, pinned tools |
| `FeatureCatalog.swift` | `Feature` (what can be switched off, with its words and cost), `FeatureCost`, and the `FeaturePreset`s |
| `FeaturesPane.swift`, `FeatureOffNote.swift`, `FeatureNotice.swift` | The Features pane; the "Turned off in Features" line with Open Features (and `\.openFeatures`); what a switch stops in words, the preset confirmation, the feature count, each feature's preview and search words |
| `SettingsView.swift` | The Settings window: a sidebar of panes over a live preview and the pane's form |
| `SettingsPane.swift` | The panes, and what the preview shows for each |
| `IslandPreview.swift` | `IslandPreviewModel` (a second view model on sample data), `IslandPreview` (the picker, arrows, tray, and hints around the band), and `PreviewBand` (the real `IslandView` on a desk band, which the first-run guide uses alone as its stage) |
| `SettingsTour.swift` | The Settings tour: `TourStop.all`, `SettingsTour`, `TourAnchors` and `.tourAnchor(_:)`, `CalloutPlacement`, `TourCallout`, `TourRing`, `SettingsTourOverlay`, and the Return key monitor |
| `PreviewFeatures.swift` | `IslandFeatures` from sample data, the samples, and the inert doubles |
| `CustomWidgetSheet.swift`, `PrivacyPane.swift`, `PrivacyAccess.swift` | Making a custom widget, and the Privacy pane (what leaves, what runs, permission states) |
| `MenuBarPreview.swift` | The preview's Menu Bar view: a menu-bar strip and the chosen module's window |
| `TabEditor.swift` | The Tabs pane's canvas: the preview's tab strip and the Not Shown tray under it (swap, replace, hide, add) |
| `HomeEditor.swift`, `HomeCanvas.swift`, `WidgetGallery.swift`, `HomeLayoutEditor.swift`, `WidgetInspector.swift`, `HomeArchive.swift` | The Home editor: the controller (gestures, keys, undo), the chrome over the preview (handles, badges, room to grow, the lifted widget, the hint), the gallery of widgets to add (chips, each size at 1:1, `FlowLayout`), the Layout section (presets, Save, file menu), the selected widget's options, and layout export and import |
| `Dropdown.swift` | The styled controls used across Settings: `StyledDropdown`, `DropdownItem`, `SettingsDropdown`, `SettingsSegmented`, `FieldButton` |
| `SettingsSidebar.swift`, `SettingsSearch.swift`, `SettingsWindow.swift` | The sidebar (search field, hide and show button, panes or results), the pure search (an entry for each setting, and the ranking), and the window setup (resizable, transparent title bar, sidebar material) |
| `ShortcutRecorder.swift`, `KeyCombo.swift` | Recording a global shortcut, and the key combination it stores |
| `ShelfPane.swift` | The Shelf pane (drag target, screenshots, retention, clipboard limit) |
| `SettingsArchive.swift` | The settings file (make, read, `restore`, `resetAll`) and its panels |
| `GeneralPane.swift`, `FeaturesPane.swift`, `TabsPane.swift`, `HomePane.swift`, `MediaPane.swift`, `ClockPane.swift`, `ToolsPane.swift`, `ShortcutToolSheet.swift`, `NotificationsPane.swift`, `ShelfPane.swift`, `PrivacyPane.swift` | One pane each |
| `GlobalHotkey.swift` | Carbon hotkeys with ids |
| `LaunchAtLogin.swift` | Start at login (bundle only) |

---

## Tests

`Tests/MacIslandTests/`: 48 files, about 10,900 lines, **789 tests**. Swift Testing.

| File | Covers |
| --- | --- |
| `TestSupport.swift` | `makeViewModel()`: a view model from test doubles |
| `KeyboardTests.swift` | Hotkey pinning, arrow tabs, banners |
| `ShelfResultTests.swift` | Staged results and their three outcomes, what is trashed, previews' cache key |
| `HoldTests.swift` | The named holds (menu, Quick Look, panel, text focus, Mirror): what they block and when the close resumes |
| `SettingsPreviewTests.swift`, `SettingsSnapshots.swift` | The Settings preview: size parity, isolation, sample data; its opt-in renders |
| `CustomWidgetTests.swift` | Web values, freshness and overlap, `BoundedProcess` (timeout, cap, environment), custom widgets in settings |
| `BehaviorTests.swift` | Shortcuts, Peek on Hover, the display choice, muting events |
| `ChoicesTests.swift` | Shelf retention, the clipboard limit, drag modes, music in compact, the tool row order |
| `SettingsArchiveTests.swift` | The settings file: round trip, refusal, repair, commands never in or out, Reset All |
| `TabDragTests.swift` | Dragging tabs (move, swap, Not Shown), the preview's arrows, and clicking a tab |
| `WidgetTests.swift` | Home layout: the default, presets, grid budget, repair, persistence, editing, the editor, the drags (driven by points), archives |
| `HomeGridTests.swift` | The grid maths: packing, geometry, targets, sizes |
| `SavedPresetTests.swift` | Saved layouts: saving, names, replacing, applying with options, removing and undo |
| `SettingsSearchTests.swift` | Finding a setting by name, other words, accents, and ranking |
| `BannerTests.swift` | The AirPods ring and low rule, Low Battery as an alert, and the smaller alert island |
| `HomeMigrationTests.swift` | Version 1 layouts and files become version 2 |
| `HomeSizeTests.swift` | What each size shows: timer segments, tools per size, forecast parsing, upcoming items, presets, the Size row |
| `WidgetSizeSnapshots.swift` | Opt-in: every widget at every size, on black (`31-widget-*.png`) |
| `URLAndSystemTests.swift` | `macisland://` links |
| `DialTests.swift` | The timer dial: drag math, rubber band, scroll routing, the dial rectangle |
| `PresentationTests.swift` | Hover, peek, expanded, banner widths, drag target, the hidden pill, swipes |
| `SettingsTests.swift` | Hotkey, tabs |
| `FeatureCatalogTests.swift` | The Features catalog: the words, defaults, presets, the two bridged settings, the clipboard migration, the shown tabs, the menu bar, the archive |
| `FeatureTests.swift`, `ToolsTests.swift` | Timer, stopwatch, tools, clipboard |
| `NowPlayingStateTests.swift`, `ArtworkAccentTests.swift` | The stream parser, elapsed time, accent color |
| `Phase2Tests.swift` | Minimal pairs, full charge, Keep Awake, drives, screenshots |
| `PlanFeatureTests.swift` | Agenda rules, meeting links, pinned tools, drop tiles |
| `MediaTests.swift` | LRC, lyrics, transport, shuffle and repeat, players |
| `Phase4Tests.swift` | Pomodoro, month grid, weather, smart actions, file tools, notes, Clean Keys, reminders, the strip, the tab sides |
| `Phase5Tests.swift` | Shortcuts CLI, menu bar and windows, the player layout, transport routing |
| `ShelfToolsTests.swift` | File kinds and targets, Copy Text, document, PDF, image, audio, and video conversions |
| `ClipboardTests.swift` | Plain-text copy, Save as Snippet |
| `AmbientTests.swift` | Rain rules and forecast, disk space rules, the Bluetooth device list |
| `CaptureTests.swift` | The Mirror, two-action banners, screen and voice recording, the recording activity, the new tools |
| `VolumeHUDTests.swift` | The volume keys' math and speaker, the controller over a stub tap and volume, the island alert, and the setting |
| `KeepAwakeTests.swift` | Keep Awake's two assertions over a stub, the wake check, and the honest label |
| `ShortcutToolTests.swift` | Shortcut tools: identity, storage and the cap, the pinned row, the archive, dimming, running and failing with a stub runner |
| `PermissionStepTests.swift` | The permission steps (the footer per state, required permissions, Done blocked, Still needed, the order, the copy), Downloads and Automation read for real, and the Shelf not looking in protected folders at launch |
| `OnboardingTests.swift`, `OnboardingFlowTests.swift` | First-run state and classification (and the evidence drift guard), access, the guide's steps, copy, practice, and model |
| `SettingsTourTests.swift` | The tour's stops, running, anchors, placement, and visibility |
| `IslandSnapshots.swift` | Opt-in: renders states to PNG |
| `OnboardingSnapshots.swift` | Opt-in: the guide's steps and the tour's sixteen stops, light and dark (`40-guide-*`, `43-tour-*`) |

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
| "MacIsland Dev" in the login keychain | The self-signed certificate and key builds are signed with (made by the first build: `sign.sh`, `make-signing-cert.sh`) |
| `~/.claude/projects/-Users-ethantiller-git-mac-island/memory/` | Claude's saved notes about how you like to work (minimal Apple design; rebuild and relaunch after UI changes), the project status, and how you like plans written |
