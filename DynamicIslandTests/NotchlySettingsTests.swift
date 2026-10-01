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
}
