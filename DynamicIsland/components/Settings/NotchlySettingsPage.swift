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

// MARK: - Page registry

/// The pages of the Notchly settings window, in sidebar order.
enum NotchlySettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case appearance
    case homeHub
    case music
    case liveActivities
    case stash
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .appearance: return String(localized: "Appearance")
        case .homeHub: return String(localized: "Home & Hub")
        case .music: return String(localized: "Music")
        case .liveActivities: return String(localized: "Live Activities")
        case .stash: return String(localized: "Stash")
        case .shortcuts: return String(localized: "Shortcuts")
        case .about: return String(localized: "About")
        }
    }

    /// SF Symbol shown in the sidebar tile and in search results.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .homeHub: return "house"
        case .music: return "music.note"
        case .liveActivities: return "waveform.path.ecg"
        case .stash: return "tray.and.arrow.down"
        case .shortcuts: return "command"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "Displays, gestures, hover and startup behaviour.")
        case .appearance: return String(localized: "Notch shape, size, effects and the idle face.")
        case .homeHub: return String(localized: "The centre Hub, its clock and chips, plus quick actions.")
        case .music: return String(localized: "Now playing, lyrics and media sources.")
        case .liveActivities: return String(localized: "Battery, devices, volume and brightness HUDs, recording, focus and lock screen.")
        case .stash: return String(localized: "The temporary text and file tray in the notch.")
        case .shortcuts: return String(localized: "Global keyboard shortcuts.")
        case .about: return String(localized: "Version, credits and license.")
        }
    }

    /// Words that should surface this page in search even when no row title matches.
    var keywords: [String] {
        switch self {
        case .general:
            return ["displays", "monitor", "launch at login", "gestures", "hover", "haptics", "menu bar", "screenshot", "privacy", "startup"]
        case .appearance:
            return ["look", "theme", "shape", "corner radius", "width", "mirror", "spectrogram", "icon", "idle animation", "shadow"]
        case .homeHub:
            return ["hub", "clock", "date", "chips", "quick actions", "timer", "stopwatch", "home", "centre", "center"]
        case .music:
            return ["media", "now playing", "lyrics", "spotify", "apple music", "album art", "player", "source", "canvas"]
        case .liveActivities:
            return ["battery", "charging", "bluetooth", "devices", "hud", "osd", "volume", "brightness", "recording", "focus", "camera", "microphone", "lock screen", "downloads", "controls"]
        case .stash:
            return ["tray", "shelf", "clipboard", "files", "drop", "temporary", "retention"]
        case .shortcuts:
            return ["keyboard", "hotkey", "key bindings", "global shortcuts"]
        case .about:
            return ["version", "build", "credits", "license", "gpl", "acknowledgements", "atoll", "boring notch"]
        }
    }

    /// Sidebar order (the `allCases` order), without `about`, which sits in the footer link.
    static var sidebarPages: [NotchlySettingsPage] {
        allCases.filter { $0 != .about }
    }
}

// MARK: - Search index

/// One searchable thing in settings: a whole page, or a single row inside one.
struct SettingsSearchEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let keywords: [String]
    let page: NotchlySettingsPage
    /// Which sub-section of the page contains the row (a legacy tab raw value), if any.
    let sectionID: String?
    /// Scroll / highlight anchor of the row, if it has one.
    let highlightID: String?

    var isPageEntry: Bool { sectionID == nil && highlightID == nil }

    init(
        id: String? = nil,
        title: String,
        keywords: [String] = [],
        page: NotchlySettingsPage,
        sectionID: String? = nil,
        highlightID: String? = nil
    ) {
        self.id = id ?? "\(page.rawValue)/\(sectionID ?? "-")/\(title)"
        self.title = title
        self.keywords = keywords
        self.page = page
        self.sectionID = sectionID
        self.highlightID = highlightID
    }

    static func entry(for page: NotchlySettingsPage) -> SettingsSearchEntry {
        SettingsSearchEntry(id: "page/\(page.rawValue)", title: page.title, keywords: page.keywords, page: page)
    }
}

struct SettingsSearchResult: Identifiable, Equatable {
    let entry: SettingsSearchEntry
    let score: Int
    var id: String { entry.id }
}

/// Pure, case- and diacritic-insensitive search over settings entries.
///
/// Ranking per query token (best match wins):
/// title prefix > title word prefix > title substring > keyword prefix >
/// keyword word prefix > keyword substring. Every token of the query has to
/// match somewhere in the entry (title, keywords or page title); the entry
/// score is the sum of the token scores, so more specific queries rank rows
/// that match more of what was typed above rows that match less.
struct SettingsSearchIndex {
    let entries: [SettingsSearchEntry]

    init(entries: [SettingsSearchEntry]) {
        self.entries = entries
    }

    /// Lowercases, strips diacritics and collapses whitespace.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        return folded
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    func search(_ query: String, limit: Int = 8) -> [SettingsSearchResult] {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)

        var results: [(index: Int, result: SettingsSearchResult)] = []
        for (index, entry) in entries.enumerated() {
            guard let score = Self.score(entry: entry, tokens: tokens, fullQuery: normalizedQuery) else { continue }
            results.append((index, SettingsSearchResult(entry: entry, score: score)))
        }

        results.sort { lhs, rhs in
            if lhs.result.score != rhs.result.score { return lhs.result.score > rhs.result.score }
            return lhs.index < rhs.index
        }
        return Array(results.prefix(limit).map(\.result))
    }

    /// The first result's page, handy for "jump to best match".
    func bestPage(for query: String) -> NotchlySettingsPage? {
        search(query, limit: 1).first?.entry.page
    }

    // MARK: Scoring

    private enum Tier {
        static let titlePrefix = 100
        static let titleWordPrefix = 80
        static let titleSubstring = 60
        static let keywordPrefix = 50
        static let keywordWordPrefix = 40
        static let keywordSubstring = 25
        static let pageTitle = 15
        static let wholeTitleBonus = 25
        static let pageEntryBonus = 5
    }

    private static func score(entry: SettingsSearchEntry, tokens: [String], fullQuery: String) -> Int? {
        let title = normalize(entry.title)
        let keywords = entry.keywords.map(normalize)
        let pageTitle = normalize(entry.page.title)

        var total = 0
        for token in tokens {
            var best = tier(of: token, in: title, prefix: Tier.titlePrefix, wordPrefix: Tier.titleWordPrefix, substring: Tier.titleSubstring)
            for keyword in keywords {
                let value = tier(of: token, in: keyword, prefix: Tier.keywordPrefix, wordPrefix: Tier.keywordWordPrefix, substring: Tier.keywordSubstring)
                best = max(best, value)
            }
            if best == 0, pageTitle.contains(token) { best = Tier.pageTitle }
            guard best > 0 else { return nil }
            total += best
        }

        if title.hasPrefix(fullQuery) { total += Tier.wholeTitleBonus }
        if entry.isPageEntry { total += Tier.pageEntryBonus }
        return total
    }

    private static func tier(of token: String, in text: String, prefix: Int, wordPrefix: Int, substring: Int) -> Int {
        guard !text.isEmpty else { return 0 }
        var best = 0
        var searchStart = text.startIndex
        while let range = text.range(of: token, range: searchStart..<text.endIndex) {
            if range.lowerBound == text.startIndex {
                return prefix
            }
            let before = text[text.index(before: range.lowerBound)]
            best = max(best, (!before.isLetter && !before.isNumber) ? wordPrefix : substring)
            searchStart = text.index(after: range.lowerBound)
        }
        return best
    }
}
