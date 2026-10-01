import AppKit
import SwiftUI
import XCTest
@testable import Notchly

final class NotchlySettingsTests: XCTestCase {

    // MARK: Page registry

    func testPageIDsAreUnique() {
        let ids = NotchlySettingsPage.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryPageHasSymbolTitleSubtitleAndKeywords() {
        for page in NotchlySettingsPage.allCases {
            XCTAssertFalse(page.symbol.isEmpty, "\(page) symbol")
            XCTAssertFalse(page.title.isEmpty, "\(page) title")
            XCTAssertFalse(page.subtitle.isEmpty, "\(page) subtitle")
            XCTAssertFalse(page.keywords.isEmpty, "\(page) keywords")
            XCTAssertNotNil(NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil), "\(page) symbol is not an SF Symbol")
        }
    }

    func testPageTitlesAreUnique() {
        let titles = NotchlySettingsPage.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testSidebarPagesExcludeAboutAndKeepOrder() {
        XCTAssertFalse(NotchlySettingsPage.sidebarPages.contains(.about))
        XCTAssertEqual(NotchlySettingsPage.sidebarPages.first, .general)
    }

    func testEveryLegacyTabIsHostedByExactlyOnePage() {
        for tab in SettingsTab.allCases {
            let hosts = NotchlySettingsPage.allCases.filter { $0.legacySections.contains(tab) }
            XCTAssertEqual(hosts, [tab.page], "\(tab) must be reachable from exactly its page")
        }
    }

    // MARK: Search

    private func index() -> SettingsSearchIndex {
        SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Show seconds", keywords: ["clock"], page: .homeHub, sectionID: "hub"),
            SettingsSearchEntry(title: "Battery percentage", keywords: ["charge"], page: .liveActivities, sectionID: "battery"),
            SettingsSearchEntry(title: "Low battery alert", keywords: ["sound"], page: .liveActivities, sectionID: "battery"),
            SettingsSearchEntry(title: "Café mode", keywords: ["espresso"], page: .general, sectionID: "general"),
            SettingsSearchEntry(title: "Enable lyrics", keywords: ["karaoke"], page: .music, sectionID: "media"),
        ])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(index().search("").isEmpty)
        XCTAssertTrue(index().search("   ").isEmpty)
    }

    func testPrefixOutranksWordPrefixOutranksSubstring() {
        let idx = SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Superbat", page: .general, sectionID: "general"),      // substring
            SettingsSearchEntry(title: "Low bat alert", page: .general, sectionID: "general"), // word prefix
            SettingsSearchEntry(title: "Battery", page: .general, sectionID: "general"),       // prefix
        ])
        XCTAssertEqual(idx.search("bat").map(\.entry.title), ["Battery", "Low bat alert", "Superbat"])
    }

    func testTitleOutranksKeyword() {
        let idx = SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Alerts", keywords: ["battery"], page: .general, sectionID: "general"),
            SettingsSearchEntry(title: "Battery", page: .general, sectionID: "general"),
        ])
        XCTAssertEqual(idx.search("battery").first?.entry.title, "Battery")
    }

    func testMatchingIsCaseAndDiacriticInsensitive() {
        XCTAssertEqual(index().search("CAFE").first?.entry.title, "Café mode")
        XCTAssertEqual(index().search("café").first?.entry.title, "Café mode")
        XCTAssertEqual(index().search("ESPRESSO").first?.entry.title, "Café mode")
    }

    func testKeywordsAreSearchable() {
        XCTAssertEqual(index().search("karaoke").first?.entry.page, .music)
        XCTAssertEqual(index().bestPage(for: "clock"), .homeHub)
    }

    func testAllTokensMustMatch() {
        XCTAssertEqual(index().search("low alert").map(\.entry.title), ["Low battery alert"])
        XCTAssertTrue(index().search("low lyrics").isEmpty)
    }

    func testNoMatchAndLimit() {
        XCTAssertTrue(index().search("zzzzqq").isEmpty)
        XCTAssertEqual(index().search("a", limit: 2).count, 2)
    }

    func testEqualScoresKeepRegistrationOrder() {
        let idx = SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Alpha one", page: .general, sectionID: "general"),
            SettingsSearchEntry(title: "Alpha two", page: .general, sectionID: "general"),
        ])
        XCTAssertEqual(idx.search("alpha").map(\.entry.title), ["Alpha one", "Alpha two"])
    }

    func testSharedIndexFindsPagesAndLegacyRows() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("about").first?.entry.page, .about)
        XCTAssertEqual(shared.search("launch at login").first?.entry.page, .general)
        XCTAssertEqual(shared.search("lyrics").first?.entry.page, .music)
        XCTAssertEqual(shared.search("low battery").first?.entry.page, .liveActivities)
        XCTAssertEqual(shared.search("stash").first?.entry.page, .stash)
    }

    func testSharedIndexRowsAreMappedToExistingSections() {
        for entry in SettingsSearchIndex.shared.entries {
            if let sectionID = entry.sectionID {
                let tab = SettingsTab(rawValue: sectionID)
                XCTAssertNotNil(tab, entry.title)
                XCTAssertEqual(tab?.page, entry.page, entry.title)
            }
        }
        let ids = SettingsSearchIndex.shared.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate search entry ids")
    }

    // MARK: Native pages

    func testNativePagesHaveNoLegacySectionsAndUniqueItems() {
        for page in NotchlySettingsPage.allCases where page.isNative && page != .about {
            XCTAssertTrue(page.legacySections.isEmpty, "\(page) is native")
            let items = page.nativeItems
            XCTAssertFalse(items.isEmpty, "\(page) has no search items")
            XCTAssertEqual(Set(items.map(\.highlightID)).count, items.count, "\(page) duplicate highlight ids")
            for item in items {
                XCTAssertEqual(item.page, page, item.title)
                XCTAssertFalse(item.keywords.isEmpty, "\(item.title) needs keywords")
            }
        }
    }

    func testEveryNativeItemIsSearchableAndJumpsToItsRow() {
        for page in NotchlySettingsPage.allCases {
            for item in page.nativeItems {
                let hit = SettingsSearchIndex.shared.search(item.title, limit: 20).first { $0.entry.highlightID == item.highlightID }
                XCTAssertNotNil(hit, "\(item.title) not found by its own title")
                XCTAssertEqual(hit?.entry.page, page)
            }
        }
    }

    func testAppearancePageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("minimalistic").first?.entry.page, .appearance)
        XCTAssertEqual(shared.search("corner radius").first?.entry.page, .appearance)
        XCTAssertEqual(shared.search("idle animation").first?.entry.page, .appearance)
        XCTAssertEqual(shared.search("expanded notch width").first?.entry.highlightID, NotchlyAppearancePage.Item.expandedWidth.highlightID)
        XCTAssertEqual(shared.search("app icon").first?.entry.page, .appearance)
    }

    func testHomeHubPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("show seconds").first?.entry.page, .homeHub)
        XCTAssertEqual(shared.search("quick actions").first?.entry.page, .homeHub)
        XCTAssertEqual(shared.search("timer sound").first?.entry.highlightID, NotchlyHomeHubPage.Item.timerSound.highlightID)
        XCTAssertEqual(shared.search("webcam").first?.entry.page, .homeHub)
        XCTAssertEqual(shared.search("paused music").first?.entry.page, .homeHub)
    }

    func testGeneralPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("launch at login").first?.entry.page, .general)
        XCTAssertEqual(shared.search("haptic").first?.entry.page, .general)
        XCTAssertEqual(shared.search("hover delay").first?.entry.highlightID, NotchlyGeneralPage.Item.hoverDelay.highlightID)
    }

    // MARK: Visual check (opt-in)

    /// Renders pages of the settings window to PNGs for eyeballing. Skipped unless
    /// `NOTCHLY_RENDER_DIR` is set (pass it through xcodebuild as
    /// `TEST_RUNNER_NOTCHLY_RENDER_DIR=/some/dir`). `NOTCHLY_RENDER_PAGES` is an
    /// optional comma separated list of page raw values; the default is every page.
    @MainActor
    func testRenderSettingsPagesToPNG() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"], !directory.isEmpty else {
            throw XCTSkip("NOTCHLY_RENDER_DIR not set")
        }
        let wanted = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_PAGES"]?
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let pages = NotchlySettingsPage.allCases.filter { wanted?.contains($0.rawValue) ?? true }
        let heights = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_HEIGHT"].flatMap(Double.init) ?? 1500

        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for page in pages {
            for dark in [false, true] {
                let size = CGSize(width: 1000, height: heights)
                let host = NSHostingView(rootView: NotchlySettingsView(initialPage: page))
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                host.layoutSubtreeIfNeeded()

                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: rep)

                let image = NSImage(size: size)
                image.lockFocus()
                (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                NSRect(origin: .zero, size: size).fill()
                rep.draw(in: NSRect(origin: .zero, size: size))
                image.unlockFocus()

                guard let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(page.rawValue)-\(dark ? "dark" : "light").png"))
            }
        }
    }
}
