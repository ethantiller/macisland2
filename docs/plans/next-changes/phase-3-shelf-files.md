# Phase 3 of 7: The Shelf's files

Previews, centering, the remove button, dragging out, and a real choice after a change that makes a file. **Depends on:** Phase 2 (the hold mechanism, used by the save panel and the menus).

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 3 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes), Phase 2 (the island stays open while it is being used). Later phases: Phase 4, Phase 5, Phase 6, Phase 7; don't start them, and
don't build ahead for them. Before you write code, open `docs/plans/next-changes/README.md` and `git log --oneline -15`. If a phase
this one depends on isn't ticked there, stop and tell the owner instead of rebuilding it.

You are working on MacIsland, a Dynamic Island for the MacBook notch (a Swift package, SwiftUI in a borderless `NSPanel`, built with
the Command Line Tools). The owner has a list of changes. Read `CLAUDE.md`, then **`DESIGN.md` (mandatory before any UI change)**,
`docs/ARCHITECTURE.md` (especially Gotchas) and `docs/ROADMAP.md`, before you write code.

## How to work

- **One item, one or more small commits, each of which builds and passes `./scripts/test.sh`.** Work through this phase's items in the order
  given. Where an item says *ask first*, stop there and ask the owner before building.
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

## 4. The Shelf's Files: preview, layout, the remove button, dragging out, and a real choice after a change

All of this is `Sources/MacIsland/Shelf/ShelfView.swift` (`ShelfView.files`, `ShelfItemView`), `Shelf/FileTools.swift`, and
`Shelf/ShelfModel.swift`. Do the parts in this order, each its own commit. **Phase 2 built the hold mechanism** (named holds that keep the island open while a menu,
panel, or Quick Look is up): use it for the save panel in 4e and for every menu you touch here, and don't add a second way to do it.

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

---

## Checklist (tick each in your report)

- [ ] Previews (4a), centered row (4b), a clean ✕ (4c)
- [ ] Dragging out is reliable, and the cause of the problem is stated (4d)
- [ ] A change that makes a file asks: folder, Shelf, or replace; staging is cleaned up; no file on disk is deleted (4e)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
