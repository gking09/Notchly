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
import SwiftUI

/// Foundry: the project-management app's next step, project health and warnings
/// in the notch. Read-only and local.
struct NotchlyFoundryPage: View {
    typealias I = Item

    @ObservedObject private var bridge = FoundryBridge.shared
    @Default(.foundryIntegration) private var integration
    @Default(.foundryShowTab) private var showTab
    @Default(.foundryShowAlerts) private var showAlerts
    @Default(.foundryShowQuickActions) private var showQuickActions
    @Default(.foundryShowInMenu) private var showInMenu
    @Default(.hubHiddenChips) private var hiddenChips

    private var settings: FoundrySettings { bridge.settings }

    var body: some View {
        NotchlyPageScroll(page: .foundry) {
            mainCard
            if settings.isEnabled {
                surfacesCard
            }
            statusCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: settings.isEnabled)
        .animation(NotchlyTheme.Motion.snappy, value: settings.installed)
        .onAppear {
            // Opening the page is a good moment to look again.
            FoundryAvailability.invalidate()
            bridge.refreshSettings()
        }
    }

    // MARK: Cards

    private var mainCard: some View {
        NotchlySettingsCard(
            footer: "Read-only and local. Notchly reads a small summary file that Foundry writes on this Mac and never opens Foundry's database. Anything that changes data, like completing a task, is sent back to Foundry, which asks you to confirm and keeps an Undo."
        ) {
            if !settings.installed {
                NotchlyNoticeRow(
                    text: "Foundry isn't installed on this Mac. You can still switch this on; it starts working as soon as Foundry shares a summary."
                )
            }
            I.master.toggle(
                "Show your next step, project health and warnings from Foundry.",
                isOn: Binding(
                    get: { settings.masterToggleIsOn },
                    set: { integration = FoundrySettings.mode(forToggle: $0) }
                )
            )
            I.open.row(
                settings.installed ? "Bring Foundry forward." : "Foundry isn't installed.",
                isEnabled: settings.installed
            ) {
                Button("Open Foundry") { bridge.openApp() }
                    .buttonStyle(.notchly(.standard))
            }
        }
    }

    private var surfacesCard: some View {
        NotchlySettingsCard(
            "Where it shows",
            footer: "With every switch off, Notchly doesn't read the summary at all."
        ) {
            I.chip.toggle(
                "Your next step, or a warning, as a chip in the Hub. Click opens the project; right-click offers Mark Done and Later.",
                isOn: Binding(
                    get: { !hiddenChips.contains(.foundry) },
                    set: { isOn in
                        var updated = hiddenChips.filter { $0 != .foundry }
                        if !isOn { updated.append(.foundry) }
                        hiddenChips = updated
                    }
                )
            )
            I.tab.toggle(
                "A tab with your next step, up to five projects and warnings. Only appears while Foundry has shared a summary.",
                key: .foundryShowTab
            )
            I.alerts.toggle(
                "A short note beside the closed notch when a new warning appears. Never when Notchly starts, and at most once every ten minutes per warning.",
                key: .foundryShowAlerts
            )
            I.quickActions.toggle(
                "Open Foundry and Foundry next up, in the Quick Actions row.",
                key: .foundryShowQuickActions
            )
            I.menu.toggle(
                "A Foundry submenu in the menu bar icon's menu.",
                key: .foundryShowInMenu
            )
        }
    }

    private var statusCard: some View {
        let summary = FoundryStatusSummary.make(
            state: bridge.state,
            installed: settings.installed,
            feedExists: FoundryAvailability.snapshot().feedExists,
            now: Date()
        )
        return NotchlySettingsCard("Status") {
            I.status.row("Foundry writes this file when something changes; it is never uploaded.") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(summary.feedFound ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                        .frame(width: 7, height: 7)
                    Text(summary.feedText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchlySettingsStyle.textSecondary)
                }
            }
            NotchlySettingRow("Last updated") {
                Text(summary.updatedText ?? "\u{2013}")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
            }
            NotchlySettingRow("Projects") {
                Text(summary.projectCount.map { "\($0)" } ?? "\u{2013}")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
            }
            NotchlySettingRow("Summary format") {
                HStack(spacing: 6) {
                    if let supported = summary.versionSupported {
                        Image(systemName: supported ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(supported ? NotchlySettingsStyle.textSecondary : Color(nsColor: .systemOrange))
                    }
                    Text(summary.versionText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NotchlySettingsStyle.textSecondary)
                }
            }
        }
    }
}

// MARK: - Search items

extension NotchlyFoundryPage {
    enum Item {
        static let master = NotchlySettingItem(.foundry, "Show Foundry in Notchly", keywords: ["foundry", "project management", "projects", "integration", "next up", "enable"])
        static let open = NotchlySettingItem(.foundry, "Open Foundry", keywords: ["foundry", "app", "launch", "open"])
        static let chip = NotchlySettingItem(.foundry, "Foundry chip in the Hub", keywords: ["foundry", "hub", "chip", "next step", "warning", "mark done", "later"])
        static let tab = NotchlySettingItem(.foundry, "Foundry tab", keywords: ["foundry", "tab", "projects", "next up", "health", "forecast", "progress"])
        static let alerts = NotchlySettingItem(.foundry, "Foundry alerts in the closed notch", keywords: ["foundry", "alerts", "warnings", "live activity", "closed notch", "notifications"])
        static let quickActions = NotchlySettingItem(.foundry, "Foundry quick actions", keywords: ["foundry", "quick actions", "buttons", "open foundry", "next up"])
        static let menu = NotchlySettingItem(.foundry, "Foundry in the menu bar", keywords: ["foundry", "menu bar", "status bar", "submenu", "next up"])
        static let status = NotchlySettingItem(.foundry, "Foundry summary status", keywords: ["foundry", "feed", "summary", "notch.json", "version", "updated", "found", "stale"])
    }

    static let items: [NotchlySettingItem] = [
        Item.master, Item.open, Item.chip, Item.tab, Item.alerts, Item.quickActions, Item.menu, Item.status,
    ]
}
