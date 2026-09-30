# Phase 5 of 7: Shortcut tools

Create a tool from one of the user's Shortcuts, with its icon from the Shortcuts app if that can be done honestly. **Depends on:** nothing.

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 5 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes), Phase 2 (the island stays open while it is being used), Phase 3 (the shelf's files), Phase 4 (the guide's permissions, one at a time). Later phases: Phase 6, Phase 7; don't start them, and
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

## Checklist (tick each in your report)

- [ ] Shortcut tools: create, edit, remove, run, pinned, archived (7)
- [ ] The icon finding is reported honestly, and the owner asked if it can't be read (7)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
