# Prompt: the next round of changes

Paste everything below the line into a new Claude session in this repo. It was written 2026-09-30 from a read of the code at
`4351cbc`; every file and symbol named here was opened and checked, but nothing was run. Where the prompt says *verify*, the
claim is what the code says today, not what the app was seen to do.

---

You are working on MacIsland, a Dynamic Island for the MacBook notch (a Swift package, SwiftUI in a borderless `NSPanel`, built with
the Command Line Tools). The owner has a list of changes. Read `CLAUDE.md`, then **`DESIGN.md` (mandatory before any UI change)**,
`docs/ARCHITECTURE.md` (especially Gotchas) and `docs/ROADMAP.md`, before you write code.

## How to work

- **One item, one or more small commits, each of which builds and passes `./scripts/test.sh`.** Work in the order at the end of this
  prompt. Don't start an item that says *ask first* until the owner answers.
- **You may not have a Swift toolchain** (a cloud session usually doesn't). Check with `which swift`. If you don't, say so in your first
  message, write the code with extra care (re-read every diff for compile errors, and follow patterns already in the repo), and never
  write "works" or "fixed" about anything you did not run. Say "written, not run" and add the hand-test steps to
  `docs/ROADMAP.md` → Hand-test checklist. Earlier rounds of this project shipped fixes that didn't work because they were assumed.
- **When a fix is a guess, say it is a guess** in the commit message and in your report, with what you'd check next.
- Colors, fonts, sizes, and motion come only from `Sources/MacIsland/Island/Theme.swift`; controls come from
  `Island/Components.swift` and `Settings/Dropdown.swift`. Prefer reuse over adding. No system `Button` chrome, `Picker`, `Menu`, pop-up
  buttons, or segmented controls in anything new on the island or in the guide (the existing Settings panes use native `Toggle`s; matching
  them there is fine).
- Keep the docs in step: `README.md`, `docs/FEATURES.md`, `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/SCRIPTS.md`, `DESIGN.md`, and the
  test count everywhere it appears (it equals the number of `@Test` lines: `grep -rh '@Test' Tests | wc -l`). Run
  `./scripts/docs-images.sh` after a UI change. Run `./scripts/lint.sh` and report nothing new.
- A new feature touches three places: `AppDelegate.makeFeatures()`, `TestSupport.makeViewModel()`, and `PreviewFeatures.make(live:scratch:)`.
  A new stored setting needs a key in `InstallEvidence.keys` (there is a test that fails if you forget), an entry in `SettingsArchive` if
  it is a personal choice, an entry in `SettingsSearch.entries`, and a setter that **does nothing unless it changes something** (the
  scene-recursion crash in ARCHITECTURE's Gotchas).
- **Git.** Commit on the feature branch the session gives you; never push elsewhere and never open a pull request unless asked. Commits are
  authored by the owner: `git config author.name "Ethan Tiller"` and `git config author.email "tilleres@mail.uc.edu"`, and leave the
  committer as it is. End each message with the attribution lines your session's instructions give.
- **Never delete or overwrite a file on the owner's disk without asking**, and nothing in the island may ask for an administrator's
  password (DESIGN's Don'ts and ROADMAP's Decisions: Low Power and Lock Screen were removed for this). Items below that seem to need
  either are marked.
- End with a report: for each item, *done*, *partly*, or *not done*; what changed (files); what you ran and what you did not; and the
  hand-test steps.

---

## 1. The peek sizes itself to the song: no lyrics, no lyric row

**Ask.** When the playing song has no lyrics at all, the music peek should be shorter, because it doesn't need the room. When lyrics
arrive, it grows to fit, and it shrinks again when the next song has none.

**What the code does today (verify first; part of this may already work).**
- `IslandViewModel.mediaContentHeight(peek:)` adds `Theme.Metrics.lyricsRowHeight` only when `features.nowPlaying.lyrics.lines` is not
  empty, and `NowPlayingView` draws `LyricLineView` only under the same condition (`!inWidget, !nowPlaying.lyrics.lines.isEmpty`).
- `LyricsModel.track(_:)` calls `show([])` on every track change, then fetches from lrclib.net and calls `show(parsed)` with
  `withAnimation(Theme.Motion.resize)`. `lines(fromResponse:)` reads only `syncedLyrics`.
- So the owner still sees extra height somewhere. Find where, by reading, before changing anything. Candidates: the peek versus the Media
  tab versus Home's Music widget (3 by 2 and 6 by 2 use `NowPlayingView(isPeek: true, inWidget: true)`); a track whose lines exist but
  the first line has not started yet (`LRC.text(at:in:)` is nil, so the row is 24 pt of nothing); a stale `lines` value between tracks; the
  height changing one frame before or after the content; `peekContentHeight` using a different case than the view draws; a fixed
  `minHeight` on the row.
- The fix must keep the row's height a function of the same value the view draws from, so they can't disagree, and the island's size
  must animate with `Theme.Motion.resize` both ways. Decide what "has lyrics" means for a track with lines that have not started (I'd
  say: lines exist means the row exists) and for a lookup still in flight (no row until it lands) and write the decision down.

**Done when.** A test covers the heights with and without lines for both the peek and the Media tab (`Tests/MacIslandTests/` has
player-layout tests; find them with `grep -rn mediaContentHeight Tests`). If it already worked, say exactly what you checked and what
you found instead.

---

## 2. Pomodoro lengths can be changed

**Ask.** The Pomodoro is fixed at 25 and 5. The owner wants to set it.

**What the code does today.** `PomodoroPhase.duration` in `Sources/MacIsland/Timer/PomodoroModel.swift` returns 25, 5, and 15 minutes as
literals, and `PomodoroModel.sessionsPerCycle` is 4. `PomodoroModel` takes only `defaults:` (for its history). `PomodoroStatus` in
`Timer/TimerView.swift` shows the phase and "n of 4". `SettingsPane` has eight panes and none for the Clock.

**Do.**
- Make focus, short break, and long break lengths, and sessions before the long break, personal settings (defaults 25, 5, 15, 4). Ranges
  that can't strand anyone: focus 1 to 90 minutes, short 1 to 30, long 5 to 60, sessions 2 to 8.
- Put them where a person looks for them. My suggestion is a new **Clock** pane in Settings (Pomodoro: four rows with
  `SettingsDropdown`; the preview shows Expanded on the Clock tab), because the Clock tab is crowded. If you choose differently (for
  example, adjusting from the Pomodoro view itself), say why. A new pane touches `SettingsPane`, `SettingsView.content`, the search entries,
  the preview context, `docs/FEATURES.md`'s pane table, and possibly a tour stop (`TourStop`, with `since: 2`; leave `tourVersion`
  alone unless you mean everyone to see it).
- A phase that is running keeps its length; a change applies from the next phase. Changing a length while idle updates the ring at once.
  Sessions-before-long-break changes how "n of 4" reads and when the long break comes; say how an in-progress cycle is treated.
- The settings reach `PomodoroModel` through an injected value, not `UserDefaults.standard`, so tests and the Settings preview (which has
  its own `PomodoroModel`) stay isolated.

**Done when.** Tests cover each length, the cycle, a change while running, and the archive round trip.

---

## 3. A copied image's card says what it is

**Ask.** Copy an image, open Shelf → Clipboard, and the card says **Copy Text** over the image. That's wrong for an image.

**What the code does today.** `ClipboardCard` in `Shelf/ShelfView.swift` draws `ChipButton(title: "Copy Text") { onCopyText(image) }` over
every image card. It is the OCR action (`FileTools.copyText(from: NSImage)`, Vision, on device), offered for images on purpose, but as a
label on the picture it reads as "this image is text".

**Do.** The image card shows the image and nothing over it. Clicking it still copies the image again. Keep the OCR as an action but make
it say what it does and not sit on the picture: my suggestion is **Copy Text from Image** in the card's right-click menu, plus the same
entry in the Shelf file menu where it already exists (`ShelfItemView`'s menu has "Copy Text" for images and PDFs; rename it the same way
for consistency). If you think a visible affordance is still needed, put it below the image in the card's own footer, not over it, and
say why. Update `docs/FEATURES.md` (Shelf → Clipboard) and the ROADMAP hand-test line that mentions "a Clipboard image card has a **Copy
Text** chip".

---

## 4. The Shelf's Files: preview, layout, the remove button, dragging out, and a real choice after a change

All of this is `Sources/MacIsland/Shelf/ShelfView.swift` (`ShelfView.files`, `ShelfItemView`), `Shelf/FileTools.swift`, and
`Shelf/ShelfModel.swift`. Do the parts in this order, each its own commit.

**4a. Previews.** Each file shows a preview, not only its file icon. Use QuickLook Thumbnailing (`QLThumbnailGenerator`) for the file's
real thumbnail (images, PDFs, movies, documents), falling back to the file icon when none comes. Generate asynchronously, cache by path
and modification date in memory only, cap the cache, cancel work for items that scroll away or leave the Shelf, and never block the
island. Today `ShelfItemView` draws `NSWorkspace.shared.icon(forFile:)` at 36 by 36. Choose a larger thumbnail size that fits the Shelf's
height (`Theme.Metrics.shelfHeight`, 96, which holds the Files/Clipboard choice and the row) with a token in `Theme.swift`, clipped to
`Theme.Metrics.nestedRadius`.

**4b. Vertical centering.** The row sits too close to the top. It should be centered between the bottom of the header and the bottom of
the island (or the space the design leaves), for one item and for many. The layout is `ScrollView(.horizontal) { HStack { ... } }` under a
`VStack(spacing: 6)` with the header; the scroll view's content is top-aligned. Fix it without a per-view magic number, and check the empty
state and the Clipboard row the same way (they should agree).

**4c. The ✕.** Hovering an item shows `xmark.circle.fill` tinted `Color.gray`, offset by hand. Make it clean and on-design: a small circular
button using the `Palette` inks (the fill/primary pair that `IconButton` uses), a real hit target, the `IslandButtonStyle`, and an
accessibility label (it has one). No `Color.gray`.

**4d. Dragging out.** Dragging files out of the Shelf "doesn't work very well" (glitchy). Investigate and fix; don't assume the cause. Read
`ShelfItemView`'s `.onDrag { NSItemProvider(object: url as NSURL) }` together with `.onTapGesture(count: 2)`, `.contextMenu`, `.onHover`
(which also calls `setHoveredShelfItem`), and `MouseTracker` (`dragStartedOnIsland` keeps the island "inside" while the button is down;
`update()` also runs the file-drag detection and `setHovering`). Things to check: the island folding (`closeDelay`, 300 ms) while a
drag leaves its rectangle; the panel's `ignoresMouseEvents` flipping mid-drag; the drag image being a generic icon and starting late;
the provider not being a proper file-URL provider for the destination (Finder, Mail, a browser upload, Desktop); the double-click
gesture delaying the drag's start. Prefer an AppKit drag source (`NSDraggingSource` with `NSPasteboardWriting`/`NSFilePromise` as
appropriate, with the thumbnail as the drag image) if SwiftUI's `onDrag` can't be made reliable. Dragging out must not remove the item
from the Shelf, must not fold the island, and must not leave `isFileDragActive` stuck. Say what the cause was.

**4e. A change that makes a new file asks where it goes.** Today every job that makes a file (`FileTools`: `zip`, `unzip`, `convert`,
`combinePDF`, `resize`, `compress`) writes it **next to the original** (`uniqueURL(for:in: source.deletingLastPathComponent())`) and
`run`/`runBlocking` adds it to the Shelf. The owner wants, instead, a choice when a result is ready:
1. **Save to a Folder** (the system save panel, `NSSavePanel`, in Finder's usual way),
2. **Add to the Shelf**, or
3. **Replace** the original's entry in the Shelf with the result.

Requirements and traps:
- Produce the result in a **staging folder in a temp directory** first, so nothing lands anywhere until the person chooses, and clean the
  staging folder up when they choose, cancel, or the app quits.
- The Shelf keeps only references (`ShelfModel.items`; "files stay where they are"). So decide and write down: where does "Add to the
  Shelf" put the file on disk? Options: an app-owned folder under Application Support (then what happens to it when the item is removed
  from the Shelf?), or next to the original as today. **Ask first.** Whatever you pick, removing an item from the Shelf must never delete
  a file the person saved to a folder.
- **Replace** replaces the *Shelf entry* (the original's reference is swapped for the result, in the same place). It must **not** delete or
  overwrite the original file on disk unless the owner says so; if they do, it needs its own confirmation and goes to the Trash, not `rm`.
- DESIGN limits a banner to two actions (`IslandBanner.actions`, "at most 2; the first is prominent"). Three choices don't fit. Options:
  an inline result card in the Shelf (the Shelf is open when you use its file menu, so the choice can live there, with the third choice
  in a small menu made from the dropdown components), or a follow-up banner with two actions plus a menu. Pick one, say why, and
  update DESIGN if the rule changes. The blue "working" activity while it runs stays as it is (`WorkTracker`).
- Decide what the choice does if the island folds before the person answers (I'd say: the result waits in the staging folder with the
  choice still showing; it is never silently added), and what happens with several results pending.
- Copy Text (OCR) makes text, not a file, so it is unchanged. Screenshots and recordings that arrive on their own
  (`ScreenshotWatcher.onScreenshot`, `ScreenRecorder.onFinish`, `VoiceRecorder`) still go straight to the Shelf: they aren't a change
  the person asked for on a file.
- Tests: the staging and cleanup, each of the three outcomes (with a stub save-panel closure; no real panels in tests), and that a
  cancel leaves no file behind.

**4f. The island stays open while a menu is in use.** Right-click a Shelf file, move into the menu (which draws outside the island), and
the island folds. It must stay open while the menu is open, and the same everywhere it happens. Build **one mechanism**, not a fix per
menu:
- While any AppKit menu is tracking (`NSMenu.didBeginTrackingNotification` and `didEndTrackingNotification` cover SwiftUI's
  `.contextMenu` and `Menu`, because they are `NSMenu`s), a panel or sheet the island opened (`NSSavePanel` from 4e, the share picker,
  Quick Look, `NSAlert`), the island must not fold on the pointer leaving and must not close on a click outside
  (`MouseTracker.handle` calls `closePinned()` on a click outside a pinned island). When it ends, the normal rules return: if the pointer
  is not over the island, the 300 ms close starts then, not never.
- Today `IslandViewModel.holdOpen()` just sets `isPinnedOpen = true`, and `isPinnedOpen` is also set false in several places (hover,
  `stopMirror`, `closePinned`, `open`). Replace it with a set of named holds (for example `.menu`, `.panel`, `.textFocus`, `.mirror`) so
  two reasons can't cancel each other, and `isPinnedOpen` (the keyboard pin) stays its own thing. Item 5 uses the same mechanism.
- Every place in the island that opens a menu or panel, at least: the Shelf item menu with its **Convert To** and **Resize** submenus and
  **Share**; the clipboard card menu; the tab strip's menu (Show in Menu Bar, Open in Window); Home's widget menu (Edit Home…); the Tools
  pin menu; the Media output chip's Disconnect menu; Notes' Delete. Grep `contextMenu`, `Menu(`, `ShareLink`, `quickLookPreview`,
  `NSSavePanel`, `NSOpenPanel`, `NSAlert` in `Sources` (outside `Settings/` and `Onboarding/`) and confirm the list yourself.
- Tests: the hold counts and ends, a hold blocks the close and a click-outside close, and the close resumes when the last hold ends.

---

## 5. Mirror keeps the island open as long as it is on

**Ask.** While Mirror is on, the island stays open.

**What the code does today.** `IslandViewModel.startMirror()` selects the Tools tab, calls `holdOpen()`, opens, and toggles
`features.mirror`. `stopMirror()` stops it and sets `isPinnedOpen = false`. But the island is still closable while it's on: a click
outside goes through `MouseTracker.handle` (`closePinned()`), Esc and the open shortcut call `closePinned()`/`toggleFromKeyboard()`, a
swipe up calls `closePinned()`, and `state` going to `.compact` or `selectedTab` leaving `.tools` stops the camera (their `didSet`s).
Check each, and check the path from a meeting banner's **Check Camera** action (`startMirror()`) and from the Tools button
(`ToolCatalog` → `toggleMirror()`).

**Do.** Use the hold from 4f: a `.mirror` hold that lasts exactly as long as `features.mirror.isOn`, released by **Done**, the tool button,
or the camera failing or being denied (`isUnavailable`, `access == .denied`). While it is held the island does not fold on hover out,
click outside, Esc, swipe up, or the shortcut, and it stays on the Tools tab (decide what a tab swipe does: I'd say it's ignored while
the camera is on; say what you chose). Say in your report which closing paths you found and closed.

---

## 6. The guide walks through permissions one at a time, and nothing asks at launch

**Ask.** The first-run guide should take each permission in turn: a screen that says why ("We need Bluetooth to show you a notification
when your AirPods connect…"), a **Grant Permission** button, and only when it is pressed does the system prompt appear. Nothing should
prompt as soon as the app is built or launched. **Skip** (the temporary one) keeps asking for everything at once.

**What the code does today.**
- The guide has one step, `GuideStepID.access`, with three rows (`AccessKind`: calendars, reminders, bluetooth) and **Allow** buttons
  (`Onboarding/OnboardingView.swift` `AccessRow`, `Onboarding/AccessRequests.swift`). `OnboardingModel.skip()` ends the guide then
  `access.requestAllPending()`.
- `AppDelegate.connectEvents` starts `accessoryMonitor.start()` (IOBluetooth: a Bluetooth prompt) and `features.transfers.start()`
  (`Progress.addSubscriber` on Downloads: a Downloads prompt) at every launch, **except** on a fresh install whose guide hasn't ended
  (`OnboardingState.holdsLaunchPrompts`). On any install that already has settings, which includes the owner's Mac, they start at launch,
  and because the build is ad-hoc signed every rebuild resets macOS permissions, so every rebuild prompts at launch.
- The other requests are on first use: Camera (Mirror, `CameraMirror`), Microphone and Speech (Voice Note, `VoiceRecorder`), Screen
  Recording (`SCKScreenRecorder.requestAccess`, needs a relaunch after), Accessibility (`KeyboardCleaner.toggle`), Calendars and Reminders
  (`AgendaMonitor.requestAccess(to:)`, which the guide calls), Focus (`FocusMode.start`, only with Quiet in Focus), Automation (Music and
  Spotify, `PlayerScripting`), and `ScreenshotWatcher`'s Spotlight query over the home folder (check whether it can prompt).

**Do.**
1. **One step per permission**, each with: a title, two or three sentences on why and what you lose without it (final copy, following
   DESIGN's writing rules: Title Case for buttons and labels, sentence case for sentences), the feature's glyph, and two buttons:
   **Grant Permission** (prominent) and **Not Now**. Show the state after: Allowed (green, beside its glyph), Off with **Open System
   Settings** (a denied permission can't be asked again), or, for Accessibility and Screen Recording, what to do in System Settings and
   (Screen Recording) that MacIsland must be reopened, with a Reopen button. Already-allowed permissions are skipped or shown as done.
   Suggested order: Calendars, Reminders, Bluetooth, Downloads, Camera, Microphone (with Speech), Screen Recording, Accessibility,
   Focus, Automation. Keep each step optional; the guide must be completable by pressing **Not Now** on all of them.
2. The step's state comes from `PrivacyAccess` (extend it to whatever is missing: Downloads can't be read without asking, so record
   "asked" in the guide's own state). The request paths are the ones above; add a public `requestAccess` where one is private, the way
   `AgendaMonitor.requestAccess(to:)` was. Extend `AccessKind`/`AccessProviding`/`StubAccess` and keep the tests.
3. **Nothing prompts at launch, for any install.** Audit every monitor started in `AppDelegate.applicationDidFinishLaunching` and
   `connectEvents`/`connectShelfChoices`/`connectAgenda` and anything they start; list what could prompt. A monitor whose permission isn't
   yet decided starts only after the person has been asked: from the guide, from Settings → Privacy (give that pane a **Grant** button
   for what is not yet asked), or at first use. One already decided (allowed) starts at launch as before. Where the state can't be read
   without asking (Downloads), use a stored "asked" flag and, for an existing install, the evidence rule; say what you chose.
4. **Skip** (temporary, still marked `TEMPORARY`) stays as it is: ends the guide and asks for everything still not asked, one after
   another. Keep the flag and its `TEMPORARY` comments.
5. **Make the guide testable on a dev Mac.** Add a `make first-run` target (and document it in `docs/SCRIPTS.md`) that quits the app,
   runs `tccutil reset All com.ethantiller.MacIsland`, **writes** `onboarding.install fresh`, `onboarding.guide 0`, and
   `onboarding.settingsTour 0` with `defaults write` (writing `fresh`, not deleting the key: a deleted key would be re-read as an
   existing install), and launches the app. Do it in that order, because the preferences daemon caches.
6. Tests for each step's states, Not Now, the order, the skipped steps, and that a fresh launch starts no monitor whose permission is
   not decided.

---

## 7. Shortcut tools

**Ask.** In Tools, the owner can add a tool made from one of their Shortcuts. Its icon should fill in from the Shortcuts app.

**What exists.** `Widgets/ShortcutsCLI.swift` lists (`/usr/bin/shortcuts list`) and runs (`run NAME`) Shortcuts; Home's custom widgets have
a `.shortcut(name:showsResult:)` source with a name and an SF Symbol; `IslandViewModel.runShortcut(_:)` runs one as the blue "working"
activity. `ToolID` is a closed enum of nine tools; `AppSettings.pinnedTools` is `[ToolID]`; `ToolCatalog.item(for:)` switches on it; the
Tools grid is two rows of six (nine tools plus **Less** is ten of twelve); Quick Tools on Home and the idle peek read the same pinned row.

**Do.**
- A **custom tool** identity next to the built-in ones (a value that is either a `ToolID` or a stored shortcut tool with an id, name,
  and icon), persisted in `AppSettings` (JSON like `widgets.custom`), valid in the pinned row, in Quick Tools, and in the grid. Keep it
  exportable in `SettingsArchive` (a Shortcut's name is fine to export). Decide how many fit (the grid has room for two more; beyond
  that it needs a design decision: say what you chose and update DESIGN's Tools note).
- **Create it** in Settings → Tools: **Add Shortcut Tool…** opens a sheet (look at `CustomWidgetSheet` for the pattern) with the
  Shortcut chosen from `ShortcutsCLI.list()` using `StyledDropdown`, a label, and the icon. Edit and Remove from the tool's right-click
  menu in the Tools tab as well.
- **The icon.** **Research before you build, and report what you found.** The `shortcuts` command prints names (and identifiers with
  `list --show-identifiers`), not icons. The Shortcuts app keeps each shortcut's glyph and color in its own database (look under
  `~/Library/Shortcuts/` and the app's group container; check whether it can be read **without** Full Disk Access, and whether the glyph
  is a number you'd have to map by hand). Rules: no private frameworks, no scraping a window, nothing that needs a new permission the
  app doesn't ask for today. If the glyph can be read and mapped to an SF Symbol honestly, use it, and the color becomes one of
  the existing tints only if it fits DESIGN's one-meaning-per-color rule (otherwise white). If it can't, don't fake it: pick the icon
  from an SF Symbol chooser in the sheet with a sensible default (`bolt.fill`), and tell the owner plainly that the Shortcuts icon
  could not be read and why. **Ask first** if the honest answer is "not possible".
- **Running it.** The same path as a Shortcut widget's button: blue working activity while it runs (`WorkTracker`), a green result alert
  on success, a red banner with the reason on failure. A Shortcut that has been deleted or renamed shows as unavailable (dimmed) with a
  way to fix it, not as a dead button.
- Tests: persistence, the pinned row with custom tools, the archive round trip, unavailable handling, run success and failure with a
  stub runner.

---

## 8. Keep Awake with the lid shut (ask first, research first)

**Ask.** Keep Awake doesn't keep the MacBook awake when the lid is closed.

**What the code does today.** `Tools/KeepAwake.swift` creates one IOKit assertion, `kIOPMAssertionTypePreventUserIdleDisplaySleep`
(`caffeinate -d`). That stops the display (and so idle sleep) from sleeping while the lid is open. **Closing the lid sleeps a Mac
regardless of any such assertion**, so this can't be fixed by adjusting the assertion type alone.

**Do, in this order.**
1. **Research and test on a real Mac, then write down** (in `docs/plans/keep-awake-lid.md`) what works on Apple silicon and macOS 26:
   - `kIOPMAssertionTypePreventSystemSleep` (what it does on battery versus power, and with the lid shut, with and without an external
     display: "clamshell mode");
   - `pmset disablesleep 1` (needs an administrator, per use or via a privileged helper);
   - what other apps of this kind (Amphetamine, Caffeine, KeepingYouAwake) actually do for closed-display mode, and what they tell users.
2. **Stop and ask the owner which to build.** The options will probably be: (a) the non-admin assertion, with honest limits shown in the
   UI ("needs power and an external display"); (b) an administrator step once, for a true lid-closed mode, which **breaks the rule that
   nothing in the island asks for a password**, so it needs the owner's explicit yes and a design for how it is asked, revoked, and
   shown; (c) leave it as is and say so in the tool's label. Don't pick (b) yourself.
3. Whatever is built: the tool says in words what it does and doesn't do (a Keep Awake that promises more than macOS allows is worse
   than none), and the lid's state is handled honestly when it closes (macOS may sleep anyway; don't leave a stuck "on" state if it
   does: listen for the wake and reconcile `isOn`).

---

## 9. Copilot approvals in VS Code (research first, then propose, then ask)

**Ask.** When Copilot in VS Code asks the owner to approve something, MacIsland notifies them. Turning the setting or tool on walks the
person through everything the integration needs.

**Constraints already in the repo.** `docs/ROADMAP.md` → *Dropped for good* says MacIsland can't read Notification Center and that there
is no local data to read for Copilot usage; → *Ideas → Agents module* has an unbuilt design for a loopback-only local API with a bearer
token, hooks that are merged (never overwritten) with a backup, and a red `hand.raised.fill` banner with **Allow** and **Deny**. Read it.
A red "needs you" banner that `staysUntilSeen` is the right presentation (DESIGN → Color).

**Do.**
1. **Research first** and write `docs/plans/copilot-approvals.md`, with sources: what VS Code and Copilot Chat expose today for a
   confirmation request (check the current VS Code docs and release notes for chat tool approvals, the
   `chat.notifyWindowOnConfirmation`-style settings, any hooks or events for agent mode, and what the extension API lets another
   extension observe; say which APIs are stable and which are proposed-only). Candidates to evaluate honestly: (a) a small companion
   VS Code extension of ours that reports to a loopback endpoint in MacIsland; (b) a documented hook or event, if one exists; (c)
   watching VS Code's window with the Accessibility API (fragile, needs a permission, and VS Code may need accessibility support turned
   on); (d) reading VS Code's own system notification, which macOS doesn't allow. For each: what it needs from the owner, what it can
   and can't see, how it breaks, and the security model.
2. **Stop and ask** which approach to build, or whether it isn't feasible and should join *Dropped for good* with the reason. Don't
   build a brittle hack on your own.
3. If approved: a setting (and/or a tool) that, when turned on, opens a **setup walkthrough** built from the same step pieces as item
   6's permission steps (reuse them; don't copy): what will be installed or changed, each step with a button, a check that it worked
   ("Waiting for VS Code…" then a green "Connected"), and what happens if it fails. It must never change the owner's VS Code
   configuration without asking, backing up, and merging. The listener binds to 127.0.0.1 only, requires a token, never logs it, and
   limits payload sizes. Turning the setting off removes what was installed, says so, and stops the listener (idle budget: nothing runs
   while it is off).

---

## 10. A custom volume HUD (this reverses a decision; read before you build)

**Ask.** Replace the system volume HUD with a MacIsland one, on the island or at the side of the screen, with a setting to turn it on or
off.

**The decision this reverses.** `docs/ROADMAP.md` lists "System HUDs, Alt HUD Styles, Caps Lock HUD" under *Dropped for good* ("The
system HUD can't be suppressed"), and "Custom volume and brightness HUDs" under *Considered, not planned* ("the HUD can't be
suppressed; macOS draws its own dots"). The owner is now asking for it, so it is no longer dropped, but **re-check the reason** rather
than trusting it. `Tools/KeyboardCleaner.swift` already holds a `CGEventTap` that swallows `NX_SYSDEFINED` events (the media keys), so
consuming the volume keys is proven to be possible in this app; the open questions are about doing it well.

**Do, in this order.**
1. **Research and write** `docs/plans/volume-hud.md` (short) on: consuming the volume and mute keys with an event tap
   (`NX_SYSDEFINED` subtype 8, key types sound up, sound down, mute, with key-down and key-up and the modifier state for the
   quarter-step Option+Shift behavior); setting the volume through CoreAudio on the default output (per-channel
   `kAudioDevicePropertyVolumeScalar` or the virtual main volume) and mute; devices with no settable volume (HDMI, some DisplayPort and
   Bluetooth outputs), where you must **not** consume the key so the system handles it; the feedback sound the system plays; what
   happens across output-device changes; and the permission (Accessibility for an active tap, `AXIsProcessTrusted`). Decide whether
   brightness and keyboard-backlight keys are in or out (I'd say out for now; say so).
2. The **setting**: **Replace the Volume HUD**, off by default, in a Settings pane that fits (Notifications, or General). Turning it on
   without Accessibility walks the person through the grant (the same step pieces as item 6) and leaves the setting off until it is
   granted. Turning it off, or revoking the permission, removes the tap and the system HUD comes back at once. Also a choice of where:
   **On the Island** or **Side of the Screen** (use `SettingsDropdown`), if you build both; if you build only one first, build the island
   one and say so.
3. **On the island:** a new kind of alert or banner (`Announcements`, `IslandAlert`/`IslandBanner`, `Announcements.sample` so the Settings
   preview draws the real one): a speaker glyph that follows the level (`speaker.wave.1/2/3.fill`, `speaker.slash.fill` when muted), a
   thin level bar made with the existing slider/ring drawing rules (read-only here), and the percent in the rounded numeral font; white
   on black, no color unless muted or at zero (DESIGN → Color: one meaning per color), hiding itself after about 1.5 seconds
   (`Theme.Timing`), and holding while the pointer is on it. It must respect Reduce Motion. It appears over the compact island without
   stealing hover, and it doesn't interrupt a banner that needs the person (`staysUntilSeen`); say how it queues.
   **At the side of the screen:** a slim vertical floating-glass HUD near the screen edge, following DESIGN's Floating surface rules
   (glass in the system appearance, shadow, never glass on glass), click-through.
4. Update `docs/ROADMAP.md` (move the entries out of *Dropped for good*, with the reason the decision changed), `DESIGN.md`
   (the new presentation and its metrics as tokens), `docs/FEATURES.md`, and `docs/ARCHITECTURE.md` (the tap, its permission, and the
   gotchas: the tap must be re-enabled when macOS disables it on a timeout, as `KeyboardCleaner` does, and must not run while Clean
   Keys holds its own tap).
5. Idle budget: no timers and no polling; the tap exists only while the setting is on. Tests: the key-to-step math (16 steps, the
   quarter step, mute), the level-to-glyph mapping, the setting turning the tap on and off (with a stub tap), and devices that can't
   take a volume.

---

## Order of work

1. Items 3, 1, 2 (small and independent).
2. Item 4f (the hold mechanism), then item 5 (Mirror) on top of it, then 4a to 4e.
3. Item 6 (the guide and launch prompts), including `make first-run`.
4. Item 7 (Shortcut tools; ask first only if the icon turns out to be impossible).
5. Item 10 (the volume HUD), which reuses item 6's permission step for Accessibility.
6. **Ask first, research first:** items 8 and 9. Write their research notes and stop for the owner's answer; don't build them before.

## Checklist (tick each in your report)

- [ ] Peek height follows lyrics (1), with tests, or a written finding that it already did and what was really wrong
- [ ] Pomodoro lengths and cycle are settings, with tests and the archive (2)
- [ ] A copied image's card shows no "Copy Text" chip (3)
- [ ] Shelf files: previews, centered, a clean ✕, reliable drag out (4a to 4d), and the cause of the drag problem stated
- [ ] A change that makes a file asks: folder, Shelf, or replace; staging is cleaned up; no file is deleted (4e)
- [ ] One hold mechanism: menus, panels, Quick Look, Mirror; the list of places checked (4f, 5)
- [ ] The guide takes permissions one at a time with **Grant Permission** and **Not Now**; nothing prompts at launch; Skip asks all; `make first-run` (6)
- [ ] Shortcut tools: create, edit, remove, run, pinned, archived; the icon finding reported honestly (7)
- [ ] Keep Awake: research note written and the owner asked (8)
- [ ] Copilot approvals: research note written and the owner asked (9)
- [ ] Volume HUD: research note, setting, island HUD (and side HUD or an explicit deferral), permission walkthrough, docs moved out of *Dropped for good* (10)
- [ ] Docs, test count, `docs-images.sh`, and `./scripts/lint.sh` (nothing new)
- [ ] The report: per item, what ran and what did not, and the hand-test steps
