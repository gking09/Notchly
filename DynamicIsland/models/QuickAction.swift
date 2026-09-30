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
import Defaults

/// One button in the Home tab's Quick Actions row.
///
/// Only actions reachable through public API are offered. There is no Do Not
/// Disturb toggle because macOS exposes none; `shortcut` covers it (and
/// anything else) by running a Shortcuts shortcut the user names in Settings.
enum QuickAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case timer
    case stopwatch
    case muteMicrophone
    case darkMode
    case screenshot
    case sleepDisplay
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: return String(localized: "Timer")
        case .stopwatch: return String(localized: "Stopwatch")
        case .muteMicrophone: return String(localized: "Mute microphone")
        case .darkMode: return String(localized: "Dark mode")
        case .screenshot: return String(localized: "Screenshot")
        case .sleepDisplay: return String(localized: "Sleep display")
        case .shortcut: return String(localized: "Run shortcut")
        }
    }

    var detail: String {
        switch self {
        case .timer: return String(localized: "Countdown with presets, shown live in the closed notch.")
        case .stopwatch: return String(localized: "Starts immediately, with pause, lap and reset.")
        case .muteMicrophone: return String(localized: "Mutes the default input device.")
        case .darkMode: return String(localized: "Switches between light and dark appearance. Asks for Automation access to System Events.")
        case .screenshot: return String(localized: "Drag-select an area and copy it to the clipboard.")
        case .sleepDisplay: return String(localized: "Turns the display off now.")
        case .shortcut: return String(localized: "Runs the Shortcuts shortcut named below, for example one that toggles a Focus.")
        }
    }

    /// Symbol for the resting state.
    var symbolName: String {
        switch self {
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .muteMicrophone: return "mic.fill"
        case .darkMode: return "circle.lefthalf.filled"
        case .screenshot: return "camera.viewfinder"
        case .sleepDisplay: return "display"
        case .shortcut: return "bolt.fill"
        }
    }

    /// Symbol once the action's state is "on" (only toggles differ).
    var activeSymbolName: String {
        switch self {
        case .muteMicrophone: return "mic.slash.fill"
        default: return symbolName
        }
    }

    static let defaultOrder: [QuickAction] = [
        .timer, .stopwatch, .muteMicrophone, .darkMode, .screenshot, .sleepDisplay, .shortcut
    ]
}

/// Pure ordering / visibility rules for the row, kept apart from the views and
/// the stored preferences so they can be tested.
enum QuickActionsLayout {
    /// The stored order with duplicates dropped and any action it does not
    /// mention (for instance one added in a later version) appended.
    static func normalizedOrder(_ stored: [QuickAction]) -> [QuickAction] {
        var seen = Set<QuickAction>()
        var result = stored.filter { seen.insert($0).inserted }
        for action in QuickAction.defaultOrder where !seen.contains(action) {
            result.append(action)
        }
        return result
    }

    /// What the row actually shows, left to right. The shortcut button needs a
    /// shortcut name to run, so it stays out until one is set.
    static func visibleActions(
        order: [QuickAction],
        hidden: [QuickAction],
        shortcutName: String
    ) -> [QuickAction] {
        let hiddenSet = Set(hidden)
        let hasShortcut = !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return normalizedOrder(order).filter { action in
            guard !hiddenSet.contains(action) else { return false }
            return action != .shortcut || hasShortcut
        }
    }

    /// Moves `action` one slot (`offset` = -1 up / +1 down), clamped to the ends.
    static func moved(_ order: [QuickAction], action: QuickAction, by offset: Int) -> [QuickAction] {
        var result = normalizedOrder(order)
        guard let index = result.firstIndex(of: action) else { return result }
        let target = min(max(index + offset, 0), result.count - 1)
        guard target != index else { return result }
        result.remove(at: index)
        result.insert(action, at: target)
        return result
    }
}

enum QuickActionsMetrics {
    static let buttonSize: CGFloat = 30
    static let barHeight: CGFloat = 38
    /// Gap between the row and the content beneath it.
    static let contentSpacing: CGFloat = 6
    /// How much taller the open notch gets to make room for the row.
    static let extraNotchHeight: CGFloat = barHeight + contentSpacing
}

/// Whether the row takes space in the open notch. Shared by the notch sizing
/// and the Home tab so they can never disagree.
func quickActionsBarVisible() -> Bool {
    guard Defaults[.enableQuickActions], !Defaults[.enableMinimalisticUI] else { return false }
    return !QuickActionsLayout.visibleActions(
        order: Defaults[.quickActionsOrder],
        hidden: Defaults[.quickActionsHidden],
        shortcutName: Defaults[.quickActionsShortcutName]
    ).isEmpty
}
