# Dynamic Notch

The iPhone's Dynamic Island, for the MacBook Pro notch.

At rest it is invisible — the black shape sits exactly over the hardware notch, to
the pixel. Then it grows: album art and dancing bars while music plays, a level
bar when you touch the volume keys, a toast when the charger goes in. Bring the
pointer to it and it unfurls into a player and a file shelf.

```
        ╭──────────────╮                    ╭──────────────────────╮
   ▸    │ ▓▓   ▁▃▅▂    │        hover  ▸    │ ▓▓▓▓   Title         │
        ╰──────────────╯                    │ ▓▓▓▓   Artist — Album│
         art   visualiser                   │        ────●───── ▸  │
                                            ╰──────────────────────╯
```

## What it does

- **Now Playing** — Apple Music and Spotify. Artwork in the pill, an accent colour
  pulled from the cover, a draggable scrubber and transport controls. No private
  APIs. Pause for ten seconds and the pill hands the notch back to the hardware,
  keeping the track for whoever opens the panel.
- **Volume & brightness** — screen brightness, keyboard backlight and system
  volume render as an inline bar in the notch.
- **File shelf** — drag files at the notch and it opens to catch them. Drag them
  back out into any app, or send them on with the share sheet.
- **Timer & stopwatch** — both run and are controlled entirely from the notch:
  presets, pause, +1m, lap, reset. Whichever is running counts in the right ear
  while album art carries on in the left — the two ears work independently, like
  the real thing. Timers running in **Apple's Clock app** are mirrored too and
  marked as theirs, since Clock is the one thing here we can read but not steer.
- **Quick actions** — dark mode, keep-awake, screenshot, lock, sleep.
- **AirPods** — connect them and the notch throws itself open with the card a
  phone shows: the device large, a pool of light behind it, and left, right and
  case sweeping up to their real levels a beat later. It closes itself, unless
  you've reached for it. Only things you wear interrupt like this — a keyboard
  reconnecting gets a toast.
- **Devices** — every paired Bluetooth device, with the charge left in it.
  Connect or disconnect without leaving the notch, and get one warning when
  what's in your ears drops low.
- **Ambient events** — charger connected, battery low, AirPods connected, a
  discreet dot whenever the microphone is live, and a padlock when the screen
  locks (which springs open, with a greeting, when you come back).
- **Menu bar manners** — folds away the instant any menu opens, so it never lands
  on top of what you're reading.

## Installing

Grab `DynamicNotch-x.y.dmg` from [Releases](../../releases), drag it to
Applications, and open it. There's no Dock icon — look in the menu bar, and look
up.

**macOS will refuse to open it the first time.** The app isn't notarised, which
needs a paid Apple Developer account, so Gatekeeper has nothing to check it
against and blocks it. It isn't a warning about this app specifically; every
unnotarised app gets it. To get past it:

> System Settings → Privacy & Security → scroll down → **Open Anyway**

then open the app again. Or from Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Dynamic Notch.app"
```

The first time it reads what's playing, macOS asks for Automation permission for
Music and Spotify. Say yes, or the player stays empty.

## Building it

```sh
make run        # build, sign and launch
make install    # copy to /Applications and launch from there
make test       # unit tests
make logs       # stream the app's own log
make dmg        # drag-to-install .dmg in dist/, for a release
make zip        # zipped .app, signature preserved
```

`dist/` is ignored by git; release artifacts don't belong in the repo.

Release builds are signed **ad-hoc** rather than with an Apple Development
certificate. That certificate is personal, and for anyone else downloading the
app it buys nothing — without a Developer ID *and* notarisation, Gatekeeper
stops it either way. One consequence worth knowing: an ad-hoc signature changes
on every build, so macOS treats each new version as a different app and asks for
Automation permission again.

To ship it properly — no scary dialog, permissions that persist across updates —
needs the paid Apple Developer Program ($99/yr) for a *Developer ID Application*
certificate, then `ENABLE_HARDENED_RUNTIME=YES`, signing with that identity, and
`xcrun notarytool submit` + `xcrun stapler staple`. The `dmg` target is the right
place to add those three steps.

Requires Xcode 26+ and macOS 26+ (it uses Liquid Glass for the controls). On a Mac without a notch, a notch of
pleasant proportions is drawn in the same place.

The first time it asks Music or Spotify what's playing, macOS shows an Automation
prompt. Say yes, or the player stays empty — there's a button in the panel to
reopen that setting if you said no by accident.

## How it works

The interesting constraint is that **the window never resizes**. It is always the
size of the fully open panel, transparent, and click-through everywhere it isn't
drawing (`PassthroughView.hitTest`). Every open, close and morph is SwiftUI
animating a shape *inside* a static window, which is why it moves like one
continuous object instead of stepping a frame at a time.

The silhouette (`NotchShape`) has square top corners flush to the bezel, a rounded
underside, and two *concave* flares at the top so the black grows out of the
screen edge rather than sitting on it. At rest the flare radius is zero — that's
what lets it vanish into the hardware.

Every spring lives in `Motion.swift` and every material in `Glass.swift`. Views
never spell out their own curves or their own blurs, so the whole surface
accelerates and settles together.

The body itself is never glass, and never tinted — it has to be the same dead
black as the camera housing at every size, or the moment it grows past the
hardware you can see exactly where the notch ends. Colour lives on the contents:
Liquid Glass controls lit from above, a light leak around the album art, a
tinted scrubber. The one concession is a hairline of light along the bottom
curve, the way a real bezel edge catches it.

The flare radius is what makes it *swoop* rather than hang. At rest it's zero —
the shape is exactly the hardware notch and disappears into it. As the pill
grows, the flare opens to 13pt and the panel to 22pt, so the black reads as the
bezel melting outward instead of a bar taped under the menu bar.

| Concern | Where | How |
| --- | --- | --- |
| Notch measurement | `ScreenGeometry.swift` | `NSScreen.auxiliaryTopLeftArea` / `safeAreaInsets` |
| Hover | `NotchWindowController` | `NSEvent` global monitors — no Accessibility prompt |
| Music | `MediaService`, `MediaScripts` | Apple events, plus each app's distributed notifications for instant reactions |
| Volume | `AudioService` | CoreAudio property listeners — event-driven, no polling |
| Brightness | `BrightnessService` | `DisplayServices` / `CoreBrightness`, adaptively polled, with an ambient-light filter so auto-brightness never triggers a HUD |
| Battery | `PowerService` | `IOPSNotificationCreateRunLoopSource` |
| Devices | `BluetoothService` | `IOBluetooth` for instant connect/disconnect and for opening connections; `system_profiler SPBluetoothDataType` for battery, which IOBluetooth won't report |
| Timers | `TimerService` | one sleeping task per timer; the pill redraws from the clock |
| Clock app | `ClockBridge` | reads `mobiletimerd`'s preference domain — Clock has no scripting dictionary, no URL scheme and no public API |
| Stopwatch | `StopwatchService` | a start date and banked time; the views derive the reading from the clock, so nothing ticks and nothing drifts |
| Menu bar | `MenuBarGuard` | measures our own status item to find where the icons begin, and caps how far the pill spreads |
| Screen lock | `SessionService` | `com.apple.screenIsLocked` / `screenIsUnlocked` |
| Mic in use | `PrivacyService` | `kAudioDevicePropertyDeviceIsRunningSomewhere` — a state read, never a capture, so no prompt |
| Quick actions | `QuickActionsService` | `caffeinate` as a child process, `pmset`, `SACLockScreenImmediate` |

## Known limits

- Brightness HUDs are triggered heuristically. macOS won't tell us whether *you*
  or the ambient light sensor moved a level, so `BrightnessService` looks at the
  shape of the change: the sensor ramps tick after tick, a key press is one jump
  out of stillness. Good in practice, not infallible — each HUD has its own
  switch in Settings.
- macOS still shows its own volume and brightness HUD alongside this one.
  Suppressing it means unloading a system agent, which this app won't do to your
  Mac behind your back.
- The shelf holds references to your files, not copies. It survives quitting —
  only paths are saved — and anything moved or deleted elsewhere is dropped on
  the way back in rather than left as an entry that won't open.
- The closed pill won't spread over your menu bar icons, but it finds the
  boundary by measuring *our own* status item — the newest item sits at the left
  of the row, so ours usually is. An app that launches after this one takes that
  spot, and then its icon is the one at risk. Exact positions for everyone
  else's icons would need the Accessibility API.
- Menu bar icons that macOS itself hides behind the notch stay hidden. Reserving
  space with a spacer status item doesn't work — the bar stacks right-to-left,
  so a spacer only pushes its neighbours *further* under the notch.
- Clock's timers can be shown but not controlled: no scripting dictionary, no
  URL scheme, and the state belongs to a daemon that takes no instruction from
  other apps. The notch's own timer and stopwatch are fully operable instead.
- Nothing can draw on the lock screen — it's a separate secure context, not a
  window another app can out-rank. Raising the panel above `loginwindow`'s
  shield was tried and shows nothing. The padlock appears for a beat before the
  lock and springs open on return.
- Now Playing covers Music and Spotify. Browser and IINA audio are invisible,
  because the system-wide API for it is entitlement-gated as of macOS 15.4.
  `NowPlayingSource` is the seam where a wider backend would slot in.

## Licence

[MIT](LICENSE). Do what you like with it.

Not affiliated with Apple. AirPods, AirDrop, Mac, MacBook Pro and Spotify are
trademarks of their respective owners.
