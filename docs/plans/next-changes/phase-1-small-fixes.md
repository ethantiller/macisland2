# Phase 1 of 7: Small fixes

Three independent fixes: a copied image's card, the peek's height, and the Pomodoro lengths. **Depends on:** nothing.

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 1 of 7. Do only this phase.** Earlier phases: none. Later phases: Phase 2, Phase 3, Phase 4, Phase 5, Phase 6, Phase 7; don't start them, and
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

## Checklist (tick each in your report)

- [ ] A copied image's card shows no "Copy Text" chip (3)
- [ ] Peek height follows lyrics (1), with tests, or a written finding that it already did and what was really wrong
- [ ] Pomodoro lengths and cycle are settings, with tests and the archive (2)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
