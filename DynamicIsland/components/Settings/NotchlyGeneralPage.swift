/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import Defaults
import LaunchAtLogin
import SwiftUI

/// General: startup, which display the notch lives on, how it opens and closes,
/// and trackpad gestures.
struct NotchlyGeneralPage: View {
    typealias I = Item

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }

    @Default(.showOnAllDisplays) private var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) private var automaticallySwitchDisplay
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @Default(.openNotchOnHover) private var openNotchOnHover
    @Default(.minimumHoverDuration) private var minimumHoverDuration
    @Default(.enableGestures) private var enableGestures
    @Default(.enableHorizontalMusicGestures) private var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) private var musicGestureBehavior
    @Default(.gestureSensitivity) private var gestureSensitivity

    var body: some View {
        NotchlyPageScroll(page: .general) {
            startupCard
            displayCard
            openingCard
            gesturesCard
            performanceCard
        }
        .onChange(of: showOnAllDisplays) {
            NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
        }
        .onChange(of: automaticallySwitchDisplay) {
            NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
        }
        .onChange(of: externalDisplayStyle) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: minimumHoverDuration) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: openNotchOnHover) {
            // Without hover, gestures are the only way to open the notch.
            if !openNotchOnHover { enableGestures = true }
        }
        .onChange(of: NSScreen.screens) {
            screens = NSScreen.screens.compactMap { $0.localizedName }
        }
    }

    // MARK: Startup

    private var startupCard: some View {
        NotchlySettingsCard("Startup") {
            I.launchAtLogin.row("Open Notchly automatically when you log in.") {
                LaunchAtLogin.Toggle { Text(I.launchAtLogin.title) }
                    .labelsHidden()
                    .toggleStyle(.notchly)
            }
            I.menuBarIcon.toggle("Keep a Notchly icon in the menu bar.", key: .menubarIcon)
        }
    }

    // MARK: Display

    private var displayCard: some View {
        NotchlySettingsCard("Display") {
            I.allDisplays.toggle("Show a notch on every screen instead of just one.", key: .showOnAllDisplays)
            I.specificDisplay.picker(
                "Which screen the notch appears on.",
                isEnabled: !showOnAllDisplays,
                selection: $coordinator.preferredScreen,
                options: screenOptions,
                label: { $0 }
            )
            I.autoSwitch.toggle(
                "Follow the screen you are working on.",
                isEnabled: !showOnAllDisplays,
                key: .automaticallySwitchDisplay
            )
            I.externalStyle.picker(
                externalDisplayStyle.description,
                key: .externalDisplayStyle,
                options: ExternalDisplayStyle.allCases,
                label: { $0.localizedName }
            )
            I.hideUntilHovered.toggle(
                "On screens without a notch, slide up and hide until you hover over the top edge.",
                key: .hideNonNotchUntilHover
            )
            I.hideInCaptures.toggle(
                "Keep the notch out of screenshots and screen recordings.",
                key: .hideDynamicIslandFromScreenCapture
            )
        }
    }

    /// The connected screens, plus the saved choice when that screen is unplugged.
    private var screenOptions: [String] {
        var options = screens
        if !coordinator.preferredScreen.isEmpty, !options.contains(coordinator.preferredScreen) {
            options.append(coordinator.preferredScreen)
        }
        return options
    }

    // MARK: Opening & closing

    private var openingCard: some View {
        NotchlySettingsCard("Opening & closing") {
            I.openOnHover.toggle("Open the notch when the pointer rests on it.", key: .openNotchOnHover)
            I.hoverDelay.slider(
                "How long to hover before it opens.",
                isEnabled: openNotchOnHover,
                key: .minimumHoverDuration,
                range: 0...1,
                step: 0.1,
                valueLabel: { String(format: "%.1fs", $0) }
            )
            I.extendHover.toggle("Make the area that triggers the notch a little bigger.", key: .extendHoverArea)
            I.rememberTab.toggle("Reopen on the tab you used last instead of Home.", isOn: $coordinator.openLastTabByDefault)
            I.haptics.toggle("A small tap on the trackpad when the notch opens.", key: .enableHaptics)
        }
    }

    // MARK: Gestures

    private var gesturesCard: some View {
        NotchlySettingsCard(
            "Gestures",
            footer: "Two-finger swipe down on the notch opens it and swipe up closes it when Open on hover is off."
        ) {
            I.gestures.toggle(
                "Two-finger swipes on the notch. Always on while Open on hover is off.",
                isEnabled: openNotchOnHover,
                key: .enableGestures
            )
            if enableGestures {
                I.closeGesture.toggle("Swipe up on the notch to close it.", key: .closeGestureEnabled)
                I.sensitivity.picker(
                    "How far you need to swipe.",
                    selection: sensitivityBinding,
                    options: [100.0, 200.0, 300.0],
                    style: .segmented,
                    label: Self.sensitivityLabel(_:)
                )
                I.reverseScroll.toggle("Flip the direction for opening and closing.", key: .reverseScrollGestures)
                I.mediaGestures.toggle("Swipe sideways on the notch to change what is playing.", key: .enableHorizontalMusicGestures)
                if enableHorizontalMusicGestures {
                    I.skipBehavior.picker(
                        musicGestureBehavior.description,
                        key: .musicGestureBehavior,
                        options: Array(MusicSkipBehavior.allCases),
                        label: { $0.displayName }
                    )
                    I.reverseSwipe.toggle("Flip the direction of the sideways swipe.", key: .reverseSwipeGestures)
                }
            }
        }
    }

    // MARK: Performance

    private var performanceCard: some View {
        NotchlySettingsCard(
            "Performance",
            footer: "Slows background checks and trims visualizer and animation frame rates. Everything pauses while the display sleeps, whatever this is set to."
        ) {
            I.efficiencyMode.toggle(
                "Reduce background activity on battery and in Low Power Mode.",
                key: .efficiencyMode
            )
        }
    }

    private var sensitivityBinding: Binding<Double> {
        Binding(get: { gestureSensitivity }, set: { gestureSensitivity = $0 })
    }

    static func sensitivityLabel(_ value: Double) -> String {
        switch value {
        case ..<150: return String(localized: "High")
        case ..<250: return String(localized: "Medium")
        default: return String(localized: "Low")
        }
    }
}

// MARK: - Search items

extension NotchlyGeneralPage {
    enum Item {
        static let launchAtLogin = NotchlySettingItem(.general, "Launch at login", keywords: ["autostart", "startup", "open at login"])
        static let menuBarIcon = NotchlySettingItem(.general, "Menu bar icon", keywords: ["menubar", "status bar", "icon"])
        static let allDisplays = NotchlySettingItem(.general, "Show on all displays", keywords: ["multi-display", "external monitor", "screens"])
        static let specificDisplay = NotchlySettingItem(.general, "Show on a specific display", keywords: ["preferred screen", "display picker", "monitor"])
        static let autoSwitch = NotchlySettingItem(.general, "Automatically switch displays", keywords: ["auto switch", "follow", "displays"])
        static let externalStyle = NotchlySettingItem(.general, "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"])
        static let hideUntilHovered = NotchlySettingItem(.general, "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"])
        static let hideInCaptures = NotchlySettingItem(.general, "Hide Notchly during screenshots & recordings", keywords: ["privacy", "screenshot", "recording", "screen capture"])
        static let openOnHover = NotchlySettingItem(.general, "Open notch on hover", keywords: ["hover to open", "auto open", "pointer"])
        static let hoverDelay = NotchlySettingItem(.general, "Minimum hover duration", keywords: ["hover", "delay", "sensitivity", "seconds"])
        static let extendHover = NotchlySettingItem(.general, "Extend hover area", keywords: ["hover", "cursor", "bigger"])
        static let rememberTab = NotchlySettingItem(.general, "Remember last tab", keywords: ["last tab", "home", "reopen"])
        static let haptics = NotchlySettingItem(.general, "Enable haptics", keywords: ["haptic", "feedback", "trackpad"])
        static let gestures = NotchlySettingItem(.general, "Enable gestures", keywords: ["gestures", "trackpad", "swipe", "two-finger"])
        static let closeGesture = NotchlySettingItem(.general, "Close gesture", keywords: ["swipe up", "swipe", "close"])
        static let sensitivity = NotchlySettingItem(.general, "Gesture sensitivity", keywords: ["gesture", "swipe", "high", "medium", "low"])
        static let reverseScroll = NotchlySettingItem(.general, "Reverse open/close gestures", keywords: ["reverse", "scroll", "open", "close", "natural scrolling"])
        static let mediaGestures = NotchlySettingItem(.general, "Change media with horizontal swipes", keywords: ["media", "swipe", "skip", "next", "previous", "horizontal"])
        static let skipBehavior = NotchlySettingItem(.general, "Swipe skip behavior", keywords: ["track skip", "10 seconds", "gesture", "media"])
        static let reverseSwipe = NotchlySettingItem(.general, "Reverse swipe direction", keywords: ["reverse", "swipe", "media"])
        static let efficiencyMode = NotchlySettingItem(.general, "Efficiency mode", keywords: ["battery", "low power", "performance", "cpu", "energy", "background activity", "frame rate", "visualizer"])
    }

    static let items: [NotchlySettingItem] = [
        Item.launchAtLogin, Item.menuBarIcon,
        Item.allDisplays, Item.specificDisplay, Item.autoSwitch, Item.externalStyle, Item.hideUntilHovered, Item.hideInCaptures,
        Item.openOnHover, Item.hoverDelay, Item.extendHover, Item.rememberTab, Item.haptics,
        Item.gestures, Item.closeGesture, Item.sensitivity, Item.reverseScroll, Item.mediaGestures, Item.skipBehavior, Item.reverseSwipe,
        Item.efficiencyMode,
    ]
}
