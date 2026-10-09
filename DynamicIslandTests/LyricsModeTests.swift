/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import SwiftUI
import XCTest
@testable import Notchly

// MARK: - Query cleaner

final class LyricsQueryCleanerTests: XCTestCase {

    private func first(_ title: String, _ artist: String, web: Bool = true) -> LyricsQuery? {
        LyricsQueryCleaner.queries(title: title, artist: artist, isWebSource: web).first
    }

    private func assertFirst(
        _ title: String, _ artist: String, web: Bool = true,
        is expected: (String, String), file: StaticString = #filePath, line: UInt = #line
    ) {
        let query = first(title, artist, web: web)
        XCTAssertEqual(query?.artist, expected.0, "artist for \(title) | \(artist)", file: file, line: line)
        XCTAssertEqual(query?.title, expected.1, "title for \(title) | \(artist)", file: file, line: line)
    }

    func testOfficialMusicVideoIsStrippedAndSplit() {
        assertFirst("Rick Astley - Never Gonna Give You Up (Official Music Video)", "Rick Astley",
                    is: ("Rick Astley", "Never Gonna Give You Up"))
    }

    func testTopicChannelSuffixIsDropped() {
        assertFirst("Never Gonna Give You Up", "Rick Astley - Topic", is: ("Rick Astley", "Never Gonna Give You Up"))
        assertFirst("Lose Yourself", "Eminem - Topic", is: ("Eminem", "Lose Yourself"))
    }

    func testVevoChannelIsSplitIntoWords() {
        assertFirst("Rick Astley - Never Gonna Give You Up (Official Video) [4K Remaster]", "RickAstleyVEVO",
                    is: ("Rick Astley", "Never Gonna Give You Up"))
        XCTAssertEqual(LyricsQueryCleaner.cleanArtist("TaylorSwiftVEVO"), "Taylor Swift")
        XCTAssertEqual(LyricsQueryCleaner.cleanArtist("AdeleVEVO"), "Adele")
    }

    func testFeaturedArtistAfterBracketIsRemoved() {
        assertFirst("Mark Ronson - Uptown Funk (Official Video) ft. Bruno Mars", "MarkRonsonVEVO",
                    is: ("Mark Ronson", "Uptown Funk"))
    }

    func testOfficialAudio() {
        assertFirst("The Weeknd - Blinding Lights (Official Audio)", "TheWeekndVEVO", is: ("The Weeknd", "Blinding Lights"))
    }

    func testLyricsChannelUsesArtistFromTitle() {
        assertFirst("Billie Eilish - bad guy (Lyrics)", "7clouds", is: ("Billie Eilish", "bad guy"))
    }

    func testPlainArtistDashTitle() {
        assertFirst("Adele - Hello", "AdeleVEVO", is: ("Adele", "Hello"))
    }

    func testEnDashAndOfficialChannel() {
        assertFirst("Queen – Bohemian Rhapsody (Official Video Remastered)", "Queen Official", is: ("Queen", "Bohemian Rhapsody"))
    }

    func testFeaturingWordBeforeBracket() {
        assertFirst("Dua Lipa - Levitating Featuring DaBaby (Official Music Video)", "Dua Lipa", is: ("Dua Lipa", "Levitating"))
    }

    func testSquareBracketLyricVideo() {
        assertFirst("Ed Sheeran - Shape of You [Official Lyric Video]", "Ed Sheeran", is: ("Ed Sheeran", "Shape of You"))
    }

    func testPipeSuffixAndHD() {
        assertFirst("Imagine Dragons - Believer (Official Music Video) | HD", "ImagineDragonsVEVO", is: ("Imagine Dragons", "Believer"))
        assertFirst("Coldplay - Viva La Vida (Official Video) [HD]", "Coldplay", is: ("Coldplay", "Viva La Vida"))
    }

    func testKpopQuotedTitle() {
        assertFirst("BTS (방탄소년단) 'Dynamite' Official MV", "HYBE LABELS", is: ("BTS", "Dynamite"))
    }

    func testJapaneseCornerBrackets() {
        assertFirst("YOASOBI「アイドル」 Official Music Video", "Ayase / YOASOBI", is: ("YOASOBI", "アイドル"))
    }

    func testFeaturingListAfterAudio() {
        assertFirst("Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams, Nile Rodgers", "Daft Punk",
                    is: ("Daft Punk", "Get Lucky"))
    }

    func testEmojiNoise() {
        assertFirst("🔥 Travis Scott - SICKO MODE (Audio) 🔥", "Travis Scott", is: ("Travis Scott", "SICKO MODE"))
    }

    func testTrailingOfficialMusicVideoAfterDash() {
        assertFirst("Gotye - Somebody That I Used To Know (feat. Kimbra) - official music video", "gotye",
                    is: ("Gotye", "Somebody That I Used To Know"))
    }

    func testMeaningfulParenthesesAreKept() {
        assertFirst("Blue Öyster Cult - (Don't Fear) The Reaper", "Blue Öyster Cult",
                    is: ("Blue Öyster Cult", "(Don't Fear) The Reaper"))
    }

    func testOfficialVevoChannel() {
        assertFirst("Avicii - Wake Me Up (Official Video)", "AviciiOfficialVEVO", is: ("Avicii", "Wake Me Up"))
    }

    func testTaylorSwiftVevo() {
        assertFirst("Taylor Swift - Anti-Hero (Official Music Video)", "TaylorSwiftVEVO", is: ("Taylor Swift", "Anti-Hero"))
    }

    func testReversedTitleDashArtist() {
        assertFirst("Hurt - Johnny Cash", "Johnny Cash", is: ("Johnny Cash", "Hurt"))
    }

    func testDashFeaturingInTitle() {
        assertFirst("Kygo - Firestone ft. Conrad Sewell", "Kygo", is: ("Kygo", "Firestone"))
    }

    func testOfficialVideoWithoutDash() {
        assertFirst("Don't Stop Me Now (Official Video)", "Queen Official", is: ("Queen", "Don't Stop Me Now"))
    }

    func testApostrophesAreNotQuotes() {
        assertFirst("Rock 'n' Roll Star", "Oasis", is: ("Oasis", "Rock 'n' Roll Star"))
    }

    // Music-app metadata stays as it is apart from the existing version noise.

    func testCleanAppMetadataIsUntouched() {
        assertFirst("Shape of You", "Ed Sheeran", web: false, is: ("Ed Sheeran", "Shape of You"))
        assertFirst("Mr. Brightside", "The Killers", web: false, is: ("The Killers", "Mr. Brightside"))
    }

    func testRemasterSuffixes() {
        assertFirst("Bohemian Rhapsody - Remastered 2011", "Queen", web: false, is: ("Queen", "Bohemian Rhapsody"))
        assertFirst("Hotel California (2013 Remaster)", "Eagles", web: false, is: ("Eagles", "Hotel California"))
    }

    func testFeatAndWithInParentheses() {
        assertFirst("Uptown Funk (feat. Bruno Mars)", "Mark Ronson", web: false, is: ("Mark Ronson", "Uptown Funk"))
        assertFirst("Stay (with Justin Bieber)", "The Kid LAROI", web: false, is: ("The Kid LAROI", "Stay"))
    }

    func testLiveSuffix() {
        assertFirst("Smells Like Teen Spirit (Live)", "Nirvana", web: false, is: ("Nirvana", "Smells Like Teen Spirit"))
    }

    func testRemixIsAVersionNotNoise() {
        assertFirst("Despacito (Remix)", "Luis Fonsi", web: false, is: ("Luis Fonsi", "Despacito (Remix)"))
    }

    func testDefeatedIsNotAFeat() {
        XCTAssertEqual(LyricsQueryCleaner.cleanTitle("Undefeated (Defeated Mix)"), "Undefeated (Defeated Mix)")
    }

    func testAppTitleWithDashIsNotSplitForAPerformer() {
        // "Song - Acoustic" by a performer from a music app: not "Artist - Title".
        let queries = LyricsQueryCleaner.queries(title: "Yellow - Acoustic", artist: "Coldplay", isWebSource: false)
        XCTAssertEqual(queries.first, LyricsQuery(artist: "Coldplay", title: "Yellow - Acoustic"))
    }

    func testEmptyArtistUsesTitleSplit() {
        assertFirst("Rick Astley - Never Gonna Give You Up", "", is: ("Rick Astley", "Never Gonna Give You Up"))
    }

    func testNoQueryWhenNothingIdentifiesASong() {
        XCTAssertTrue(LyricsQueryCleaner.queries(title: "Never Gonna Give You Up", artist: "").isEmpty)
        XCTAssertTrue(LyricsQueryCleaner.queries(title: "Track 7", artist: "Unknown Artist").isEmpty)
    }

    func testQueriesAreDeduplicated() {
        let queries = LyricsQueryCleaner.queries(title: "Hello", artist: "Adele", isWebSource: true)
        XCTAssertEqual(queries, [LyricsQuery(artist: "Adele", title: "Hello")])
    }

    func testWebSourceDetection() {
        XCTAssertTrue(LyricsQueryCleaner.isWebSource(bundleIdentifier: "com.google.Chrome"))
        XCTAssertTrue(LyricsQueryCleaner.isWebSource(bundleIdentifier: "com.apple.Safari"))
        XCTAssertTrue(LyricsQueryCleaner.isWebSource(bundleIdentifier: "company.thebrowser.Browser"))
        XCTAssertFalse(LyricsQueryCleaner.isWebSource(bundleIdentifier: "com.apple.Music"))
        XCTAssertFalse(LyricsQueryCleaner.isWebSource(bundleIdentifier: "com.spotify.client"))
        XCTAssertFalse(LyricsQueryCleaner.isWebSource(bundleIdentifier: nil))
    }

    func testDurationTolerance() {
        XCTAssertTrue(LyricsQueryCleaner.durationsAgree(213, 214.5, tolerance: 3))
        XCTAssertFalse(LyricsQueryCleaner.durationsAgree(213, 240, tolerance: 3))
        XCTAssertTrue(LyricsQueryCleaner.durationsAgree(0, 240, tolerance: 3), "unknown never rules out")
        XCTAssertGreaterThan(
            LyricsQueryCleaner.durationTolerance(isWebSource: true),
            LyricsQueryCleaner.durationTolerance(isWebSource: false)
        )
    }
}

// MARK: - Timeline

final class LyricsTimelineTests: XCTestCase {
    private let stamps: [TimeInterval] = [5, 10, 10, 15.5, 20]

    func testBeforeFirstLineIsMinusOne() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 0), -1)
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 4.999), -1)
    }

    func testExactTimestampSelectsThatLine() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 5), 0)
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 15.5), 3)
    }

    func testBetweenLines() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 7), 0)
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 17), 3)
    }

    func testSharedTimestampResolvesToLastOfThem() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 10), 2)
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 12), 2)
    }

    func testAfterLastLine() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: 999), 4)
    }

    func testEmptyAndNonFinite() {
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: [], at: 10), -1)
        XCTAssertEqual(LyricsTimeline.activeIndex(timestamps: stamps, at: .nan), -1)
    }

    func testMatchesLinearScanEverywhere() {
        let lines = LRCParser.parse("[00:01.00]a\n[00:02.50]b\n[00:02.50]c\n[00:07.00]\n[00:09.25]d\n[01:00.00]e")
        for step in 0...700 {
            let time = Double(step) / 10
            let linear = lines.lastIndex { $0.timestamp <= time } ?? -1
            XCTAssertEqual(LyricsTimeline.activeIndex(in: lines, at: time), linear, "t=\(time)")
        }
    }

    func testOffsetTagShiftsTheActiveLine() {
        // [offset:+500] makes every line show half a second earlier.
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]first\n[00:20.00]second")
        XCTAssertEqual(LyricsTimeline.activeIndex(in: lines, at: 9.5), 0)
        XCTAssertEqual(LyricsTimeline.activeIndex(in: lines, at: 9.4), -1)
        XCTAssertEqual(LyricsTimeline.activeIndex(in: lines, at: 19.6), 1)
    }

    func testLeadTimeIsAppliedBeforeTheLookup() {
        // The manager adds a quarter second of lead before looking the line up.
        let lines = LRCParser.parse("[00:10.00]first\n[00:20.00]second")
        XCTAssertEqual(LyricsTimeline.activeIndex(in: lines, at: 9.8 + MusicManager.lyricLeadTime), 0)
    }
}

// MARK: - LRCLIB parsing

final class LRCLIBLyricsTests: XCTestCase {

    static let getFixture = """
    {"id":1009665,"name":"Never Gonna Give You Up","trackName":"Never Gonna Give You Up","artistName":"Rick Astley",
     "albumName":"Whenever You Need Somebody","duration":214.0,"instrumental":false,
     "plainLyrics":"We're no strangers to love\\nYou know the rules and so do I",
     "syncedLyrics":"[00:18.80] We're no strangers to love\\n[00:22.84] You know the rules and so do I"}
    """

    static let searchFixture = """
    [
     {"id":1,"trackName":"Blinding Lights","artistName":"The Weeknd","albumName":"After Hours","duration":200.0,
      "instrumental":false,"plainLyrics":"Yeah","syncedLyrics":"[00:01.00]Yeah"},
     {"id":2,"trackName":"Blinding Lights","artistName":"The Weeknd","albumName":"Blinding Lights (Remixes)","duration":262.0,
      "instrumental":false,"plainLyrics":"Remix words","syncedLyrics":"[00:05.00]Remix words"},
     {"id":3,"trackName":"Blinding Lights (Karaoke)","artistName":"Sing King","albumName":"","duration":200.0,
      "instrumental":false,"plainLyrics":"Karaoke","syncedLyrics":"[00:01.00]Karaoke"}
    ]
    """

    func testGetResponseParsesToTimedLyrics() throws {
        let row = try XCTUnwrap(LRCLIBLyrics.parseGetResponse(Data(Self.getFixture.utf8)))
        let resolution = LRCLIBLyrics.resolution(
            for: row, query: LyricsQuery(artist: "Rick Astley", title: "Never Gonna Give You Up"), duration: 213
        )
        XCTAssertEqual(resolution.availability, .timed)
        XCTAssertEqual(resolution.lines.count, 2)
        XCTAssertEqual(resolution.lines.first?.timestamp ?? 0, 18.8, accuracy: 0.001)
        XCTAssertEqual(resolution.lines.first?.text, "We're no strangers to love")
    }

    func testNotFoundBodyIsNotARow() {
        let body = #"{"code":404,"name":"TrackNotFound","message":"Failed to find specified track"}"#
        XCTAssertNil(LRCLIBLyrics.parseGetResponse(Data(body.utf8)))
        XCTAssertTrue(LRCLIBLyrics.parseSearchResponse(Data("garbage".utf8)).isEmpty)
    }

    func testPlainOnlyRowIsUntimed() throws {
        let body = #"{"trackName":"Song","artistName":"Band","duration":180,"instrumental":false,"plainLyrics":"one\ntwo","syncedLyrics":null}"#
        let row = try XCTUnwrap(LRCLIBLyrics.parseGetResponse(Data(body.utf8)))
        let resolution = LRCLIBLyrics.resolution(for: row, query: LyricsQuery(artist: "Band", title: "Song"), duration: 180)
        XCTAssertEqual(resolution.availability, .untimed)
        XCTAssertEqual(resolution.lines.map(\.text), ["one", "two"])
        XCTAssertFalse(resolution.lines.contains { $0.isTimed })
    }

    func testInstrumentalRow() throws {
        let body = #"{"trackName":"Song","artistName":"Band","duration":180,"instrumental":true,"plainLyrics":null,"syncedLyrics":null}"#
        let row = try XCTUnwrap(LRCLIBLyrics.parseGetResponse(Data(body.utf8)))
        XCTAssertEqual(
            LRCLIBLyrics.resolution(for: row, query: LyricsQuery(artist: "Band", title: "Song"), duration: 180).availability,
            .instrumental
        )
    }

    func testSearchPrefersTheRowWhoseLengthAgrees() throws {
        let rows = LRCLIBLyrics.parseSearchResponse(Data(Self.searchFixture.utf8))
        XCTAssertEqual(rows.count, 3)
        let query = LyricsQuery(artist: "The Weeknd", title: "Blinding Lights")
        let match = try XCTUnwrap(LRCLIBLyrics.bestSearchMatch(in: rows, query: query, album: "", duration: 201, tolerance: 3))
        XCTAssertEqual(match["id"] as? Int, 1)
        // The remix length matches only when that is what is playing.
        let remix = try XCTUnwrap(LRCLIBLyrics.bestSearchMatch(in: rows, query: query, album: "", duration: 262, tolerance: 3))
        XCTAssertEqual(remix["id"] as? Int, 2)
    }

    func testSearchRejectsTimedRowsOfTheWrongLength() {
        let rows = LRCLIBLyrics.parseSearchResponse(Data(Self.searchFixture.utf8))
        let query = LyricsQuery(artist: "The Weeknd", title: "Blinding Lights")
        XCTAssertNil(LRCLIBLyrics.bestSearchMatch(in: rows, query: query, album: "", duration: 400, tolerance: 3))
    }

    func testURLsCarryOnlyArtistTitleAndDuration() throws {
        let get = try XCTUnwrap(LRCLIBLyrics.getURL(artist: "Beyoncé", title: "Halo & Love", duration: 261.6))
        XCTAssertEqual(get.host, "lrclib.net")
        let items = URLComponents(url: get, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Set(items.map(\.name)), ["artist_name", "track_name", "duration"])
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "Halo & Love")
        XCTAssertEqual(items.first { $0.name == "artist_name" }?.value, "Beyonce")
        XCTAssertEqual(items.first { $0.name == "duration" }?.value, "262")
        XCTAssertNil(LRCLIBLyrics.getURL(artist: "A", title: "B", duration: 0), "get needs a duration")
        XCTAssertNotNil(LRCLIBLyrics.searchURL(artist: "A", title: "B"))
    }

    func testSessionIdentifiesItselfAndTimesOutQuickly() {
        let configuration = LyricsNetwork.lrclibSession.configuration
        XCTAssertLessThanOrEqual(configuration.timeoutIntervalForRequest, 8)
        XCTAssertEqual(configuration.httpAdditionalHeaders?["User-Agent"] as? String, LyricsNetwork.userAgent)
        XCTAssertTrue(LyricsNetwork.userAgent.contains("Notchly"))
    }
}

// MARK: - Cache

final class LyricsCacheTests: XCTestCase {

    func testLRUEvictsTheOldest() {
        var lru = LyricsLRU<String, Int>(capacity: 2)
        lru.insert(1, for: "a")
        lru.insert(2, for: "b")
        let evicted = lru.insert(3, for: "c")
        XCTAssertEqual(evicted, ["a"])
        XCTAssertNil(lru.peek("a"))
        XCTAssertEqual(lru.count, 2)
    }

    func testReadingMakesAnEntryNewest() {
        var lru = LyricsLRU<String, Int>(capacity: 2)
        lru.insert(1, for: "a")
        lru.insert(2, for: "b")
        XCTAssertEqual(lru.value(for: "a"), 1)
        lru.insert(3, for: "c")
        XCTAssertNotNil(lru.peek("a"))
        XCTAssertNil(lru.peek("b"))
        XCTAssertEqual(lru.order, ["a", "c"])
    }

    func testReplacingDoesNotGrow() {
        var lru = LyricsLRU<String, Int>(capacity: 3)
        lru.insert(1, for: "a")
        lru.insert(2, for: "a")
        XCTAssertEqual(lru.count, 1)
        XCTAssertEqual(lru.peek("a"), 2)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-cache-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDiskCacheRoundTripsAndSurvivesRelaunch() {
        let directory = temporaryDirectory()
        let cache = LyricsDiskCache(directory: directory, capacity: 3)
        let lyrics = LyricsResolution(lines: LRCParser.parse("[00:01.00]hello\n[00:02.00]world"))
        let key = LyricsDiskCache.key(artist: "Adele", title: "Hello", duration: 295.4)
        cache.store(lyrics, for: key)
        cache.flush()

        let reopened = LyricsDiskCache(directory: directory, capacity: 3)
        let restored = reopened.lookup(key)
        XCTAssertEqual(restored?.availability, .timed)
        XCTAssertEqual(restored?.lines, lyrics.lines)
    }

    func testDiskCacheEvictsBeyondCapacity() {
        let directory = temporaryDirectory()
        let cache = LyricsDiskCache(directory: directory, capacity: 2)
        for name in ["a", "b", "c"] {
            cache.store(LyricsResolution(lines: [LyricLine(timestamp: 0, text: name, isTimed: false)]), for: name)
        }
        cache.flush()
        let reopened = LyricsDiskCache(directory: directory, capacity: 2)
        XCTAssertEqual(reopened.count, 2)
        XCTAssertNil(reopened.lookup("a"))
        XCTAssertNotNil(reopened.lookup("c"))
    }

    func testNothingFoundIsNeverCached() {
        let cache = LyricsDiskCache(directory: temporaryDirectory(), capacity: 2)
        cache.store(LyricsResolution(), for: "x")
        XCTAssertNil(cache.lookup("x"))
    }

    func testInstrumentalIsCached() {
        let cache = LyricsDiskCache(directory: temporaryDirectory(), capacity: 2)
        cache.store(LyricsResolution(instrumental: true), for: "i")
        XCTAssertEqual(cache.lookup("i")?.availability, .instrumental)
    }

    func testKeyNormalisesCaseDiacriticsAndRoundsDuration() {
        XCTAssertEqual(
            LyricsDiskCache.key(artist: "Beyoncé", title: "  HALO ", duration: 261.4),
            LyricsDiskCache.key(artist: "beyonce", title: "halo", duration: 260.6)
        )
        XCTAssertNotEqual(
            LyricsDiskCache.key(artist: "a", title: "b", duration: 100),
            LyricsDiskCache.key(artist: "a", title: "b", duration: 200)
        )
    }
}

// MARK: - Stage state machine

final class LyricsStageStateTests: XCTestCase {

    func testStates() {
        func state(_ availability: LyricsAvailability, track: Bool = true, ad: Bool = false, online: Bool = true) -> LyricsStageState {
            LyricsStageState.resolve(hasTrack: track, isAdvertisement: ad, fetchOnline: online, availability: availability)
        }
        XCTAssertEqual(state(.timed, track: false), .nothingPlaying)
        XCTAssertEqual(state(.timed, ad: true), .nothingPlaying)
        XCTAssertEqual(state(.timed, online: false), .onlineLookupOff)
        XCTAssertEqual(state(.loading), .searching)
        XCTAssertEqual(state(.timed), .synced)
        XCTAssertEqual(state(.untimed), .unsynced)
        XCTAssertEqual(state(.instrumental), .instrumental)
        XCTAssertEqual(state(.unavailable), .notFound)
    }

    func testWindowAnchorsOnTheCurrentRow() throws {
        let window = try XCTUnwrap(LyricsStageWindow.window(rowIndices: [0, 1, 2, 3, 4, 5, 6, 7, 8], currentIndex: 4))
        XCTAssertEqual(window.rows, [2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(window.rows[window.anchor], 4)
        XCTAssertTrue(window.anchorIsCurrent)
    }

    func testWindowBeforeTheFirstLineAnchorsOnTheFirstRowUnlit() throws {
        let window = try XCTUnwrap(LyricsStageWindow.window(rowIndices: [0, 1, 2], currentIndex: -1))
        XCTAssertEqual(window.anchor, 0)
        XCTAssertFalse(window.anchorIsCurrent)
    }

    func testShortGapKeepsThePreviousLineAnchored() throws {
        // Index 3 is a short blank gap with no row of its own.
        let window = try XCTUnwrap(LyricsStageWindow.window(rowIndices: [0, 1, 2, 4, 5], currentIndex: 3))
        XCTAssertEqual(window.rows[window.anchor], 2)
        XCTAssertFalse(window.anchorIsCurrent)
    }

    func testWindowEdges() throws {
        XCTAssertNil(LyricsStageWindow.window(rowIndices: [], currentIndex: 0))
        let end = try XCTUnwrap(LyricsStageWindow.window(rowIndices: [0, 1, 2], currentIndex: 9))
        XCTAssertEqual(end.rows[end.anchor], 2)
    }

    func testCreditsAreNotDisplayed() {
        let lines = LRCParser.parse("[00:00.00]作词 : Someone\n[00:01.00]Producer: X\n[00:05.00]Real words")
        let rows = LyricsStageWindow.displayRows(lines: lines, duration: 30)
        XCTAssertEqual(rows.count, 1)
        if case let .line(_, text) = rows[0] { XCTAssertEqual(text, "Real words") } else { XCTFail() }
    }

    func testLyricsModeToggles() {
        let mode = LyricsModeController(initial: false)
        XCTAssertFalse(mode.isActive)
        mode.toggle()
        XCTAssertTrue(mode.isActive)
        mode.set(false)
        XCTAssertFalse(mode.isActive)
    }
}

// MARK: - Rendering (throwaway: run with NOTCHLY_RENDER_DIR set)

final class LyricsStageRenderTests: XCTestCase {

    @MainActor
    func testRenderLyricsStagesToPNG() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"], !directory.isEmpty else {
            throw XCTSkip("NOTCHLY_RENDER_DIR not set")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let lrc = """
        [00:00.00]作词 : Someone
        [00:12.00]Is this the real life?
        [00:15.50]Is this just fantasy?
        [00:19.00]Caught in a landslide, no escape from reality
        [00:25.00]Open your eyes, look up to the skies and see
        [00:31.00]I'm just a poor boy, I need no sympathy
        [00:36.00]Because I'm easy come, easy go
        [00:39.00]Little high, little low
        """
        let lines = LRCParser.parse(lrc)
        let rows = LyricsStageWindow.displayRows(lines: lines, duration: 60)
        let plain = LyricLine.untimedLines(from: "Is this the real life?\nIs this just fantasy?\nCaught in a landslide\nNo escape from reality\nOpen your eyes")

        func snapshot(_ state: LyricsStageState, lines: [LyricLine] = [], rows: [LyricRow] = [], current: Int = -1, playing: Bool = true) -> LyricsStageSnapshot {
            LyricsStageSnapshot(state: state, lines: lines, rows: rows, currentIndex: current, isPlaying: playing, canSeek: true,
                                accent: NotchlyTheme.Palette.silver)
        }

        let cases: [(String, LyricsStageSnapshot, LyricsTextSize, Double)] = [
            ("searching", snapshot(.searching), .medium, 0),
            ("synced-mid", snapshot(.synced, lines: lines, rows: rows, current: 3), .medium, 0.45),
            ("synced-start", snapshot(.synced, lines: lines, rows: rows, current: -1), .medium, 0),
            ("synced-paused-large", snapshot(.synced, lines: lines, rows: rows, current: 4, playing: false), .large, 0.7),
            ("synced-small", snapshot(.synced, lines: lines, rows: rows, current: 2), .small, 0.2),
            ("unsynced", snapshot(.unsynced, lines: plain), .medium, 0),
            ("not-found", snapshot(.notFound), .medium, 0),
            ("instrumental", snapshot(.instrumental), .medium, 0),
            ("offline", snapshot(.onlineLookupOff), .medium, 0),
        ]

        for (name, snap, size, progress) in cases {
            let view = LyricsStageContent(snapshot: snap, textSize: size, animatesSweep: false, progress: { _ in progress })
                .frame(width: HomeLayoutBudget.hubWidth, height: HomeLayoutBudget.hubHeight)
                .padding(16)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            let size = CGSize(width: HomeLayoutBudget.hubWidth + 32, height: HomeLayoutBudget.hubHeight + 32)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            host.layoutSubtreeIfNeeded()

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("lyrics-\(name).png"))
        }
    }

    /// The Home tab with lyrics mode on, to check the title-row button and the
    /// card's footprint against the Hub's. Same opt-in as above.
    @MainActor
    func testRenderHomeWithLyricsModeToPNG() throws {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"], !directory.isEmpty else {
            throw XCTSkip("NOTCHLY_RENDER_DIR not set")
        }
        let coordinator = DynamicIslandViewCoordinator.shared
        let savedFirstLaunch = coordinator.firstLaunch
        let savedMode = LyricsModeController.shared.isActive
        defer {
            coordinator.firstLaunch = savedFirstLaunch
            LyricsModeController.shared.set(savedMode)
        }
        coordinator.firstLaunch = false

        let vm = DynamicIslandViewModel()
        for active in [false, true] {
            LyricsModeController.shared.set(active)
            let size = openNotchSize
            let view = HomeRenderHost()
                .environmentObject(vm)
                .frame(width: size.width, height: size.height)
                .background(Color.black)
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(1.2))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("home-lyrics-\(active ? "on" : "off").png"))
        }
    }
}

private struct HomeRenderHost: View {
    @Namespace private var namespace
    var body: some View {
        NotchHomeView(albumArtNamespace: namespace)
            .padding(.top, 34)
    }
}
