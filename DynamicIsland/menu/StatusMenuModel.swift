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
    /// Foundry's entry; nil while the integration is off, so the menu has no Foundry item.
    var foundry: FoundryMenuState?
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
    case openFoundry
    case openFoundryNextUp
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

        if let foundry = state.foundry {
            items.append(StatusMenuItem(
                id: "foundry",
                kind: .submenu,
                title: String(localized: "Foundry"),
                symbol: "square.stack.3d.up",
                children: foundryItems(for: foundry)
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

    /// The longest line the Foundry submenu shows before cutting it with an ellipsis.
    static let foundryTitleLimit = 48

    static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(1, limit - 1))).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    static func foundryItems(for foundry: FoundryMenuState) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = []
        let next = foundry.nextUpTitle.map { truncated($0, limit: foundryTitleLimit) }.flatMap { $0.isEmpty ? nil : $0 }

        // A disabled header: information, not something to choose.
        items.append(StatusMenuItem(
            id: "foundry.next",
            kind: .header,
            title: next.map { String(localized: "Next up: \($0)") } ?? String(localized: "Nothing queued"),
            isEnabled: false
        ))
        if foundry.attentionCount > 0 {
            items.append(StatusMenuItem(
                id: "foundry.attention",
                title: foundry.attentionCount == 1
                    ? String(localized: "1 item needs attention")
                    : String(localized: "\(foundry.attentionCount) items need attention"),
                symbol: "exclamationmark.triangle",
                isEnabled: false
            ))
        }
        items.append(.separator("foundry.sep"))
        items.append(StatusMenuItem(
            id: "foundry.open",
            title: String(localized: "Open Foundry"),
            symbol: "arrow.up.forward.app",
            action: .openFoundry
        ))
        if next != nil {
            items.append(StatusMenuItem(
                id: "foundry.openNext",
                title: String(localized: "Open Next Up Project"),
                symbol: "arrow.right.circle",
                action: .openFoundryNextUp
            ))
        }
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
