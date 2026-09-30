# Features

Everything MacIsland does, in the order you meet it. Back to the [README](../README.md). How it is built:
[ARCHITECTURE.md](ARCHITECTURE.md). What is left: [ROADMAP.md](ROADMAP.md).

**Contents:** [Presentations](#presentations) · [Live activities](#live-activities) · [Alerts and banners](#alerts-and-banners) ·
[The tab strip](#the-tab-strip) · [Modules](#modules) · [Command palette](#command-palette) ·
[Menu bar and windows](#menu-bar-and-windows) · [Settings](#settings) · [Keys and gestures](#keys-and-gestures) ·
[Accessibility](#accessibility)

---

## Presentations

The island is always in one of four presentations. Sizes are in points.

| Presentation | When | Shows | Size |
| --- | --- | --- | --- |
| **Compact** | Something is live | One activity split around the notch, or two as a pair | Notch plus a side on each end |
| **Banner** | An event worth noticing once | Glyph, title, one detail line, at most one action | 380 wide, notch + 56 tall |
| **Peek** | Pointer rests on the island (swells at once, opens after 120 ms) | The top live activity at full size, no tabs. With nothing live, the day and everyday tools | 380 wide |
| **Expanded** | Click, two-finger swipe down, or ⌃⌥Space | The tab strip and the selected module | 520 wide |

The pointer leaving for 300 ms folds it back in. Opening it with the keyboard (⌃⌥Space) *pins* it open until Esc, the
shortcut again, or a click outside. Focusing a text field pins it too, so it does not close while you type.

### The music peek and the Media tab

![Music peek](images/03b-peek-media.png)
![Media tab](images/04b-expanded-media-lyrics.png)

The peek is the Dynamic Island's own layout: album art, the song in bold over the artist, sound bars at the far side, a
scrubber, and big centered transport buttons. The compact island's artwork and sound bars *travel* into place when the peek
opens instead of appearing. The Media tab is the same with larger art, shuffle and repeat on the left, and Favorite and
AirPlay on the right.

### The idle peek

![Idle peek](images/03e-peek-idle-weather.png)

Nothing live: the date, the weather (if a city is set), what is next (or this Mac's battery), your first four pinned tools,
and `5m` / `25m` timer chips.

### Timer, Pomodoro, and stopwatch peeks

![Timer peek](images/03f-peek-timer-compact.png)
![Pomodoro peek](images/03g-peek-pomodoro.png)
![Stopwatch peek](images/03h-peek-stopwatch.png)

Each is the ring and its controls, sized to the 380 pt peek: the timer shows when it ends and `+1m` / `+5m`; the Pomodoro
shows the session, the streak, and what is next; the stopwatch shows the lap in progress and the last lap.

---

## Live activities

Compact shows the **top two** live activities, ranked. Highest first:

| Rank | Activity | Left of the notch | Right of the notch |
| --- | --- | --- | --- |
| 1 | Banner | (a banner is a presentation of its own) | |
| 2 | **Alert** (always shown alone: its text is the message) | Glyph | Text |
| 3 | **Microphone in use** | The app's icon | How long |
| 4 | **Timer** | Ring | Countdown |
| 5 | **Pomodoro** | Ring | Countdown |
| 6 | **Stopwatch** | Stopwatch glyph | Elapsed |
| 7 | **Working** (zipping, converting, running a Shortcut) | Pulsing gear, blue | What it is doing |
| 8 | **Download in progress** | File icon in a ring | Percent |
| 9 | **Music** | Album art | Play/pause, or sound bars while playing |

![A pair](images/09b-compact-pair-timer-media.png)

In a pair, each side shows only its activity's glyph, ring, or artwork. Music's play/pause button is left out of a pair.

### Color

A tint means something is live, one meaning per color. Everything else is white on black.

| Tint | Means |
| --- | --- |
| The album art's most vivid color | Music |
| Orange | Time: timer, stopwatch, Pomodoro |
| Blue | In progress: zipping, converting, running a Shortcut |
| Green | Done or connected |
| Red | Needs you: low battery, missing permission, a failure |

---

## Alerts and banners

An **alert** is a short message beside the notch. A **banner** drops below it with a title, a detail line, and at most one
action. Alerts that need you (a timer finishing, a Pomodoro phase ending) stay until you open the island.

| Event | What you see |
| --- | --- |
| Charger plugged in | Alert: a bolt with a green ring drawing around it, and the percent |
| Battery hits **20%** or **10%** | Red banner "Low Battery", with a *Low Power Mode* action |
| Battery reaches your full-charge level (80 to 100%, Settings) | Green alert while charging |
| Headphones connect (Bluetooth) | Banner with the name and left, right, and case battery |
| An external drive mounts | Banner with the name, size, and **Eject** (then "Ejected", or the reason it failed) |
| A screenshot is saved | Green "Shelf" alert; the file is added to the Shelf |
| A meeting is 5 minutes away | Banner, with **Join** if it has a Zoom, Meet, Teams, or Webex link |
| A reminder comes due | Banner, with **Done** |
| Timer or Pomodoro finishes | Alert that stays until seen; opens the Clock tab |
| A download finishes | Green "Saved" alert |
| A color is picked | Alert tinted with the color, and the hex code (also copied) |
| Something is copied from the island | "Copied" |
| Personal Hotspot connects | Green alert |
| The Mac unlocks | "Unlocked" with a Touch ID glyph |
| Zip, convert, or a Shortcut finishes | Green "Zipped", "Converted", "Done"; or a red banner with the reason |
| Rain is due within 30 minutes (only with a city set) | Banner "Rain Soon", "Starts around 3:45 PM"; once per rain spell, and again only after a dry hour |
| Free space falls under 10 GB | Red banner "Low Disk Space", "8.2 GB free", with **Open Storage**; a red alert stays until seen. Checked on unlock, on wake, and after a finished job or download, never on a schedule; it warns again only after space passes 15 GB |

**Quiet in Focus** (Settings): while a Focus is on, banners and short alerts are held back. Alerts that stay until seen, and
feedback to something you just did, still arrive.

---

## The tab strip

![The strip](images/04e-right-tab.png)

Left of the notch: up to **five tabs**. Right of the notch, from the notch outward: live status (a running clock, or a glyph
for hotspot, Ring Light, Keep Awake, or a locked keyboard), the **weather**, the **New Note** pencil, up to **one tab**, and
**Settings**.

Space on the right is limited, so it fills in this order and never reaches the notch: Settings, the right-hand tab, live
status, then the weather, then the pencil. The pencil is left out when Notes is already a tab. Right-click a tab for
*Show in Menu Bar* and *Open in Window*.

Arrange the tabs in **Settings**: three lists (Left of the Notch, Right of the Notch, Not Shown). Drag a row to reorder it or
to another list; each row has an on/off switch, and a right-click menu has Move Up/Down and Move to Left/Right. The last tab
cannot be turned off.

---

## Modules

Seven are built. The default tabs are Home, Media, Clock, Reminders, and Tools. Shelf and Notes are in Not Shown but still
open other ways (dropping a file opens Shelf; the pencil and the palette open Notes).

### Home

![Home](images/04a-expanded-home.png)

A dashboard, in two rows of boxes that share the same left and right edges.

- **Top left**: today on one line (tap it for a **month calendar**, six weeks with arrows; today is a filled circle), over
  **Up Next**: the next meeting or due reminder (tap to join a call, or open Reminders). Reads Calendar and Reminders only
  if you turn them on in Settings.
- **Top right**: what is playing, with play and pause (tap for the Media tab).
- **Bottom left**: your first four pinned tools as a 2 by 2 of round buttons. White fill means on.
- **Bottom right**: one segmented pill: `5 min`, `25 min`, `Pomodoro`, `Shelf`. While a timer, Pomodoro, or stopwatch runs,
  its segment shows the running time instead; tap it to open the Clock tab.

![Calendar](images/04a-expanded-home-calendar.png)

### Meetings, Outlook, and Teams

Up Next and the 5-minute banner read every calendar in System Settings → Internet Accounts, so **Outlook, Microsoft 365, Exchange, and
Google calendars appear once the account is added there** (Settings → Up Next has a button that opens it). The new Outlook for Mac
keeps its own store, which macOS can't read; add the account to Internet Accounts as well.

**Join** opens the meeting app when there is one: a Teams `https://teams.microsoft.com/l/…` link opens Teams (`msteams:`), and a Zoom
`/j/<id>` link opens Zoom (`zoommtg:`), each only if this Mac has that app; otherwise it opens the link in your browser.
Outlook SafeLinks and Google redirect links are unwrapped to the real address first.

### Media

![Media](images/04-expanded-media.png)

- **Now Playing** from any app, through the bundled adapter. The artwork's most vivid color tints the scrubber and bars.
- **Transport**: back, play/pause, forward; scrub; **shuffle** and **repeat** (off, all, one).
- **Music and Spotify are controlled directly**, so play/pause hits *that* app even while a video plays elsewhere. Other
  apps use the system's command.
- **Favorite** (Apple Music only) is a heart. **App volume** (Music and Spotify) is a slider beside the output chips, behind
  the AirPlay button. **Audio output**: chips for each output device, then a *Not Connected* group with your paired Bluetooth headphones and speakers: click one to connect it (blue "Connecting" while it works; the headphones banner confirms, or "Couldn't Connect"). Right-click a connected Bluetooth output to *Disconnect*. The paired list is read only when the picker opens. In the palette, `connect airpods` finds them too.
- **Synced lyrics** under the scrubber, from LRCLIB, while the track has them. Turn off in Settings.
- Compact: the artwork and, on the right, a play button that becomes bouncing bars while playing. Click it to play or pause.

### Shelf

![Shelf](images/05-expanded-shelf-empty.png)

A **Files / Clipboard** choice.

- **Files.** Drag files onto the island (the left half is *Add to Shelf*, the right half is *AirDrop*, drawn in AirDrop blue while a file is dragged). Only references are
  kept; files stay where they are. Double-click opens, drag out to use, hover for an ✕. **Space** over an item previews it with
  Quick Look. **Right-click** an item for *Quick Look*, *Share* (the system menu), *Copy Text* (images and PDFs), *Zip*, *Unzip*,
  *Convert To*, *Resize* and *Compress* (images), or *Show in Finder*. **Zip All** zips everything; **Combine into PDF** joins
  two or more images and PDFs. Results land on the Shelf. New screenshots are added automatically.
  - **Copy Text** reads the text in an image (and any QR code) with Vision, on this Mac, and copies it. A PDF's own text is used
    first; only pages without text are read as images, up to 10. It says *Copied*, or *No Text Found*.
  - **Convert To** is offered for every kind, and never lists the format the file already is:

    | From | To |
    | --- | --- |
    | Images | HEIC, PNG, JPEG, TIFF, PDF |
    | DOCX, DOC, RTF, RTFD, ODT, TXT, HTML, Markdown | PDF, DOCX, RTF, TXT, HTML, ODT |
    | PDF | TXT; PNG or JPEG (one file per page, in a "name Pages" folder) |
    | MOV, MP4, M4V | MP4, M4A (audio only), GIF (the first 15 s, 12 fps, up to 640 px) |
    | WAV, AIFF, MP3, CAF | M4A |

  - **Word fidelity.** Documents use TextEdit's engine: text, fonts, lists, simple tables, and images survive; headers, footers,
    footnotes, text boxes, and tracked changes do not.
  - **Resize** is half size, or 1920 or 1280 px on the long edge (never larger than the original); **Compress** makes a JPEG at
    quality 0.7.
- **Clipboard.** The last ten things you copied, text and images, in memory only (never written to disk). Copies that
  password managers mark as concealed are skipped. Click a card to copy it again; drag it out. Text that is *entirely* a
  link, an email address, or a `#hex` color gets one action: **Open**, **New Email**, or **Copy RGB** (with a swatch). An
  image card gets **Copy Text**. Right-click a text card for *Copy as Plain Text* (the string only, no other types) or *Save as
  Snippet* (kept in Notes, and written to disk because you chose to). History itself stays in memory.

### Clock

![Timer](images/06-expanded-timer.png)

Timer, Stopwatch, and Pomodoro share one tab.

- **Timer**: presets 1, 5, 10, 25 minutes, `+1m`, pause and cancel.
- **Stopwatch**: start, stop, laps (the lap in progress and the last lap), reset. Drift-free.
- **Pomodoro**: 25-minute focus sessions, 5-minute breaks, and a 15-minute break after the fourth. Sessions **chain**
  automatically and stop after the long break. A **streak** counts consecutive days with a finished session, and a
  **7-day bar chart** shows sessions per day.

![Pomodoro](images/06b-expanded-pomodoro.png)

### Reminders

![Reminders](images/04c-expanded-reminders.png)

An add field (Return saves to your default Reminders list), then your open reminders, soonest and most overdue first, then
undated ones. Tap the circle to check one off. Asks for Reminders access the first time.

### Tools

![Tools](images/08c-expanded-tools-eight.png)

Nine tools. The row shows **4, 6, or 8** of them (Settings); the rest are behind a chevron, in a grid of two rows of five.
Right-click a tool to pin it. The row is always full: unpinning fills the gap with another tool.

| Tool | Does |
| --- | --- |
| **Keep Awake** | Stops the display sleeping. Chips choose *Indefinitely*, *1 Hour*, or *Until* an hour you pick |
| **Low Power** | Toggles Low Power Mode (macOS asks for your password or Touch ID) |
| **Ring Light** | A soft white glow around the screen edge, for video calls; brightness and width sliders |
| **Mute Mic** | Mutes the default input device |
| **Pick Color** | The system eyedropper; copies the hex code |
| **Screenshot** | Area capture to the clipboard |
| **Focus** | Turns a Focus on or off through *your* Shortcuts named `Focus On` and `Focus Off` (a banner explains if missing) |
| **Clean Keys** | Swallows every key for 30 seconds so the keyboard can be wiped; the mouse still works. Needs Accessibility |
| **Lock Screen** | Locks the screen (posts Control-Command-Q). Needs Accessibility, like Clean Keys |

### Notes

![Notes](images/08d-expanded-notes.png)

Notes, Snippets, and a Prompter, stored as JSON in Application Support.

- **Notes**: a list and an editor. A note is named by its first line.
- **Snippets**: named text you copy in one tap (also findable in the palette).
- **Prompter**: the selected note, scrolling under the camera at a speed you set, with fade at the edges.

---

## Command palette

**⌃⌥K** opens a floating glass panel under the notch. Type; ↑ ↓ move; Return runs; Esc or a click away closes it. Empty, it
lists the modules. A web search is always the last row.

| Type | Row |
| --- | --- |
| A name: `notes`, `clock` | *Open Notes*. Also *Open Notes in a Window* and *Show Notes in the Menu Bar* (`notes window`, `notes menu bar`) |
| A tool: `keep awake` | The tool (toggles it) |
| An app: `safari` | Opens it |
| A shortcut's name | *Run "name"* (shows as blue work while it runs) |
| A snippet's title | Copies its text |
| `25m`, `1h30m`, `90s`, `timer 45` | *Start a 25-minute timer* |
| `remind buy milk` or `todo buy milk` | *Add Reminder "buy milk"* |
| `new note`, `settings` | The action |
| `clip alpha` or `cb alpha` | Up to five recent copies that contain "alpha"; Return copies one back. `clip` alone lists the latest |
| `yt swift`, `gh repo`, `w rome` | Searches that engine |
| Anything else | The last row: *Search Google for "…"* (your default engine) |
| `tr hello` | *Translate to* your system language |
| `tr es hello` | *Translate to Spanish*; the result row copies on Return |
| `define serendipity`, `def x` | The word and its first sense; Return opens the Dictionary app |
| `5 km in mi`, `72f to c` | `3.11 mi`: length, mass, volume, temperature, speed, area, duration, and data. Return copies |
| `100 usd in eur`, `€50 to $` | `€92.10`, with the ECB rate and its date. Return copies |
| `2*(3+4)` | `= 14`. `+ - * / ^`, brackets, `×` and `÷`. Return copies |

Nine engines are built in: Google `g`, DuckDuckGo `ddg`, Bing `b`, YouTube `yt`, Wikipedia `w`, GitHub `gh`, Apple Maps `m`,
Stack Overflow `so`, Amazon `a`. Add your own in Settings with `%s` where the search goes. Translation uses the system
Translation framework and may ask macOS to download a language.

Currency rates come from Frankfurter (European Central Bank data, free, no key). They are fetched only when you type a currency
query, and kept for 12 hours per currency; the row says *Converting…* until the rate arrives.

### The `macisland://` link

Other apps, scripts, and Shortcuts can drive MacIsland with a link (`open "macisland://timer?minutes=5"`).

| Link | Does |
| --- | --- |
| `timer?minutes=5` | Starts a timer (1 to 1440 minutes) |
| `stopwatch`, `pomodoro` | Starts one if it is not running |
| `open?module=notes` | Opens that module (`home`, `media`, `shelf`, `clock`, `reminders`, `tools`, `notes`) |
| `palette` | Opens the command palette |
| `shelf/add?path=/full/path` | Adds an existing file or folder to the Shelf; never reads its contents |
| `banner?title=&detail=&symbol=` | A neutral banner with no actions. The title is cut at 60 characters, the detail at 80, and a symbol must be an SF Symbol name. One banner every 2 seconds at most |

Anything else is ignored.

---

## Menu bar and windows

Nothing is in the menu bar until you choose. In **Settings → Menu Bar**, or by right-clicking a tab, give any module its own
menu-bar icon. Its window has a header you can **drag away** (or click the window button) to pop the module out into a
resizable **floating glass window**. The pin button on that window is **Keep on Desktop**: it drops the window to just above
the desktop icons, on every Space. Dragging an icon off the menu bar removes it.

The main capsule icon is always there: *Command Palette*, *Settings…*, *Quit*.

---

## Settings

Opened from the gear, or the menu bar icon. The window scrolls and resizes.

| Section | Choices |
| --- | --- |
| General | Launch at Login; Quiet in Focus; the open shortcut (⌃⌥Space, ⌃⌥I, or off) |
| Up Next | Show Calendar events; show due Reminders; a button that opens Internet Accounts |
| Weather | City (only the name is sent to Open-Meteo) |
| Left of the Notch / Right of the Notch / Not Shown | The tabs, dragged and switched |
| Media | Synced Lyrics |
| Menu Bar | A switch per module |
| Command Palette Search | Default engine; your own engines (name, keyword, address with `%s`) |
| Battery | Full Charge Alert level, 80 to 100% |
| Tools | How many tools in the row: 4, 6, or 8 |

---

## Keys and gestures

| Input | Result |
| --- | --- |
| Hover | Swell, then peek after 120 ms |
| Click, two-finger swipe down, **⌃⌥Space** | Expanded |
| Pointer away for 300 ms | Compact |
| Two-finger swipe up (expanded) | Close |
| Two-finger swipe left or right (expanded) | Previous or next tab (once per swipe; follows your finger) |
| ← / → | Previous or next tab |
| Esc | Close |
| **⌃⌥K** | Command palette |

---

## Accessibility

Every icon-only control has a label; selected states carry the selected trait. Nothing is conveyed by color alone (every
tint sits next to a glyph or a number). Text is at least 10 pt, and controls have at least a 28 pt hit target. **Reduce
Motion** turns springs into short eases, removes the hover swell, and stops looping animation. Glass surfaces follow
**Reduce Transparency**.
