import AppKit
import Defaults
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

    // MARK: Search

    private func index() -> SettingsSearchIndex {
        SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Show seconds", keywords: ["clock"], page: .homeHub, highlightID: "hub"),
            SettingsSearchEntry(title: "Battery percentage", keywords: ["charge"], page: .liveActivities, highlightID: "battery"),
            SettingsSearchEntry(title: "Low battery alert", keywords: ["sound"], page: .liveActivities, highlightID: "battery"),
            SettingsSearchEntry(title: "Café mode", keywords: ["espresso"], page: .general, highlightID: "general"),
            SettingsSearchEntry(title: "Enable lyrics", keywords: ["karaoke"], page: .music, highlightID: "media"),
        ])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(index().search("").isEmpty)
        XCTAssertTrue(index().search("   ").isEmpty)
    }

    func testPrefixOutranksWordPrefixOutranksSubstring() {
        let idx = SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Superbat", page: .general, highlightID: "general"),      // substring
            SettingsSearchEntry(title: "Low bat alert", page: .general, highlightID: "general"), // word prefix
            SettingsSearchEntry(title: "Battery", page: .general, highlightID: "general"),       // prefix
        ])
        XCTAssertEqual(idx.search("bat").map(\.entry.title), ["Battery", "Low bat alert", "Superbat"])
    }

    func testTitleOutranksKeyword() {
        let idx = SettingsSearchIndex(entries: [
            SettingsSearchEntry(title: "Alerts", keywords: ["battery"], page: .general, highlightID: "general"),
            SettingsSearchEntry(title: "Battery", page: .general, highlightID: "general"),
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
            SettingsSearchEntry(title: "Alpha one", page: .general, highlightID: "general"),
            SettingsSearchEntry(title: "Alpha two", page: .general, highlightID: "general"),
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

    func testSharedIndexHasUniqueEntryIds() {
        let ids = SettingsSearchIndex.shared.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate search entry ids")
    }

    // MARK: Native pages

    func testNativePagesHaveUniqueItems() {
        for page in NotchlySettingsPage.allCases where page != .about {
            let items = page.nativeItems
            XCTAssertFalse(items.isEmpty, "\(page) has no search items")
            let own = items.filter { $0.anchorTitle == nil }
            XCTAssertEqual(Set(own.map(\.highlightID)).count, own.count, "\(page) duplicate highlight ids")
            XCTAssertEqual(Set(items.map(\.title)).count, items.count, "\(page) duplicate titles")
            // An anchored item has to point at a row that exists on the same page.
            for item in items where item.anchorTitle != nil {
                XCTAssertTrue(own.contains { $0.title == item.anchorTitle }, "\(item.title) is anchored to a missing row")
                XCTAssertNil(item.rowHighlightID)
            }
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

    func testMusicPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("lyrics").first?.entry.page, .music)
        XCTAssertEqual(shared.search("sneak peek style").first?.entry.highlightID, NotchlyMusicPage.Item.sneakPeekStyle.highlightID)
        XCTAssertEqual(shared.search("spotify like").first?.entry.page, .music)
        XCTAssertEqual(shared.search("parallax").first?.entry.page, .music)
        // Rows that only exist while lyrics are on scroll to the lyrics toggle instead.
        XCTAssertEqual(NotchlyMusicPage.Item.lyricHighlight.highlightID, NotchlyMusicPage.Item.lyrics.highlightID)
        XCTAssertEqual(shared.search("lyric highlight").first?.entry.highlightID, NotchlyMusicPage.Item.lyrics.highlightID)
    }

    func testRemovedLegacyRowsAreGone() {
        // Dead experiments that used to be listed under Appearance.
        XCTAssertTrue(SettingsSearchIndex.shared.search("custom visualizers lottie").isEmpty)
    }

    func testGeneralPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("launch at login").first?.entry.page, .general)
        XCTAssertEqual(shared.search("haptic").first?.entry.page, .general)
        XCTAssertEqual(shared.search("hover delay").first?.entry.highlightID, NotchlyGeneralPage.Item.hoverDelay.highlightID)
    }

    func testStashPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("enable stash").first?.entry.highlightID, NotchlyStashPage.Item.enable.highlightID)
        XCTAssertEqual(shared.search("keep items").first?.entry.highlightID, NotchlyStashPage.Item.keepItems.highlightID)
        XCTAssertEqual(shared.search("big files").first?.entry.page, .stash)
        XCTAssertEqual(shared.search("hide previews").first?.entry.highlightID, NotchlyStashPage.Item.hidePreviews.highlightID)
    }

    func testShortcutsPageSearch() {
        let shared = SettingsSearchIndex.shared
        XCTAssertEqual(shared.search("global keyboard").first?.entry.highlightID, NotchlyShortcutsPage.Item.enable.highlightID)
        XCTAssertEqual(shared.search("toggle notch").first?.entry.highlightID, NotchlyShortcutsPage.Item.toggleNotch.highlightID)
        XCTAssertEqual(shared.search("toggle sneak peek").first?.entry.highlightID, NotchlyShortcutsPage.Item.sneakPeek.highlightID)
        // The clipboard shortcut can be set from either page.
        let pages = Set(shared.search("stash clipboard", limit: 20).map(\.entry.page))
        XCTAssertTrue(pages.contains(.shortcuts) && pages.contains(.stash))
    }

    func testLiveActivitiesPageSearch() {
        let shared = SettingsSearchIndex.shared
        for query in ["low battery hud", "charger wattage", "battery health", "critical battery threshold", "bluetooth low battery alert",
                      "caps lock color", "camera detection", "download speed", "lock/unlock sounds", "siri detection", "focus label",
                      "recording hover", "third-party ddc", "volume step", "brightness fine step", "crash report", "airpods listening"] {
            XCTAssertEqual(shared.search(query).first?.entry.page, .liveActivities, query)
        }
        XCTAssertEqual(shared.search("charge limit hud").first?.entry.highlightID, NotchlyLiveActivitiesPage.Item.chargeLimitHUD.highlightID)
        XCTAssertEqual(shared.search("glowing effect").first?.entry.highlightID, NotchlyLiveActivitiesPage.Item.glow.highlightID)
        // Style-specific rows land on the style picker, which is always on screen.
        XCTAssertEqual(shared.search("vertical bar position").first?.entry.highlightID, NotchlyLiveActivitiesPage.Item.displayStyle.highlightID)
        XCTAssertEqual(shared.search("enable custom osd").first?.entry.highlightID, NotchlyLiveActivitiesPage.Item.displayStyle.highlightID)
        XCTAssertEqual(shared.search("lunar provider").first?.entry.page, .liveActivities)
    }

    func testLiveActivitiesSectionsAreAnchoredAndUnique() {
        let sections = NotchlyLiveActivitiesPage.Section.allCases
        XCTAssertEqual(Set(sections.map(\.anchorID)).count, sections.count)
        XCTAssertEqual(Set(sections.map(\.title)).count, sections.count)
        for section in sections {
            XCTAssertNotNil(NSImage(systemSymbolName: section.symbol, accessibilityDescription: nil), "\(section) symbol")
        }
    }

    func testRemovedLegacyRowsStayRemoved() {
        // The music live activity toggle lives on the Music page only.
        let hits = SettingsSearchIndex.shared.search("music live activity", limit: 20)
        XCTAssertTrue(hits.contains { $0.entry.page == .music })
        XCTAssertFalse(hits.contains { $0.entry.page == .liveActivities && !$0.entry.isPageEntry && $0.entry.title.lowercased().contains("music") })
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

        // Optional state overrides so conditional rows can be looked at; restored afterwards.
        let env = ProcessInfo.processInfo.environment
        let savedSource = Defaults[.mediaController]
        let savedLyrics = Defaults[.enableLyrics]
        let savedIdle = Defaults[.showNotHumanFace]
        defer {
            Defaults[.mediaController] = savedSource
            Defaults[.enableLyrics] = savedLyrics
            Defaults[.showNotHumanFace] = savedIdle
        }
        let savedHUD = (Defaults[.enableSystemHUD], Defaults[.enableCustomOSD], Defaults[.enableVerticalHUD], Defaults[.enableCircularHUD])
        let savedDDC = Defaults[.enableThirdPartyDDCIntegration]
        defer {
            (Defaults[.enableSystemHUD], Defaults[.enableCustomOSD], Defaults[.enableVerticalHUD], Defaults[.enableCircularHUD]) = savedHUD
            Defaults[.enableThirdPartyDDCIntegration] = savedDDC
        }
        if let hud = env["NOTCHLY_RENDER_HUD"] {
            Defaults[.enableSystemHUD] = hud == "notch"
            Defaults[.enableCustomOSD] = hud == "osd"
            Defaults[.enableVerticalHUD] = hud == "vertical"
            Defaults[.enableCircularHUD] = hud == "circular"
        }
        if env["NOTCHLY_RENDER_DDC"] == "1" { Defaults[.enableThirdPartyDDCIntegration] = true }
        if let raw = env["NOTCHLY_RENDER_SOURCE"], let source = MediaControllerType(rawValue: raw) { Defaults[.mediaController] = source }
        if env["NOTCHLY_RENDER_LYRICS"] == "1" { Defaults[.enableLyrics] = true }
        if env["NOTCHLY_RENDER_IDLE"] == "1" { Defaults[.showNotHumanFace] = true }

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
