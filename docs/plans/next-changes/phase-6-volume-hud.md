# Phase 6 of 7: A custom volume HUD

Replace the system volume HUD with an island one (and a side-of-screen one if built), behind a setting. **Depends on:** Phase 4 (its permission step pieces, for the Accessibility grant).

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 6 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes), Phase 2 (the island stays open while it is being used), Phase 3 (the shelf's files), Phase 4 (the guide's permissions, one at a time), Phase 5 (shortcut tools). Later phases: Phase 7; don't start them, and
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
   without Accessibility walks the person through the grant (Phase 4's permission step pieces) and leaves the setting off until it is
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

## Checklist (tick each in your report)

- [ ] Research note written (10)
- [ ] Setting, permission walkthrough, island HUD (and side HUD or an explicit deferral) (10)
- [ ] Docs moved out of *Dropped for good*, with why the decision changed (10)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
