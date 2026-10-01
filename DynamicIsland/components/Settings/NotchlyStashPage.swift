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

/// Stash: the temporary tray for text, links, images and files.
struct NotchlyStashPage: View {
    typealias I = Item

    @Default(.enableStash) private var enableStash
    @Default(.stashRetention) private var retention
    @Default(.stashMaxItems) private var maxItems
    @Default(.stashLinkThresholdMB) private var linkThresholdMB
    @Default(.enableShortcuts) private var enableShortcuts

    var body: some View {
        NotchlyPageScroll(page: .stash) {
            mainCard
            storageCard
            privacyCard
            shortcutCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: enableStash)
    }

    // MARK: Cards

    private var mainCard: some View {
        NotchlySettingsCard(
            footer: "Drop text, links, images and files on the notch, or add what is on the clipboard. The Stash is not shown in Minimalistic UI."
        ) {
            I.enable.toggle("A temporary tray in the notch for things you are carrying around.", key: .enableStash)
        }
    }

    private var storageCard: some View {
        NotchlySettingsCard(
            "Storage",
            footer: "Files are copied into Notchly's own folder so they survive the original being moved or deleted. Bigger files are only linked and show a Linked badge. When the cap is reached the oldest item is removed. Text is kept in a file on this Mac until it expires."
        ) {
            I.keepItems.picker(
                "How long things stay in the tray.",
                isEnabled: enableStash,
                selection: $retention,
                options: Array(StashRetention.allCases),
                label: { $0.localizedName }
            )
            I.maxItems.slider(
                "The oldest item goes first once the tray is full.",
                isEnabled: enableStash,
                value: $maxItems,
                range: StashLimits.maxItemsRange,
                step: 5,
                valueLabel: { "\($0)" }
            )
            I.linkThreshold.slider(
                "Larger files are linked instead of copied.",
                isEnabled: enableStash,
                value: $linkThresholdMB,
                range: 10...5000,
                step: 50,
                valueLabel: { "\($0) MB" }
            )
        }
    }

    private var privacyCard: some View {
        NotchlySettingsCard(
            "Privacy",
            footer: "Nothing is uploaded, and the clipboard is only read when you press Add from clipboard or use the shortcut. Items that password managers mark as private are never taken."
        ) {
            I.clearOnSleep.toggle("Empty the tray whenever the Mac goes to sleep or locks.", isEnabled: enableStash, key: .stashClearOnSleepOrLock)
            I.hidePreviews.toggle("Blur text and image previews until you point at them.", isEnabled: enableStash, key: .stashHidePreviewsUntilHover)
        }
    }

    private var shortcutCard: some View {
        NotchlySettingsCard(
            "Shortcut",
            footer: enableShortcuts
                ? "Adds whatever is on the clipboard to the Stash. No shortcut is set by default."
                : "Global keyboard shortcuts are turned off on the Shortcuts page."
        ) {
            I.shortcut.row("Add the clipboard to the Stash from anywhere.", isEnabled: enableStash && enableShortcuts) {
                KeyboardShortcuts.Recorder(for: .stashClipboard)
            }
        }
    }
}

// MARK: - Search items

extension NotchlyStashPage {
    enum Item {
        static let enable = NotchlySettingItem(.stash, "Enable Stash", keywords: ["stash", "tray", "shelf", "clipboard", "drop", "files", "temporary"])
        static let keepItems = NotchlySettingItem(.stash, "Keep items", keywords: ["stash", "retention", "expire", "hours", "days", "quit"])
        static let maxItems = NotchlySettingItem(.stash, "Maximum items", keywords: ["stash", "cap", "limit", "oldest"])
        static let linkThreshold = NotchlySettingItem(.stash, "Link files larger than", keywords: ["stash", "size", "copy", "link", "megabytes", "big files"])
        static let clearOnSleep = NotchlySettingItem(.stash, "Clear when the Mac sleeps or locks", keywords: ["stash", "sleep", "lock", "privacy", "clear"])
        static let hidePreviews = NotchlySettingItem(.stash, "Hide previews until hover", keywords: ["stash", "privacy", "blur", "text", "preview"])
        static let shortcut = NotchlySettingItem(.stash, "Stash clipboard shortcut", keywords: ["stash", "shortcut", "keyboard", "clipboard"])
    }

    static let items: [NotchlySettingItem] = [
        Item.enable, Item.keepItems, Item.maxItems, Item.linkThreshold, Item.clearOnSleep, Item.hidePreviews, Item.shortcut,
    ]
}
