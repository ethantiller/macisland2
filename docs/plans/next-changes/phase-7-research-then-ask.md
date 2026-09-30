# Phase 7 of 7: Two things to research, then ask

Keep Awake with the lid shut, and Copilot approvals in VS Code. Research notes only; build nothing until the owner answers. **Depends on:** Phase 4 (for item 9's setup walkthrough, if it is approved later).

Paste everything below the line into a new Claude session in this repo, one phase per session. The order, what each phase needs, and
where progress is ticked are in [README.md](README.md). Written 2026-09-30 from a read of the code at `4351cbc`; every file and symbol
named here was opened and checked, but nothing was run. Where it says *verify*, the claim is what the code says today, not what the
app was seen to do.

---

**This is phase 7 of 7. Do only this phase.** Earlier phases: Phase 1 (small fixes), Phase 2 (the island stays open while it is being used), Phase 3 (the shelf's files), Phase 4 (the guide's permissions, one at a time), Phase 5 (shortcut tools), Phase 6 (a custom volume hud). Later phases: none; don't start them, and
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
3. If approved: a setting (and/or a tool) that, when turned on, opens a **setup walkthrough** built from the same step pieces as Phase 4's permission steps (reuse them; don't copy): what will be installed or changed, each step with a button, a check that it worked
   ("Waiting for VS Code…" then a green "Connected"), and what happens if it fails. It must never change the owner's VS Code
   configuration without asking, backing up, and merging. The listener binds to 127.0.0.1 only, requires a token, never logs it, and
   limits payload sizes. Turning the setting off removes what was installed, says so, and stops the listener (idle budget: nothing runs
   while it is off).

---

## Checklist (tick each in your report)

- [ ] Keep Awake: research note written and the owner asked (8)
- [ ] Copilot approvals: research note written and the owner asked (9)
- [ ] Nothing built for either (this phase ends at the question)
- [ ] Docs, test count, `docs-images.sh` (after a UI change), and `./scripts/lint.sh` (nothing new)
- [ ] This phase ticked in `docs/plans/next-changes/README.md` (your last commit)
- [ ] The report: per item, what ran and what did not, and the hand-test steps

## When you finish

Tick this phase in `docs/plans/next-changes/README.md` as your last commit, push, give the report, and **stop**. Don't begin the next
phase.
