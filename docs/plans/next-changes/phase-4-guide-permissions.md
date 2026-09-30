# Phase 4 of 7: The guide's permissions, one at a time

A step per permission with Grant Permission and Not Now, nothing asking at launch, and a way to test it on a dev Mac. **Depends on:** nothing.

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 4 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes), Phase 2 (the island stays open while it is being used), Phase 3 (the shelf's files). Later phases: Phase 5, Phase 6, Phase 7; don't start them, and
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

## Checklist (tick each in your report)

- [ ] One step per permission with **Grant Permission** and **Not Now**; already-allowed ones skipped (6)
- [ ] Nothing prompts at launch for any install; the audit list is in your report (6)
- [ ] **Skip** (temporary) still asks for everything at once (6)
- [ ] `make first-run` works and is documented (6)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
