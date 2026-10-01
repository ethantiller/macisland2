# Can MacIsland read a Shortcut's icon? (Phase 5, item 7)

**Answer: not honestly, so Shortcut tools use an SF Symbol the owner picks.** This note says what that rests on, and what I could not check.

**Written 2026-09-30 from a session with no Mac and no Swift toolchain.** I could not run `shortcuts`, open the Shortcuts database, or test
a permission. Every claim below about the Shortcuts app's storage is from memory of how it is laid out, marked *unverified*. The
decision does not depend on the unverified parts being right: each route fails one of the owner's own rules, so none was built.

## What is known (verified in this repo)

- `/usr/bin/shortcuts list` prints names only (`ShortcutsCLI.list`); `list --show-identifiers` adds each shortcut's identifier. Neither prints an icon or color.
- `shortcuts run NAME` runs one; `ShortcutsCLI.run` already does, and Shortcut widgets use it.

## Routes considered

1. **The Shortcuts database.** *Unverified:* the app keeps each shortcut in a Core Data store under `~/Library/Shortcuts/` (a `Shortcuts.sqlite`) and the
   app's group container, and a shortcut's icon is stored there as a glyph **number** and a color number (the workflow's icon record, `glyphNumber` and
   `startColor`).
   - Reading another app's SQLite file means depending on its private schema, which can change in any macOS release without notice.
   - The group container is protected since macOS 14 (an "access data from other apps" prompt, or Full Disk Access), which would add a permission MacIsland does not ask for today.
   - The glyph number indexes Shortcuts' own glyph set, which is not the SF Symbols set. A mapping would be hand-made, partial, and wrong for new glyphs. The color is one of a fixed palette that cannot honestly become one of MacIsland's tints (DESIGN: one meaning per color).
2. **Scraping the Shortcuts window or its icon files.** Fails "no scraping a window" and would need Screen Recording or Accessibility.
3. **A private framework** (WorkflowKit and friends). Fails "no private frameworks".
4. **The `shortcuts` command with other flags.** Nothing in `shortcuts help` (as far as I know) returns an icon.
5. **An App Intents or Shortcuts API for reading a person's shortcut metadata.** None public that I know of; not checked against current Apple documentation.

## What was built instead

A sheet with the Shortcut chosen from `shortcuts list`, a label (up to 14 characters), and an icon chosen as an SF Symbol: a text field with a live
preview, sixteen common glyphs as one-click buttons, and `bolt.fill` as the default. The Settings footer and the sheet both say plainly that MacIsland
cannot read the icon Shortcuts shows.

## What to check on a real Mac, if the owner wants this revisited

- `ls ~/Library/Shortcuts` and whether a normal process (no Full Disk Access) can open what is there, and what happens in
  `~/Library/Group Containers/group.is.workflow.shortcuts`.
- Whether the glyph numbers are stable across macOS versions, and whether Apple documents any way to read them.

If the answer to both is "yes, without a new permission", a mapping of the most used glyphs to SF Symbols, falling back to the picker, would be honest. Until then it is not.
