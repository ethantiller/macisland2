# Roadmap and status

Where the project stands, what is next, and what needs a hand test. Back to the [README](../README.md). The design rules are in
[../DESIGN.md](../DESIGN.md).

**Contents:** [Start here next session](#start-here-next-session) · [What is built](#what-is-built) ·
[Decisions](#decisions) · [Next](#next) · [Hand-test checklist](#hand-test-checklist) ·
[Dormant code and cleanup](#dormant-code-and-cleanup) · [Ideas](#ideas) · [Dropped for good](#dropped-for-good)

---

## Start here next session

1. **Check `git status`.** Commit any work since the last commit, and commit new work in small steps; `.gitignore` already
   excludes `build/` and `.build/`.
2. Read [README.md](../README.md), then [ARCHITECTURE.md](ARCHITECTURE.md#gotchas-and-lessons) for the gotchas.
3. Run `./scripts/test.sh` (216 tests should pass) and `./scripts/bundle.sh && pkill -x MacIsland; open build/MacIsland.app`.
4. Work through the [hand-test checklist](#hand-test-checklist): most features were verified by tests and renders, not by
   using the app.
5. Then [Next](#next), below.

Working preferences (also saved in Claude's memory): clean, minimal, Apple-like UI that follows `DESIGN.md`; rebuild and relaunch the
app after UI changes before saying to look; the user reviews visually and iterates quickly, so prefer small, checked changes.

---

## What is built

- **The island:** the notch container, compact, banner, peek, and expanded presentations, gestures, the glass pill for displays
  without a notch, and the Settings window.
- **Live activities:** the minimal pair, full charge, drive eject, the screenshot shelf, Keep Awake durations, headphone batteries.
- **Media:** shuffle, repeat, Favorite, app volume, and synced lyrics, in a Dynamic Island style player.
- **Home and productivity:** the Home dashboard, weather, Reminders, Pomodoro, zip and convert, smart actions, notes, Clean Keys.
- **Reach:** the command palette, search and translate, Shortcuts, menu-bar modules, torn-off windows, Keep on Desktop.

Beyond that, the user directed: a redesigned Home, an own Reminders tab, a two-sided tab strip, timer, Pomodoro, and stopwatch
peeks, and direct control of Music and Spotify.

---

## Decisions

Where the app ended up differently from what was first planned, and why. The design decisions themselves are in
[../DESIGN.md](../DESIGN.md).

| Decision | Why |
| --- | --- |
| 7 modules; **5 tabs left of the notch and 1 right**, arranged in Settings | User request |
| Default tabs Home, Media, **Clock, Reminders**, Tools. Shelf and Notes are in *Not Shown* | Reminders became its own tab; Shelf still opens on a drop |
| Reminders is its own module, not part of Home | User request |
| No Launch module: apps and Shortcuts are only searched from the palette | User did not like it |
| Home is two rows of boxes: Up Next, music, four tools, timers and Shelf. Battery and stats are not on it | Iterated with the user |
| Weather is in the tab strip and the idle peek | User liked it beside the notch |
| Menu-bar windows use the system's own material and only adapt the ink | Avoid glass on glass |
| Idle peek shows the day and tools; timer, Pomodoro, and stopwatch have their own peeks | Fit the 380 pt width; use the space |
| The palette hotkey ⌃⌥K is fixed, not a setting | Simplicity |
| Banners carry one action today; DESIGN allows two; N6 adds the second | Nothing needed two until Check Camera |
| `Theme.Palette` is surface-aware, as `SurfaceInk` | One view draws on the island and on glass |
| Type gains `prompter`, `headline`, `subheadline` | The Prompter and the music player |
| `expandedWidth` stays 520; the right side gets one tab | Fits without widening |
| Agents is an idea, not a module | The user moved to everyday features: see [Next](#next) and [Ideas](#ideas) |
| AirDrop blue (`Tint.airDrop`) is an exception to "one meaning per color" | It marks the AirDrop half of the drop target, beside `AirDropGlyph`, so it reads as AirDrop and not as storage |

---

## Next

Everyday features that fit [DESIGN.md](../DESIGN.md): on-device processing, no subscriptions, no custom backend. Work through the
packages in order, and tick each one when it lands (with its hand checks added to the [checklist](#hand-test-checklist)).

| Pkg | Features | New permissions |
| --- | --- | --- |
| N1 | Copy Text (OCR) · Quick Look · Share, Combine into PDF, Resize, Compress · **document, PDF, video, and audio converters** | none |
| N2 | Clipboard: Copy as Plain Text, Save as Snippet, `clip …` in the palette | none |
| N3 | Palette answers (define, units, currency, calculate) · `macisland://` URL scheme · Lock Screen | Accessibility (Lock Screen only; already asked for by Clean Keys) |
| N4 | Outlook and Teams: Join opens the meeting app, Outlook SafeLinks unwrapped, Internet Accounts pointer | none |
| N5 | Rain-soon banner · Low disk space banner · Bluetooth device switcher | none (Bluetooth is already granted) |
| N6 | Mirror with Check Camera · Record Screen · Voice Note · two-action banners · the Tools grid becomes 2 × 6 · delete dormant code | Camera, Microphone, Screen Recording |

**Progress:** N1 ☐ · N2 ☐ · N3 ☐ · N4 ☐ · N5 ☐ · N6 ☐

### N1: Shelf and files

**Goal:** everything you'd do to a file on the Shelf, on-device, run like Zip already runs: `FileTools.run`, the blue
"working" activity, and the result added to the Shelf.

| Feature | Where | How |
| --- | --- | --- |
| Copy Text | File menu (images, PDFs) → **Copy Text**; Clipboard image card → **Copy Text** chip | Vision `RecognizeTextRequest` (`.accurate`, language correction, automatic language) plus `DetectBarcodesRequest` (QR payloads appended). For a PDF, try `PDFDocument.string` first and OCR only pages with no text, up to 10 pages. The text goes to the pasteboard, then `flash(IslandAlert("doc.on.clipboard.fill", .neutral, "Copied"))`; an empty result flashes "No Text Found" |
| Quick Look | File menu → **Quick Look**; Space while an item is hovered | SwiftUI `.quickLookPreview($previewURL, in: shelf.items)` on `ShelfView`. The panel is non-activating, so check in the app that Quick Look takes the keyboard. If it doesn't, call `NSApp.activate()` first |
| Share | File menu → **Share** | `ShareLink(items: [url])` inside the context menu (the system share submenu) |
| Combine into PDF | `ShelfTextButton` next to **Zip All** when there are 2 or more images or PDFs | PDFKit: each image becomes a page, and PDFs append their pages. Output "Combined.pdf" |
| Resize, Compress | Image menu → **Resize** (50%, 1920 px, 1280 px on the long edge), **Compress** (JPEG, quality 0.7) | ImageIO: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` and `…WithTransform`; `kCGImageDestinationLossyCompressionQuality` |
| **Converters** | The existing **Convert To** menu, now offered for every kind below | See the table below |

The converters (all native Swift; `Convert To` never lists the format the file is already in):

| From | To | Framework |
| --- | --- | --- |
| Images | HEIC, PNG, JPEG, TIFF, PDF | ImageIO, PDFKit (exists today) |
| DOCX, DOC, RTF, RTFD, ODT, TXT, HTML, Markdown | **PDF**, DOCX, RTF, TXT, HTML, ODT | `NSAttributedString` reads and writes (`.officeOpenXML`, `.docFormat`, `.rtf`, `.rtfd`, `.openDocument`, `.html`, `.plain`). Markdown comes in through `AttributedString(markdown:, options: .init(interpretedSyntax: .full))`. PDF is made by laying out an `NSTextView` and running `NSPrintOperation` with `jobDisposition = .save`, no panels, and the paper size from `NSPrintInfo.shared` (paginated) |
| PDF | TXT, PNG, JPEG (one file per page, in a "<name> Pages" folder) | PDFKit `string`; each page drawn into a `CGContext` at 2× |
| MOV, MP4, M4V | MP4, M4A (audio only), GIF (the first 15 s, 12 fps, 640 px) | `AVAssetExportSession.export(to:as:)` for MP4 and M4A. GIF frames come from `AVAssetImageGenerator` and are written with ImageIO as a looping GIF |
| WAV, AIFF, MP3, CAF | M4A | `AVAssetExportSession` with the `AppleM4A` preset |

- **Word fidelity:** the Word path uses TextEdit's engine. Text, fonts, lists, simple tables, and images survive; headers,
  footers, footnotes, text boxes, and tracked changes do not. Say this in FEATURES. Converting through Pages (AppleScript)
  is in Ideas.
- **Threading:** HTML import and `NSPrintOperation` run on the main actor. Everything else runs in `Task.detached`, as
  `FileTools.run` does now.
- **Files:**
  - new `Shelf/Converters.swift`, holding `ConversionTarget`, which replaces `ImageFormat`, and `FileKind`;
  - new `Shelf/TextRecognizer.swift`;
  - `Shelf/FileTools.swift` (the new entry points);
  - `Shelf/ShelfView.swift` (menus, the Combine button, the Space key, the Copy Text chip);
  - `Island/IslandPanel.swift` (Space).

```swift
enum FileKind { case image, document, pdf, video, audio
    nonisolated static func of(_ url: URL) -> FileKind? }                 // pure, tested
enum ConversionTarget: String, CaseIterable, Identifiable {                // replaces ImageFormat
    case heic, png, jpeg, tiff, pdf, docx, rtf, txt, html, odt, mp4, m4a, gif, pages
    nonisolated static func targets(for url: URL) -> [ConversionTarget] }  // pure, tested
struct RecognizedText: Equatable, Sendable { var lines: [String]; var barcodePayloads: [String]
    nonisolated static func ordered(_ boxes: [(text: String, box: CGRect)]) -> [String] }  // top-down, left-right
protocol TextRecognizing: Sendable { func recognize(_ image: CGImage) async throws -> RecognizedText }
// FileTools: init(shelf:work:recognizer: TextRecognizing = VisionTextRecognizer())
//   copyText(from: URL) · copyText(from: NSImage) · convert(_ url: URL, to: ConversionTarget)
//   combinePDF(_ urls: [URL]) · resize(_ url: URL, maxPixel: Int?) · compress(_ url: URL)
```

**Done when:**
- Tests pass for `FileKind.of`, `targets(for:)`, `RecognizedText.ordered`, and Copy Text with a stub recognizer (Copied,
  No Text Found).
- A DOCX → PDF → TXT round trip on a temp file passes, as does a Markdown → HTML one.
- In the app: Quick Look opens and takes Space and Esc; Share shows the system menu.

### N2: Clipboard

- On text cards, the context menu gets **Copy as Plain Text** (writes the `.string` type only) and **Save as Snippet**
  (`NotesModel`; saved to disk only because the person chose to).
- In the palette, `clip <text>` or `cb <text>` lists matching history entries; Return copies one.
- History stays in memory only.
- **Files:** `Shelf/ShelfView.swift`, `Shelf/ClipboardHistory.swift` (`matches(_:) -> [ClipboardEntry]`, pure),
  `Palette/PaletteModel.swift`.
- **Done when:** tests pass for the match function and the plain-text write, using a private pasteboard
  (`NSPasteboard(name:)`).

### N3: Palette answers, URL scheme, Lock Screen

**Palette answers** are new rows in `PaletteModel.specialItems`, ahead of the matches.

| Type | Example | Title | Subtitle | Return |
| --- | --- | --- | --- | --- |
| Define | `define serendipity`, `def x` | the word | first sense, one line | opens `dict://word` |
| Units | `5 km in mi`, `72f to c` | `3.11 mi` | Units | copies |
| Currency | `100 usd in eur`, `€50 to $` | `€92.10` | Currency · ECB rate, the date | copies |
| Calculate | `2*(3+4)` | `= 14` | Calculator | copies |

- Define uses DictionaryServices `DCSCopyTextDefinition`.
- Units use Foundation `Measurement` and `MeasurementFormatter`: length, mass, volume, temperature, speed, area, duration,
  and data.
- Calculate uses a recursive-descent evaluator, not `NSExpression`, which throws Objective-C exceptions on bad input.
- Currency comes from Frankfurter (free, keyless, ECB). Check the current host and path when implementing. It is fetched
  only when a currency query is typed and cached for 12 h per base; the row moves from working to done like the
  translation row.
- ARCHITECTURE Network table: add the host (it sends a currency code). README privacy line: add the host.

**URL scheme `macisland://`**
- Add `CFBundleURLTypes` to `Support/Info.plist`, and handle it in `AppDelegate.application(_:open:)`.
- Commands: `timer?minutes=`, `stopwatch`, `pomodoro`, `open?module=`, `palette`, `shelf/add?path=`, and
  `banner?title=&detail=&symbol=`.
- Guardrails:
  - banners are neutral tint only, with no actions;
  - the title is capped at 60 characters and the detail at 80;
  - at most one banner every 2 s;
  - `shelf/add` accepts only existing paths and never reads contents;
  - unknown commands are ignored.

**Lock Screen**
- A tool (`lock.fill`, "Lock Screen", Apple's own name for it) and a palette row.
- It posts ⌃⌘Q through `CGEvent` (key code 12, `.maskControl` and `.maskCommand`).
- If `AXIsProcessTrusted()` is false, show the existing "Accessibility Access Needed" banner with **Open Settings**,
  following `KeyboardCleaner`.
- With nine tools plus Less, the Tools grid stays 5 × 2.

**Files:**
- new `Palette/Answers.swift` and `Palette/ExchangeRates.swift`;
- `Palette/PaletteModel.swift`;
- new `App/URLCommand.swift`;
- `App/MacIslandApp.swift`;
- `Tools/ToolID.swift`, `Tools/ToolCatalog.swift`, `Tools/SystemActions.swift`;
- `Support/Info.plist`.

```swift
protocol DictionaryLookup: Sendable { func definition(of term: String) -> String? }
enum DictionaryText { nonisolated static func firstSense(_ text: String) -> String? }
enum UnitConversion { struct Request: Equatable { let value: Double; let from: Dimension; let to: Dimension }
    nonisolated static func parse(_ s: String) -> Request?; nonisolated static func format(_ r: Request, locale: Locale) -> String }
enum Calculator { nonisolated static func evaluate(_ s: String) -> Double? }
struct CurrencyRequest: Equatable { let amount: Double; let from: String; let to: String
    nonisolated static func parse(_ s: String) -> CurrencyRequest? }
@MainActor @Observable final class ExchangeRates {                         // IslandFeatures.rates
    typealias Fetch = @Sendable (String) async throws -> (rates: [String: Double], date: Date)
    init(fetch: @escaping Fetch, now: @escaping () -> Date = Date.init)
    func rate(from: String, to: String) -> (value: Double, date: Date)?     // cache only
    func load(base: String) async }                                         // fetch if missing or older than 12 h
enum URLCommand: Equatable { case timer(minutes: Int), stopwatch, pomodoro, open(IslandModule), palette,
    addToShelf(URL), banner(title: String, detail: String?, symbol: String?)
    nonisolated static func parse(_ url: URL) -> URLCommand? }              // enforces the limits above
```

**Done when:**
- Tests pass for every parser, `firstSense`, `ExchangeRates` staleness (injected `fetch` and `now`), and `URLCommand`
  limits.
- In the app: `open "macisland://timer?minutes=1"` starts a timer, and Lock Screen locks.

### N4: Outlook and Teams

What already works:
- EventKit reads every account in System Settings → Internet Accounts, so **Outlook, Microsoft 365, and Exchange
  calendars already feed Up Next and the 5-minute banner** once the account is added there.
- `MeetingLink` already finds `teams.microsoft.com` and `teams.live.com` links.

What to build:
- **Join opens the app.** `MeetingLink.appURL(for:)`:
  - Teams: `https://teams.microsoft.com/l/…` becomes `msteams:/l/…`;
  - Zoom: `https://…zoom.us/j/<id>?pwd=<p>` becomes `zoommtg://zoom.us/join?confno=<id>&pwd=<p>`;
  - these apply only when `NSWorkspace.shared.urlForApplication(toOpen:)` finds a handler; otherwise Join keeps the https
    link.
- **Unwrap Outlook SafeLinks.** `MeetingLink.unwrap(_:)` decodes the `url=` parameter of
  `*.safelinks.protection.outlook.com` links, and the `q=` parameter of `google.com/url` links, before returning the link.
- **Point to the account setup.** Settings → Up Next gets one line, "Outlook, Google, and Exchange calendars come from
  Internet Accounts.", with an **Open Internet Accounts** button
  (`x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension`).
- **Not planned (goes in Ideas):** Microsoft Graph sign-in (MSAL). It needs an Azure app registration, often admin
  consent, and tokens in the Keychain; it's only for organizations that block Exchange sync. The new Outlook for Mac
  keeps its own store, which EventKit can't read.
- **Files:** `Agenda/AgendaMonitor.swift`, `Settings/SettingsView.swift`, and the Join call sites in `App/MacIslandApp.swift`
  and `Home/`.
- **Done when:** tests pass for `appURL` (Teams, Zoom, fallback) and for `unwrap` (SafeLinks, Google redirect, a plain
  link untouched).

### N5: Ambient banners and devices

| Feature | Trigger | Banner | How |
| --- | --- | --- | --- |
| Rain soon | The existing 30-minute weather refresh, only when a city is set | `cloud.rain.fill`, neutral: "Rain Soon", "Starts around 3:45 PM"; times out; once per rain spell (resets after a dry hour); respects Quiet in Focus | Add `minutely_15=precipitation` to the Open-Meteo forecast request. The pure rule is `RainRule.start(samples:now:) -> Date?` (dry now, ≥ 0.2 mm within 30 min) |
| Low disk space | Unlock (already observed), `NSWorkspace.didWakeNotification`, a finished `FileTools` job, a finished download. Never on a schedule | `internaldrive.fill`, `Tint.attention`: "Low Disk Space", "8.2 GB free", with **Open Storage** (`x-apple.systempreferences:com.apple.settings.Storage`); stays until seen | `volumeAvailableCapacityForImportantUsageKey`. `DiskRule.shouldWarn(free:armed:)`: warn under 10 GB, re-arm above 15 GB |
| Bluetooth switcher | The Media output picker gets a "Not Connected" section; a palette row "Connect <name>" | Connecting shows the blue working activity; the existing headphones banner confirms | IOBluetooth `IOBluetoothDevice.pairedDevices()` filtered to the audio major class; `openConnection(_:)` with a target (async); `closeConnection()` for **Disconnect**. Listed only when the picker opens |

- **Files:** `Weather/WeatherModel.swift`; new `System/DiskSpace.swift` and `System/BluetoothDevices.swift`;
  `NowPlaying/NowPlayingView.swift` (the picker); `App/MacIslandApp.swift` (wiring).

```swift
protocol BluetoothDeviceProviding: AnyObject {
    func pairedAudioDevices() -> [PairedDevice]                       // PairedDevice: id, name, isConnected
    func connect(_ id: String) async -> Bool; func disconnect(_ id: String) }
@MainActor @Observable final class BluetoothDevices { init(provider: BluetoothDeviceProviding) }  // IslandFeatures.bluetooth
```

**Done when:**
- Tests pass for `RainRule` and `DiskRule`, and for `BluetoothDevices` with a stub (connect updates the list; a failure
  flashes "Couldn't Connect").
- In the app: AirPods connect from the picker.

### N6: Capture (new permissions)

**Mirror**
- A tool (`person.crop.rectangle`). When on, it replaces the Tools row or grid with:
  - a 16:9 preview, `mirrorHeight` 180 × `mirrorWidth` 320 (new tokens), clipped to `widgetRadius` 14 (continuous),
    `.resizeAspect`, and mirrored;
  - a column beside it holding Ring Light's `ControlButton`, its brightness `IslandSlider` while Ring Light is on, and a
    **Done** `ChipButton`.
- Height: 38 + 8 + 180 + 18 = 244, which is ≤ `panelSize` 260.
- It calls `holdOpen()` while shown.
- The camera comes from `AVCaptureDevice.DiscoverySession` (built-in, Continuity, external). `AVCaptureSession` start and
  stop run on a private serial queue. `AVCaptureVideoPreviewLayer` sits in an `NSViewRepresentable`, and no frames reach
  the app. Everything is released when the island folds, the tab changes, or Done is pressed.
- Add `NSCameraUsageDescription`: "MacIsland shows your camera so you can check how you look before a call." If access is
  denied: "Camera access is off." with an **Open Settings** chip.

**Two-action banners**
- `IslandBanner.action` becomes `actions: [Action]` (at most 2; the first is prominent). Update `BannerContent` and the
  roughly seven call sites.
- The 5-minute meeting banner gets **Join** (prominent) and **Check Camera** when the event has a `joinURL`.

**Record Screen**
- A tool (`record.circle`, title "Record", label "Record Screen") and a palette row.
- A region picker opens: a full-screen transparent `NSPanel` at `.screenSaver` level with a crosshair. Drag to choose a
  region, click for the whole display, Esc cancels.
- Recording uses `SCContentFilter(display:excludingApplications: [MacIsland])`, `SCStreamConfiguration.sourceRect`, 30 fps,
  and `SCStream` with `SCRecordingOutput` writing to `~/Movies/Screen Recording <date>.mov`. It is capped at 30 minutes,
  and the result goes to the Shelf.
- While recording, the compact island shows `.recording(.screen)`: `record.circle.fill` and the elapsed time, in
  `Tint.working`. Clicking it stops the recording (it is excluded from opening the island, like the compact play button).
- Screen Recording access is checked with `CGPreflightScreenCaptureAccess` and requested with
  `CGRequestScreenCaptureAccess`. If denied, show a red banner with **Open Settings**.

**Voice Note**
- An `IconButton("mic", "Record Voice Note")` in the Notes header, and a palette row.
- `AVAudioEngine` input writes an `.m4a` to `~/Library/Application Support/MacIsland/Voice Notes/` and streams to
  `SpeechAnalyzer` with `SpeechTranscriber` (macOS 26, on-device; make sure the model is installed through
  `AssetInventory`).
- Stop makes a note titled "Voice Note, <time>" holding the transcript, and adds the audio to the Shelf.
- Compact: `.recording(.voice)`, `waveform` and the elapsed time, in `Tint.working`. The peek shows the elapsed time, a
  level meter (sampled only while the peek is visible), and **Stop**. It is capped at 10 minutes.
- If Mute Mic is on, show a banner with **Unmute**.
- `PrivacyMonitor` hides the `.microphone` activity when MacIsland itself is the recorder.
- Add `NSMicrophoneUsageDescription`: "MacIsland records voice notes and turns them into text on this Mac." Check whether
  `SpeechTranscriber` also needs `NSSpeechRecognitionUsageDescription`.

**Tools and cleanup**
- Eleven tools plus Less make 12, so the grid becomes **2 × 6** (`gridColumns` count 6; `toolsGridHeight` is unchanged).
  The row still pins 4, 6, or 8.
- Compact priority becomes: banner, alert, **recording**, microphone, timer/Pomodoro, stopwatch, working, transfer, music.
- Remove one thing, per DESIGN: delete the dormant `DeviceBatteries`, `SystemStats`, and `toggleDarkMode`, their
  `IslandFeatures` entries, and their tests.
- DESIGN: the Tools note, banner actions, compact priority, and the new tokens. ARCHITECTURE: the permissions table and
  storage (the Voice Notes folder).

```swift
enum CameraAccess: Equatable { case notDetermined, granted, denied }
protocol CameraSessionProviding: AnyObject { var access: CameraAccess { get }
    func requestAccess() async -> Bool; func start() async throws -> AVCaptureSession; func stop() }
@MainActor @Observable final class CameraMirror { private(set) var isOn: Bool; private(set) var access: CameraAccess
    init(provider: CameraSessionProviding); func toggle() async; func stop() }            // IslandFeatures.mirror
protocol ScreenRecording: AnyObject { func start(region: CGRect?, on display: CGDirectDisplayID) async throws
    func stop() async throws -> URL }
@MainActor @Observable final class ScreenRecorder { private(set) var startedAt: Date?     // IslandFeatures.screenRecorder
    init(recorder: ScreenRecording); func start(region: CGRect?) async; func stop() async }
protocol Transcribing: AnyObject { func start(writingTo file: URL) async throws
    func stop() async throws -> String; var level: Float { get } }                         // 0...1, read only while visible
@MainActor @Observable final class VoiceRecorder { private(set) var startedAt: Date?     // IslandFeatures.voice
    init(transcriber: Transcribing, notes: NotesModel, shelf: ShelfModel); func start() async; func stop() async }
struct IslandBanner { /* … */ var actions: [Action] = [] }                                // at most two; first is prominent
// CompactActivity gains: case recording(RecordingKind)   // .screen, .voice
```

**Done when:**
- Tests pass for:
  - `CameraMirror` with a stub (denied access; stop on fold);
  - `ScreenRecorder` and `VoiceRecorder` with stubs (start, stop, the Shelf and note results, the caps);
  - `contentHeight(.tools)` with Mirror on;
  - two-action banners;
  - compact ranking with recording.
- The dormant tests are gone, and the test count is updated in the docs.
- In the app: all three permission prompts appear once, and denied states link to Settings.

---

### Considered, not planned

| Idea | Why not now |
| --- | --- |
| Island on the lock screen | Private SkyLight API; still Dropped for good unless the user asks for a test build first |
| Away summary on unlock, walk-away lock, meeting countdown, world clocks, music sleep timer | Not picked this round (walk-away lock would break the idle budget) |
| Custom volume and brightness HUDs, camera-in-use pill | Dropped for good: the HUD can't be suppressed; macOS draws its own dots |
| Hide desktop icons | Needs `defaults write com.apple.finder CreateDesktop` and relaunching Finder |
| 20-20-20 eye breaks | Needs a standing timer while nothing is live |
| Microsoft Graph calendar | See N4 |
| Converting with Pages for full Word fidelity; XLSX | Needs Pages through AppleScript; there is no native XLSX reader |

---

## Hand-test checklist

Built and covered by unit tests or renders, but **not yet tried by hand** in the running app. Tick these off in the first session.

**Island and input**
- [ ] Hover swell, then peek at 120 ms; leaving closes without dipping into the notch
- [ ] Two-finger swipes: down opens, up closes, left and right change tabs (direction follows your fingers)
- [ ] The music art and sound bars **fly** into the peek and the Media tab instead of appearing
- [ ] Reduce Motion: no swell, everything eases; Reduce Transparency: the glass pill (no-notch display) turns opaque
- [ ] Idle CPU (see [gotchas](ARCHITECTURE.md#gotchas-and-lessons)) settles near 0.1 to 0.3%

**Settings and tabs**
- [ ] The Settings gear opens the window without crashing (a crash here was fixed); the window scrolls and resizes
- [ ] Drag a tab between Left, Right, and Not Shown; reorder within a list; the switches work; right-click menu works
- [ ] The right-hand tab, the weather, and the pencil never reach the notch, even with a running timer

**Media**
- [ ] Music playing, then a video: the play/pause button controls the **music**; first use asks for Automation permission
- [ ] Shuffle, repeat, Favorite (Apple Music), app volume, and lyrics on a real track
- [ ] The Automation prompt for Spotify

**Home, Clock, Reminders**
- [ ] Reminder field: typing works in the panel (focus), Return saves, access prompt appears once
- [ ] Up Next with a real event: the 5-minute banner and **Join**
- [ ] Weather from a real city; changing it updates after a pause in typing
- [ ] Pomodoro chains and stops after the long break; the streak and chart update

**Shelf and Tools**
- [ ] Drop a file on each half; it lands on the Shelf, the drop tiles go away, and AirDrop opens the picker
- [ ] Right-click a file: Zip, Unzip, Convert To (HEIC), Show in Finder; Zip All; results appear and the blue activity shows
- [ ] Clipboard cards: Open, New Email, Copy RGB actions
- [ ] Take a screenshot: it lands on the Shelf with the "Shelf" alert
- [ ] Plug a drive in: the banner and **Eject**; a failing eject shows the reason
- [ ] **Clean Keys**: asks for Accessibility, swallows keys for 30 s, the banner and status glyph, Unlock works
- [ ] Keep Awake durations; Low Power (password prompt); Ring Light; Mute Mic; Focus with and without the shortcuts

**Notes**
- [ ] Editing a note and a snippet (focus in the panel, the island stays open); the Prompter scrolls and pauses

**Reach**
- [ ] ⌃⌥K opens the palette under the notch; typing, arrows, Return, Esc; clicking away closes it
- [ ] `25m`, `remind …`, `yt …`, an app name, a shortcut name, and `tr es hello` (which may download a language)
- [ ] A menu-bar module: add from Settings and from a tab's menu; drag its header away; Keep on Desktop; close
- [ ] Add and remove a custom search engine; change the default engine

---

## Dormant code and cleanup

| Item | Note |
| --- | --- |
| `System/DeviceBatteries.swift`, `System/SystemStats.swift` | Built and tested, but Home no longer shows them. N6 deletes them, with `IslandFeatures.batteries` and `.stats` and their tests |
| `SystemActions.toggleDarkMode` | Never called (the dark-mode AppleScript is unused). N6 deletes it |
| `ClipboardHistory` | Polls every 0.7 s from launch, the one standing timer. Revisit it against the idle budget |
| `.swift-format` and `format.sh` | Never run over the codebase (~490 findings). Commit first, then format in its own commit |
| `IslandModule.agents` | Reserved for the Agents idea |
| `Theme.Metrics.cardRadius` (10) vs `widgetRadius` (14) | Home uses 14; older cards and fields use 10. Unify later if it bothers |
| No repo `LICENSE` | Only the vendored adapter's BSD-3 license is present |

---

## Ideas

Not planned, not promised.

- **Automatic updates** need Developer ID signing and a hosted feed (dropped for now). Signing would also stop permissions
  resetting on each rebuild.
- **An app icon** and a proper first-run tour (the app has no Dock icon and no first-run guidance).
- **Continuous integration**: `./scripts/test.sh` on a macOS runner.
- **Per-display islands** (currently one, on the notched screen).
- **Palette: recents and frequency**, so what you use floats up.
- **A Dynamic Island style for more activities** (the music player's layout, applied to timers on expand).
- **Converting through Pages** (AppleScript) for full Word fidelity.
- **Microsoft Graph sign-in (MSAL)** for organizations that block Exchange sync. It needs an Azure app registration, often admin
  consent, and tokens in the Keychain. The new Outlook for Mac keeps its own store, which EventKit can't read.
- Features already **dropped for good**, with the reasons, are [listed below](#dropped-for-good); check there before proposing one.

### Agents module (unscheduled)

The old plan for an eighth module. `IslandModule.agents` is reserved for it and `isAvailable` is false. Features: Developer API,
Agent Activity, Agent Approvals, AI Usage Tracker (Claude Code, Codex), Shell Activity.

- **`Agents/LocalAPI.swift`.** An `NWListener` on **127.0.0.1** only, with a bearer token stored at
  `~/Library/Application Support/MacIsland/api-token` (create it 0600).
  - `POST /activities` starts, updates, or ends an activity (blue tint).
  - `POST /approvals` **long-polls** until the person decides.
- **Hooks.** Settings → Agents → **Install Claude Code Hooks** asks for confirmation, then writes the hooks into
  `~/.claude/settings.json`: turn start, stop, and the permission-request hook. **Check the current event names in the Claude Code
  docs at implementation time.** Also set up Codex `notify`. Back up the file first, and merge; never overwrite.
- **Approvals.** A red `hand.raised.fill` banner with **Allow** (prominent) and **Deny**. It stays until answered, and after a timeout
  falls back to asking in the terminal.
- **Usage.** Parse token usage from `~/.claude/projects/**/*.jsonl` and `~/.codex/sessions`; cost from a price table; estimate the
  5-hour window. Parse in the background and cache; these files are large.
- **Shell.** An opt-in zsh `preexec` / `precmd` snippet: a command running longer than 10 s becomes a blue activity; on exit, a green
  or red alert.

**Where it hooks in**

| Need | Existing thing |
| --- | --- |
| A blue "working" activity | `WorkTracker` and `Theme.Tint.working` (already ranks in `compactActivities`) |
| A red "needs you" banner | `IslandViewModel.showBanner` with `Theme.Tint.attention` |
| Two actions on a banner | Extend `IslandBanner` (`action` becomes `actions`, one prominent) and `BannerContent` in `IslandView` |
| The Agents tab | `IslandModule.agents`, a view in `ModuleContent`, a height in `contentHeight(for:)`, `isAvailable = true` |
| Settings section | `SettingsView`, a new `Section`; persist through `AppSettings` (mind the [no-op setter rule](ARCHITECTURE.md#gotchas-and-lessons)) |
| A listener that survives launches | Start in `AppDelegate.connectEvents` |
| Tests | Keep the HTTP parsing, token check, and hook-merging as pure functions; stub the socket |

**Security notes for the API.** Bind to loopback only; require the bearer token on every request; never log it; long-poll with a
timeout; validate JSON sizes. Treat hook writing as a change to the user's own tool configuration: ask, back up, merge.

---

## Dropped for good

Considered during planning and ruled out, each for a concrete reason. Check here before proposing one again.

| Feature | Reason |
| --- | --- |
| Knock to Control | No public accelerometer or force API |
| Call Island | No incoming-call API |
| Message Island | Needs Full Disk Access to the Messages database |
| Notification Mirror | No API to read Notification Center |
| Lock Screen Widgets | Apps can't draw on the lock screen |
| Keyboard Backlight | Private CoreBrightness |
| External Display Control | DDC/CI is private on Apple silicon |
| Sound Mixer, EQ, Live Audio Spectrum | Audio process taps; breaks the idle budget |
| System HUDs, Alt HUD Styles, Caps Lock HUD | The system HUD can't be suppressed |
| Keystroke HUD | Input Monitoring for a niche use |
| Window Snapping | A separate product |
| Menu Bar Icon Hiding | Fragile on macOS 26 and later |
| Hide the Notch | Menu bar text can't follow a fake black bar |
| Hidden from Screen Capture | ScreenCaptureKit ignores `sharingType` on macOS 15 and later |
| Privacy Indicator | macOS draws its own dots |
| Custom Idle Animation, Timer Mascots | Decoration; would need Lottie |
| Stocks Ticker | Needs a paid API key |
| Notch Terminal | Needs a terminal emulator dependency |
| AirPods nearby-case detection | Undocumented BLE payloads; the connected battery stays |
| Copilot and Cursor usage | No local data to read |
| Desktop Widgets | WidgetKit needs an Xcode app extension; **Keep on Desktop** for torn-off windows covers it |
| Automatic Updates | Needs Developer ID signing and a hosted feed; revisit once the app is signed |
| More than two live activities | Capped at two (the minimal pair), after the HIG |

Also settled, because macOS offers no way to do the iPhone version:

| iPhone feature | On the Mac |
| --- | --- |
| Face ID | A Touch ID "Unlocked" alert when the Mac unlocks; other apps' Touch ID prompts can't be seen |
| Flashlight | Ring Light |
| Incoming calls with Accept and Decline | Not possible. The microphone activity shows which app has the mic, and Mute Mic is a tool |
| AirDrop send progress | Not observable. Incoming files show progress once they reach Downloads |
| Incoming AirDrop request | The system's own notification can't be replaced or suppressed |
| Sending by AirDrop | Picker only: `NSSharingService(.sendViaAirDrop)` always asks for the recipient in the system picker |
| AirPods 3D model | The matching SF Symbol with a bounce |
| Focus / Do Not Disturb | Readable (a Focus is on) but not changeable directly; the Focus tool runs your own `Focus On` and `Focus Off` Shortcuts |
| Apple Pay, Maps navigation | No public API |
