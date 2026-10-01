import AppKit
import XCTest
@testable import Notchly

final class StatusMenuTests: XCTestCase {

    private func items(_ state: StatusMenuState = StatusMenuState()) -> [StatusMenuItem] {
        StatusMenuModel.items(for: state)
    }

    private func flattened(_ items: [StatusMenuItem]) -> [StatusMenuItem] {
        items.flatMap { [$0] + flattened($0.children) }
    }

    // MARK: Layout

    func testHeaderIsDisabledAndShowsVersionAndBuild() {
        let header = items(StatusMenuState(version: "1.0", build: "3")).first
        XCTAssertEqual(header?.kind, .header)
        XCTAssertEqual(header?.title, "Notchly 1.0 (3)")
        XCTAssertEqual(header?.isEnabled, false)
        XCTAssertNil(header?.action)
    }

    func testHeaderDropsMissingOrDuplicateBuild() {
        XCTAssertEqual(StatusMenuModel.headerTitle(version: "2.3.3", build: nil), "Notchly 2.3.3")
        XCTAssertEqual(StatusMenuModel.headerTitle(version: "2.3.3", build: ""), "Notchly 2.3.3")
        XCTAssertEqual(StatusMenuModel.headerTitle(version: "2", build: "2"), "Notchly 2")
    }

    func testNotchItemTitleTogglesWithState() {
        let closed = items(StatusMenuState(isNotchOpen: false)).first { $0.id == "notch" }
        let open = items(StatusMenuState(isNotchOpen: true)).first { $0.id == "notch" }
        XCTAssertEqual(closed?.title, "Open Notch")
        XCTAssertEqual(open?.title, "Close Notch")
        XCTAssertEqual(closed?.action, .toggleNotch)
        XCTAssertEqual(open?.action, .toggleNotch)
    }

    func testToggleItemsReflectDefaults() {
        let on = items(StatusMenuState(stashEnabled: true, hubEnabled: true))
        let off = items(StatusMenuState(stashEnabled: false, hubEnabled: false))
        XCTAssertEqual(on.first { $0.id == "stash" }?.isChecked, true)
        XCTAssertEqual(on.first { $0.id == "hub" }?.isChecked, true)
        XCTAssertEqual(off.first { $0.id == "stash" }?.isChecked, false)
        XCTAssertEqual(off.first { $0.id == "hub" }?.isChecked, false)
        XCTAssertEqual(on.first { $0.id == "stash" }?.action, .toggleStash)
        XCTAssertEqual(on.first { $0.id == "hub" }?.action, .toggleHub)
    }

    func testSettingsAndQuitShortcuts() {
        let all = items()
        XCTAssertEqual(all.first { $0.id == "settings" }?.shortcut?.key, ",")
        XCTAssertEqual(all.first { $0.id == "settings" }?.action, .openSettings)
        XCTAssertEqual(all.first { $0.id == "about" }?.action, .openAbout)
        XCTAssertEqual(all.first { $0.id == "quit" }?.shortcut?.key, "q")
        XCTAssertEqual(all.last?.id, "quit")
        XCTAssertEqual(all.last?.title, "Quit Notchly")
    }

    func testQuickActionsSubmenuFollowsTheSetting() {
        XCTAssertNotNil(items(StatusMenuState(quickActionsEnabled: true)).first { $0.id == "quickActions" })
        XCTAssertNil(items(StatusMenuState(quickActionsEnabled: false)).first { $0.id == "quickActions" })
    }

    func testQuickActionTitlesAndActionsFollowState() {
        let idle = StatusMenuModel.quickActions(for: StatusMenuState())
        XCTAssertEqual(idle.first { $0.id == "quick.timer" }?.title, "Start 5-Minute Timer")
        XCTAssertEqual(idle.first { $0.id == "quick.timer" }?.action, .startTimer(minutes: 5))
        XCTAssertEqual(idle.first { $0.id == "quick.stopwatch" }?.action, .startStopwatch)
        XCTAssertEqual(idle.first { $0.id == "quick.mic" }?.title, "Mute Microphone")

        let busy = StatusMenuModel.quickActions(for: StatusMenuState(
            isTimerActive: true, isStopwatchActive: true, isMicMuted: true, isDarkMode: true
        ))
        XCTAssertEqual(busy.first { $0.id == "quick.timer" }?.action, .cancelTimer)
        XCTAssertEqual(busy.first { $0.id == "quick.stopwatch" }?.action, .resetStopwatch)
        XCTAssertEqual(busy.first { $0.id == "quick.mic" }?.title, "Unmute Microphone")
        XCTAssertEqual(busy.first { $0.id == "quick.dark" }?.isChecked, true)
    }

    func testItemIDsAreUnique() {
        let ids = flattened(items()).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEverySymbolIsARealSFSymbol() {
        for item in flattened(items()) {
            guard let symbol = item.symbol else { continue }
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(item.id): \(symbol)")
        }
        // The alternate states too.
        let alternates = flattened(items(StatusMenuState(isNotchOpen: true, isMicMuted: true)))
        for item in alternates {
            guard let symbol = item.symbol else { continue }
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), "\(item.id): \(symbol)")
        }
    }

    func testNothingMentionsTheOldName() {
        for item in flattened(items()) {
            XCTAssertFalse(item.title.contains("Atoll"), item.title)
            XCTAssertFalse(item.title.contains("Dynamic Island"), item.title)
        }
    }

    // MARK: Rendering

    private final class Target: NSObject {
        @objc func fire(_ sender: NSMenuItem) {}
    }

    func testRendererProducesMatchingMenuItems() {
        let target = Target()
        let model = items(StatusMenuState(version: "1.0", build: "3", stashEnabled: true, hubEnabled: false))
        let rendered = StatusMenuRenderer.menuItems(from: model, target: target, action: #selector(Target.fire(_:)))
        XCTAssertEqual(rendered.count, model.count)

        let header = rendered[0]
        XCTAssertFalse(header.isEnabled)
        XCTAssertEqual(header.title, "Notchly 1.0 (3)")

        func find(_ title: String) -> NSMenuItem? { rendered.first { $0.title == title } }
        XCTAssertEqual(find("Stash")?.state, .on)
        XCTAssertEqual(find("Hub")?.state, .off)
        XCTAssertEqual(find("Settings…")?.keyEquivalent, ",")
        XCTAssertEqual(find("Settings…")?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(find("Quit Notchly")?.keyEquivalent, "q")
        XCTAssertEqual(find("Settings…")?.representedObject as? StatusMenuAction, .openSettings)
        XCTAssertNotNil(find("Settings…")?.image)
        XCTAssertTrue(find("Settings…")?.target === target)

        let quick = find("Quick Actions")
        XCTAssertNotNil(quick?.submenu)
        XCTAssertEqual(quick?.submenu?.items.count, StatusMenuModel.quickActions(for: StatusMenuState()).count)
        XCTAssertNil(quick?.representedObject, "a submenu parent must not carry an app action")

        XCTAssertEqual(rendered.filter(\.isSeparatorItem).count, model.filter { $0.kind == .separator }.count)
    }

    // MARK: Live controller

    @MainActor
    func testControllerBuildsItsMenuFromLiveState() {
        let controller = StatusBarController()
        controller.menuNeedsUpdate(controller.menu)
        let titles = controller.menu.items.map(\.title)
        XCTAssertTrue(titles.first?.hasPrefix("Notchly ") == true, "\(titles)")
        XCTAssertTrue(titles.contains("Open Notch") || titles.contains("Close Notch"), "\(titles)")
        XCTAssertTrue(titles.contains("Settings…"))
        XCTAssertEqual(titles.last, "Quit Notchly")

        // Opening it twice must not duplicate anything.
        let count = controller.menu.items.count
        controller.menuNeedsUpdate(controller.menu)
        XCTAssertEqual(controller.menu.items.count, count)
    }

    // MARK: About panel

    func testAboutCreditsMentionLicenseAndLineage() {
        let text = NotchlyAboutPanel.credits().string
        XCTAssertTrue(text.contains("GPL-3.0"))
        XCTAssertTrue(text.contains("Atoll"))
        XCTAssertTrue(text.contains("boring.notch"))
        XCTAssertTrue(text.contains("Notchly"))
    }

    func testAboutCreditsLinkTheLicenseAndBothProjects() {
        let credits = NotchlyAboutPanel.credits()
        var links = Set<URL>()
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { links.insert(url) }
        }
        XCTAssertTrue(links.contains(NotchlyCredits.licenseURL))
        XCTAssertTrue(links.contains(NotchlyCredits.atoll.url))
        XCTAssertTrue(links.contains(NotchlyCredits.boringNotch.url))
    }

    func testCrashReportMatchesBothExecutableNames() {
        XCTAssertTrue(NotchlyLogExport.isCrashReport("Notchly-2026-01-01.ips"))
        XCTAssertTrue(NotchlyLogExport.isCrashReport("Atoll-2025-01-01.ips"))
        XCTAssertFalse(NotchlyLogExport.isCrashReport("Safari-2026.ips"))
    }
}
