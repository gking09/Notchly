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

import AVFoundation
import AppKit
import Defaults
import SwiftUI

/// Home & Hub: what the Home tab shows, the Hub clock and chips, the Quick
/// Actions row, and the webcam mirror.
struct NotchlyHomeHubPage: View {
    typealias I = Item

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var webcamManager = WebcamManager.shared

    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.enableHub) private var enableHub
    @Default(.hubTimeFormat) private var timeFormat
    @Default(.hubHiddenChips) private var hiddenChips
    @Default(.enableQuickActions) private var enableQuickActions
    @Default(.quickActionsOrder) private var order
    @Default(.quickActionsHidden) private var hiddenActions
    @Default(.quickActionsShortcutName) private var shortcutName
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.mirrorShape) private var mirrorShape
    @Default(.selectedCameraID) private var selectedCameraID
    @Default(.showMirror) private var showMirror

    @State private var soundRefresh = 0

    private var orderedActions: [QuickAction] {
        QuickActionsLayout.normalizedOrder(order)
    }

    var body: some View {
        NotchlyPageScroll(page: .homeHub) {
            homeCard
            if enableHub {
                clockCard
                chipsCard
            }
            quickActionsCard
            if enableQuickActions {
                actionButtonsCard
                shortcutAndTimerCard
            }
            mirrorCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: enableHub)
        .animation(NotchlyTheme.Motion.snappy, value: enableQuickActions)
    }

    // MARK: Home tab

    private var homeCard: some View {
        NotchlySettingsCard(
            "Home tab",
            footer: enableMinimalisticUI
                ? "Minimalistic UI is on, so the Hub and Quick Actions are hidden in the notch."
                : "The Hub is a big clock in the middle of Home, with chips for whatever matters right now."
        ) {
            I.hub.toggle("A clock with chips for timers, focus, battery and more.", key: .enableHub)
            I.mediaPlayer.toggle(
                "Show the music player on the Home tab.",
                isEnabled: !enableMinimalisticUI,
                key: .showStandardMediaControls
            )
            I.autoHidePlayer.toggle(
                "Hide the player when nothing is playing. Off keeps it visible with placeholder text.",
                isEnabled: !enableMinimalisticUI && showStandardMediaControls,
                key: .autoHideInactiveNotchMediaPlayer
            )
        }
    }

    // MARK: Clock

    private var clockCard: some View {
        NotchlySettingsCard("Clock") {
            I.showSeconds.toggle("Tick every second.", key: .hubShowSeconds)
            I.timeFormat.picker(
                "Follow system uses the 12 or 24-hour setting of your Mac.",
                selection: $timeFormat,
                options: Array(HubTimeFormat.allCases),
                style: .menu,
                label: { $0.title }
            )
            I.showDate.toggle("Show the day and date under the time.", key: .hubShowDate)
        }
    }

    // MARK: Chips

    private var chipsCard: some View {
        NotchlySettingsCard(
            "Chips",
            footer: "Chips only appear while they have something to show. Up to three show at once, most important first."
        ) {
            ForEach(HubChip.priority) { chip in
                NotchlySettingRow(
                    chip.title,
                    subtitle: chip.detail,
                    highlightID: chip == HubChip.priority.first ? I.chips.highlightID : nil,
                    symbol: Self.symbol(for: chip)
                ) {
                    Toggle(chip.title, isOn: chipBinding(for: chip))
                        .labelsHidden()
                        .toggleStyle(.notchly)
                }
            }
        }
    }

    static func symbol(for chip: HubChip) -> String {
        switch chip {
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .focus: return "moon"
        case .battery: return "battery.75percent"
        case .music: return "pause.circle"
        case .stash: return "tray"
        }
    }

    private func chipBinding(for chip: HubChip) -> Binding<Bool> {
        Binding(
            get: { !hiddenChips.contains(chip) },
            set: { isOn in
                var updated = hiddenChips.filter { $0 != chip }
                if !isOn { updated.append(chip) }
                hiddenChips = updated
            }
        )
    }

    // MARK: Quick actions

    private var quickActionsCard: some View {
        NotchlySettingsCard(
            "Quick actions",
            footer: "A row of small glass buttons at the top of the Home tab. Not shown in Minimalistic UI."
        ) {
            I.quickActions.toggle("Show the row of quick action buttons.", key: .enableQuickActions)
        }
    }

    private var actionButtonsCard: some View {
        NotchlySettingsCard("Buttons", footer: "Choose which buttons appear and in what order, left to right.") {
            ForEach(orderedActions) { action in
                NotchlySettingRow(action.title, subtitle: action.detail, symbol: action.symbolName) {
                    HStack(spacing: 4) {
                        Button {
                            move(action, by: -1)
                        } label: {
                            Image(systemName: "chevron.up").frame(width: 14, height: 14)
                        }
                        .buttonStyle(.notchly(.quiet))
                        .disabled(orderedActions.first == action)
                        .help("Move earlier")

                        Button {
                            move(action, by: 1)
                        } label: {
                            Image(systemName: "chevron.down").frame(width: 14, height: 14)
                        }
                        .buttonStyle(.notchly(.quiet))
                        .disabled(orderedActions.last == action)
                        .help("Move later")

                        Toggle(action.title, isOn: actionBinding(for: action))
                            .labelsHidden()
                            .toggleStyle(.notchly)
                            .padding(.leading, 6)
                    }
                }
            }
        }
    }

    private func actionBinding(for action: QuickAction) -> Binding<Bool> {
        Binding(
            get: { !hiddenActions.contains(action) },
            set: { isOn in
                var updated = hiddenActions.filter { $0 != action }
                if !isOn { updated.append(action) }
                hiddenActions = updated
            }
        )
    }

    private func move(_ action: QuickAction, by offset: Int) {
        withAnimation(.smooth) {
            order = QuickActionsLayout.moved(order, action: action, by: offset)
        }
    }

    private var shortcutAndTimerCard: some View {
        let customPath = UserDefaults.standard.string(forKey: "customTimerSoundPath")
        return NotchlySettingsCard(
            "Shortcut & timer",
            footer: "macOS has no public switch for Do Not Disturb. Make a Shortcut that sets a Focus (or anything else) and enter its exact name. The button stays hidden until a name is set."
        ) {
            I.shortcutName.row("The Shortcut the Run Shortcut button starts.") {
                NotchlyTextField(placeholder: "Shortcut name", text: $shortcutName)
            }
            I.timerLiveActivity.toggle(
                "Show a running timer or stopwatch in the closed notch.",
                isOn: $coordinator.timerLiveActivityEnabled
            )
            I.timerSound.row(
                customPath.map { "Custom: \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? "Default: timer.mp3. Plays once when a timer ends."
            ) {
                HStack(spacing: 6) {
                    Button("Choose file", action: selectCustomTimerSound)
                        .buttonStyle(.notchly(.standard))
                    Button("Reset") {
                        UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                        soundRefresh += 1
                    }
                    .buttonStyle(.notchly(.quiet))
                    .disabled(customPath == nil)
                }
            }
            .id(soundRefresh)
        }
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            soundRefresh += 1
        }
    }

    // MARK: Webcam mirror

    private var hasVideoInput: Bool { AVCaptureDevice.default(for: .video) != nil }

    private var mirrorCard: some View {
        NotchlySettingsCard(
            "Mirror",
            footer: hasVideoInput ? "A quick look at yourself from the Home tab, using the front camera." : "No camera was found on this Mac."
        ) {
            I.mirror.toggle("Show a live camera preview on the Home tab.", isEnabled: hasVideoInput, key: .showMirror)
            I.mirrorShape.picker(
                selection: $mirrorShape,
                options: [.circle, .rectangle],
                style: .segmented,
                label: { $0 == .circle ? String(localized: "Circle") : String(localized: "Square") }
            )
            if webcamManager.cameraAvailable {
                I.mirrorCamera.picker(
                    selection: $selectedCameraID,
                    options: webcamManager.availableCameras.map(\.uniqueID),
                    label: { id in webcamManager.availableCameras.first { $0.uniqueID == id }?.localizedName ?? (id.isEmpty ? String(localized: "Default") : id) }
                )
                .onChange(of: selectedCameraID) {
                    if showMirror {
                        webcamManager.stopSession()
                        webcamManager.startSession()
                    }
                }
            }
        }
    }
}

// MARK: - Search items

extension NotchlyHomeHubPage {
    enum Item {
        static let hub = NotchlySettingItem(.homeHub, "Show the Hub", keywords: ["hub", "clock", "centre", "center", "home"])
        static let mediaPlayer = NotchlySettingItem(.homeHub, "Show media controls in Notchly", keywords: ["music player", "home tab", "media", "now playing", "layout"])
        static let autoHidePlayer = NotchlySettingItem(.homeHub, "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media", "player"])
        static let showSeconds = NotchlySettingItem(.homeHub, "Show seconds", keywords: ["hub", "clock", "seconds"])
        static let timeFormat = NotchlySettingItem(.homeHub, "Time format", keywords: ["hub", "clock", "12-hour", "24-hour", "am pm", "military"])
        static let showDate = NotchlySettingItem(.homeHub, "Show the date", keywords: ["hub", "clock", "date", "day"])
        static let chips = NotchlySettingItem(.homeHub, "Hub chips", keywords: ["hub", "chips", "timer", "battery", "stash", "focus", "paused music", "stopwatch"])
        static let quickActions = NotchlySettingItem(.homeHub, "Show Quick Actions row", keywords: ["quick actions", "buttons", "row", "home", "reorder"])
        static let shortcutName = NotchlySettingItem(.homeHub, "Shortcut name", keywords: ["shortcuts", "focus", "do not disturb", "automation", "run shortcut"])
        static let timerLiveActivity = NotchlySettingItem(.homeHub, "Timer & stopwatch live activity", keywords: ["timer", "stopwatch", "live activity", "closed notch"])
        static let timerSound = NotchlySettingItem(.homeHub, "Timer sound", keywords: ["timer", "sound", "alarm", "chime", "audio file"])
        static let mirror = NotchlySettingItem(.homeHub, "Dynamic mirror", keywords: ["mirror", "reflection", "webcam", "camera", "selfie"])
        static let mirrorShape = NotchlySettingItem(.homeHub, "Mirror shape", keywords: ["mirror shape", "circle", "square", "rectangle", "webcam"])
        static let mirrorCamera = NotchlySettingItem(.homeHub, "Mirror camera", keywords: ["camera", "webcam", "mirror", "device"])
    }

    static let items: [NotchlySettingItem] = [
        Item.hub, Item.mediaPlayer, Item.autoHidePlayer,
        Item.showSeconds, Item.timeFormat, Item.showDate, Item.chips,
        Item.quickActions, Item.shortcutName, Item.timerLiveActivity, Item.timerSound,
        Item.mirror, Item.mirrorShape, Item.mirrorCamera,
    ]
}
