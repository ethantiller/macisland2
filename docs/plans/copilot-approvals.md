# Copilot approvals in VS Code (Phase 7, item 9): research, options, and a question

**Written 2026-09-30.** Web research only (search results and one documentation page); nothing installed, nothing run. The VS Code docs pages I
tried to fetch (`code.visualstudio.com/docs/agents/run/approvals`) were blocked by the network proxy, so claims about them are from search
summaries and are marked. **Nothing is built.**

## The request

When Copilot in VS Code asks the owner to approve something, MacIsland notifies them (a red `hand.raised.fill` banner that stays until seen, per DESIGN's
"needs you"). Turning it on walks the person through everything the integration needs.

## Constraints already in this repo

`docs/ROADMAP.md` says MacIsland can't read Notification Center, and that there is no local data to read for Copilot usage. The *Agents module* idea has
an unbuilt design: a loopback-only local API with a bearer token, hooks that are merged (never overwritten) with a backup, and a banner with Allow and Deny.

## What VS Code exposes today (from search results)

- **An OS notification of its own.** `chat.notifyWindowOnConfirmation` (values `off`, `windowNotFocused` (the default), `always`) shows a system
  notification when a chat session needs the person's input or a confirmation. So VS Code already notifies, through macOS Notification Center, which MacIsland
  cannot read. (Source: the VS Code settings reference and release notes in the results.)
- **Approvals.** Agent mode asks before running tools and terminal commands, with "remember" at session, workspace, and application level, and an
  experimental `chat.tools.autoApprove`. (Release notes and the approvals doc, via search summaries.)
- **Hooks.** The Copilot chat extension documents hooks with eight events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
  `PreCompact`, `SubagentStart`, `SubagentStop`, `Stop`. They are JSON files (`.github/hooks/*.json`, `.claude/settings.json`,
  `.claude/settings.local.json`, `~/.claude/settings.json`; all found are run, none overrides another), each entry a `command` with a timeout; a hook
  gets JSON on stdin and answers JSON on stdout (exit 2 blocks). `PreToolUse` can answer `permissionDecision`: `ask`, `allow`, or `deny`.
  **There is no event for "the user is being asked to confirm"**: the decision is inside `PreToolUse` processing. I could not tell from the page whether hooks
  are stable or preview. (Source: the `hooks.md` in `microsoft/vscode-copilot-chat`, read in full.)
- **An extension's view.** Not checked in depth: whether another extension can observe a chat confirmation request. I believe the chat participant and
  language model tool APIs let an extension *provide* a tool with its own confirmation, not watch others'; a proposed-only API may exist. *Verify* against
  the current `vscode.d.ts` and proposed API list before relying on this.

## Options, honestly

**(a) A hook that reports `ask`.** A `PreToolUse` hook (a small script we would install) that, when a tool call would prompt, POSTs to MacIsland on
127.0.0.1 and lets VS Code continue (answers `ask` or nothing). *Needs:* installing a hook file (and trusting that VS Code runs hooks for the owner's
sessions), a loopback listener in MacIsland with a token. *Sees:* every tool call that reaches `PreToolUse`, but **not whether VS Code will actually
prompt** (auto-approve and "remembered" approvals would still fire the hook), so it can cry wolf. It could answer `ask` itself to force a prompt,
which changes the owner's workflow. *Breaks:* if hooks are preview and change. *Security:* loopback, token, size limits, merge-with-backup of any config it touches.

**(b) A companion VS Code extension of ours.** Reports to the loopback endpoint. *Needs:* building, signing, and installing an extension (the owner
installs it from a file or marketplace). *Can see:* only what the extension API allows, which for other extensions' confirmations is probably nothing stable.
Most honest value: it can detect the window's focus and VS Code's own notification settings. *Verify* the API before choosing this.

**(c) Watch VS Code's window with the Accessibility API.** Fragile (VS Code is Electron and needs accessibility support turned on), needs the
Accessibility permission (which MacIsland may already have), breaks with any UI change. Not recommended.

**(d) Read VS Code's system notification.** macOS doesn't allow it (and the roadmap already says so). Not possible.

**(e) Use what VS Code already does.** Leave `chat.notifyWindowOnConfirmation` on. It is the only signal that means "the user is being asked", and it already
reaches the owner's screen; MacIsland can't mirror it. This is the "say it isn't feasible" answer.

## Recommendation and question

The one thing that would make this honest is knowing *when VS Code is really waiting for a click*, and as far as I can find **no public event says so**
(hooks don't have one). (a) and (b) would notify on things that may not prompt, or not at all.

**Question for the owner:** should I (1) stop here and move this to *Dropped for good* (VS Code already notifies; there is no public event for
a pending approval), (2) build (a), a `PreToolUse` hook reporting to a loopback listener, accepting that it can't tell a real prompt from an auto-approved
call (and only if you want it when hooks are confirmed stable), or (3) first spend an hour verifying the extension API on your machine for (b)? I'd start with (3),
then choose. If any is approved, the setup walkthrough would reuse the permission-step pieces from the guide (Phase 4) and never change your VS Code
configuration without asking, backing up, and merging.

## Sources

- [AI settings reference (VS Code)](https://code.visualstudio.com/docs/copilot/reference/copilot-settings)
- [Manage approvals and permissions (VS Code)](https://code.visualstudio.com/docs/agents/run/approvals) (search summary only; the page was blocked)
- [hooks.md in microsoft/vscode-copilot-chat](https://github.com/microsoft/vscode-copilot-chat/blob/main/assets/prompts/skills/agent-customization/references/hooks.md)
- [Support a notification when chat response has finished, microsoft/vscode#259683](https://github.com/microsoft/vscode/issues/259683)
- [VS Code February 2026 (version 1.110)](https://code.visualstudio.com/updates/v1_110)
