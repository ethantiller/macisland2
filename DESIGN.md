# MacIsland design guide (v2)

**Thesis.** The island is part of the hardware. It grows out of the notch to show what's live, then folds back in.

**HIG anchors.** Each rule below rests on one of these guidelines:
- `live-activities.md › Color`: "Live Activities in the Dynamic Island use a black opaque background."
- `materials.md › Liquid Glass`: "Don't use Liquid Glass in the content layer."
- `live-activities.md › Minimal`: two activities are shown at most.
- `tab-bars.md › Tablet`: "aim for a default list of five or fewer."
- `popovers.md › macOS`: "Consider letting people detach a popover."
- `the-menu-bar.md`: "Let people — not your app — decide whether to put your menu bar extra in the menu bar."

### Surfaces
| Surface | Where | Material |
| --- | --- | --- |
| Island | Attached to the hardware notch | Opaque `#000000`. Never glass. |
| Virtual pill | Displays without a notch | `.glassEffect(.regular)`, forced dark. Hidden while nothing is live; the hover zone stays. |
| Floating | Command palette, modules shown in the menu bar, torn-off panels | `.glassEffect(.regular)` in the system appearance, with a window shadow. |

Glass never goes inside the island, and glass is never stacked on glass.

### Presentations
| Presentation | Trigger | Shows | Size |
| --- | --- | --- | --- |
| Compact | Something is live | One activity split around the notch, or two as a minimal pair: leading is the top rank, trailing the second. | Notch + 2 × side |
| Banner | An event worth noticing once | Glyph, title, one detail line, at most 2 actions (with two, the first is prominent) | 380 × (notch + 56) |
| Peek | Pointer rests on the island. It swells immediately and opens after 120 ms. | The top activity at full size, no tabs. With nothing live it shows the day and the everyday tools. | 380 × content |
| Expanded | Click, two-finger swipe down, or ⌃⌥Space | Tab strip and the selected module | 520 × content |

Peek and banner share a width of 380, so one becomes the other by changing height only.

### Modules and tabs
There are 7 modules. (An Agents slot is reserved in code; it is an [idea](docs/ROADMAP.md#ideas) for now.) The tab strip has two sides: up to **5 left of the notch** and **1 right of it**, arranged in Settings by dragging tabs between the Left, Right, and Not Shown lists (each with an on/off switch). The defaults are **Home, Media, Clock, Reminders, Tools** on the left and nothing on the right; **Shelf, Notes** wait in Not Shown. Shelf still opens by itself when a file is dropped on the island, and Home has a Shelf chip. People can put any module in the menu bar, and everything is reachable from the palette. Settings open in a standard Settings window; the gear opens that window.

| Module | Holds |
| --- | --- |
| Home | A dashboard: today (opens a month calendar), what is next, what is playing, the four everyday tools, timer chips, Shelf |
| Media | Now Playing, scrubber, shuffle, repeat, Favorite, app volume, output, lyrics |
| Shelf | Files (Quick Look, zip, convert, screenshots, AirDrop drop target) / Clipboard (history, smart actions) |
| Clock | Timer / Stopwatch / Pomodoro |
| Reminders | Add a reminder, the open list, check them off |
| Tools | Keep Awake, Mic Mute, Ring Light, Capture, Color Picker, Focus, Low Power, Clean Keyboard, Lock Screen, Mirror, Record Screen |
| Notes | Quick Notes, Snippets, Prompter |

### Color: a tint means something is live, one meaning per color
| Tint | Token | Means |
| --- | --- | --- |
| Artwork accent | `NowPlayingModel.accent` | Music |
| Orange | `Tint.clock` | Time: timer, stopwatch, Pomodoro |
| Blue | `Tint.working` | In progress: downloads, zip/convert, running a Shortcut, recording |
| Green | `Tint.positive` | Done or connected |
| Red | `Tint.attention` | Needs you: low battery, missing permission, a failure |
| White | `Palette.*` | Everything else |

One exception: AirDrop blue (`Tint.airDrop`) appears only on the AirDrop half of the drop target, while a file is dragged, and always beside `AirDropGlyph`.

Rules:
- Text is `primary` (21:1) or `secondary` (7.4:1). `tertiary` (3.4:1) is for glyphs only.
- "Selected" is shown by a white fill with black content.
- Every tint sits next to a glyph or a number.

**Compact priority:** banner, needs-you alert, recording, microphone, timer/Pomodoro, stopwatch, working, transfer, music. At most 2 activities show at once.

### Type
Type is SF Pro for text and SF Pro Rounded with monospaced digits for changing numbers; 10 pt minimum. Tokens beyond the base set: `prompter` (20 medium), because the Prompter is read from arm's length while looking at the camera; `query` (20 regular) for the palette field; and `headline` (15 semibold) and `subheadline` (13 regular) for the music player.

### Metrics
| Metric | Value |
| --- | --- |
| `expandedWidth` | 520 (five tab glyphs left of the notch; the right side holds one tab, the status, and Settings) |
| `peekWidth` / `bannerWidth` | 380 / 380 |
| `maxTabs` / `maxRightTabs` | 5 / 1 |
| `swell` | 8 × 2 |
| `floatRadius` / `floatPadding` / `floatGap` | 24 / 14 / 8 (24 − 14 = `cardRadius` 10, so corners are concentric) |
| `mirrorWidth` / `mirrorHeight` | 320 / 180 (16:9; 180 is the Mirror's whole content height, which keeps the island under the 260 panel) |
| `ScreenGeometry.panelSize` | 560 × 260 (at least as wide as the widest presentation) |

Radii (32 / 10 / inner 14; Home's widgets use the inner 14 and nested elements 8), the 18 pt margin, and the 28 pt hit targets are unchanged. Bottom corners are **continuous** curvature.

### Motion
| Token | Curve | Use |
| --- | --- | --- |
| `open` | `.spring(response: 0.42, dampingFraction: 0.78)` | Compact → peek or expanded; alerts and banners arriving |
| `close` | `.spring(response: 0.34, dampingFraction: 1)` | Folding back in. No overshoot into the hardware. |
| `resize` | `.spring(response: 0.36, dampingFraction: 0.88)` | Tab, mode, or height changes inside an open island |
| `track` | `.interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.1)` | Pointer-driven: swell, swipes, drag target |
| `float` | `.spring(response: 0.34, dampingFraction: 0.84)` | Floating glass appearing |
| `content` | `BlurFade`: blur 8 → 0, opacity 0 → 1, scale 0.94 → 1 anchored at the top | Content swaps while the shape morphs |

Reduce Motion turns every token into a short ease, removes the swell, and swaps `content` for `.opacity`.

### Input
| Input | Result |
| --- | --- |
| Hover | Swell (`track`), then peek after 120 ms |
| Click, two-finger swipe down, or ⌃⌥Space | Expanded |
| Pointer leaves for 300 ms | Compact (`close`) |
| Two-finger horizontal swipe | Previous or next tab |
| ←/→ | Previous or next tab |
| Esc | Close |
| ⌃⌥K | Command palette |

### Carried over

- Every icon-only control has an accessibility label; selected states add `.isSelected`.
- Nothing is conveyed by color alone. Text is at least 10 pt; hit targets at least 28 pt (20 pt absolute minimum).
- Reduce Motion is respected (see Motion). Glass surfaces also check **Reduce Transparency**: the system makes them opaque.
- Idle budget: no timers run while nothing is live, and samplers run only while their view is visible.
- Writing: Title Case for buttons and labels ("Clear All"), sentence case for sentences. Labels say what
  happens, and an action keeps its name everywhere. Empty states invite the next action; errors say how to fix
  it and take you there. Alerts that need attention set `staysUntilSeen`; informational ones time out.
- iPhone features that don't exist on the Mac, and features already ruled out, are settled in [docs/ROADMAP.md](docs/ROADMAP.md#dropped-for-good) and are not re-litigated.

## Components (`Island/Components.swift`)

Reuse before writing anything new: `IconButton`, `ChipButton` (`isProminent` for the main of two), `SegmentedChoice` (not the system segmented
picker on the island), `IslandSlider`, `ProgressRing`, `ChargingBadge`, `ArtworkView`, `AirDropGlyph`, `Glyph` (a symbol in a
fixed square so different widths share one center), `IslandButtonStyle`. Tools use `ControlButton`.

## Structure

- Nothing is drawn behind the notch. Content starts below `notchSize.height`.
- Height follows content: each module declares `contentHeight(for:)`. Don't pad one to match another.
- Settings live in a standard Settings window (the gear and the menu bar item open it), not in the island.
  Only personal choices go there.
- `IslandContainer` owns the outline, surface, size, and motion; `IslandView` supplies what goes inside.
- A new feature lives inside an existing module, replaces something, or earns a module. Then remove one thing.

## Reviewing a change visually

```
ISLAND_SNAPSHOT_DIR=/tmp/island ./scripts/test.sh --filter IslandSnapshots
```

`ImageRenderer` draws yellow at the top corners (its drop-target placeholder), skips horizontal scroll views,
and may not draw `.glassEffect`. Check those in the running app.

## Don'ts

- No gradients, glows, borders, or blur on the island. Glass never goes inside it or on top of glass.
- No new typefaces, no light or thin weights, no text under 10 pt.
- No per-view magic numbers for color, font, or spacing: add a token in `Theme.swift`.
- No settings for how the island looks or behaves by default.
- No logos or app icons in the island.

## Module notes

- **The strip beside the notch.** Tabs on the leading side. On the trailing side: live status (a running timer), or the weather when nothing is live, then a New Note pencil, then the gear. The weather never shares the strip with live status, so nothing reaches the notch.
- **Home.** Two rows of widgets on one corner hierarchy (the island's 32, widgets at 14, what is inside them at 8, all continuous). Each block sits in a quiet box (a very dark fill and a hairline edge, all flush to the same left and right edges) so blocks are told apart without standing out. Row 1 is two equal halves: one widget with the date on a single line (it opens a month calendar) over what is next and Music. Row 2 is the four quick tools as a 2 by 2 grid beside one segmented pill: two quick timers, Pomodoro, and Shelf, each replaced by its running clock while it runs. Weather comes from the city in Settings, is refreshed every 30 minutes, and needs no location permission. The month calendar is six weeks, so the height doesn't jump.
- **Reminders.** Its own tab: the add field (Reminders access is asked for on first use) and the open list with a check-off circle. Focusing the field keeps the island open.
- **Idle peek.** With nothing live, hovering shows the day (date, weather, what is next or this Mac's battery) and the everyday tools with 5m and 25m timers. A running timer, stopwatch, or Pomodoro peeks as its ring and controls only, sized to fit the 380 pt width.
- **Clock.** Timer, Stopwatch, and Pomodoro share the tab. Pomodoro chains four focus sessions with short
  breaks and a long break, then stops. Its streak and 7-day chart live under the ring.
- **Shelf.** Right-click an item to preview, share, copy its text, zip, unzip, convert, resize, compress, or show it in Finder. These
  run as the blue "in progress" activity; the result is added to the Shelf. Clipboard text that is only a link,
  address, or `#hex` color gets one action on its card.
- **Notes.** Notes, Snippets, and a Prompter share the tab. Focusing a text field keeps the island open
  until Esc, the shortcut, or a click outside.
- **Tools.** Eleven tools and Less fill the grid, two rows of six; the row pins 4, 6, or 8 and keeps its More chevron. Clean Keys swallows every key
  for 30 seconds (the mouse still works) and needs Accessibility access, and so does Lock Screen (Control-Command-Q).
  The Mirror replaces the row or grid with a 16:9 camera view (clipped to `widgetRadius`) and a column of Ring Light and **Done**.

## Reach: the palette, the menu bar, and windows

- **Command palette (⌃⌥K).** A floating glass panel hung below the notch, centered on it, 520 wide. Rows: modules, tools,
  timers ("25m", "1h30m", "timer 45"), apps, Shortcuts, snippets, "remind …", `clip …`, web searches, translation, and answers (a definition, a unit or currency conversion, a sum). Empty, it lists the
  modules. A web search is always the last row. Search with a keyword (`yt swift`) or the default engine; there are nine
  built-in engines and any number of custom ones (Settings, with `%s` where the search goes). `tr hello` translates into the
  system language and `tr es hello` picks the language, through the system Translation framework. Arrows move, Return runs,
  Esc or a click away closes it.
- **Menu bar and windows.** Nothing is in the menu bar until the person chooses (Settings, or right-click a tab). Each module
  can have its own menu-bar icon; its window can be popped out by dragging the header away, or with the button, into a
  resizable floating window. **Keep on Desktop** drops that window to just above the desktop icons.
- **Surfaces.** `Theme.Palette` follows the surface it is drawn on: white opacities on the island, the system's primary
  color on floating glass, set with `\.islandSurface`. Glass is never used inside the island, and never on glass.

## The music player

After the Dynamic Island's: the album art at the leading edge, the song in bold over the artist, the sound bars at the far
side, the scrubber, then big centered transport buttons (back, play or pause, forward). In the Media tab the art is larger
(`playerArtwork`), the player sits a little lower (`playerTopInset`), and shuffle and repeat sit left of the transport with
Favorite and AirPlay on the right. The peek is narrower: smaller art, and only the transport and AirPlay. The compact
island's artwork and sound bars share a `mediaNamespace` with the peek and the Media tab, so they travel to their new
places when it opens instead of appearing.
