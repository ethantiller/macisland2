# A volume HUD of MacIsland's own (Phase 6, item 10)

**Written 2026-09-30 in a session with no Mac and no Swift toolchain.** Everything here about how macOS behaves is from memory and
from the code already in this repo, and nothing was run. Where a claim needs checking on a real Mac it says *verify*.

## The decision this reverses

`docs/ROADMAP.md` said custom volume HUDs were dropped because "the system HUD can't be suppressed". **That reason was wrong for this
app.** The system draws its HUD in response to the volume key; if the key never reaches the system, there is no HUD. `KeyboardCleaner`
already holds a `CGEventTap` that swallows `NX_SYSDEFINED` events (the media keys), so consuming them is proven to work in this app. What
was true is narrower: you cannot *hide* the HUD while still letting the system change the volume. So the HUD is replaced by taking the
keys and doing the work ourselves: set the volume, and draw our own feedback.

## How it works

- **Taking the keys.** A `CGEventTap` (`SystemMediaKeyTap`) on system-defined events (type 14). An event is a media key when its `NSEvent`
  subtype is 8; `data1` holds the key in its high 16 bits and the state in the low 16. Sound up is key 0, sound down 1, mute 7
  (`NX_KEYTYPE_SOUND_UP`, `SOUND_DOWN`, `MUTE`). Key down is `(flags & 0xFF00) >> 8 == 0xA`, and bit 0 marks a repeat. The tap is
  `headInsertEventTap`, `defaultTap` (it may consume), and needs **Accessibility** (`AXIsProcessTrusted`); without it
  `CGEvent.tapCreate` fails, which is how "needs access" is detected. Returning `nil` from the callback consumes the event.
- **The steps.** The system volume has 16 steps, and **Option and Shift together** make a step a quarter of that (64). A press moves to the
  next step from the *nearest* one, so a level set by a slider lands on the grid. Either volume key also unmutes; mute toggles and keeps the
  level. (`VolumeStep`, tested.)
- **Setting the volume.** CoreAudio on the default output device. In order of preference: the virtual main volume
  (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`), the main element's `kAudioDevicePropertyVolumeScalar`, or channels 1 and 2. Mute is
  `kAudioDevicePropertyMute`. Each is written only if `AudioObjectIsPropertySettable`. The device is looked up on every press, so a change of
  output (headphones in, AirPods connected) needs no handling.
- **Devices with no settable volume** (HDMI, some DisplayPort and Bluetooth outputs, some USB interfaces): `canSetVolume` is false, and the key is
  **not** consumed, so the system handles it and draws its own HUD. A write that fails is not consumed either.
- **Other times it steps aside**, for the same reason (a press must never go unanswered): when the island is open or peeking, or when an alert that
  needs the person (`staysUntilSeen`) or a banner is showing. The HUD is never queued behind one, and never replaces one.
- **Clean Keys** holds its own tap and swallows the media keys (that is its job). While it is locked the HUD does not act, and Clean Keys' tap
  (created later, so first in line) sees the keys first anyway.
- **When macOS turns the tap off.** `tapDisabledByTimeout` (the callback was slow): turned back on, as `KeyboardCleaner` does.
  `tapDisabledByUserInput` (*verify*: this is what revoking Accessibility while running produces): the controller stops, the setting is turned
  off, and a red banner says so. The system HUD is back at once, because there is no tap.
- **The permission.** Turning the setting on without Accessibility leaves it off, asks once through the guide's access pieces
  (`AccessCenter.model.allow(.accessibility)`), and shows a banner with **Open Settings** and what to do. At launch, and when the app comes
  forward again, it never asks: with the setting on and no access it waits, and the system HUD stays (Phase 4's rule: nothing prompts at launch).

## What is not done, and why

- **The feedback sound.** macOS plays a short pop when the volume changes by key (unless "Play feedback when volume is changed" is off in Sound
  settings). Taking the key takes the sound with it. Not replicated; *verify* whether it is missed.
- **Brightness and keyboard backlight keys are out.** Brightness has no public API (display brightness is private `DisplayServices`, and
  external displays are DDC, which is private on Apple silicon); the roadmap already drops both. Only volume and mute.
- **Volume changed by something else** (a slider in Control Center, another app) shows no HUD; the island does not watch for it.
- **The side-of-screen HUD is not built.** The island one is, because it is the one the owner's request is about. A slim floating-glass HUD at the screen edge
  (DESIGN's Floating surface, click-through) is the next step, behind the same setting; it would need its own panel and a placement choice.
- **The bar on an island that is already open** is not drawn: the key goes to the system instead. A HUD on the open island would need a slot in every tab.

## Things to check on a real Mac

1. With the setting on, volume up, down, and mute change the volume and show the island HUD; holding a key repeats; Option+Shift is fine.
2. With the setting off, or after turning it off, the system HUD is back at once.
3. Revoke Accessibility in System Settings while it is on: does the HUD turn itself off and say so, or does the tap fail silently? (*verify* `tapDisabledByUserInput`.)
4. An HDMI display as the output, and AirPods: the system handles the keys.
5. Whether Reduce Motion leaves the HUD readable, and whether the quarter step is exactly a quarter of the system's step.
