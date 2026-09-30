# Phase 2 of 7: The island stays open while it is being used

One hold mechanism so menus, panels, and Mirror keep the island open, built first because Phase 3 uses it. **Depends on:** nothing.

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 2 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes). Later phases: Phase 3, Phase 4, Phase 5, Phase 6, Phase 7; don't start them, and
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

## 4f. The island stays open while a menu is in use

Right-click a Shelf file, move into the menu (which draws outside the island), and
the island folds. It must stay open while the menu is open, and the same everywhere it happens. Build **one mechanism**, not a fix per
menu:
- While any AppKit menu is tracking (`NSMenu.didBeginTrackingNotification` and `didEndTrackingNotification` cover SwiftUI's
  `.contextMenu` and `Menu`, because they are `NSMenu`s), a panel or sheet the island opened (`NSSavePanel`, which Phase 3 adds, the share picker,
  Quick Look, `NSAlert`), the island must not fold on the pointer leaving and must not close on a click outside
  (`MouseTracker.handle` calls `closePinned()` on a click outside a pinned island). When it ends, the normal rules return: if the pointer
  is not over the island, the 300 ms close starts then, not never.
- Today `IslandViewModel.holdOpen()` just sets `isPinnedOpen = true`, and `isPinnedOpen` is also set false in several places (hover,
  `stopMirror`, `closePinned`, `open`). Replace it with a set of named holds (for example `.menu`, `.panel`, `.textFocus`, `.mirror`) so
  two reasons can't cancel each other, and `isPinnedOpen` (the keyboard pin) stays its own thing. Item 5, below, uses the same mechanism.
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

## Checklist (tick each in your report)

- [ ] One hold mechanism (named holds, not a flag): menus, panels, Quick Look (4f)
- [ ] The list of places that open a menu or panel, checked and written in your report (4f)
- [ ] Mirror keeps the island open for exactly as long as it is on, and the closing paths you found are listed (5)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
