<p align="center">
  <img src=".github/assets/notchly-logo.png" alt="Notchly logo" width="120">
</p>
<h1 align="center">Notchly</h1>
<p align="center">
  A soft-glass, monochrome command surface for the MacBook notch.
</p>

Notchly turns the notch on MacBook Pro and Air models into a small, focused surface for media, system events and quick utilities. It stays out of the way until you need it, then expands with native SwiftUI spring animations. The visual language is deliberately quiet: the notch stays pure black so it melts into the hardware, and everything drawn on it is translucent white or silver glass. Colour is kept only where it carries meaning (battery state, screen recording, camera and microphone privacy).

Notchly is a **notch-only** app. The non-notch features of the project it was forked from have been removed.

> Notchly is a fork of [Atoll](https://github.com/Ebullioscopic/Atoll) by Ebullioscopic (GPL-3.0). See [Credits & License](#credits--license).

## Features

**Music**
- Media controls and now-playing for Apple Music, Spotify, YouTube Music, Amazon Music, TIDAL, Cider, and any app that reports to macOS Now Playing.
- Synced lyrics (side panel, line under the notch, or pinned while closed), optional Spotify canvas artwork, waveform scrubber, AirPlay and output picker.
- Standard layout and a compact minimalistic layout.

**Hub** (centre of the Home tab)
- A large glanceable clock in a soft-glass card: hours and minutes that roll over with numeric transitions, an optional seconds readout, the date line, a slowly breathing monochrome glow, and a gentle lean toward the pointer.
- A context-aware chip row under the clock that only shows what is relevant right now and springs in and out: battery (charging bolt, time remaining or to full, or when it runs low), a running timer or stopwatch (click to open it), Stash item count (click to open the Stash), Focus, and paused music (click to resume). With nothing to report, only the clock shows.
- Settings: show seconds, 12 / 24-hour (follows the system by default), show the date, and which chips to show. Not shown in the Minimalistic layout.

**Live activities** (shown in the closed notch)
- Battery and charging, low-battery and full-battery alerts.
- Focus / Do Not Disturb.
- Downloads (beta; Safari, Chrome and Chromium-based browsers, Firefox).
- Screen recording indicator.
- Privacy indicators for camera and microphone use.
- Bluetooth device connections, including AirPods battery.
- Network connectivity (Wi-Fi, hotspot, no connection).
- Caps Lock indicator.
- Lock and unlock animation with optional lock sounds.
- Timer countdown.

**HUD replacements**
- Volume, brightness and keyboard backlight shown in the notch, or as a vertical, circular or custom OSD.
- Optional BetterDisplay and Lunar integration for external displays.

**Tabs and tools**
- Timer with presets and a ruler-style picker.
- Webcam mirror.
- Stash: a temporary tray in the notch for text, links, images and files. Drop things on the notch (or add the clipboard on demand), click to copy back, drag out to other apps; items expire on a retention you choose.
- Global keyboard shortcuts, gesture controls (swipe to open/close, horizontal swipes to skip), haptics, and per-feature toggles in Settings.

## Requirements
- macOS 14.0 or later (optimised for macOS 15+).
- A MacBook with a notch.
- Xcode 15 or later to build from source.
- Permissions as needed: Accessibility, Camera, Screen Recording, Music / media.

## Build from source
```bash
# from the root of this repository
xcodebuild -scheme DynamicIsland -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```
The Xcode target and scheme keep the internal name `DynamicIsland`. Open `DynamicIsland.xcodeproj` in Xcode to run and sign the app with your own team. Swift packages (Defaults, Sparkle, KeyboardShortcuts, LottieUI, Pow, SkyLightWindow, MacroVisionKit, LaunchAtLogin, swiftui-introspect) resolve automatically.

## Quick start
- Hover near the notch to expand it; click to interact.
- Use the tab selector for Home and Stash.
- Adjust layout, appearance, HUDs and shortcuts from Settings (gear icon in the expanded notch).

## Gesture controls
- Two-finger swipe down opens the notch when hover-to-open is disabled; swipe up closes it.
- Enable horizontal media gestures in **Settings > General > Gesture control** to use the music pane as a trackpad for previous/next or 10-second seeks.

## Troubleshooting
- After granting Accessibility or Screen Recording, quit and relaunch the app.
- Media not responding: make sure the player is running and media permission has been granted.

## Credits & License

Notchly is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE) for the full terms and [NOTICE](NOTICE) for attribution details. Because it is GPL-3.0 software, any distributed modification must remain GPL-3.0 and ship with its source.

**Lineage.** Notchly is a fork of [**Atoll**](https://github.com/Ebullioscopic/Atoll) by Ebullioscopic, which in turn builds on [**boring.notch**](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam. Atoll would not exist without boring.notch, and Notchly would not exist without either of them.

**Acknowledgments** for code and ideas that remain in this project:

- [**boring.notch**](https://github.com/TheBoredTeam/boring.notch) - foundational codebase: media player integration, notch interaction model, calendar display and many architectural patterns.
- [**Atoll**](https://github.com/Ebullioscopic/Atoll) - the live activities, HUD system, lyrics, timer, Bluetooth, lock screen and settings work this fork is built on.
- [**Alcove**](https://tryalcove.com) - inspiration for the minimalistic layout.
- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) - window rendering for HUD overlays and the lock screen live activity.
- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) - the live music visualizer was adapted from this project.
- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) - battery HUD designs.
- Sparkle, Defaults, KeyboardShortcuts, LottieUI, Pow, MacroVisionKit and LaunchAtLogin-Modern for the Swift packages the app depends on.
- The "Fingerprint Scan" Lottie animation by Eddy Gann (Lottie Simple License, see NOTICE).
