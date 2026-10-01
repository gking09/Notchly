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


import AppKit
import Combine
import Defaults

// MARK: - Rendering

/// Turns the pure `StatusMenuModel` into real `NSMenuItem`s.
enum StatusMenuRenderer {
    /// Each item's `representedObject` carries its `StatusMenuAction`.
    static func menuItems(
        from model: [StatusMenuItem],
        target: AnyObject?,
        action: Selector,
        headerImage: NSImage? = nil
    ) -> [NSMenuItem] {
        model.map { menuItem(from: $0, target: target, action: action, headerImage: headerImage) }
    }

    static func menuItem(
        from item: StatusMenuItem,
        target: AnyObject?,
        action: Selector,
        headerImage: NSImage? = nil
    ) -> NSMenuItem {
        switch item.kind {
        case .separator:
            return NSMenuItem.separator()

        case .header:
            let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
            menuItem.isEnabled = false
            menuItem.image = headerImage
            menuItem.attributedTitle = headerTitle(item.title)
            return menuItem

        case .action, .submenu:
            let menuItem = NSMenuItem(
                title: item.title,
                action: item.kind == .action ? action : nil,
                keyEquivalent: item.shortcut?.key ?? ""
            )
            if item.shortcut != nil { menuItem.keyEquivalentModifierMask = .command }
            menuItem.target = target
            menuItem.representedObject = item.action
            menuItem.isEnabled = item.isEnabled
            menuItem.state = item.isChecked ? .on : .off
            if let symbol = item.symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                image.isTemplate = true
                menuItem.image = image
            }
            if item.kind == .submenu {
                let submenu = NSMenu(title: item.title)
                submenu.autoenablesItems = false
                menuItems(from: item.children, target: target, action: action).forEach(submenu.addItem)
                menuItem.submenu = submenu
            }
            return menuItem
        }
    }

    /// "Notchly" in the primary label colour, the version quieter beside it.
    private static func headerTitle(_ title: String) -> NSAttributedString {
        let name = "Notchly"
        let result = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        if title.hasPrefix(name) {
            result.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                    .foregroundColor: NSColor.labelColor,
                ],
                range: NSRange(location: 0, length: name.count)
            )
        }
        return result
    }
}

// MARK: - Status item

/// Owns the menu-bar icon and its menu. The icon follows the "menu bar icon" setting;
/// the menu is rebuilt from fresh state every time it opens.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    let menu = NSMenu(title: "Notchly")
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false

        Defaults.publisher(.menubarIcon)
            .map(\.newValue)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.setVisible(visible)
            }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "Notchly"
            if let button = item.button {
                let glyph = NSImage(named: "menubar")
                glyph?.isTemplate = true
                button.image = glyph
                button.setAccessibilityLabel("Notchly")
            }
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: State

    static func currentState() -> StatusMenuState {
        QuickActionsManager.shared.refreshSystemState()
        return StatusMenuState(
            version: Bundle.main.releaseVersionNumber ?? "1.0",
            build: Bundle.main.buildVersionNumber,
            isNotchOpen: AppDelegate.shared?.isNotchOpenOnActiveScreen ?? false,
            stashEnabled: Defaults[.enableStash],
            hubEnabled: Defaults[.enableHub],
            quickActionsEnabled: Defaults[.enableQuickActions],
            isTimerActive: TimerManager.shared.isTimerActive,
            isStopwatchActive: StopwatchManager.shared.isActive,
            isMicMuted: QuickActionsManager.shared.isMicMuted,
            isDarkMode: QuickActionsManager.shared.isDarkMode
        )
    }

    private static func headerImage() -> NSImage? {
        guard let source = NSImage(named: "logo2") else { return nil }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
            source.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: NSMenuDelegate

    /// Titles, checkmarks and the notch toggle are rebuilt on every open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menu.removeAllItems()
        let model = StatusMenuModel.items(for: Self.currentState())
        StatusMenuRenderer
            .menuItems(from: model, target: self, action: #selector(performMenuAction(_:)), headerImage: Self.headerImage())
            .forEach(menu.addItem)
    }

    // MARK: Actions

    @objc private func performMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? StatusMenuAction else { return }
        perform(action)
    }

    func perform(_ action: StatusMenuAction) {
        switch action {
        case .toggleNotch:
            AppDelegate.shared?.toggleNotchOnActiveScreen()
        case .toggleStash:
            Defaults[.enableStash].toggle()
        case .toggleHub:
            Defaults[.enableHub].toggle()
        case .startTimer(let minutes):
            TimerManager.shared.start(duration: TimeInterval(minutes * 60))
        case .cancelTimer:
            TimerManager.shared.cancel()
        case .startStopwatch:
            StopwatchManager.shared.start()
        case .resetStopwatch:
            StopwatchManager.shared.reset()
        case .toggleMicrophone:
            QuickActionsManager.shared.perform(.muteMicrophone, closeNotch: {})
        case .toggleDarkMode:
            QuickActionsManager.shared.perform(.darkMode, closeNotch: {})
        case .screenshot:
            QuickActionsManager.shared.perform(.screenshot) {
                AppDelegate.shared?.closeNotchOnActiveScreen()
            }
        case .openSettings:
            SettingsWindowController.shared.showWindow()
        case .openAbout:
            SettingsWindowController.shared.showWindow(page: .about)
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
