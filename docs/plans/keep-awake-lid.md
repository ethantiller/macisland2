# Keep Awake with the lid shut (Phase 7, item 8): research, and a question

**Written 2026-09-30 in a session with no Mac.** I could not test any of this on Apple silicon or macOS 26, which the task asked for. What
follows is from the code in this repo, from memory, and from web search results (sources at the end; two pages I tried to fetch were blocked
by the network proxy, so I only have their search summaries). **Nothing is built.** Every *verify* is something to run on a real Mac.

## What the code does today

`Tools/KeepAwake.swift` holds one IOKit assertion, `kIOPMAssertionTypePreventUserIdleDisplaySleep` (`caffeinate -d`). That stops the *display*
(and so idle sleep) from sleeping while the lid is open. It cannot stop the lid closing from sleeping the Mac.

## What keeps a Mac awake with the lid shut

1. **Clamshell mode (Apple's own).** With power, an external display, and an input device attached, macOS stays awake lid-closed with no command at all.
   Without an external display, the lid closing sleeps the Mac.
2. **An assertion.** The common keep-awake apps (Caffeine, KeepingYouAwake, `caffeinate -i`) hold `PreventUserIdleSystemSleep`, which stops *idle*
   sleep. Reports say a lid closed with no external display goes through a separate, lower-level clamshell sleep that this assertion does not stop.
   `kIOPMAssertionTypePreventSystemSleep` is stronger but, from memory, only takes effect **on AC power**. *Verify* on this Mac, battery and power,
   with and without a display, for both assertion types. This is the one I can't settle without testing.
3. **`pmset disablesleep 1`** (`sudo pmset -a disablesleep 1`). Tells the system never to sleep, including on lid close with no display. Needs an
   **administrator**, every time it is changed. It is system-wide and persists until turned off (a reboot does not necessarily clear it: *verify*), and a
   Mac in a bag with it on stays awake until the battery runs flat, and can get hot. Reports say it still works on current macOS; *verify* on macOS 26.
4. **Amphetamine** has a "closed-display mode" that keeps a session running with the lid shut. As far as I can find it does this by using
   `pmset`-level settings with an administrator step (its own helper), and it tells users to use it on power and away from a bag. *Verify* what it asks for.

## The three options, and what each costs

| | What it is | Cost |
| --- | --- | --- |
| **(a)** | Non-admin assertion only (`PreventSystemSleep` plus the display one), with the limits shown in the UI | No password. May not work lid-closed without an external display and power; the tool would say "needs power and an external display" and I'd have to be sure it is true. |
| **(b)** | An administrator step for a true lid-closed mode (`pmset disablesleep`) | Works. **Breaks the rule that nothing in the island asks for a password** (DESIGN's Don'ts; ROADMAP's Decisions removed Low Power and Lock Screen for it). Needs a design for how it is asked, shown as on, revoked, and cleaned up if the app quits or crashes (a stuck `disablesleep 1` drains a bag). |
| **(c)** | Leave it as is, and say in the tool's label what it does (keeps the display awake while the lid is open) | Honest and free. Doesn't do what was asked. |

**I did not pick (b).** Whichever is built, the tool must say in words what it does and does not do, and must not be left showing "on" after macOS
sleeps anyway: listen for the wake (`NSWorkspace.didWakeNotification`) and reconcile `isOn` with whether the assertion still exists.

## What was built (option a)

Keep Awake now holds the display assertion *and* `PreventSystemSleep`, says in words (a caption beside its chips, and its tooltip) that a shut lid can still sleep a Mac that isn't on power with an external display, and after every wake checks that the display assertion still exists, showing Off if it doesn't. No password, no `pmset`. **Whether `PreventSystemSleep` keeps a lid-closed Mac awake on power without a display is still untested**; if it does, the caption can say so. Options (b) and (c) are unchanged, below.

## Question for the owner

Which do you want: **(a)** try the no-password route and report honestly what works once tested on your Mac, **(b)** accept a password step (and say
how you'd want it to look), or **(c)** leave Keep Awake as it is and make its label honest? My recommendation is **(a) first**: it costs nothing to try and
tells us whether (b) is needed at all.

## Sources

- [How to use a MacBook with the lid closed: clamshell mode, sleep settings and fixes (Macworld)](https://www.macworld.com/article/673295/how-to-use-macbook-with-lid-closed-stop-closed-mac-sleeping.html)
- [Use a MacBook with the lid closed without an external monitor (clamshell.dev)](https://clamshell.dev/guides/clamshell-mode-without-external-display)
- [pmset disablesleep: what it does and how to turn it off (slack.green)](https://slack.green/en/blog/pmset-disablesleep) (search summary only; the page was blocked)
