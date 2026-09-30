# The next round of changes, in 7 phases

One phase per Claude session, in this order. Each file is a complete prompt: paste it whole into a new session in this repo. A phase
ends with a report and stops, so you can try the app before starting the next one.

| # | Phase | What | Needs | Done |
| --- | --- | --- | --- | --- |
| 1 | [Small fixes](phase-1-small-fixes.md) | Three independent fixes: a copied image's card, the peek's height, and the Pomodoro lengths. | nothing | ☑ |
| 2 | [The island stays open while it is being used](phase-2-island-stays-open.md) | One hold mechanism so menus, panels, and Mirror keep the island open, built first because Phase 3 uses it. | nothing | ☑ |
| 3 | [The Shelf's files](phase-3-shelf-files.md) | Previews, centering, the remove button, dragging out, and a real choice after a change that makes a file. | Phase 2 (the hold mechanism, used by the save panel and the menus) | ☐ |
| 4 | [The guide's permissions, one at a time](phase-4-guide-permissions.md) | A step per permission with Grant Permission and Not Now, nothing asking at launch, and a way to test it on a dev Mac. | nothing | ☐ |
| 5 | [Shortcut tools](phase-5-shortcut-tools.md) | Create a tool from one of the user's Shortcuts, with its icon from the Shortcuts app if that can be done honestly. | nothing | ☐ |
| 6 | [A custom volume HUD](phase-6-volume-hud.md) | Replace the system volume HUD with an island one (and a side-of-screen one if built), behind a setting. | Phase 4 (its permission step pieces, for the Accessibility grant) | ☐ |
| 7 | [Two things to research, then ask](phase-7-research-then-ask.md) | Keep Awake with the lid shut, and Copilot approvals in VS Code. Research notes only; build nothing until the owner answers. | Phase 4 (for item 9's setup walkthrough, if it is approved later) | ☐ |

**Why this order.** Phase 1 is three small independent fixes. Phase 2 builds the one hold mechanism that keeps the island open for menus,
panels, and Mirror, because Phase 3's save choice opens a panel and its menus need it. Phase 4 builds the permission step pieces that
Phases 6 and 7 reuse. Phase 7 is research only: two requests (Keep Awake with the lid shut, Copilot approvals) that may not be possible
as asked, and need the owner's answer before anything is built.

**Ticking a phase.** The session that finishes a phase changes its ☐ to ☑ here as its last commit.

**Where the prompts came from.** They were split from one larger prompt (kept in git history as `docs/plans/next-changes-prompt.md`, commit
`52a614f`), so the item numbers (1 to 10, and 4a to 4f) match it.
