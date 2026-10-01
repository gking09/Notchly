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

import Foundation


import Foundation

// MARK: - Pure menu model

/// Everything the status-bar menu reacts to. Plain values so the menu layout can be
/// built and tested without touching AppKit, Defaults or any manager.
struct StatusMenuState: Equatable {
    var version: String = "1.0"
    var build: String?
    var isNotchOpen = false
    var stashEnabled = true
    var hubEnabled = true
    var quickActionsEnabled = true
    var isTimerActive = false
    var isStopwatchActive = false
    var isMicMuted = false
    var isDarkMode = false
}

/// What choosing a menu item does. The controller maps each case onto the real app.
enum StatusMenuAction: Equatable {
    case toggleNotch
    case toggleStash
    case toggleHub
    case startTimer(minutes: Int)
    case cancelTimer
    case startStopwatch
    case resetStopwatch
    case toggleMicrophone
    case toggleDarkMode
    case screenshot
    case openSettings
    case openAbout
    case quit
}

/// A Command-modified key equivalent (the menu only uses plain Command shortcuts).
struct StatusMenuKeyEquivalent: Equatable {
    var key: String
}

struct StatusMenuItem: Equatable, Identifiable {
    enum Kind: Equatable {
        case header
        case action
        case separator
        case submenu
    }

    var id: String
    var kind: Kind = .action
    var title = ""
    /// SF Symbol name; every menu icon is a monochrome symbol except the header glyph.
    var symbol: String?
    var shortcut: StatusMenuKeyEquivalent?
    var isChecked = false
    var isEnabled = true
    var action: StatusMenuAction?
    var children: [StatusMenuItem] = []

    static func separator(_ id: String) -> StatusMenuItem {
        StatusMenuItem(id: id, kind: .separator)
    }
}

enum StatusMenuModel {
    static let timerMinutes = 5

    /// "Notchly 1.0 (3)" -- the build is left out when unknown or identical to the version.
    static func headerTitle(version: String, build: String?) -> String {
        guard let build, !build.isEmpty, build != version else { return "Notchly \(version)" }
        return "Notchly \(version) (\(build))"
    }

    static func items(for state: StatusMenuState) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = []

        items.append(StatusMenuItem(
            id: "header",
            kind: .header,
            title: headerTitle(version: state.version, build: state.build),
            isEnabled: false
        ))
        items.append(.separator("sep.header"))

        items.append(StatusMenuItem(
            id: "notch",
            title: state.isNotchOpen ? String(localized: "Close Notch") : String(localized: "Open Notch"),
            symbol: state.isNotchOpen ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
            action: .toggleNotch
        ))
        items.append(.separator("sep.notch"))

        items.append(StatusMenuItem(
            id: "stash",
            title: String(localized: "Stash"),
            symbol: "tray.and.arrow.down",
            isChecked: state.stashEnabled,
            action: .toggleStash
        ))
        items.append(StatusMenuItem(
            id: "hub",
            title: String(localized: "Hub"),
            symbol: "circle.grid.2x2",
            isChecked: state.hubEnabled,
            action: .toggleHub
        ))

        if state.quickActionsEnabled {
            items.append(StatusMenuItem(
                id: "quickActions",
                kind: .submenu,
                title: String(localized: "Quick Actions"),
                symbol: "bolt",
                children: quickActions(for: state)
            ))
        }

        items.append(.separator("sep.settings"))
        items.append(StatusMenuItem(
            id: "settings",
            title: String(localized: "Settings…"),
            symbol: "gearshape",
            shortcut: StatusMenuKeyEquivalent(key: ","),
            action: .openSettings
        ))
        items.append(StatusMenuItem(
            id: "about",
            title: String(localized: "About Notchly"),
            symbol: "info.circle",
            action: .openAbout
        ))
        items.append(.separator("sep.quit"))
        items.append(StatusMenuItem(
            id: "quit",
            title: String(localized: "Quit Notchly"),
            symbol: "power",
            shortcut: StatusMenuKeyEquivalent(key: "q"),
            action: .quit
        ))
        return items
    }

    static func quickActions(for state: StatusMenuState) -> [StatusMenuItem] {
        [
            StatusMenuItem(
                id: "quick.timer",
                title: state.isTimerActive
                    ? String(localized: "Cancel Timer")
                    : String(localized: "Start \(timerMinutes)-Minute Timer"),
                symbol: "timer",
                action: state.isTimerActive ? .cancelTimer : .startTimer(minutes: timerMinutes)
            ),
            StatusMenuItem(
                id: "quick.stopwatch",
                title: state.isStopwatchActive
                    ? String(localized: "Reset Stopwatch")
                    : String(localized: "Start Stopwatch"),
                symbol: "stopwatch",
                action: state.isStopwatchActive ? .resetStopwatch : .startStopwatch
            ),
            .separator("quick.sep"),
            StatusMenuItem(
                id: "quick.mic",
                title: state.isMicMuted ? String(localized: "Unmute Microphone") : String(localized: "Mute Microphone"),
                symbol: state.isMicMuted ? "mic.slash" : "mic",
                action: .toggleMicrophone
            ),
            StatusMenuItem(
                id: "quick.dark",
                title: String(localized: "Dark Mode"),
                symbol: "circle.lefthalf.filled",
                isChecked: state.isDarkMode,
                action: .toggleDarkMode
            ),
            StatusMenuItem(
                id: "quick.screenshot",
                title: String(localized: "Screenshot to Clipboard"),
                symbol: "camera.viewfinder",
                action: .screenshot
            ),
        ]
    }
}
