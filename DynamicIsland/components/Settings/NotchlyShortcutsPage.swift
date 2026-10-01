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

import Defaults
import KeyboardShortcuts
import SwiftUI

/// Shortcuts: the global key bindings, grouped by what they act on.
struct NotchlyShortcutsPage: View {
    typealias I = Item

    @Default(.enableShortcuts) private var enableShortcuts

    var body: some View {
        NotchlyPageScroll(page: .shortcuts) {
            masterCard
            notchCard
            stashCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: enableShortcuts)
    }

    private var masterCard: some View {
        NotchlySettingsCard(
            footer: "When this is off, every shortcut below is inactive. You can still use the buttons in the notch."
        ) {
            I.enable.toggle("Let Notchly respond to keyboard shortcuts from any app.", key: .enableShortcuts)
        }
    }

    private var notchCard: some View {
        NotchlySettingsCard("Notch", footer: "Click a box, then press the keys you want. Press Delete to clear it.") {
            I.toggleNotch.row("Open or close the notch from anywhere.", isEnabled: enableShortcuts) {
                KeyboardShortcuts.Recorder(for: .toggleNotchOpen)
            }
            I.sneakPeek.row("Show the title and artist under the notch for a few seconds.", isEnabled: enableShortcuts) {
                KeyboardShortcuts.Recorder(for: .toggleSneakPeek)
            }
        }
    }

    private var stashCard: some View {
        NotchlySettingsCard("Stash", footer: "No shortcut is set by default for the Stash.") {
            I.stashClipboard.row("Add whatever is on the clipboard to the Stash.", isEnabled: enableShortcuts) {
                KeyboardShortcuts.Recorder(for: .stashClipboard)
            }
        }
    }
}

// MARK: - Search items

extension NotchlyShortcutsPage {
    enum Item {
        static let enable = NotchlySettingItem(.shortcuts, "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut", "hotkey"])
        static let toggleNotch = NotchlySettingItem(.shortcuts, "Toggle notch open", keywords: ["shortcut", "keyboard", "open", "close", "hotkey", "navigation"])
        static let sneakPeek = NotchlySettingItem(.shortcuts, "Toggle sneak peek", keywords: ["shortcut", "keyboard", "media", "music", "title", "artist", "hotkey"])
        static let stashClipboard = NotchlySettingItem(.shortcuts, "Stash clipboard", keywords: ["shortcut", "keyboard", "stash", "clipboard", "hotkey"])
    }

    static let items: [NotchlySettingItem] = [Item.enable, Item.toggleNotch, Item.sneakPeek, Item.stashClipboard]
}
