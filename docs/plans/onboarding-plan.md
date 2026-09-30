# Plan: the first-run guide and the Settings tour

**For:** Sonnet 5.5, to carry out on the user's Mac (`/Users/ethantiller/git/mac-island`).
**Status:** plan only. Nothing here is built yet.
**Written:** 2026-09-30, from a read of the code at `c99d4a0`.

Every claim about today's code below names the file and symbol it comes from. Where the plan makes a choice, it gives a one-line
reason, and the choices the user may want to change are collected in [Open questions](#10-open-questions).

## How to work through this plan

- Read `CLAUDE.md`, then **`DESIGN.md` (mandatory before any UI)**, then this plan top to bottom before writing code.
- Work in the checkpoint order in [section 6](#6-file-by-file-change-list-and-checkpoints). Each checkpoint must build, pass
  `./scripts/test.sh`, and be looked at with `make build-and-restart` before the next one starts. Commit after each checkpoint
  with a message that names it (for example `Onboarding C3: tokens, StepDots, KeyCaps, PreviewBand`).
- Don't widen the scope. If something outside this plan looks wrong, note it for the user; don't fix it here.
- Ask the user before anything destructive to their data (checkpoint 0 backs up and restores their defaults and notes).
- Colors, fonts, and sizes come only from `Theme.swift`. Controls come from `Island/Components.swift` and `Settings/Dropdown.swift`.
  New tokens and components are listed in [section 5](#5-new-components-and-tokens); don't add others without a reason written
  into the token's doc comment.
- **No native controls in the guide or the tour:** no `.bordered`/`.borderedProminent`/`.link`/default button styles, no
  `Picker`, `Menu`, pop-up button, `Toggle`, or segmented control. A SwiftUI `Button` with `IslandButtonStyle` or `.plain` and our
  own drawing (that is what `ChipButton`, `IconButton`, and `FieldButton` are) is custom and allowed.

---

## 1. Summary and scope

Two features:

1. **A first-run guide.** A floating glass window hung below the island that walks through ten short steps: what the island is,
   the gestures and keys (with a "try it on your notch" check on the real island), the seven modules, dropping files, the menu bar
   and torn-off windows, access to Calendars, Reminders, and Bluetooth, and Settings. Each step shows the real island, drawn from
   sample data by the same preview the Settings window uses. A temporary **Skip** ends it at once but still asks for the
   permissions.
2. **A Settings tour.** The first time the Settings window opens, a black callout with an arrow points at a real control, with a
   ring in the system accent color around it, and walks through all eight panes in fifteen stops. It follows the control when the
   window resizes or the pane scrolls.

Both remember that they ran, both can be replayed from Settings → General → Guide, and neither runs for someone updating from a
build they already used.

### In scope

- `OnboardingState` (where the guide and tour stand), the rule that tells an existing install from a fresh one, versioning.
- The guide window, its ten steps, the access rows, the practice checks, Skip (temporary), Close, and Replay.
- The Settings tour: its stops, anchoring, layering, placement, navigation, and Replay.
- Small supporting changes: an Accessibility row in `PrivacyAccess`, a public access request on `AgendaMonitor`, a CoreBluetooth
  access request, `macisland://guide` and `macisland://tour` links, and extracting the preview band so the guide can reuse it.
- Tests, snapshots, and the docs.

### Out of scope

- **The command palette.** It was removed on 2026-09-30 (`docs/ROADMAP.md` → What is built, and Decisions: "The command palette
  and everything for it … was removed"). There is no `Palette/` folder, and `ShortcutSlot` has only `.open`
  (`Settings/KeyCombo.swift:5`). The guide does not teach it. See [Open question 6](#10-open-questions).
- Asking for Camera, Microphone, Speech Recognition, Screen Recording, Accessibility, Focus, Automation, or folder access in the
  guide. They stay asked on first use, as today (reasons in [3.4](#34-the-access-step-permissions)).
- A weather-city field in the guide (the tour points at it instead).
- Changing any existing Settings control to a custom one (for example `GeneralPane`'s `Toggle`s or `ShortcutRecorder`'s
  `.bordered` button). The "no native controls" rule applies to what this plan adds.
- The documentation drift noticed on the way (see [section 8](#8-docs-to-update)); only the lines this feature touches are fixed.

### What the code does today (verified, and where the brief differs)

| Fact | Where |
| --- | --- |
| Settings is **not** a SwiftUI `Settings` scene. `SettingsWindowController.shared.show()` makes an `NSWindow` hosting `SettingsView`, with frame autosave name `MacIslandSettings`. The app's scenes are the capsule `MenuBarExtra` and `ModuleMenuBars` only. (`CLAUDE.md` and `ARCHITECTURE.md`'s Startup table still say a `Settings` scene.) | `App/SettingsWindowController.swift:23-60`, `App/MacIslandApp.swift:9-18` |
| `ControlButton` lives in `Tools/ToolsView.swift:88`, not `Components.swift`. | |
| `SettingsDropdown` is `LabeledContent` + `StyledDropdown` (a popover list), not a `Picker`. `FieldButton` is the Settings window's custom button. | `Settings/Dropdown.swift:181`, `:203` |
| `AgendaMonitor.hasAccess(_:)` (the EventKit request) is **private**. Today it runs when `settings.showsCalendar`/`showsReminders` flips (`onAgendaChange` → `configure` → `refresh` → `reload`), when the Reminders tab shows (`showReminderList`), or on `addReminder`. | `Agenda/AgendaMonitor.swift:220-354`, `App/MacIslandApp.swift:381-387` |
| `FocusMode.start()` asks for Focus **and starts a 3 s poll**; it is only called when Quiet in Focus is on. | `System/FocusMode.swift:23-35`, `App/MacIslandApp.swift:390-394` |
| Bluetooth has no explicit request. `PrivacyAccess` reads `CBManager.authorization`, but the app only uses IOBluetooth: `AudioAccessoryMonitor.start()` (every launch) and `IOBluetoothProvider`. | `Settings/PrivacyAccess.swift:50-55`, `System/AudioAccessoryMonitor.swift:79-85` |
| Every launch starts `accessoryMonitor.start()` and `features.transfers.start()` (Downloads progress). On a clean install these **may** show the Bluetooth and Downloads prompts before any guide. Checkpoint 0 verifies. | `App/MacIslandApp.swift:190`, `:192`; `Transfers/TransferMonitor.swift:30` |
| Accessibility is asked by `KeyboardCleaner.toggle()` (`AXIsProcessTrustedWithOptions` with the prompt option) and is not in `PrivacyAccess`. Screen Recording is `CGPreflight…`/`CGRequestScreenCaptureAccess` in `SCKScreenRecorder`. Camera is `AVCameraProvider.requestAccess()`. Microphone is `AVAudioApplication.requestRecordPermission()` in the voice recorder. | `Tools/KeyboardCleaner.swift:40-52`, `Tools/ScreenRecorder.swift:49-52, 114-116`, `Tools/CameraMirror.swift:99`, `Notes/VoiceRecorder.swift:161` |
| Settings are written **only when changed** (`didSet`); a fresh install that changed nothing has almost no keys. | `Settings/AppSettings.swift:67-222`, `init` at `:257` |
| `NotesModel.save()` runs on **every clean quit** (`applicationWillTerminate`) and writes `~/Library/Application Support/MacIsland/notes.json` even when there are no notes. It is the strongest sign that the app has run before, and also why a fresh install must be recorded on its first launch (see [2.2](#22-telling-an-existing-install-from-a-fresh-one)). | `Notes/NotesModel.swift:143-150`, `App/MacIslandApp.swift:109-112` |
| The island's panel is `.nonactivatingPanel` with `becomesKeyOnlyIfNeeded`, and `panel.keyHandler` handles Esc, ←, → only while it is key: after ⌃⌥Space (`toggleFromKeyboard` then `makeKey`) or when a text field needs keys. After a **click** opens it, Esc and the arrows go to whatever window is key. | `Island/IslandPanel.swift:8-32`, `App/MacIslandApp.swift:428-447` |
| The Settings preview is a second `IslandViewModel` over `PreviewFeatures` (sample track, weather, agenda; inert camera, screen, microphone), sharing the live `AppSettings`, with a private defaults suite and temp folder removed by `stop()`. | `Settings/IslandPreview.swift:34-49`, `Settings/PreviewFeatures.swift:12-23` |
| `SettingsArchive.make`/`restore` list every field explicitly, and `resetAll()` rebuilds from a scratch `AppSettings`. Anything not in `AppSettings` is untouched by Export, Import, and Reset All. | `Settings/SettingsArchive.swift:52, 110, 156` |
| Named coordinate spaces already resolve across the Settings `Form` boundary: `WidgetGallery`'s drag (inside the Form) uses `.named(HomeEditor.space)`, set on the detail column. Frames are published with `onGeometryChange` into an `@Observable` (`HomeEditor.gridFrame`, `bandFrame`, `islandFrame`), not preferences. | `Settings/WidgetGallery.swift:165`, `Settings/SettingsView.swift:112`, `Settings/IslandPreview.swift:231-251`, `Home/HomeGrid.swift:66` |
| Search scrolls a pane with `ScrollViewReader` and `.id(SettingsAnchor…)` on section headers, through `SettingsView.scrollTarget`. | `Settings/SettingsView.swift:104-156`, `Settings/SettingsSearch.swift:16-39` |
| Hidden gestures worth teaching: right-click a tab → Show in Menu Bar / Open in Window; right-click a Home widget → Edit Home…; right-click a tool → Pin to Row; the New Note pencil (`IslandModule.otherWayIn`); a text field keeps the island open (`holdOpen`). | `Island/IslandView.swift:516-521`, `Home/HomeGrid.swift:50-52`, `Tools/ToolsView.swift:62-68`, `Island/IslandViewModel.swift` (`otherWayIn`, `holdOpen`) |
| The `@Entry` macro is unavailable with the Command Line Tools: environment keys are written by hand. Setters that bindings call must do nothing unless something changes (the scene recursion crash). | `docs/ARCHITECTURE.md` → Gotchas |

---

## 2. State model

### 2.1 Where it lives: a new `OnboardingState`, not `AppSettings`

`Onboarding/OnboardingState.swift`, an `@MainActor @Observable final class` with an injectable `defaults:` like `AppSettings`.

Not in `AppSettings`, because:
- `AppSettings` is "personal choices only" (its doc comment, `AppSettings.swift:43`). Whether a guide was seen is history, not a
  choice, like `settings.pane`, `shelf.added`, and `pomodoro.history`, which already live outside it.
- `AppSettings` is shared with the Settings preview, and `SettingsArchive`/`resetAll()` operate on it. Onboarding progress must
  never be exported, imported, or reset by Reset All (someone who resets their choices still knows the app).

Keys, all in the app's own domain (`UserDefaults.standard`), all prefixed `onboarding.`:

| Key | Type | Meaning |
| --- | --- | --- |
| `onboarding.install` | String, `fresh` or `existing` | How this install was classified, **written once**, on the first launch that has this code |
| `onboarding.guide` | Int | The guide version completed, skipped, or closed. Absent is 0 |
| `onboarding.settingsTour` | Int | The tour version completed or ended. Absent is 0 |

```swift
@MainActor @Observable
final class OnboardingState {
    enum Install: String { case fresh, existing }

    /// Bump to show the guide again to everyone who saw an older one. Only steps with a newer `since` are shown on a re-run.
    static let guideVersion = 1
    static let tourVersion = 1

    private(set) var install: Install
    private(set) var guideSeen: Int
    private(set) var tourSeen: Int
    /// In memory only. Set by Replay, the guide's Open Settings, and `macisland://tour`; `SettingsView` starts the tour and clears it.
    var tourRequested = false

    init(defaults: UserDefaults = .standard,
         isExistingInstall: () -> Bool = InstallEvidence.live,
         guideVersion: Int = OnboardingState.guideVersion,
         tourVersion: Int = OnboardingState.tourVersion)

    var needsGuide: Bool { guideSeen < guideVersion }
    var needsTour: Bool { tourSeen < tourVersion }

    func finishGuide()      // guideSeen = max(guideSeen, guideVersion); writes only if it changed
    func finishTour()       // the same for the tour
    func resetToFresh()     // DEBUG and `macisland://guide?reset=1` only: install = fresh, guide = 0, tour = 0
}
```

`AppDelegate` owns it as its **first stored property**, `let onboarding = OnboardingState()`, declared above
`let features = AppDelegate.makeFeatures()` (`App/MacIslandApp.swift:23`), so it classifies before anything in this launch could
write a key. (Checked: nothing in `makeFeatures()` writes an evidence key on a fresh install. `AppSettings.init` sets stored
properties without `didSet`; `ShelfModel.init` writes `shelf.added` only when stored Shelf paths exist, which is itself evidence.)
`SettingsWindowController.shared.onboarding` and the guide's controller get the same instance.

### 2.2 Telling an existing install from a fresh one

On `init`, if `onboarding.install` is **absent**, classify once and write it:

- **Existing** if `InstallEvidence.isExisting` is true. Write `install = existing`, `guide = 1`, `settingsTour = 1`, so an updater
  sees neither the guide nor the tour (they can replay both).
- **Fresh** otherwise. Write `install = fresh` and nothing else (guide and tour stay 0).

If `onboarding.install` is **present**, trust it and don't look at evidence again. This matters: a fresh user who quits mid-guide
now has `notes.json` (every clean quit writes it), so re-deriving on the next launch would wrongly call them existing.

```swift
/// Signs that MacIsland ran here before this code existed. Keys only a used install has, and the notes file every clean quit writes.
enum InstallEvidence {
    static let keys: [String]
    static func isExisting(defaults: UserDefaults, notesFile: URL, fileExists: (URL) -> Bool) -> Bool
    @MainActor static func live() -> Bool   // .standard, NotesModel.defaultFileURL, FileManager
}
```

`keys` (exact strings; `AppSettings.Key` is private, so they are listed here and guarded by a test):

- From `AppSettings.Key` (`AppSettings.swift:227-255`): `tabs`, `tabsLeft`, `tabsRight`, `menuBarModules`, `hotkey`,
  `shortcut.open`, `peeksOnHover`, `swipesEnabled`, `islandDisplay`, `mutedEvents`, `dragTarget`, `addsScreenshots`,
  `shelfRetention`, `clipboardLimit`, `shelfMode`, `showsMusicCompact`, `quietDuringFocus`, `showsCalendar`, `showsReminders`,
  `pinLimit`, `fullChargeLevel`, `showsLyrics`, `weatherCity`, `pinnedTools`, `home.layout`, `home.savedPresets`, `widgets.custom`.
- Elsewhere: `shelf.paths`, `shelf.added` (`ShelfModel.swift:33-34`), `pomodoro.history` (`PomodoroModel.swift:91`),
  `settings.pane` (`SettingsView.swift:9`, `MacIslandApp.swift:401`), `settings.sidebarHidden` (`SettingsView.sidebarHiddenKey`),
  and `NSWindow Frame MacIslandSettings` (AppKit's frame autosave for `SettingsWindowController.frameName`).

A key counts if `defaults.object(forKey:) != nil`. The notes file counts if it exists. Add
`static var defaultFileURL: URL` to `NotesModel` (the path its `init` builds today, `NotesModel.swift:40-45`) and use it in both
places so the path is written once.

Don't use `persistentDomain(forName:)` over "any key": the system can write its own keys into an app's domain (status item
positions, panel directories), which would misclassify a fresh install.

### 2.3 Versioning

- `OnboardingState.guideVersion` and `.tourVersion` are the only knobs. A future guide revision that everyone should see bumps
  `guideVersion`; one only new installs should see changes the steps and leaves the version.
- Each guide step has `since: Int` (all `1` today). A re-run for someone who saw version `n` shows the steps with `since > n`, then
  the last step (Make It Yours). A fresh install (seen 0) sees every step. Replay always shows every step.
- The tour works the same way at stop level (`TourStop.since`), so a new pane can add a stop without replaying the rest.

### 2.4 How Skip, Close, Finish, and Replay change it

| Action | Guide state | Tour state | Permissions | Monitors deferred on a fresh install ([3.4](#34-the-access-step-permissions)) |
| --- | --- | --- | --- | --- |
| **Done** (last step) | `finishGuide()` | unchanged | only what rows asked | started |
| **Open Settings** (last step) | `finishGuide()` | `tourRequested = true` if `needsTour`, and Settings opens | as above | started |
| **Close** (the ⊗ in the header) | `finishGuide()` (closing counts as seen; [Open question 5](#10-open-questions)) | unchanged | none | started |
| **Skip** (temporary) | `finishGuide()` | unchanged | asks every row still `notAsked`, one at a time, in order Calendars, Reminders, Bluetooth | started |
| App quits with the guide open | unchanged (it shows again next launch) | unchanged | | |
| **Replay guide** (Settings, `macisland://guide`) | unchanged until it ends, then `finishGuide()` (a no-op when already current) | unchanged | only what rows ask; Skip still asks pending rows | already running |
| **Tour ends** (Done, End Tour ⊗, Settings window closed) | unchanged | `finishTour()` | | |
| **Replay tour** (Settings, `macisland://tour`) | unchanged | `finishTour()` again at the end (a no-op) | | |
| **Reset All Settings** | untouched | untouched | | |
| `macisland://guide?reset=1` (DEBUG builds only) | `resetToFresh()`, then the guide shows | reset to 0 | | |

---

## 3. The guide

### 3.1 Surface: floating glass, hung below the island

The guide is a **Floating** surface in DESIGN's terms: `.glassEffect(.regular)` in the system appearance with a window shadow, the
material DESIGN gives to "modules shown in the menu bar, torn-off panels", windows that belong to the island and float free of the
notch. Why not the others:

- **Not the island itself.** The island is at most 212 pt of content (`homeMaxContentHeight`), folds back in 300 ms after the
  pointer leaves, is replaced by live activities and banners, and must stay free so the person can practise on it.
- **Not a standard window.** A titled window with traffic lights reads as a template; the floating glass window reads as part of
  the island, and it drops in with the island's own `float` motion.

Inside it, the **stage** is the Settings preview's band: the real `IslandView` over `PreviewFeatures`, black and opaque on the desk
wallpaper, at 1:1. That is an opaque image inside glass, not glass on glass. Reduce Transparency makes the glass opaque (system).
Ink is `Theme.Palette` with `\.islandSurface = .glass`, so `ChipButton`, `IconButton`, and `Glyph` read correctly in light and
dark, as in torn-off windows (`App/FloatingPanels.swift:116-118`).

**The window.** `OnboardingPanel`, a `FloatingGlassPanel` (`Island/FloatingGlassPanel.swift`) with `.resizable` removed from its
style mask; it keeps `level = .floating`, hidden traffic lights, `isMovableByWindowBackground`, `canBecomeKey`. Content is
`OnboardingView(...).floatingGlass().environment(\.islandSurface, .glass)`.

**Where.** On the island's screen (`viewModel.geometry`), horizontally centered, with its top edge `floatGap` below the island
panel's full extent (`geometry.panelFrame.minY - floatGap`), so the real island can open all the way during the practice steps
without covering it. If that would put the bottom below `visibleFrame.minY + floatGap` (a short screen), move it up just enough to
fit; the island (a higher window level) then draws over its top when fully open, which is acceptable.

**Size.** Fixed for the whole guide, so it never changes height between steps: `guideWidth` wide (the 560 pt band plus
`floatPadding` on each side), and tall enough for the header, the stage, the copy, the tallest step detail (`guideDetailHeight`),
and the footer. Take it from the SwiftUI content's fitting size once, at open.

**Arriving.** Content appears with `Theme.Motion.floatTransition` under `Theme.Motion.float` (scale 0.94 from the top and fade;
opacity only with Reduce Motion). Closing: `orderOut` after a `Theme.Motion.close` fade.

```
╭─────────────────────────────── guideWidth (588) ───────────────────────────────╮  floatingGlass(): radius 24, padding 14
│ ● ● ━━ ● ● ● ● ● ● ●                                                        ⊗ │  StepDots · IconButton "Close Guide"
│ ┌──────────────────────── PreviewBand 560 × 280 ─────────────────────────────┐ │  desk wallpaper, clipped to cardRadius 10
│ │                       ▀▀▀▀▀▀▀▀▀▀ island, 1:1 ▀▀▀▀▀▀▀▀▀▀                     │ │  (24 − 14 = 10, concentric)
│ └────────────────────────────────────────────────────────────────────────────┘ │
│ Rest the Pointer to Peek                                                       │  Typography.headline, Palette.primary
│ Rest the pointer on the notch: the island swells, then shows what's live …     │  Typography.subheadline, Palette.secondary, ≤ 2 lines
│ ┌──────────────────────── step detail, guideDetailHeight ────────────────────┐ │  key caps / chips / access rows / practice line
│ └────────────────────────────────────────────────────────────────────────────┘ │
│ Skip                                                       Back     Continue   │  ChipButton, ChipButton, ChipButton(isProminent)
╰────────────────────────────────────────────────────────────────────────────────╯
```

Spacing between the blocks uses existing metrics (`rowSpacing` 8, `margin` 18 where it separates groups); add no new spacing
numbers.

**Keyboard.** Return is Continue (`.keyboardShortcut(.defaultAction)` on the prominent `ChipButton`; there are no text fields in
the guide). **Do not bind Esc, ←, or → in the guide.** During the practice steps a person presses those for the island; when the
island was opened by a click it isn't key, so the keys land in the guide and would close it or change the step. Close is the ⊗ only.

**Accessibility.** The step title has `.isHeader`. On every step change post
`AccessibilityNotification.Announcement("\(title). Step \(n) of \(count).")`. The stage is one element with a label that says what
it shows ("The island, open on Home."). `StepDots` is one element ("Step 3 of 10"). Every icon-only control has a label.

**Idle budget.** The stage's `IslandPreviewModel` is created when the guide opens and `stop()`ed when it closes. Practice checks
observe the live view model; access states refresh on `NSWindow.didBecomeKeyNotification` for the guide and
`NSApplication.didBecomeActiveNotification`; nothing polls.

### 3.2 The steps

`Onboarding/OnboardingFlow.swift` holds the steps as pure data, and `OnboardingModel` (`@Observable`) walks them.

```swift
enum GuideStepID: String, CaseIterable { case welcome, peek, open, tabs, close, modules, drop, menuBar, access, finish }

struct GuideStep: Equatable {
    let id: GuideStepID
    let since: Int
    let practice: PracticeGoal?
    /// What the stage shows. Nil for `menuBar`, which calls `IslandPreviewModel.showMenuBar(.clock)` instead.
    let stage: PreviewContext?
}

struct OnboardingFlow: Equatable {
    private(set) var steps: [GuideStep]
    private(set) var index = 0
    /// Every step for a fresh install or a replay; for a re-run, the steps newer than `seen`, then `finish`.
    /// `access` is left out when every access row is already allowed.
    static func make(seen: Int, replay: Bool, allAccessAllowed: Bool) -> OnboardingFlow
    var current: GuideStep
    var isFirst: Bool; var isLast: Bool
    mutating func next(); mutating func back()   // clamp at the ends
}
```

The copy below is final. Strings use typographic apostrophes and quotes (`\u{2019}`, `\u{201C}`, `\u{201D}`) as the codebase does.
Titles are Title Case (they are labels); body copy is sentence case. `⌃⌥Space` below stands for the person's open shortcut,
`settings.shortcut(.open)?.display` (`KeyCombo.display`, `Settings/KeyCombo.swift:35`); **the notch** stands for
`geometry.hasNotch ? "the notch" : "the top center of the screen"`.

| # | Step | Title | Copy | Stage (`PreviewContext`) | Detail (fills `guideDetailHeight`) | Practice |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `welcome` | Welcome to MacIsland | MacIsland turns the notch into a live island. It grows to show what's playing, what's counting down, and what's arriving, then folds back in. | `.compact` (the sample track: art left, bars right) | Empty | none |
| 2 | `peek` | Rest the Pointer to Peek | Rest the pointer on the notch: the island swells, then shows what's live at full size. With nothing live, it shows your day and your everyday tools. | `.peek` | Practice line | `.peek` |
| 3 | `open` | Open It | Click the island or swipe down on it with two fingers. From anywhere, press ⌃⌥Space. | `.expanded`, `.home` | `KeyCaps(combo:)`, then the practice line | `.open` |
| 4 | `tabs` | Change Tabs | Swipe sideways on it with two fingers. When you opened it with ⌃⌥Space, ← and → switch tabs too. | `.expanded`, `.media` | `KeyCap("←")`, `KeyCap("→")`, practice line | `.changeTab` |
| 5 | `close` | Fold It Away | Move the pointer away and it folds back in, or swipe up on it. When you opened it from the keyboard, or you're typing in it, it stays until you press Esc or click outside. | `.compact` | `KeyCap("Esc")`, practice line | `.close` |
| 6 | `modules` | Seven Modules | Your tabs are Home, Media, Clock, Reminders, and Tools. Shelf and Notes open when you need them. Choose one to see it. | `.expanded` on the chosen module | 7 `ChipButton`s in a `FlowLayout`, then one line about the chosen module | none |
| 7 | `drop` | Drop Files on It | Drag a file toward the notch. Drop it on the left half to keep it on the Shelf, or on the right to AirDrop it. New screenshots land on the Shelf by themselves. | `.compact`, `tab: .shelf`, `fileDrag: true` | Practice line | `.dropFile` |
| 8 | `menuBar` | Keep a Module Close | Right-click a tab and choose Show in Menu Bar to give that module its own icon. Drag its window's header away to pop it out, and pin it there with Keep on Desktop. | `showMenuBar(.clock)` (the band slides to the menu bar) | Empty | none |
| 9 | `access` | Allow What You'll Use | Each is optional, and you can change it later in System Settings. Settings → Privacy shows where each one stands. | `.banner`, `event: .meeting` (the meeting banner with Join) | Three access rows and a note ([3.4](#34-the-access-step-permissions)) | none |
| 10 | `finish` | Make It Yours | Choose your tabs, arrange Home, and pick what may interrupt you in Settings. The gear beside the tabs opens it. | `.expanded`, `.home` | `ChipButton("Open at Login", systemImage: "power", isSelected: settings.launchAtLogin)` | none |

Copy that depends on the person's setup (built by small pure functions in `OnboardingFlow.swift`, each tested):

- **No open shortcut** (`shortcut(.open) == nil`): step 3 drops "From anywhere, press ⌃⌥Space." and its key caps; step 4 drops its
  second sentence; step 5 says "When you're typing in it, it stays until you press Esc or click outside."
- **Step 6** is built from `settings.tabs` and `settings.hiddenModules` with `.formatted(.list(type: .and))`: "Your tabs are
  \(tabs). \(hidden) open when you need them. Choose one to see it." Leave out the second sentence when nothing is hidden.
- **Step 7** follows `settings.dragTarget` (`DragTarget`, `AppSettings.swift:5`): `.shelfOnly` "Drop it on the island to keep it
  on the Shelf.", `.airDropOnly` "Drop it on the island to AirDrop it.", `.nothing` "Dragging files to the island is off. Turn it on
  in Settings → Shelf." (and no practice line). The screenshot sentence only when `settings.addsScreenshots`.

**Step 6's module lines** (one line each; for a module not in the tabs, append its `IslandModule.otherWayIn` as a second line,
`IslandViewModel.swift:18-26`):

| Module | Line |
| --- | --- |
| Home | Widgets for your day: what's next, music, tools, and timers. Right-click one to edit Home. |
| Media | What's playing in any app, with lyrics, shuffle, repeat, and where the sound goes. |
| Clock | A timer, a stopwatch, and Pomodoro. Drag or swipe the dial to set a timer. |
| Reminders | Add a reminder, and check off what's due. |
| Tools | Keep Awake, Ring Light, Mute Mic, Mirror, Record Screen, and more. Right-click one to pin it. |
| Shelf | Files you drop and what you copied. Right-click a file to convert, zip, or share it. |
| Notes | Notes, snippets, a Prompter, and voice notes turned into text on this Mac. |

Chips are `ChipButton(title: module.title, systemImage: module.systemImage, isSelected: module == chosen)`; clicking one calls
`preview.show(PreviewContext(presentation: .expanded, tab: module))`. Reuse `FlowLayout` (`Settings/WidgetGallery.swift:175`).

**Footer.** Leading: `ChipButton("Skip")` on every step but the last (temporary, [3.5](#35-skip-temporary)). Trailing: `Back` on
every step but the first, then the prominent button: "Get Started" on step 1, "Continue" on steps 2 to 9, "Done" on step 10. Step 10
also has `ChipButton("Open Settings")` before Done. The prominent button sits last, at the trailing edge (macOS's default-button
place).

**Stage.** Every step change calls `preview.show(step.stage, animated: true)` (or `showMenuBar(.clock)`), which already animates with
`Theme.Motion.open` or `.slide` and becomes a short ease under Reduce Motion (`IslandPreview.swift:92-131`). The title, copy, and
detail swap with `Theme.Motion.content` (`BlurFade`; opacity under Reduce Motion), keyed by the step id.

### 3.3 Practising on the real island

```swift
enum PracticeGoal: Equatable {
    case peek, open, changeTab, close, dropFile

    /// What the island was and is now. Pure, so it is tested without a panel.
    struct Island: Equatable { var state: IslandViewModel.State; var tab: IslandModule; var isFileDragActive: Bool }

    func isMet(from old: Island, to new: Island) -> Bool
    // peek:      new.state == .peek || new.state == .expanded    (with Peek on Hover off, a click still counts)
    // open:      new.state == .expanded
    // changeTab: new.state == .expanded && old.state == .expanded && new.tab != old.tab
    // close:     old.state != .compact && new.state == .compact
    // dropFile:  new.isFileDragActive && !old.isFileDragActive
}
```

`OnboardingView` watches the **live** `IslandViewModel` (from `AppDelegate`, not the stage's) with
`.onChange(of: island.state)`, `.onChange(of: island.selectedTab)`, `.onChange(of: island.isFileDragActive)` and passes each
change to `model.observe(_:)`, which marks the current step's goal met. No timers.

The practice line (a private view in `OnboardingView.swift`):
- Not met: `Glyph("hand.point.up.left")` in `Palette.tertiary` (a glyph, so tertiary is allowed) and the prompt in
  `Palette.secondary`, `Typography.body`.
- Met: `Glyph("checkmark.circle.fill", tint: Theme.Tint.positive)` and "Done", swapped with `Theme.Motion.content`. Green means
  done, and it sits beside its glyph (DESIGN → Color).
- Continue is always enabled. A practice check never blocks, and it never advances on its own.

| Goal | Prompt |
| --- | --- |
| `.peek` | Try it: rest the pointer on the notch. |
| `.open` | Try it: click the notch. |
| `.changeTab` | Try it: open the island, then swipe sideways. |
| `.close` | Try it: open the island, then move the pointer away. |
| `.dropFile` | Try it: drag any file toward the notch. |

**Giving the keyboard back.** ⌃⌥Space makes the island's panel key, so the guide stops being key. When the live state returns to
`.compact` while the guide is open and `NSApp.isActive`, call `onboardingPanel.makeKey()` so Return works again without a click.

### 3.4 The access step (permissions)

**Asked in the guide:** Calendars, Reminders, Bluetooth. These power things that arrive on their own (meeting and due-reminder
banners, Up Next, the headphones banner), so there is no "first use" moment at which to ask. Reminders is also a default tab.

**Asked on first use, as today** (named in a note under the rows): Camera (Mirror), Microphone and Speech (Voice Note), Screen
Recording (Record Screen), Accessibility (Clean Keys). Screen Recording and Accessibility send the person to System Settings, and
Screen Recording needs MacIsland to relaunch; asking at first use keeps that detour next to the feature that needs it, where the
existing banners already explain it. Focus is not asked: asking means turning on Quiet in Focus, which starts a 3 s poll
(`FocusMode.start()`), and the tour points at that switch instead.

**Rows.** `AccessRow` (private in `OnboardingView.swift`), `guideRowHeight` tall:

| Row | Glyph | Title | Reason (caption, secondary) |
| --- | --- | --- | --- |
| Calendars | `calendar` | Calendars | Your next meeting in Up Next, and a banner before it starts |
| Reminders | `checklist` | Reminders | Your reminders in their tab, and a banner when one is due |
| Bluetooth | `headphones` | Bluetooth | Your headphones and their battery when they connect |

Trailing control by state (`PrivacyAccess.State`, `Settings/PrivacyAccess.swift:9`):
- `notAsked`: `ChipButton("Allow")`; disabled while its request is in flight.
- `allowed`: `Glyph("checkmark.circle.fill", tint: Theme.Tint.positive)` and "Allowed" in `Palette.secondary`.
- `denied`: `Glyph("exclamationmark.circle.fill", tint: Theme.Tint.attention)` and `ChipButton("Open Settings")`, which opens that
  row's `PrivacyAccess.settingsURL`. (A denied permission can't be asked again; macOS answers no at once.)

Under the rows, in `Typography.caption`, `Palette.secondary`: "Camera, Microphone, Screen Recording, and Accessibility are asked for
the first time you use Mirror, Voice Note, Record Screen, or Clean Keys."

If all three rows are `allowed` when the flow is built, the step is left out (`OnboardingFlow.make(allAccessAllowed:)`).

**The model.** `Onboarding/AccessRequests.swift`:

```swift
enum AccessKind: String, CaseIterable { case calendars, reminders, bluetooth }   // rawValue = PrivacyAccess.id

@MainActor protocol AccessProviding: AnyObject {
    func state(of kind: AccessKind) -> PrivacyAccess.State
    func request(_ kind: AccessKind) async -> Bool
}

/// The real Mac. States come from `PrivacyAccess.current()` by id; requests use the app's own paths.
@MainActor final class LiveAccess: AccessProviding {
    init(agenda: AgendaMonitor, bluetooth: BluetoothAccess)
    // calendars: await agenda.requestAccess(to: .event)       reminders: await agenda.requestAccess(to: .reminder)
    // bluetooth: await bluetooth.request()
}

@MainActor @Observable final class AccessModel {
    private(set) var states: [AccessKind: PrivacyAccess.State]
    private(set) var asking: AccessKind?
    init(provider: AccessProviding, settings: AppSettings, onBluetoothAllowed: @escaping () -> Void)
    var allAllowed: Bool
    func refresh()                          // re-reads every state
    func allow(_ kind: AccessKind) async    // one row
    func requestAllPending() async          // Skip: every notAsked row, in AccessKind order, one after another
}
```

What a grant does, so the permission and the choice it serves are one step:
- Calendars granted: `settings.showsCalendar = true` (Up Next and the meeting banner; this is the switch that asks today).
- Reminders granted: `settings.showsReminders = true`.
- Bluetooth granted: `onBluetoothAllowed()` starts `AudioAccessoryMonitor` if it was deferred.
- Denied: change nothing.

Existing code to add:
- `AgendaMonitor.requestAccess(to type: EKEntityType) async -> Bool { await hasAccess(type) }`: a public door to the request the
  Settings switches and the Reminders tab already use. Doc comment says so.
- `Onboarding/BluetoothAccess.swift`: `@MainActor final class BluetoothAccess: NSObject, CBCentralManagerDelegate` with
  `func request() async -> Bool`. If `CBManager.authorization` is already decided, return it. Otherwise create a
  `CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])`, keep it until
  `centralManagerDidUpdateState` sees `CBManager.authorization != .notDetermined`, resume, and release it. This is a new request
  because the app has no explicit Bluetooth request today; it is the same authority `PrivacyAccess` already reads, and it returns
  the answer (IOBluetooth's implicit prompt does not). `NSBluetoothAlwaysUsageDescription` is already in `Support/Info.plist`.
- `PrivacyAccess.current()`: add `row("accessibility", "Accessibility", "Clean Keys", AXIsProcessTrusted() ? .allowed : .denied,
  pane: "Privacy_Accessibility")`, after Screen Recording. Like Screen Recording it can't tell "never asked" from "off". The Privacy
  pane shows it with no other change.

**Deferring launch-time prompts** (only if checkpoint 0 shows them). On a fresh install whose guide is pending
(`onboarding.install == .fresh && onboarding.needsGuide`), `connectEvents` does not call `accessoryMonitor.start()` or
`features.transfers.start()`. They start when the guide ends in any way (Done, Open Settings, Close, Skip), and the accessory
monitor also starts when the Bluetooth row is granted. Make both starts idempotent first (`AudioAccessoryMonitor.start` returns if
`notification != nil`; `TransferMonitor.start` returns if `subscriber != nil`). An existing install, and every later launch, starts
them at launch exactly as today.

### 3.5 Skip (temporary)

> **TEMPORARY.** Skip exists so the user can test the permission prompts without clicking through every step. Remove it before
> release. Everything about it hangs off one flag, so removing it is deleting the flag and the code it guards.

- `static let showsSkip = true  // TEMPORARY (onboarding Skip): remove before release; see docs/plans/onboarding-plan.md` in
  `OnboardingModel`. Every Skip line is inside `if OnboardingModel.showsSkip` and carries the same `TEMPORARY` comment.
- `ChipButton("Skip")` at the footer's leading edge on steps 1 to 9.
- `skip()`: `state.finishGuide()`, close the window, then `await access.requestAllPending()`, then start any deferred monitors.
  Closing first means the system prompts aren't fighting the guide for the screen.
- Add a line to `docs/ROADMAP.md` → Dormant code and cleanup: "Onboarding **Skip** is temporary: delete
  `OnboardingModel.showsSkip` and what it guards before release."

### 3.6 Showing the guide

- `App/OnboardingWindowController.swift`, shaped like `SettingsWindowController`: `static let shared`, a `context` set at launch,
  `isOpen`, `show(replay: Bool)`, and `close(_ reason: CloseReason)` (`.done`, `.openSettings`, `.closed`, `.skipped`). `show`
  calls `NSApp.activate()` first (an accessory app must activate for its window to take keys and for the system prompts to come
  forward), builds `OnboardingModel` and a fresh `IslandPreviewModel(live: features)` (with `allowsMenuBar = true` for step 8), and
  stops the preview in `windowWillClose`.
- `OnboardingContext` holds what the model needs from the app: `features`, the live `island: IslandViewModel`, `state`, `access`,
  `startDeferredMonitors: () -> Void`, and `openSettings: () -> Void`.
- At the end of `applicationDidFinishLaunching` (after `connectReach()`, `App/MacIslandApp.swift:94`): set the context and
  `SettingsWindowController.shared.onboarding`, then `if onboarding.needsGuide { OnboardingWindowController.shared.show(replay: false) }`.
- `URLCommand` (`App/URLCommand.swift`) gains `.guide(reset: Bool)` for `macisland://guide` and `.settingsTour` for
  `macisland://tour`. `reset=1` is parsed only `#if DEBUG`. `URLCommandRunner` gets `onGuide: ((Bool) -> Void)?` and
  `onTour: (() -> Void)?`, set by `AppDelegate`. Both commands only show UI, so they fit the link's guardrails.
- The Settings tour does not start by itself while the guide window is open ([4.6](#46-starting-advancing-going-back-and-ending)).

---

## 4. The Settings tour

### 4.1 The look

- **The ring** around the target: `RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)`, stroked
  `Color.accentColor`, `tourRingWidth`, `tourRingInset` outside the target's frame, no hit testing. This is Settings chrome in the
  system accent color, like the Home editor's rings and handles (DESIGN → Structure).
- **The callout**: black, like the island, because it is MacIsland speaking; it reads the same in light and dark windows.
  `Theme.Palette.surface` fill, `cardRadius` continuous corners, and a 1 pt `Theme.Palette.widgetEdge` hairline (the Home widgets'
  edge, so it still separates from a dark window), `tourCalloutWidth` wide. The arrow is a filled triangle (`tourArrow`) in the same
  black on the side facing the target, `tourGap` from it. No stroke on the arrow, so no seam. It uses the island's own ink
  (`\.islandSurface = .hardware`, the default).
- Contents, top to bottom: the title (`Typography.title`, `Palette.primary`) with `IconButton(systemName: "xmark", label: "End
  Tour", size: 12)` at the trailing edge; the copy (`Typography.body`, `Palette.secondary`, wraps); a footer with "3 of 15"
  (`Typography.caption`, `Palette.secondary`), then `ChipButton("Back")` (not on the first stop) and
  `ChipButton("Next", isProminent: true)`, which reads "Done" on the last stop.

```
                 ┌───────────────────────┐   ← the control; ring: accentColor, tourRingWidth, tourRingInset
                 └───────────────────────┘
                            ▲                  tourArrow, tourGap from the ring
      ╭──────────────────── tourCalloutWidth ───────────────────╮
      │ Open It From Anywhere                                 ⊗ │   title · IconButton "End Tour"
      │ Click here and press the keys you want to open the      │   body, secondary
      │ island from anywhere.                                   │
      │ 3 of 15                                  Back    Next   │   caption · ChipButton · ChipButton(isProminent)
      ╰─────────────────────────────────────────────────────────╯
```

- Motion: the callout arrives with `Theme.Motion.floatTransition` under `Theme.Motion.float`; moving to the next stop, the ring and
  callout move with `Theme.Motion.resize`. Geometry-only updates (the window resizing, the pane scrolling) apply **without**
  animation, so they track instead of lagging.

### 4.2 The stops

`Settings/SettingsTour.swift` holds `TourStop.all` as data. "Placement" is where the callout sits relative to the target; the
placement function flips it when there isn't room. "Scroll to" is the `SettingsAnchor` the pane scrolls to (top) when the stop
starts. "Preview" is what the stop shows in the preview, restored to the pane's own `previewContext` when the stop ends.

| # | id | Pane | Target (file → view to anchor) | Placement | Scroll to | Preview | Title | Copy |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `search` | General | `SettingsSidebar.swift` → `SidebarHeader.searchField` | trailing | | | Find Any Setting | Search by name, or by another word for it, like “airpods”. ⌘F works from anywhere in this window. |
| 2 | `preview` | General | `IslandPreview.swift` → `PreviewBand` | below | | | Your Island, Live | Each pane shows the real island from sample data, so a change appears where it lands. Click Compact, Peek, Banner, or Expanded above it, or swipe on it. |
| 3 | `shortcut` | General | `GeneralPane.swift` → the `ShortcutRecorder` row | below | `shortcut` | | Open It From Anywhere | Click here and press the keys you want to open the island from anywhere. |
| 4 | `input` | General | `GeneralPane.swift` → `Toggle("Peek on Hover")` | below | `input` | | Hover and Swipe | If the island opens when you reach for the menu bar, turn off Peek on Hover; a click still opens it. Swiping can be turned off here too. |
| 5 | `tabs` | Tabs | `IslandPreview.swift` → `NotShownTray` | below | | | Arrange Your Tabs | Drag a tab onto another to swap them, or drag one from Not Shown to replace a tab. Five fit left of the notch and one right of it. |
| 6 | `menuBar` | Tabs | `TabsPane.swift` → the first row of `MenuBarSection` | above | `menuBar` | `showMenuBar(.home)` | Put a Module in the Menu Bar | Switch a module on to give it its own icon. Drag its window's header away to pop it out. |
| 7 | `homeCanvas` | Home | `PreviewBand` | below | | | Arrange Home | Drag a widget to move it, or drag its corner to resize it. The island grows and shrinks with its rows. |
| 8 | `addWidgets` | Home | `WidgetGallery.swift` → the chips' `FlowLayout` (or the "Every widget is on Home." text) | above | `widgets` | | Add Widgets | Everything not on Home waits here. Drag a widget into the island, or press its plus. |
| 9 | `upNext` | Home | `HomePane.swift` → `Toggle("Calendar Events")` | above | `upNext` | | Up Next | Turn these on to see your next meeting and due reminders on Home, with a banner before they start. |
| 10 | `dragTarget` | Shelf | `ShelfPane.swift` → `SettingsDropdown("When You Drag a File")` | below | `files` | | When You Drag a File | Choose what the island becomes as a file comes near: the Shelf, AirDrop, both, or nothing. |
| 11 | `music` | Media | `MediaPane.swift` → `Toggle("Show Music Beside the Notch")` | below | `music` | | Music Beside the Notch | Turn this off to keep music in Home and the Media tab only. |
| 12 | `toolsRow` | Tools | `ToolsPane.swift` → `LabeledContent("Tools in the Row")` | below | `toolsRow` | | Your Tools Row | Choose how many tools the row shows, then drag them into order below. Home's quick tools are the first four. |
| 13 | `interruptions` | Notifications | `NotificationsPane.swift` → `Toggle("Quiet in Focus")` | below | `interruptions` | | Choose What Interrupts You | Click an interruption to see its banner above, and switch off any you don't want. Quiet in Focus holds them while a Focus is on. |
| 14 | `privacy` | Privacy | `PrivacyPane.swift` → the first row of the Access section | above | `access` | (none) | Privacy in One Place | Everything MacIsland sends, runs, and may use is listed here, and each can be turned off. |
| 15 | `guide` | General | `GeneralPane.swift` → the new Guide section's buttons | above | `guide` (new) | | See This Again | Replay the welcome guide or this tour here anytime. |

Every pane has at least one stop, and each pane's stops are consecutive except General, which opens and closes the tour.

```swift
enum TourTarget: Hashable { case search, previewBand, shortcut, peekOnHover, notShownTray, menuBarRow, addWidgets,
                            calendarEvents, dragTarget, musicCompact, toolsRow, quietInFocus, accessList, guide, paneViewport }

struct TourStop: Identifiable, Equatable {
    enum Placement { case above, below, leading, trailing }
    let id: String; let since: Int; let pane: SettingsPane; let target: TourTarget; let placement: Placement
    let scrollAnchor: String?; let preview: PreviewContext?; let title: String; let copy: String
    static let all: [TourStop]
}
```

### 4.3 Anchoring: frames into an observable registry

Follow the pattern the Home editor already uses (`onGeometryChange` into an `@Observable`, in a named coordinate space), not
`anchorPreference`. Preferences from inside a macOS `Form`'s rows are not guaranteed to reach an ancestor; `onGeometryChange` reports
through a closure, and `.named(...)` spaces are already proven to resolve across the Form (`WidgetGallery`'s drag).

```swift
@MainActor @Observable final class TourAnchors {
    static let space = "SettingsTour"
    private(set) var frames: [TourTarget: CGRect] = [:]
    func set(_ target: TourTarget, _ frame: CGRect?)   // does nothing unless it changes (no-op setter rule)
}

// Hand-written EnvironmentKey (no @Entry with the Command Line Tools): \.tourAnchors: TourAnchors?
extension View {
    /// Tells the Settings tour where this view is. Free when no tour registry is in the environment.
    func tourAnchor(_ target: TourTarget) -> some View   // onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TourAnchors.space)) }
                                                         // action: anchors?.set(target, $0); .onDisappear { anchors?.set(target, nil) }
}
```

- `SettingsView` owns one `TourAnchors` and one `SettingsTour` in `@State`, puts `.environment(\.tourAnchors, anchors)` and
  `.coordinateSpace(.named(TourAnchors.space))` on the `HStack` inside its `GeometryReader` (`SettingsView.swift:46`), so the
  sidebar and the detail share one space. Removing an anchor on disappear means a pane that is gone never leaves a stale frame.
- `content` (the pane's Form) gets `.tourAnchor(.paneViewport)`, so the overlay knows the visible part of the pane.
- Add `.tourAnchor(...)` at the call sites in the table above. For views built in a `ForEach` (the first Menu Bar row, the first
  access row), apply it only to the first element.

**Checkpoint rule (C9).** Before building the other stops, wire one (`shortcut`) and check by hand that the ring follows the row when
the pane scrolls and when the window resizes. If `onGeometryChange` does not fire while a `Form` scrolls, use this fallback instead
of the modifier's body, and keep its API: an invisible `NSViewRepresentable` probe at the target that reports
`convert(bounds, to: nil)` (window coordinates) to the registry on `NSView.frameDidChangeNotification` and on the enclosing
`NSScrollView`'s `contentView` `boundsDidChangeNotification`, with the overlay converting from window coordinates with its own probe.
Record which one was used in ARCHITECTURE's gotchas.

### 4.4 Layering over the sidebar and the preview

- `SettingsTourOverlay(tour:anchors:)` is an `.overlay` on that same `HStack`, so it is above the sidebar (which has `zIndex(1)`
  inside the `HStack`), the preview, the pane, and `HomeDragLayer` (an overlay on the detail column).
- The overlay is a `GeometryReader` (its size is the placement bounds) holding the ring and the callout. **Only the callout takes
  clicks**: the container and the ring have `.allowsHitTesting(false)`, so the person can try the control being pointed at. The
  preview stays look-only as today; `PreviewSwipe` still hears swipes through its local monitor.
- Sheets (`CustomWidgetSheet`), `NSAlert`s, save and open panels, and `StyledDropdown` popovers are separate windows above the
  overlay. The tour needs no special case for them.
- Nothing is dimmed. A scrim with a cutout reads as a template tutorial and hides the preview the tour is about.

### 4.5 Placement, resizing, and scrolling

`CalloutPlacement` is pure and tested:

```swift
struct CalloutPlacement: Equatable {
    var frame: CGRect                 // the callout, in the tour space
    var placement: TourStop.Placement // where it ended up
    var arrowOffset: CGFloat          // along the side facing the target, from that side's leading or top end
    static func place(target: CGRect, size: CGSize, in bounds: CGRect, preferred: TourStop.Placement,
                      gap: CGFloat, arrow: CGSize, edgeInset: CGFloat, cornerRadius: CGFloat) -> CalloutPlacement
}
```

1. Try `preferred`, then the opposite side, then the two remaining sides; take the first where the callout plus `gap` plus the
   arrow fits inside `bounds.insetBy(edgeInset)`. If none fits, take the side with the most room.
2. Center the callout on the target along the other axis, then clamp it inside `bounds.insetBy(edgeInset)`.
3. `arrowOffset` points at the target's center, clamped to `[cornerRadius + arrow.width / 2, side length − cornerRadius −
   arrow.width / 2]` so the arrow never sits on a rounded corner.

The callout's height comes from its content (width fixed), measured with `onGeometryChange` on the callout itself.

- **Resizing:** every anchor and the overlay's bounds update through geometry, so placement is recomputed on each layout. Apply those
  updates without animation.
- **Scrolling:** when a stop starts and has a `scrollAnchor`, set `SettingsView.scrollTarget` (the existing search path; it waits
  150 ms for the pane, then `scrollTo(anchor, anchor: .top)`). If the person scrolls afterwards the ring follows (see C9).
- **Target out of view:** when a Form target's frame doesn't intersect `.paneViewport`, hide the ring and dock the callout without
  its arrow at the bottom center of the viewport, with a `ChipButton("Show Me")` that sets `scrollTarget` again.
- **Sidebar hidden:** starting the tour shows the sidebar (`setSidebar(hidden: false)`). If the person hides it during stop 1, the
  search field has no frame and the callout docks the same way.
- **No frame yet** (the pane is still appearing): draw nothing for that stop until its target reports a frame.

### 4.6 Starting, advancing, going back, and ending

```swift
@MainActor @Observable final class SettingsTour {
    private(set) var index: Int?                 // nil: not running
    var current: TourStop?
    init(stops: [TourStop] = TourStop.all, onFinish: @escaping () -> Void)
    func start()                                  // index = 0
    func next()                                   // past the last stop: end()
    func back()                                   // clamps at 0
    func jump(to pane: SettingsPane)              // the first stop on that pane
    func end()                                    // index = nil, onFinish()
}
```

- **Starting.** In `SettingsView.onAppear` (after the preview model exists) and on `.onChange(of: onboarding.tourRequested)`: start
  if (`onboarding.needsTour` or `onboarding.tourRequested`), the guide window is not open, and the window was not opened for a
  specific destination (`settings.requestedHomeSelection == nil`, the "Edit Home…" path). Clear `tourRequested` when starting.
  The first stop is drawn once its anchor reports a frame (no timer).
- **Each stop** sets `storedPane` to its pane (the preview follows through the existing `.onChange(of: storedPane)`), shows its
  `preview` context if it has one (`preview.showMenuBar(.home)` for stop 6), and sets `scrollTarget`. Leaving a stop that changed
  the preview calls `showPreview(for: pane)` to restore it.
- **Next / Back / End Tour** are the callout's buttons. **Return** is Next through a local key monitor installed while the tour
  runs, which passes the event on when `window.firstResponder is NSTextView` (the search field, a text field) or while
  `ShortcutCapture` is recording. Add `static private(set) var isActive` to `ShortcutCapture`
  (`Settings/ShortcutRecorder.swift:31`), set in `start` and `stop`. Don't use `.keyboardShortcut(.defaultAction)` here: a default
  button takes Return from the focused search field and the weather field. **Esc is not bound**: in this window it already clears
  search, cancels the recorder, and calls off a Home drag.
- **Choosing a pane in the sidebar** during the tour calls `tour.jump(to:)`, so the tour follows the person instead of fighting them.
- **Ending** in any way (Done on the last stop, End Tour, closing the window, which runs `.onDisappear`) calls `finishTour()` and
  removes the key monitor.
- On each stop change, post `AccessibilityNotification.Announcement("\(title). \(copy)")`. The callout is one container element;
  the ring is hidden from accessibility.

### 4.7 Replay from Settings

`GeneralPane` gains a section after Input:

```swift
Section {
    HStack(spacing: 8) {
        FieldButton(title: "Show the Welcome Guide", systemImage: "sparkles") { onReplayGuide() }
        FieldButton(title: "Take the Settings Tour", systemImage: "hand.point.up.left") { onReplayTour() }
    }
    .tourAnchor(.guide)
} header: {
    Text("Guide").id(SettingsAnchor.guide)
} footer: {
    Text("The guide shows the gestures and modules again. The tour points out each pane's main controls.")
}
```

`FieldButton` is Settings' own custom button (`Dropdown.swift:203`). Add `SettingsAnchor.guide = "general.guide"` and two
`SettingsSearch.entries`: "Welcome Guide" (keywords: onboarding, tutorial, intro, help, getting started, gestures) and "Settings
Tour" (keywords: tour, tutorial, help, walkthrough, tips), both with `anchor: SettingsAnchor.guide`. `SettingsView` passes the two
closures: the guide opens with `OnboardingWindowController.shared.show(replay: true)`; the tour starts in place.

---

## 5. New components and tokens

Reused as they are: `ChipButton`, `IconButton`, `Glyph`, `IslandButtonStyle`, `FieldButton`, `FlowLayout`, `floatingGlass()`,
`FloatingGlassPanel`, `IslandPreviewModel`, `PreviewFeatures`, `Announcements.sample`, `PrivacyAccess`, `KeyCombo.display`,
`IslandModule.title`/`.systemImage`/`.otherWayIn`, the `SettingsView.scrollTarget` path, and the motion tokens.

### 5.1 Components

| Name | File | API | Why it is new |
| --- | --- | --- | --- |
| `StepDots` | `Island/Components.swift` | `StepDots(count: Int, current: Int)` | Nothing in the app shows progress through steps. Dots are `stepDot` circles in `Palette.tertiary` (glyph ink); the current one is a `stepDotCurrent`-wide capsule in `Palette.primary`, moving with `Theme.Motion.resize`. One accessibility element, "Step 3 of 10". Not interactive. |
| `KeyCap`, `KeyCaps` | `Island/Components.swift` | `KeyCap(_ symbol: String, spoken: String)`; `KeyCaps(combo: KeyCombo)` | Shortcuts are named in three steps; nothing draws a key. `Typography.bodyEmphasized`, `Palette.primary` on `Palette.fill`, `keyCapHeight` tall, `keyCapRadius` continuous, symbols ⌃ ⌥ ⇧ ⌘ as their own caps, spoken labels ("Control Option Space") for VoiceOver. |
| `KeyCombo.parts` | `Settings/KeyCombo.swift` | `var parts: [(symbol: String, spoken: String)]` | `KeyCaps` needs the pieces; `display` becomes `parts.map(\.symbol).joined()`, so the two can't disagree. |
| `PreviewBand` | `Settings/IslandPreview.swift` | `PreviewBand(model:, editor: HomeEditor? = nil, tabEditor: TabEditor? = nil)` | **Extracted, not new.** Today the band (the wallpaper, `BandSlide`, `islandBand`, the clip, and `bandFrame`) is private inside `IslandPreview` (`:219-281`). The guide's stage needs the band without the switcher, arrows, tray, and hints. `IslandPreview` keeps its behavior by composing it; the arrows stay an overlay in `IslandPreview`. |
| `OnboardingPanel` | `App/OnboardingWindowController.swift` | `final class OnboardingPanel: FloatingGlassPanel` | A `FloatingGlassPanel` without `.resizable`. |
| `AccessRow`, practice line | `Onboarding/OnboardingView.swift` (private) | | Used only by the guide. |
| `TourCallout`, `TourRing`, `SettingsTourOverlay`, `.tourAnchor(_:)` | `Settings/SettingsTour.swift` | See [section 4](#4-the-settings-tour) | The tour's own chrome. |

### 5.2 Tokens (`Island/Theme.swift`, `Metrics`)

Each goes in with a doc comment giving its reason, as the existing tokens have.

| Token | Value | Reason |
| --- | --- | --- |
| `previewBandHeight` | `panelHeight + 4` | Moves `IslandPreview.bandHeight` (`IslandPreview.swift:331`) into Theme so the Settings preview and the guide's stage share it. `IslandPreview.bandHeight` goes away. |
| `guideWidth` | `ScreenGeometry.panelSize.width + 2 * floatPadding` | The stage is the 560 pt band at 1:1 inside the glass inset. |
| `guideRowHeight` | `hitTarget + rowSpacing` | One access row: a 28 pt control and its spacing. |
| `guideDetailHeight` | `150` | The tallest step detail (three access rows and a two-line note). Every step gets this much, so the window never changes height. Measure in the app and adjust; keep the doc comment's arithmetic true. |
| `stepDot` / `stepDotCurrent` | `6` / `18` | The step indicator. |
| `keyCapHeight` / `keyCapRadius` | `22` / `6` | A key, drawn a little taller than body text. |
| `tourCalloutWidth` | `280` | Wide enough for the longest copy in four lines. |
| `tourArrow` | `CGSize(width: 16, height: 8)` | The callout's arrow. |
| `tourGap` | `6` | Between the ring and the arrow's tip. |
| `tourRingInset` / `tourRingWidth` | `4` / `2` | The ring around the control. |
| `tourEdgeInset` | `12` | The nearest a callout comes to the window's edge. |

No new colors, fonts, or motion tokens:
- The step title is `Typography.headline` and the copy `Typography.subheadline`, like the player's song and artist pair. Update
  DESIGN's Type paragraph to say so.
- Permission and practice states use `Tint.positive` and `Tint.attention`. The tour's ring is `Color.accentColor` (Settings chrome).
- The guide window and a callout arriving use `float`/`floatTransition`; a callout moving uses `resize`; step content uses
  `content`; the stage uses the preview's own `open`/`slide`. Add those uses to DESIGN's Motion table.

---

## 6. File-by-file change list and checkpoints

Each checkpoint ends with: `./scripts/test.sh` passes, `make build-and-restart`, the named look, and a commit. Use
`open macisland://guide` to see the guide after a restart, and (DEBUG) `open 'macisland://guide?reset=1'` to see it as a fresh install
would. Format **new** files only with `./scripts/format.sh <new files>`; never run it over existing files.

### C0: baseline and facts (no code)

1. `git status` is clean; `./scripts/test.sh` passes (514). Save `./scripts/lint.sh > /tmp/lint-before.txt`.
2. **Ask the user first**, then: back up with `defaults export com.ethantiller.MacIsland ~/Desktop/macisland-defaults.plist` and
   copy `~/Library/Application Support/MacIsland/notes.json` aside; quit MacIsland; `defaults delete com.ethantiller.MacIsland`;
   move `notes.json` away; `tccutil reset All com.ethantiller.MacIsland`; launch `build/MacIsland.app`. Write down every system
   prompt that appears before touching anything (expect Bluetooth and possibly Downloads).
3. Restore: quit, `defaults import com.ethantiller.MacIsland ~/Desktop/macisland-defaults.plist`, put `notes.json` back.
4. If no prompt appeared at launch, skip the deferral in C7 and say so in the ROADMAP decision row.

### C1: state

- New `Sources/MacIsland/Onboarding/OnboardingState.swift`: `OnboardingState`, `InstallEvidence` ([section 2](#2-state-model)).
- `Notes/NotesModel.swift`: `static var defaultFileURL: URL`; `init` uses it.
- `App/MacIslandApp.swift`: `let onboarding = OnboardingState()` as `AppDelegate`'s first stored property.
- New `Tests/MacIslandTests/OnboardingTests.swift`: the state tests in [section 7](#7-tests).
- Look: launch is unchanged; `defaults read com.ethantiller.MacIsland onboarding.install` prints `existing` on the user's Mac.

### C2: access

- `Settings/PrivacyAccess.swift`: the Accessibility row.
- `Agenda/AgendaMonitor.swift`: `requestAccess(to:)`.
- New `Onboarding/BluetoothAccess.swift`, new `Onboarding/AccessRequests.swift` (`AccessKind`, `AccessProviding`, `LiveAccess`,
  `AccessModel`).
- `System/AudioAccessoryMonitor.swift`, `Transfers/TransferMonitor.swift`: idempotent `start()`.
- Tests: access tests with a `StubAccess` in `TestSupport.swift`.
- Look: Settings → Privacy lists Accessibility.

### C3: tokens and components

- `Island/Theme.swift`: the tokens in [5.2](#52-tokens-islandthemeswift-metrics).
- `Island/Components.swift`: `StepDots`, `KeyCap`, `KeyCaps`. `Settings/KeyCombo.swift`: `parts`.
- `Settings/IslandPreview.swift`: extract `PreviewBand`; use `Theme.Metrics.previewBandHeight`. Update
  `Tests/MacIslandTests/SettingsSnapshots.swift` only if it referenced `IslandPreview.bandHeight`.
- Tests: `KeyCombo.parts` for ⌃⌥Space, ⌘⇧K, and F5; `display` unchanged for the same.
- Look: every Settings pane's preview is exactly as before (Home editing, Tabs dragging, Menu Bar slide, arrows).

### C4: the guide's shell

- New `Onboarding/OnboardingFlow.swift` (`GuideStepID`, `GuideStep`, `OnboardingFlow`, the copy functions).
- New `Onboarding/OnboardingModel.swift` (`@Observable`: flow, preview, access, practice results, `showsSkip`, `next`, `back`,
  `skip`, `finish`, `close`, `observe`).
- New `Onboarding/OnboardingView.swift`: header (`StepDots`, ⊗), stage (`PreviewBand`), title and copy, detail area, footer.
  Only `welcome` and `finish` have their details yet.
- New `App/OnboardingWindowController.swift`: `OnboardingPanel`, the controller, `OnboardingContext`.
- `App/MacIslandApp.swift`: show at launch when needed; wire `URLCommandRunner.onGuide`/`onTour`.
- `App/URLCommand.swift`: `.guide(reset:)`, `.settingsTour`.
- Look: `open macisland://guide`. The window drops in below the island, centered, the stage shows the compact island with music,
  Return continues, ⊗ closes, and `defaults read … onboarding.guide` is `1` after closing.

### C5: the gesture steps

- `peek`, `open`, `tabs`, `close`: stage contexts, key caps, practice lines, `PracticeGoal`, the live-island observation, and
  giving the keyboard back.
- Look: on the real notch, hover (the peek step turns green), click (open), swipe sideways (tabs), move away (close); ⌃⌥Space, the
  arrows, and Esc work on the island while the guide is open and never change the guide's step. Hovering the island **while the guide
  window is key** must still peek (see [Risk 3](#9-risks-and-gotchas)).

### C6: modules, dropping files, the menu bar

- `modules` (chips in `FlowLayout`, the module lines, the stage following the chip), `drop` (drop-target stage, dynamic copy,
  `dropFile` practice), `menuBar` (`showMenuBar(.clock)`).
- Look: every module chip shows its tab at 1:1; dragging a Finder file toward the notch turns the drop step green; the menu bar
  slide plays and comes back when going Back.

### C7: access and Skip

- `access` step: rows, note, `Open Settings` for denied rows, refresh on key and on activation, the step left out when all are
  allowed.
- `Skip` (temporary) on steps 1 to 9.
- `App/MacIslandApp.swift`: the deferral in `connectEvents` (only if C0 found launch prompts) and `startDeferredMonitors`.
- Look, on a clean TCC state (`tccutil reset Calendar com.ethantiller.MacIsland`, likewise `Reminders` and `BluetoothAlways`, then
  `open 'macisland://guide?reset=1'`): each Allow shows its prompt once; Allowed and Off draw as specified; Skip on step 1 closes the
  guide and shows the three prompts one after another; after granting Calendars, Settings → Home → Up Next has Calendar Events on.

### C8: the last step and closing

- `finish`: Open at Login chip (`settings.setLaunchAtLogin`, refreshed with `settings.refresh()` on appear), Open Settings, Done.
- Look: Open at Login toggles (from the bundle); Open Settings closes the guide and opens Settings (the tour starts once C10 lands).

### C9: the tour's machinery and one stop

- New `Settings/SettingsTour.swift`: `TourTarget`, `TourStop` (with `all` holding only `shortcut` for now), `SettingsTour`,
  `TourAnchors` and its environment key, `.tourAnchor(_:)`, `CalloutPlacement`, `TourCallout`, `TourRing`,
  `SettingsTourOverlay`.
- `Settings/SettingsView.swift`: owns the tour and anchors; environment, coordinate space, overlay, `.tourAnchor(.paneViewport)`
  on `content`; starts the tour; `onboarding` passed in by `SettingsWindowController`.
- `App/SettingsWindowController.swift`: `var onboarding: OnboardingState?`, passed to `SettingsView`.
- `Settings/GeneralPane.swift`: `.tourAnchor(.shortcut)` on the recorder.
- New `Tests/MacIslandTests/SettingsTourTests.swift`: placement and controller tests.
- Look: the ring follows the Shortcut row while scrolling General and while resizing the window from its minimum (830 × 600) to
  large. If not, switch to the fallback in [4.3](#43-anchoring-frames-into-an-observable-registry) now.

### C10: every stop

- `TourStop.all` complete. Anchors at every call site in the table: `SettingsSidebar.swift`, `IslandPreview.swift` (`PreviewBand`,
  `NotShownTray`), `GeneralPane.swift`, `TabsPane.swift`, `WidgetGallery.swift`, `HomePane.swift`, `ShelfPane.swift`,
  `MediaPane.swift`, `ToolsPane.swift`, `NotificationsPane.swift`, `PrivacyPane.swift`.
- Stop previews (stop 6's Menu Bar), `jump(to:)` from the sidebar, the Return key monitor, `ShortcutCapture.isActive`, the
  docked out-of-view callout.
- Look: all 15 stops at the minimum window size and at a large size, in light and dark; clicking panes mid-tour jumps; closing the
  window mid-tour ends it and it doesn't come back on reopening.

### C11: replay and search

- `Settings/GeneralPane.swift`: the Guide section. `Settings/SettingsSearch.swift`: `SettingsAnchor.guide`, two entries.
- `SettingsView`: the replay closures; `.onChange(of: onboarding.tourRequested)`.
- Look: both buttons work, search finds "tour" and "onboarding", `open macisland://tour` opens Settings on the tour.

### C12: snapshots and pictures

- New `Tests/MacIslandTests/OnboardingSnapshots.swift` ([section 7](#7-tests)).
- `scripts/docs-images.sh`: add `40-guide-01-welcome`, `40-guide-06-modules`, `40-guide-09-access`, `43-tour-03-shortcut`.
- Run `ISLAND_SNAPSHOT_DIR=/tmp/island ./scripts/test.sh --filter OnboardingSnapshots` and look at every PNG, then
  `./scripts/docs-images.sh`.

### C13: docs ([section 8](#8-docs-to-update))

### C14: hand test and finish

- Every "First run" item in the ROADMAP hand-test checklist, on the user's Mac, then the [completion checklist](#11-completion-checklist).

---

## 7. Tests

Swift Testing (`import Testing`), `@MainActor` suites, a private `UserDefaults` suite per test (as `TestSupport.makeViewModel()`
does), temp folders, no real permissions, no sleeping for fixed times.

### `OnboardingTests.swift`

State:
- `freshInstallNeedsBoth`: empty suite, no notes file: `install == .fresh`, `needsGuide`, `needsTour`, and `onboarding.install`
  is written.
- `updaterWithSettingsSkipsBoth`: suite has `tabsLeft`: `.existing`, neither needed, `guide == 1` and `settingsTour == 1` written.
- `updaterWithOnlyTheNotesFileSkipsBoth`: empty suite, `fileExists` true for the notes URL: `.existing`.
- `classificationIsWrittenOnce`: fresh, then `tabsLeft` written and the notes file "exists" (a quit mid-guide), then a new
  `OnboardingState` on the same suite: still `.fresh` and `needsGuide`.
- `finishingIsRemembered`: `finishGuide()`, `finishTour()`, a new instance: neither needed.
- `aNewGuideVersionShowsAgain`: seen 1, `guideVersion: 2`: `needsGuide`; `OnboardingFlow.make(seen: 1, …)` holds only steps with
  `since > 1` and `finish`.
- `resetToFreshShowsBothAgain`.
- `evidenceKeysCoverEverySetting` (**the drift guard**): on a private suite, change every `AppSettings` choice (each property, a
  tab move, a menu-bar module, a pin, a muted event, a custom widget, a Home layout, a saved preset), add a Shelf file, record a
  Pomodoro session; every key in `defaults.persistentDomain(forName: suite)` is in `InstallEvidence.keys`.
- `onboardingNeverEntersTheSettingsFile`: after `finishGuide()`, `SettingsArchive.make(from:).data()` has no `onboarding`; after
  `resetAll()`, the onboarding keys are unchanged.

Flow and copy:
- `everyStepForAFreshInstall`: 10 steps in the table's order.
- `accessIsLeftOutWhenAllAllowed`.
- `replayShowsEveryStep`, `nextAndBackClamp`.
- `copyFollowsTheShortcut`: with the shortcut off, step 3 has no "⌃⌥Space" and no key caps.
- `copyFollowsTheDragTarget`: each `DragTarget` gives its sentence; `.nothing` has no practice.
- `modulesCopyNamesTheTabs`: after moving Notes into the tabs, step 6 names it among the tabs.
- `noNotchSaysTopCenter`.

Practice:
- One test per `PracticeGoal` for met and not met (for example `changeTab` isn't met by the first open, and `close` isn't met when
  the island was already compact).

Access (with `StubAccess`, which records requests and answers from a table):
- `allowGrantsAndTurnsOnUpNext`: Calendars granted: state `.allowed`, `settings.showsCalendar == true`.
- `denyLeavesUpNextOff`.
- `skipAsksOnlyPendingInOrder`: Calendars `notAsked`, Reminders `allowed`, Bluetooth `notAsked`: requests are exactly
  `[.calendars, .bluetooth]`, one at a time, and `needsGuide` is false.
- `skipAsksNothingWhenAllDecided`.
- `bluetoothGrantStartsTheMonitor`: the closure runs once.
- `replayDoesNotAsk`: replaying and pressing Done requests nothing.
- `privacyAccessListsAccessibility`: `PrivacyAccess.current()` has an `accessibility` row.

URL:
- `guideAndTourLinksParse`: `macisland://guide`, `macisland://tour`; `macisland://guide?reset=1` is `.guide(reset: true)` in DEBUG;
  an unknown command is still nil.

### `SettingsTourTests.swift`

- `everyPaneHasAStop`, `stopsAreGroupedByPane` (General only at the ends), `copyIsShort` (each stop's copy ≤ 170 characters).
- `startNextBackEnd`: next through the last stop calls `onFinish` once; back at the first stop stays.
- `jumpGoesToThePanesFirstStop`.
- `finishTourIsRemembered` (with `OnboardingState`).
- Placement: `preferredSideWhenItFits`, `flipsWhenThereIsNoRoom` (a target at the window's bottom with `.below` ends `.above`),
  `staysInsideTheWindow` (a target at each corner), `arrowAvoidsCorners` (a target at the callout's far edge clamps the offset),
  `mostRoomWhenNothingFits`.
- `anchorsIgnoreUnchangedFrames`: setting the same frame twice changes nothing observable (the no-op setter rule).

### `OnboardingSnapshots.swift` (opt-in, `ISLAND_SNAPSHOT_DIR`)

Built like `SettingsSnapshots` (`IslandPreviewModel(live: TestSupport.makeViewModel().features)`, `ImageRenderer`, scale 2). Glass
can't render, so the guide's content is drawn with `\.islandSurface = .glass` on `Color(nsColor: .windowBackgroundColor)`, once
in light and once with `.environment(\.colorScheme, .dark)`:

- `40-guide-NN-<step>.png` and `…-dark.png` for all 10 steps.
- `40-guide-02-peek-done.png` (a met practice line).
- `40-guide-09-access-mixed.png` (Calendars allowed, Reminders denied, Bluetooth not asked).
- `43-tour-NN-<stop>.png` for all 15 stops: the callout alone, with its arrow on its preferred side, on the window background in
  light and dark.
- `42-tour-placement-<side>.png`: a `FieldButton` target with the ring and a placed callout, one per side.
- `44-step-dots.png`, `44-key-caps.png` on the island (black) and on glass (window background).

What renders can't show (glass, the real window's position, the ring over real Form rows, focus) is checked by hand in C14.

---

## 8. Docs to update

Run `./scripts/docs-images.sh` after C12 and again after any later change to what a rendered step or callout looks like.

- **`DESIGN.md`**:
  - Surfaces: the Floating row's "Where" adds "the first-run guide".
  - A short **First run** section after "Reach": the guide is floating glass hung below the island with the real island as its
    stage; the tour's callouts are black like the island with a `widgetEdge` hairline, and its ring is Settings chrome in the accent
    color; nothing is dimmed; the guide and tour use no native controls; Skip is temporary.
  - Type: `headline`/`subheadline` are also the guide's title and copy. Motion: add the guide's and the tour's uses to `float`,
    `resize`, and `content`. Components: add `StepDots` and `KeyCaps`. Metrics: the new tokens.
  - Replace "everything is reachable from the palette" (Modules and tabs) with what is true now.
- **`README.md`**: "How you use it" gains a line about the guide; Privacy: the guide asks for Calendars, Reminders, and Bluetooth
  up front (each optional), and everything else is still asked on first use; the test count; Status.
- **`docs/FEATURES.md`**: a **First run** section (the steps, practice checks, what is asked, Close, Replay, Skip as temporary,
  pictures `40-guide-01-welcome`, `40-guide-06-modules`, `40-guide-09-access`); a **The Settings tour** paragraph under Settings
  (picture `43-tour-03-shortcut`); the General row adds Guide; the Privacy row adds Accessibility; the link table adds `guide` and
  `tour`.
- **`docs/ARCHITECTURE.md`**: Startup (`OnboardingState` classifies first; the guide shows at the end of launch; the deferred
  monitors); Storage (the three `onboarding.*` keys, not in the settings file or Reset All); Permissions (Calendars and Reminders are
  also asked by the guide through `AgendaMonitor.requestAccess(to:)`; Bluetooth through `BluetoothAccess`; Accessibility in
  `PrivacyAccess`); a new **First run** section (the evidence rule and why it is written once, `OnboardingFlow`, practice
  observation, `TourAnchors`, placement, layering, keys); Gotchas (the evidence key list and its test; which anchoring approach C9
  kept; no `.defaultAction` in Settings; no Esc or arrows in the guide); the test count.
- **`docs/ROADMAP.md`**: What is built (the guide and tour); Decisions rows (the guide is floating glass; three permissions up
  front; existing installs skip both; closing counts as seen; the palette is not taught because it was removed); Next (tick it);
  **Hand-test checklist** gains a "First run" group (every "Look" in section 6, plus the risks below); Dormant code and cleanup
  gains the temporary Skip; Ideas drops "a proper first-run tour" (keep "An app icon").
- **`docs/SCRIPTS.md`**: source map (`Onboarding/` with its five files, `App/OnboardingWindowController.swift`,
  `Settings/SettingsTour.swift`, and the missing `App/SettingsWindowController.swift`); the tests table (`OnboardingTests`,
  `SettingsTourTests`, `OnboardingSnapshots`) and count; cheat sheet (`open macisland://guide`, `open macisland://tour`, and for
  debug builds `open 'macisland://guide?reset=1'`).
- **`CLAUDE.md`**: the Layout list gains `Onboarding/`, and its Settings line says the window is an `NSWindow` made by
  `App/SettingsWindowController.swift`.

---

## 9. Risks and gotchas

1. **Key window and focus.** The app is an accessory app: `show()` must call `NSApp.activate()` before `makeKeyAndOrderFront`, or
   Return and the system prompts won't come to the front. ⌃⌥Space makes the island's panel key; give the guide the keyboard back
   when the island closes (only while `NSApp.isActive`, never stealing focus from another app). After a system prompt closes, the
   app becomes active again: refresh access states then.
2. **Esc and the arrows.** They reach the island only when its panel is key (after ⌃⌥Space). The guide therefore never binds
   them, and its copy says when they work. The tour doesn't bind Esc either.
3. **Hover while MacIsland is active.** `MouseTracker` hears `mouseMoved` through a global monitor (events for other apps) and a
   local one (events for ours). With the guide window key, MacIsland is the active app, so moves no longer reach the global
   monitor, and the local one only sees them if our windows get mouse-moved events. Check in C5 that the island still peeks with the
   guide key. If not, set `acceptsMouseMovedEvents = true` on `OnboardingPanel` and check again (the Settings window has the same
   exposure today).
4. **Click-through.** The guide is its own window and never changes `IslandPanel.ignoresMouseEvents`. On a short screen the guide
   sits partly under the island's full extent; the island's panel is above it, so clicks there go to the island only while the
   island is that big. `MouseTracker` closes a keyboard-pinned island on a click outside it, including a click in the guide:
   expected.
5. **A floating window over everything.** `FloatingGlassPanel` is `.floating` and doesn't hide on deactivate, so the guide stays
   above Finder while the person looks for a file to drag. It is movable by its background. [Open question 10](#10-open-questions).
6. **Permission prompts come once per install.** After a denial, EventKit and CoreBluetooth answer no at once with no UI, which is
   why denied rows offer Open Settings, never Allow. The build is signed ad hoc, so every rebuild is a new identity and macOS asks
   again: the guide won't re-run (its state is in defaults), and features keep asking on first use. Test prompts with
   `tccutil reset Calendar|Reminders|BluetoothAlways com.ethantiller.MacIsland`.
7. **Screen Recording needs a relaunch** after it is granted (`CGRequestScreenCaptureAccess`). It is not asked in the guide. If a
   later revision moves it up front, the step needs a "Quit and Reopen" action and must say why.
8. **Where prompts appear.** System prompts should be above a `.floating` window; check in C7. Skip closes the guide before asking,
   so its prompts never land on it.
9. **Launch-time prompts.** If C0 shows Bluetooth or Downloads prompting at launch, they would land on top of the guide; the
   deferral in [3.4](#34-the-access-step-permissions) moves them after it. It applies only to a fresh install's first launches, so an
   existing install behaves exactly as before.
10. **Tour anchors inside a `Form`.** Whether `onGeometryChange` fires while a macOS `Form` scrolls is not verified here; C9 checks
    it before the other stops are built, with a ready fallback.
11. **No-op setters.** `TourAnchors.set` and `OnboardingState`'s writers must do nothing when nothing changes, or observation loops
    can recur (the scene recursion crash in ARCHITECTURE's gotchas).
12. **Reduce Motion.** Everything goes through `Theme.Motion` (which eases under Reduce Motion) and `Theme.Motion.content` (opacity);
    the practice check has no symbol bounce under Reduce Motion; the stage's springs are the preview's own tokens. Check with System
    Settings → Accessibility → Display → Reduce Motion on.
13. **Reduce Transparency.** The guide's glass turns opaque on its own; the callout is opaque black already. Check it once.
14. **Idle budget.** The guide's preview model runs only while the guide is open and is stopped in `windowWillClose`; the tour's key
    monitor is removed when the tour ends. After closing both, idle CPU should be back at 0.1 to 0.3%
    (`ps -o cputime= -p $(pgrep -x MacIsland)` ten seconds apart).
15. **Tests in parallel.** Never touch `UserDefaults.standard` or the real notes file in tests; pass a private suite and a
    `fileExists` closure.
16. **`swift run`.** Without a bundle there is no bundle identifier, so defaults live in another domain and an existing developer
    install looks fresh there. Harmless; mention it in SCRIPTS.
17. **The Settings window opened for "Edit Home…".** The tour doesn't start then, so it doesn't pull the person away from the widget
    they asked for; it starts on the next ordinary open.

---

## 10. Open questions

The plan goes ahead with the choice in bold; change any of them before or during the work.

1. **The guide's surface.** **A floating glass window hung below the island.** The alternative, the guide inside the island, is too
   small, closes when the pointer leaves, and would block the practice steps.
2. **What is asked up front.** **Calendars, Reminders, and Bluetooth**; Camera, Microphone and Speech, Screen Recording,
   Accessibility, and Focus on first use. Do you want all of them in the guide (Skip would then ask for all of them)?
3. **A grant also turns the feature on.** **Granting Calendars turns on Calendar Events in Up Next, and Reminders turns on Due
   Reminders.** Or ask only, and leave the switches off?
4. **Existing installs.** **They skip both the guide and the tour** (both can be replayed). Or show them the Settings tour once?
5. **Closing early.** **Closing the guide with ⊗ counts as seen.** Or show it again next launch until Done?
6. **The palette.** It was removed on 2026-09-30, so **the guide doesn't mention it.** Should it come back, or did you mean something
   else (Settings search, or the menu-bar capsule)?
7. **Launch-time prompts.** **Deferred on a fresh install until the guide ends**, if C0 shows any. OK to change launch behavior
   for fresh installs?
8. **Where Replay lives.** **Settings → General → Guide, and `macisland://guide` and `macisland://tour`.** Also add "Welcome
   Guide…" to the menu-bar capsule's menu?
9. **The weather city.** **Not in the guide**; the tour's Up Next stop mentions Home's settings. Want a city field on the last step?
10. **Window level.** **The guide floats above other apps while it is open.** Or a normal window level, so it goes behind Finder?

---

## 11. Completion checklist

Tick each one. The work is done only when every box is ticked, `./scripts/test.sh` passes, and `./scripts/lint.sh` reports nothing
new (new files have no findings; no existing file has more findings than in `/tmp/lint-before.txt`).

**State**
- [ ] `OnboardingState` and `InstallEvidence` exist, with keys `onboarding.install`, `onboarding.guide`, `onboarding.settingsTour`
- [ ] It is `AppDelegate`'s first stored property; classification is written once and trusted after
- [ ] On the user's Mac `onboarding.install` reads `existing`, and neither the guide nor the tour appeared on update
- [ ] Onboarding keys are absent from an exported settings file and untouched by Reset All
- [ ] The evidence drift test passes

**Guide**
- [ ] Floating glass window, hung below the island, `guideWidth` wide, fixed height, `float` arrival
- [ ] All 10 steps with the copy in [3.2](#32-the-steps), including the dynamic sentences
- [ ] The stage is `PreviewBand` and follows each step; the Menu Bar slide plays and reverses
- [ ] Practice checks for peek, open, tabs, close, and drop turn green on the real island, and never block or advance
- [ ] Esc, ←, → never change the guide; Return continues
- [ ] Access rows show Allow, Allowed, and Off with Open Settings; the step is left out when all are allowed
- [ ] Granting Calendars or Reminders turns on its Up Next switch
- [ ] Skip is marked `TEMPORARY`, guarded by `OnboardingModel.showsSkip`, ends the guide, and asks each pending permission in order
- [ ] ⊗, Done, Open Settings, and Skip each record the guide as seen; quitting with it open does not
- [ ] Deferred monitors (if C0 found launch prompts) start when the guide ends and at every later launch
- [ ] No native controls anywhere in the guide

**Tour**
- [ ] 15 stops as in [4.2](#42-the-stops), every pane covered
- [ ] Callout and ring follow their control while resizing (830 × 600 to large) and scrolling; the out-of-view dock works
- [ ] Next, Back, End Tour, Return, and choosing a pane in the sidebar all behave as in [4.6](#46-starting-advancing-going-back-and-ending)
- [ ] It starts on the first open only, never over the guide, never for "Edit Home…", and ends when the window closes
- [ ] Light and dark both read well; no native controls in the callout

**Replay and links**
- [ ] Settings → General → Guide has both buttons (`FieldButton`), and search finds them
- [ ] `macisland://guide`, `macisland://tour`, and (DEBUG) `macisland://guide?reset=1` work

**Access plumbing**
- [ ] `AgendaMonitor.requestAccess(to:)`, `BluetoothAccess`, and the Accessibility row in `PrivacyAccess`

**Design**
- [ ] Every color, font, and size is a `Theme` token; the new tokens have doc comments with their reasons
- [ ] Reduce Motion and Reduce Transparency checked by hand
- [ ] Idle CPU back to 0.1 to 0.3% after both close

**Tests and pictures**
- [ ] Every test in [section 7](#7-tests) exists and passes; the full suite passes
- [ ] `OnboardingSnapshots` renders every step, access state, stop, and component, and each PNG was looked at
- [ ] `./scripts/docs-images.sh` run after the last visual change

**Docs**
- [ ] `DESIGN.md`, `README.md`, `docs/FEATURES.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/SCRIPTS.md`, and `CLAUDE.md`
      updated as in [section 8](#8-docs-to-update), with the new test count everywhere it appears
- [ ] ROADMAP: the hand-test "First run" group, the Decisions rows, and the temporary Skip under cleanup

**Finish**
- [ ] Every "Look" in section 6 checked with `make build-and-restart`
- [ ] `./scripts/lint.sh` reports nothing new
- [ ] Committed per checkpoint; open questions that the user answered are reflected in the code and the docs
