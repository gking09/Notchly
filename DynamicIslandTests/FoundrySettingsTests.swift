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

import XCTest
@testable import Notchly

/// The Foundry integration's switches, the places it plugs into (Quick Actions,
/// the menu, the settings page) and how often it may look at the feed.
final class FoundrySettingsTests: XCTestCase {

    // MARK: Master switch

    func testAutoFollowsWhetherFoundryHasPublishedAFeed() {
        XCTAssertFalse(FoundrySettings(mode: .auto, feedFileExists: false).isEnabled)
        XCTAssertTrue(FoundrySettings(mode: .auto, feedFileExists: true).isEnabled)
    }

    func testChoosingPinsTheSwitchWhateverTheFileDoes() {
        XCTAssertTrue(FoundrySettings(mode: .on, feedFileExists: false).isEnabled)
        XCTAssertFalse(FoundrySettings(mode: .off, feedFileExists: true).isEnabled)
    }

    func testTheToggleChoosesOnOrOff() {
        XCTAssertEqual(FoundrySettings.mode(forToggle: true), .on)
        XCTAssertEqual(FoundrySettings.mode(forToggle: false), .off)
        XCTAssertTrue(FoundrySettings(mode: .auto, feedFileExists: true).masterToggleIsOn)
    }

    func testSwitchedOffNothingShowsAndNothingIsRead() {
        let off = FoundrySettings(mode: .off, feedFileExists: true, installed: true)
        XCTAssertFalse(off.showsChip)
        XCTAssertFalse(off.allowsTab)
        XCTAssertFalse(off.alertsEnabled)
        XCTAssertFalse(off.showsInMenu)
        XCTAssertFalse(off.quickActionsAvailable)
        XCTAssertFalse(off.wantsFeed, "a disabled integration must not read the file")
    }

    func testEnabledWithEverySurfaceOffStillReadsNothing() {
        let quiet = FoundrySettings(mode: .on, feedFileExists: true, installed: true, chipHidden: true,
                                    showTab: false, showAlerts: false, showQuickActions: true, showInMenu: false)
        XCTAssertFalse(quiet.wantsFeed)
    }

    func testAnySingleSurfaceIsEnoughToWantTheFeed() {
        let base = FoundrySettings(mode: .on, feedFileExists: true, installed: true, chipHidden: true,
                                   showTab: false, showAlerts: false, showQuickActions: false, showInMenu: false)
        var chip = base; chip.chipHidden = false
        var tab = base; tab.showTab = true
        var alerts = base; alerts.showAlerts = true
        var menu = base; menu.showInMenu = true
        XCTAssertTrue(chip.wantsFeed)
        XCTAssertTrue(tab.wantsFeed)
        XCTAssertTrue(alerts.wantsFeed)
        XCTAssertTrue(menu.wantsFeed)
    }

    func testMinimalisticUIHasNoRoomForTheChipOrTab() {
        let settings = FoundrySettings(mode: .on, feedFileExists: true, installed: true, minimalistic: true)
        XCTAssertFalse(settings.showsChip)
        XCTAssertFalse(settings.allowsTab)
    }

    func testChipNeedsTheHub() {
        XCTAssertFalse(FoundrySettings(mode: .on, hubVisible: false).showsChip)
        XCTAssertTrue(FoundrySettings(mode: .on, hubVisible: true).showsChip)
    }

    func testQuickActionsNeedFoundryInstalled() {
        XCTAssertFalse(FoundrySettings(mode: .on, installed: false).quickActionsAvailable)
        XCTAssertTrue(FoundrySettings(mode: .on, installed: true).quickActionsAvailable)
        XCTAssertFalse(FoundrySettings(mode: .on, installed: true, showQuickActions: false).quickActionsAvailable)
    }

    func testFoundrysBundleIdentifierMatchesItsBuildScript() {
        XCTAssertEqual(FoundryAvailability.bundleIdentifier, "io.github.gking09.foundry")
    }

    // MARK: Availability cache

    func testAvailabilityIsLookedUpOncePerTTL() {
        var cache = FoundryAvailabilityCache()
        var probes = 0
        let probe: () -> (installed: Bool, feedExists: Bool) = { probes += 1; return (true, false) }
        let t0 = Date(timeIntervalSince1970: 1_000)

        cache.refreshIfNeeded(now: t0, ttl: 30, probe: probe)
        cache.refreshIfNeeded(now: t0.addingTimeInterval(10), ttl: 30, probe: probe)
        cache.refreshIfNeeded(now: t0.addingTimeInterval(29), ttl: 30, probe: probe)
        XCTAssertEqual(probes, 1)
        XCTAssertTrue(cache.installed)
        XCTAssertFalse(cache.feedExists)

        cache.refreshIfNeeded(now: t0.addingTimeInterval(31), ttl: 30) { probes += 1; return (false, true) }
        XCTAssertEqual(probes, 2)
        XCTAssertFalse(cache.installed)
        XCTAssertTrue(cache.feedExists)
    }

    func testAnInvalidatedCacheLooksAgain() {
        var cache = FoundryAvailabilityCache()
        var probes = 0
        let t0 = Date(timeIntervalSince1970: 1_000)
        cache.refreshIfNeeded(now: t0, ttl: 30) { probes += 1; return (true, true) }
        cache.checkedAt = nil
        cache.refreshIfNeeded(now: t0.addingTimeInterval(1), ttl: 30) { probes += 1; return (true, true) }
        XCTAssertEqual(probes, 2)
    }

    // MARK: Polling

    func testPollingRunsEveryThreeMinutesAtMost() {
        XCTAssertEqual(FoundryPolling.baseInterval, 180)
        XCTAssertEqual(FoundryPolling.interval(wantsFeed: true, gate: ActivityGate()), 180)
    }

    func testPollingIsParkedWhenNothingWantsTheFeedOrTheDisplaySleeps() {
        XCTAssertNil(FoundryPolling.interval(wantsFeed: false, gate: ActivityGate()))
        XCTAssertNil(FoundryPolling.interval(wantsFeed: true, gate: ActivityGate(screenAsleep: true)))
    }

    func testPollingSlowsDownOnBattery() {
        let gate = ActivityGate(efficiencyModeEnabled: true, lowPowerMode: false, onBattery: true)
        XCTAssertEqual(FoundryPolling.interval(wantsFeed: true, gate: gate), 360)
    }

    // MARK: Quick actions

    func testFoundryActionsAreOnlyInTheRowWhenAvailable() {
        let off = QuickActionsLayout.visibleActions(order: QuickAction.defaultOrder, hidden: [], shortcutName: "x", foundryAvailable: false)
        XCTAssertFalse(off.contains(.openFoundry))
        XCTAssertFalse(off.contains(.foundryNextUp))
        let on = QuickActionsLayout.visibleActions(order: QuickAction.defaultOrder, hidden: [], shortcutName: "x", foundryAvailable: true)
        XCTAssertTrue(on.contains(.openFoundry))
        XCTAssertTrue(on.contains(.foundryNextUp))
    }

    func testFoundryActionsCanBeHiddenLikeAnyOther() {
        let visible = QuickActionsLayout.visibleActions(order: QuickAction.defaultOrder, hidden: [.foundryNextUp], shortcutName: "", foundryAvailable: true)
        XCTAssertTrue(visible.contains(.openFoundry))
        XCTAssertFalse(visible.contains(.foundryNextUp))
    }

    func testAnOldStoredOrderGainsTheFoundryActionsAtTheEnd() {
        let old: [QuickAction] = [.timer, .stopwatch, .muteMicrophone, .darkMode, .screenshot, .sleepDisplay, .shortcut]
        let order = QuickActionsLayout.normalizedOrder(old)
        XCTAssertEqual(Array(order.suffix(2)), [.openFoundry, .foundryNextUp])
        XCTAssertEqual(Array(order.prefix(7)), old, "nobody's layout is reshuffled")
    }

    func testNoQuickActionCompletesAnything() {
        // Completing needs the explicit two-step path in the tab or the chip's
        // menu; the row only ever navigates.
        let titles = QuickAction.allCases.filter(\.requiresFoundry).map { $0.title.lowercased() + $0.detail.lowercased() }
        XCTAssertEqual(titles.count, 2)
        XCTAssertTrue(QuickAction.foundryNextUp.detail.contains("never completes"))
    }

    func testFoundryActionsDescribeThemselves() {
        for action in [QuickAction.openFoundry, .foundryNextUp] {
            XCTAssertTrue(action.requiresFoundry)
            XCTAssertFalse(action.title.isEmpty)
            XCTAssertFalse(action.detail.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil))
        }
        XCTAssertFalse(QuickAction.timer.requiresFoundry)
    }

    // MARK: Status menu

    private func items(_ foundry: FoundryMenuState?) -> [StatusMenuItem] {
        StatusMenuModel.items(for: StatusMenuState(foundry: foundry))
    }

    func testMenuHasNoFoundryItemWhileItIsOff() {
        XCTAssertNil(items(nil).first { $0.id == "foundry" })
    }

    func testMenuShowsAFoundrySubmenuWithNextUpAsADisabledHeader() throws {
        let submenu = try XCTUnwrap(items(FoundryMenuState(nextUpTitle: "Finish the lightbox", nextUpProjectName: "Harper", attentionCount: 0)).first { $0.id == "foundry" })
        XCTAssertEqual(submenu.kind, .submenu)
        XCTAssertEqual(submenu.title, "Foundry")
        let header = try XCTUnwrap(submenu.children.first)
        XCTAssertEqual(header.kind, .header)
        XCTAssertFalse(header.isEnabled)
        XCTAssertEqual(header.title, "Next up: Finish the lightbox")
        XCTAssertNil(header.action)
        XCTAssertEqual(submenu.children.first { $0.id == "foundry.open" }?.action, .openFoundry)
        XCTAssertEqual(submenu.children.first { $0.id == "foundry.openNext" }?.action, .openFoundryNextUp)
    }

    func testMenuWithNothingQueuedOffersOnlyOpen() throws {
        let submenu = try XCTUnwrap(items(FoundryMenuState()).first { $0.id == "foundry" })
        XCTAssertEqual(submenu.children.first?.title, "Nothing queued")
        XCTAssertNil(submenu.children.first { $0.id == "foundry.openNext" })
        XCTAssertNotNil(submenu.children.first { $0.id == "foundry.open" })
        XCTAssertNil(submenu.children.first { $0.id == "foundry.attention" })
    }

    func testMenuMentionsAttentionAsInformationOnly() throws {
        let one = try XCTUnwrap(items(FoundryMenuState(attentionCount: 1)).first { $0.id == "foundry" }?.children.first { $0.id == "foundry.attention" })
        XCTAssertEqual(one.title, "1 item needs attention")
        XCTAssertFalse(one.isEnabled)
        XCTAssertNil(one.action)
        let many = try XCTUnwrap(items(FoundryMenuState(attentionCount: 4)).first { $0.id == "foundry" }?.children.first { $0.id == "foundry.attention" })
        XCTAssertEqual(many.title, "4 items need attention")
    }

    func testLongNextUpTitlesAreCutInTheMenu() throws {
        let long = String(repeating: "word ", count: 30)
        let submenu = try XCTUnwrap(items(FoundryMenuState(nextUpTitle: long)).first { $0.id == "foundry" })
        let title = try XCTUnwrap(submenu.children.first?.title)
        XCTAssertLessThanOrEqual(title.count, "Next up: ".count + StatusMenuModel.foundryTitleLimit)
        XCTAssertTrue(title.hasSuffix("\u{2026}"))
    }

    func testFoundryMenuIDsAreUniqueAndSymbolsReal() {
        let all = items(FoundryMenuState(nextUpTitle: "x", attentionCount: 2)).flatMap { [$0] + $0.children }
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for item in all {
            if let symbol = item.symbol { XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol) }
        }
    }

    // MARK: Settings page

    func testTheFoundryPageIsRegisteredAndSearchable() {
        XCTAssertTrue(NotchlySettingsPage.sidebarPages.contains(.foundry))
        XCTAssertEqual(SettingsSearchIndex.shared.search("Show Foundry in Notchly").first?.entry.page, .foundry)
        XCTAssertEqual(SettingsSearchIndex.shared.search("foundry tab").first?.entry.page, .foundry)
        XCTAssertEqual(SettingsSearchIndex.shared.search("open foundry").first?.entry.page, .foundry)
    }

    func testEverySettingOnThePageIsSearchable() {
        XCTAssertEqual(NotchlyFoundryPage.items.count, 8)
        XCTAssertEqual(NotchlySettingsPage.foundry.nativeItems, NotchlyFoundryPage.items)
    }
}
