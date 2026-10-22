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
import Foundation

// Settings for the Foundry integration, as plain values.
//
// One master switch ("Show Foundry in Notchly") gates everything: with it off,
// nothing reads Foundry's feed file, no timer runs and nothing is drawn. Each
// surface (Hub chip, tab, closed-notch alerts, quick actions, menu) then has its
// own switch beneath it.

/// The master switch. `auto` follows whether Foundry has published a feed, so the
/// integration lights up by itself for someone who has Foundry and stays out of
/// the way for everyone else; choosing either way in settings pins it.
enum FoundryIntegrationMode: String, CaseIterable, Defaults.Serializable {
    case auto
    case on
    case off
}

extension Defaults.Keys {
    static let foundryIntegration = Key<FoundryIntegrationMode>("foundryIntegration", default: .auto)
    static let foundryShowTab = Key<Bool>("foundryShowTab", default: true)
    static let foundryShowAlerts = Key<Bool>("foundryShowAlerts", default: true)
    static let foundryShowQuickActions = Key<Bool>("foundryShowQuickActions", default: true)
    static let foundryShowInMenu = Key<Bool>("foundryShowInMenu", default: true)
}

struct FoundrySettings: Equatable {
    var mode: FoundryIntegrationMode = .auto
    /// Foundry has written a feed (a stat, not a read).
    var feedFileExists = false
    /// Foundry.app is registered with Launch Services.
    var installed = false
    /// The Hub is on and Minimalistic UI is off, so a chip has somewhere to show.
    var hubVisible = true
    var chipHidden = false
    var minimalistic = false
    var showTab = true
    var showAlerts = true
    var showQuickActions = true
    var showInMenu = true

    /// The master switch, resolved.
    var isEnabled: Bool {
        switch mode {
        case .on: return true
        case .off: return false
        case .auto: return feedFileExists
        }
    }

    var showsChip: Bool { isEnabled && hubVisible && !minimalistic && !chipHidden }
    /// The tab, before the feed is considered: the tab also needs a valid feed.
    var allowsTab: Bool { isEnabled && showTab && !minimalistic }
    var alertsEnabled: Bool { isEnabled && showAlerts }
    var showsInMenu: Bool { isEnabled && showInMenu }
    /// Foundry's quick actions need Foundry to be there to open.
    var quickActionsAvailable: Bool { isEnabled && showQuickActions && installed }

    /// Whether anything on screen needs the feed. When not, the file is never read.
    var wantsFeed: Bool { isEnabled && (showsChip || allowsTab || alertsEnabled || showsInMenu) }

    /// What a master toggle in settings should show.
    var masterToggleIsOn: Bool { isEnabled }

    /// The mode a flip of the master toggle chooses.
    static func mode(forToggle isOn: Bool) -> FoundryIntegrationMode { isOn ? .on : .off }
}

extension FoundrySettings {
    /// The settings as they are right now. Safe from any thread.
    static func current(availability: FoundryAvailability.Snapshot = FoundryAvailability.snapshot()) -> FoundrySettings {
        FoundrySettings(
            mode: Defaults[.foundryIntegration],
            feedFileExists: availability.feedExists,
            installed: availability.installed,
            hubVisible: Defaults[.enableHub],
            chipHidden: Defaults[.hubHiddenChips].contains(.foundry),
            minimalistic: Defaults[.enableMinimalisticUI],
            showTab: Defaults[.foundryShowTab],
            showAlerts: Defaults[.foundryShowAlerts],
            showQuickActions: Defaults[.foundryShowQuickActions],
            showInMenu: Defaults[.foundryShowInMenu]
        )
    }
}

// MARK: - Availability

/// Whether Foundry is on this Mac, and whether it has published a feed. Both are
/// looked up at most once per `ttl`, because the notch's sizing code asks often.
struct FoundryAvailabilityCache: Equatable {
    var installed = false
    var feedExists = false
    var checkedAt: Date?

    /// Re-runs `probe` when the cached answer is older than `ttl` (or missing).
    mutating func refreshIfNeeded(now: Date, ttl: TimeInterval, probe: () -> (installed: Bool, feedExists: Bool)) {
        if let checkedAt, now.timeIntervalSince(checkedAt) >= 0, now.timeIntervalSince(checkedAt) < ttl { return }
        let result = probe()
        installed = result.installed
        feedExists = result.feedExists
        checkedAt = now
    }
}

enum FoundryAvailability {
    /// Foundry's bundle identifier (from its build script's Info.plist).
    static let bundleIdentifier = "io.github.gking09.foundry"
    static let ttl: TimeInterval = 30

    struct Snapshot: Equatable {
        var installed: Bool
        var feedExists: Bool
    }

    private static let lock = NSLock()
    private static var cache = FoundryAvailabilityCache()

    static func snapshot(now: Date = Date()) -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        cache.refreshIfNeeded(now: now, ttl: ttl) { (isInstalled(), FoundryFeedLoader.exists()) }
        return Snapshot(installed: cache.installed, feedExists: cache.feedExists)
    }

    /// Forgets the cached answer (Foundry just pinged, or settings were opened).
    static func invalidate() {
        lock.lock()
        cache.checkedAt = nil
        lock.unlock()
    }

    static func isInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// For the sizing code and menus that only need to know.
    static var quickActionsAvailable: Bool { FoundrySettings.current().quickActionsAvailable }

    static var tabAllowed: Bool { FoundrySettings.current().allowsTab }
}

// MARK: - Polling

/// The fallback poll. Foundry's ping is the real trigger; the poll only covers a
/// ping missed while Notchly wasn't running, so it is slow, stretched further on
/// battery, and parked entirely while the display sleeps or nothing needs the feed.
enum FoundryPolling {
    static let baseInterval: TimeInterval = 180

    static func interval(wantsFeed: Bool, gate: ActivityGate) -> TimeInterval? {
        guard wantsFeed, !gate.isSuspended else { return nil }
        return gate.interval(baseInterval)
    }
}
