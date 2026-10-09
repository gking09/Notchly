<p align="center">
  <img src=".github/assets/notchly-logo.png" alt="Notchly logo" width="120">
</p>
<h1 align="center">Notchly</h1>
<p align="center">
  A quiet, glass-and-monochrome control surface for the MacBook notch.<br>
  My own take on an open-source app I already loved.
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-lightgrey?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-orange?style=flat-square">
  <img alt="License GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square">
</p>

<!-- Add screenshots or a short screen recording here: the closed notch, the Home tab with the Hub, lyrics mode, and the Stash. -->

Notchly turns the notch on a MacBook into something useful: now-playing and synced lyrics, live activities for battery, timers and Focus, volume and brightness HUDs, and a small tray where you can park text and files. It stays out of the way until you need it, then expands with spring animations. The notch stays pure black so it melts into the hardware, and everything drawn on it is translucent white or silver glass. Colour appears only where it means something: battery state, screen recording, and camera and microphone privacy.

---

## Why I made my own version

I didn't start from a blank page. I started from [Atoll](https://github.com/Ebullioscopic/Atoll), an open-source "Dynamic Island for macOS" app that I already liked using. It is built on [boring.notch](https://github.com/TheBoredTeam/boring.notch).

Three things pushed me to fork it instead of just installing it:

1. **I wanted to build the skill.** Reading, taking apart and reshaping a real, large SwiftUI/AppKit codebase teaches things a tutorial can't: window management, event monitoring, IOKit, animation, Xcode project structure, and how to remove code without breaking everything around it.
2. **I wanted to personalise something I already liked.** I liked the idea and the notch interactions. I didn't like that it had grown into an everything-app.
3. **I didn't want all the features, and I wanted some of my own.** The original had a terminal, clipboard history, system stats, notes, file shelf, lock-screen widgets, an extension system and more. I wanted only the notch things. Then I wanted things that don't exist upstream, built the way I'd use them.

So Notchly is deliberately **smaller and more opinionated**: a notch-only app with its own look, its own settings, and a handful of features that are mine.

## What's different from Atoll

**Removed on purpose** (one at a time, with the build and tests kept green after each): terminal, clipboard history, system stats, notes, the file shelf and AirDrop, lock-screen widgets, color picker, keep-awake, LLM usage tracking, screen assistant, per-app volume, the extension system, the calendar, the old timer tab, the updater, and the profile-picker/Pro/donate onboarding.

**Added or rebuilt for Notchly**

| | |
|---|---|
| **Look** | A soft-glass, monochrome design language, new logo and menu bar glyph, and spring-based motion everywhere (respecting Reduce Motion). |
| **Hub** | A new centrepiece on the Home tab: a large animated clock with a context-aware chip row (battery, timer, stopwatch, Focus, paused music, Stash) that only shows what's relevant. |
| **Lyrics mode** | A lyrics button on the player takes over the centre of the open notch with rolling, time-synced lyrics. It works with Apple Music, Spotify and, through Now Playing, YouTube in a browser, with cleanup for messy video titles, an on-disk cache and graceful "not found / unsynced" states. |
| **Quick Actions** | A row of glass buttons: timer, stopwatch, mute mic, dark mode, screenshot, sleep display, and run any Shortcuts shortcut. |
| **Timer and stopwatch live activities** | A progress ring and countdown beside the notch, with a "Done" state; the stopwatch has laps. |
| **Battery extras** | Time remaining or to full, charger wattage, battery health and cycle count, charge-held detection, low/critical/full alerts, and low-battery alerts for Bluetooth devices. |
| **Stash** | A temporary tray for text, links, images and files. Drop things on the notch, click to copy back, drag them out again. Items expire on a retention you choose. |
| **Notch-safe live activities** | A shared layout keeps all content in wings either side of the hardware notch, so nothing hides behind it. HUDs and music activities were redone to match. |
| **Efficiency mode** | Gates background work on display sleep, battery and Low Power Mode. |
| **Settings, menu, onboarding** | Rebuilt from scratch with a custom settings window (search, eight pages), a custom menu bar menu, and a three-step first-launch flow. |

## Features at a glance

- **Music:** now-playing and controls for Apple Music, Spotify, YouTube Music, Amazon Music, TIDAL, Cider, and anything that reports to macOS Now Playing. Waveform scrubber, optional lyrics, standard and minimalistic layouts.
- **Live activities in the closed notch:** battery and charging, Focus, downloads (beta), screen recording, camera and microphone privacy, Bluetooth devices, network status, Caps Lock, lock and unlock, timer and stopwatch, Stash confirmations.
- **HUD replacements:** volume, brightness and keyboard backlight in the notch, or as a vertical, circular or custom OSD. Optional BetterDisplay and Lunar support.
- **Gestures and shortcuts:** swipe to open and close, horizontal swipes to skip, haptics, global shortcuts.

## Requirements

- macOS 14.0 or later (best on macOS 15+).
- A MacBook with a notch.
- Xcode 15 or later to build it.
- Permissions are requested as needed: Accessibility, Camera (webcam mirror), Bluetooth, Automation (media control and the dark-mode quick action), Full Disk Access (downloads activity).

## Build and run

```bash
git clone https://github.com/gking09/Notchly.git
cd Notchly
open DynamicIsland.xcodeproj
```

Pick your own team under **Signing & Capabilities**, then press ⌘R. Or from the command line:

```bash
xcodebuild -scheme DynamicIsland -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

The Xcode target and scheme keep the internal name `DynamicIsland` (renaming them would only add churn); the built app is **Notchly.app**. An unsigned build can be opened with right-click → Open. The Metal toolchain is needed for the visualizer shader: `xcodebuild -downloadComponent MetalToolchain`.

Run the unit tests with:

```bash
xcodebuild -scheme DynamicIsland -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO test -only-testing:DynamicIslandTests
```

## Using it

- Hover near the notch to expand it, and click to interact.
- Use the lyrics button next to the song title to roll lyrics through the notch. For YouTube in a browser, set **Settings → Music → Source** to *Now Playing*.
- Drag files or text onto the notch to stash them.
- Open **Settings** from the menu bar icon (or ⌘,) to change layout, HUDs, battery alerts, shortcuts and efficiency options.

## Status

This is a personal project that I use daily and keep tinkering with. It builds and its unit tests pass, but it hasn't had broad testing across Mac models or macOS versions, so expect rough edges. Issues and suggestions are welcome.

## Ideas I may build next

Meeting countdown, a Pomodoro mode, more Quick Actions, theme presets, and a keyboard-driven mode. These are ideas, not promises.

## Credits and license

Notchly is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full terms and [NOTICE](NOTICE) for attribution. Because it is GPL-3.0 software, any distributed modification must stay GPL-3.0 and ship with its source.

**Lineage.** Notchly is a fork of [**Atoll**](https://github.com/Ebullioscopic/Atoll) by Ebullioscopic, which builds on [**boring.notch**](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam. Notchly would not exist without either of them, and a large part of the notch plumbing here is their work. Thank you both.

**Also credited** for code and ideas that remain in this project:

- [**Alcove**](https://tryalcove.com): inspiration for the minimalistic layout.
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow): window rendering for HUD overlays and the lock-screen live activity.
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio): the live music visualizer was adapted from it.
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch): battery HUD designs.
- [**LRCLIB**](https://lrclib.net) and NetEase Cloud Music for lyrics lookups.
- Swift packages: Defaults, KeyboardShortcuts, LaunchAtLogin-Modern, LottieUI, MacroVisionKit, Pow and swiftui-introspect.
- The "Fingerprint Scan" Lottie animation by Eddy Gann (Lottie Simple License, see NOTICE).

"Dynamic Island" is an Apple trademark. Notchly is not affiliated with or endorsed by Apple.
