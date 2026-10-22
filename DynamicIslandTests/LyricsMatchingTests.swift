/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import XCTest
@testable import Notchly

// Findings these tests pin down, measured against lrclib.net with 135 real
// tracks (Apple Music and Spotify spellings):
//
//  * about one `get` in five and more `search`es answer `503 ServerOverloaded`,
//    and a retry a moment later succeeds -- the first 503 used to be "no lyrics";
//  * `search` returns twenty rows at most, so for a hit the exact-length row can
//    be missing from the page (see `LyricsFixtures.worryChild*`);
//  * `search` with an artist field like "Post Malone, Swae Lee" finds nothing;
//  * the old ranking ignored length, so in 43% of search picks a row up to 2.8s
//    further from the track's length than the closest candidate was chosen.

// MARK: - Fixtures

private func fixtureRows(_ json: String) -> [[String: Any]] {
    LRCLIBLyrics.parseSearchResponse(Data(json.utf8))
}

private func lrclibRow(
    id: Int = 1, title: String, artist: String, album: String = "", duration: Double?,
    synced: Bool = true, plain: Bool = true, instrumental: Bool = false
) -> [String: Any] {
    var row: [String: Any] = [
        "id": id, "trackName": title, "artistName": artist, "albumName": album,
        "instrumental": instrumental
    ]
    if let duration { row["duration"] = duration }
    row["syncedLyrics"] = synced ? "[00:01.00]one\n[00:03.00]two" : NSNull()
    row["plainLyrics"] = plain ? "one\ntwo" : NSNull()
    return row
}

private func request(
    _ title: String, _ artist: String, album: String = "", duration: Double, tolerance: Double = 4
) -> LyricsMatchRequest {
    LyricsMatchRequest(titles: [title], originalTitle: title, artists: [artist], album: album, duration: duration, tolerance: tolerance)
}

// MARK: - Text and artists

final class LyricsTextTests: XCTestCase {

    func testCurlyQuotesAndDashesBecomeStraight() {
        XCTAssertEqual(LyricsText.canonical("Don\u{2019}t Stop Believin\u{2019}"), "Don't Stop Believin'")
        XCTAssertEqual(LyricsText.canonical("\u{201C}Heroes\u{201D}"), "\"Heroes\"")
        XCTAssertEqual(LyricsText.canonical("A \u{2013} B \u{2014} C"), "A - B - C")
    }

    func testFullWidthFoldsToAscii() {
        XCTAssertEqual(LyricsText.canonical("\u{FF2C}\u{FF4F}\u{FF56}\u{FF45}"), "Love")
    }

    func testComparableIgnoresCaseAccentsPunctuationAndLeadingThe() {
        XCTAssertEqual(LyricsText.comparable("Don\u{2019}t Stop Believin\u{2019}"), LyricsText.comparable("don't stop believin'"))
        XCTAssertEqual(LyricsText.comparable("Beyonc\u{00E9}"), LyricsText.comparable("BEYONCE"))
        XCTAssertEqual(LyricsText.comparable("Earth, Wind & Fire"), LyricsText.comparable("Earth Wind and Fire"))
        XCTAssertEqual(LyricsText.comparable("The Weeknd"), LyricsText.comparable("Weeknd"))
        XCTAssertEqual(LyricsText.comparable("\"Heroes\""), LyricsText.comparable("Heroes"))
    }

    func testJapaneseVoicingMarksAreNotFoldedAway() {
        // A diacritic-insensitive fold would not touch these, and must not.
        XCTAssertEqual(LyricsText.comparable("\u{30A2}\u{30A4}\u{30C9}\u{30EB}"), "\u{30A2}\u{30A4}\u{30C9}\u{30EB}")
        XCTAssertNotEqual(LyricsText.comparable("\u{30A2}\u{30A4}\u{30C9}\u{30EB}"), LyricsText.comparable("\u{30A2}\u{30A4}\u{30C8}\u{30EB}"))
    }

    func testRemovingBracketsAndDashSuffix() {
        XCTAssertEqual(LyricsText.removingBrackets("Get Lucky (Radio Edit) [Live]"), "Get Lucky")
        XCTAssertEqual(LyricsText.removingDashSuffix("Wake Me Up - Radio Edit"), "Wake Me Up")
        XCTAssertEqual(LyricsText.removingDashSuffix("My Heart Will Go On - Love Theme from \"Titanic\""), "My Heart Will Go On")
        XCTAssertEqual(LyricsText.removingDashSuffix("No Dash Here"), "No Dash Here")
    }
}

final class LyricsArtistNamesTests: XCTestCase {

    func testSpotifyListIsSplit() {
        XCTAssertEqual(LyricsArtistNames.performers("Post Malone, Swae Lee"), ["Post Malone", "Swae Lee"])
        XCTAssertEqual(
            LyricsArtistNames.performers("Daft Punk, Pharrell Williams & Nile Rodgers"),
            ["Daft Punk", "Pharrell Williams", "Nile Rodgers"]
        )
    }

    func testAppleMusicAmpersandSemicolonAndFeaturing() {
        XCTAssertEqual(LyricsArtistNames.performers("Post Malone & Swae Lee"), ["Post Malone", "Swae Lee"])
        XCTAssertEqual(LyricsArtistNames.performers("A; B"), ["A", "B"])
        XCTAssertEqual(LyricsArtistNames.performers("Mark Ronson feat. Bruno Mars"), ["Mark Ronson", "Bruno Mars"])
        XCTAssertEqual(LyricsArtistNames.performers("Rihanna ft. Calvin Harris"), ["Rihanna", "Calvin Harris"])
        XCTAssertEqual(LyricsArtistNames.performers("Calvin Harris x Rihanna"), ["Calvin Harris", "Rihanna"])
    }

    func testNetEaseSlashSplitsButBandsWithSlashesDoNot() {
        XCTAssertEqual(LyricsArtistNames.performers("Jolin Tsai/Jay Chou"), ["Jolin Tsai", "Jay Chou"])
        XCTAssertEqual(LyricsArtistNames.performers("\u{5468}\u{6770}\u{4F26}/\u{8D39}\u{7389}\u{6E05}"), ["\u{5468}\u{6770}\u{4F26}", "\u{8D39}\u{7389}\u{6E05}"])
        XCTAssertEqual(LyricsArtistNames.performers("AC/DC"), ["AC/DC"])
    }

    func testPrimaryIsTheFirstPerformer() {
        XCTAssertEqual(LyricsArtistNames.primary("Post Malone, Swae Lee"), "Post Malone")
        XCTAssertEqual(LyricsArtistNames.primary("Adele"), "Adele")
    }

    func testAgreementAcceptsAnyPerformerOrTheWholeName() {
        XCTAssertTrue(LyricsArtistNames.agree(request: "Post Malone, Swae Lee", row: "Post Malone"))
        XCTAssertTrue(LyricsArtistNames.agree(request: "Post Malone", row: "Post Malone & Swae Lee"))
        XCTAssertTrue(LyricsArtistNames.agree(request: "Simon & Garfunkel", row: "Simon and Garfunkel"))
        XCTAssertTrue(LyricsArtistNames.agree(request: "The Weeknd", row: "Weeknd"))
        XCTAssertTrue(LyricsArtistNames.agree(request: "Beyonc\u{00E9}", row: "Beyonce"))
        XCTAssertTrue(LyricsArtistNames.agree(request: "Tyler, The Creator", row: "Tyler, the Creator"))
    }

    func testAgreementRejectsOtherArtistsAndPartialWords() {
        XCTAssertFalse(LyricsArtistNames.agree(request: "Queen", row: "V\u{00C9}RIT\u{00C9}"))
        XCTAssertFalse(LyricsArtistNames.agree(request: "Ann", row: "Joanne"))
        XCTAssertFalse(LyricsArtistNames.agree(request: "", row: "Queen"))
    }
}

// MARK: - Variants

final class LyricsQueryPlannerTests: XCTestCase {

    private func variants(_ title: String, _ artist: String, web: Bool = false) -> [String] {
        LyricsQueryPlanner.variants(title: title, artist: artist, isWebSource: web).map { "\($0.artist) | \($0.title)" }
    }

    func testPlainTrackIsOneVariant() {
        XCTAssertEqual(variants("Levitating", "Dua Lipa"), ["Dua Lipa | Levitating"])
    }

    func testSpotifyRemasterSuffixIsStrippedByTheFirstVariant() {
        XCTAssertEqual(variants("Bohemian Rhapsody - Remastered 2011", "Queen").first, "Queen | Bohemian Rhapsody")
        XCTAssertEqual(variants("Dreams - 2004 Remaster", "Fleetwood Mac").first, "Fleetwood Mac | Dreams")
        XCTAssertEqual(variants("Don't You Worry Child - Radio Edit", "Swedish House Mafia").first, "Swedish House Mafia | Don't You Worry Child")
    }

    func testMultipleArtistsTryTheFirstPerformerNext() {
        let list = variants("Sunflower", "Post Malone, Swae Lee")
        XCTAssertEqual(list, ["Post Malone, Swae Lee | Sunflower", "Post Malone | Sunflower"])
    }

    func testSpotifyDashSubtitleAddsABareTitleVariant() {
        let list = variants("Sunflower - Spider-Man: Into the Spider-Verse", "Post Malone, Swae Lee")
        XCTAssertEqual(list.first, "Post Malone, Swae Lee | Sunflower - Spider-Man: Into the Spider-Verse")
        XCTAssertTrue(list.contains("Post Malone, Swae Lee | Sunflower"), "\(list)")
        XCTAssertTrue(list.contains("Post Malone | Sunflower"), "\(list)")
    }

    func testQuotedSubtitleLeavesNoStrayQuote() {
        // The cleaner used to leave `... from "Titanic` -- an unbalanced quote
        // that lrclib answers with 400.
        let list = variants("My Heart Will Go On - Love Theme from \"Titanic\"", "Celine Dion")
        XCTAssertTrue(list.contains("Celine Dion | My Heart Will Go On"), "\(list)")
        XCTAssertFalse(list.contains { $0.hasSuffix("\"Titanic") }, "\(list)")
    }

    func testBracketsAreStrippedOnARetryNotTheFirstTry() {
        let list = variants("Sunflower (Spider-Man: Into the Spider-Verse)", "Post Malone")
        XCTAssertEqual(list.first, "Post Malone | Sunflower (Spider-Man: Into the Spider-Verse)")
        XCTAssertTrue(list.contains("Post Malone | Sunflower"))
    }

    func testLeadingTheIsDroppedAsAVariant() {
        XCTAssertEqual(variants("Believer", "The Weeknd"), ["The Weeknd | Believer", "Weeknd | Believer"])
    }

    func testVariantsAreCapped() {
        let list = LyricsQueryPlanner.variants(
            title: "Song (A) - B (C)", artist: "The One, Two & Three", isWebSource: false
        )
        XCTAssertLessThanOrEqual(list.count, LyricsQueryPlanner.maximumVariants)
        XCTAssertEqual(Set(list.map { $0.artist.lowercased() + "|" + $0.title.lowercased() }).count, list.count)
    }

    func testPlaceholderMetadataHasNoVariants() {
        XCTAssertTrue(variants("Track 7", "Unknown Artist").isEmpty)
    }

    func testCurlyQuotesAreStraightened() {
        XCTAssertEqual(variants("Don\u{2019}t Stop Believin\u{2019}", "Journey").first, "Journey | Don't Stop Believin'")
    }
}

// MARK: - Selection

final class LyricsCandidateSelectorTests: XCTestCase {

    func testSyncedBeatsPlainEvenWhenThePlainRowIsCloserInLength() throws {
        let rows = [
            lrclibRow(id: 1, title: "Song", artist: "Band", duration: 200, synced: false),
            lrclibRow(id: 2, title: "Song", artist: "Band", duration: 202.5, synced: true)
        ]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200)))
        XCTAssertEqual(pick.row["id"] as? Int, 2)
        XCTAssertEqual(pick.kind, .synced)
    }

    func testClosestLengthWinsAmongSyncedRows() throws {
        let rows = [
            lrclibRow(id: 1, title: "Song", artist: "Band", duration: 202.8),
            lrclibRow(id: 2, title: "Song", artist: "Band", duration: 200.2),
            lrclibRow(id: 3, title: "Song", artist: "Band", duration: 198.5)
        ]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200)))
        XCTAssertEqual(pick.row["id"] as? Int, 2)
        XCTAssertEqual(try XCTUnwrap(pick.durationDelta), 0.2, accuracy: 0.001)
    }

    func testTimedRowOfAnotherLengthDegradesToPlainWords() throws {
        let rows = [lrclibRow(id: 1, title: "Song", artist: "Band", duration: 262)]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200)))
        XCTAssertEqual(pick.kind, .plain, "its timings are for another recording")
        let resolution = LRCLIBLyrics.resolution(for: pick)
        XCTAssertEqual(resolution.availability, .untimed)
        XCTAssertEqual(resolution.lines.map(\.text), ["one", "two"])
        XCTAssertFalse(resolution.lines.contains { $0.isTimed })
    }

    func testTimedOnlyRowOfAnotherLengthStillGivesWordsLabelledUnsynced() throws {
        let rows = [lrclibRow(id: 1, title: "Song", artist: "Band", duration: 262, plain: false)]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200)))
        XCTAssertEqual(pick.kind, .syncedOffLength)
        let resolution = LRCLIBLyrics.resolution(for: pick)
        XCTAssertEqual(resolution.availability, .untimed)
        XCTAssertEqual(resolution.lines.map(\.text), ["one", "two"])
    }

    func testToleranceIsConfigurable() throws {
        let rows = [lrclibRow(id: 1, title: "Song", artist: "Band", duration: 210)]
        XCTAssertEqual(
            LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200, tolerance: 4))?.kind, .plain
        )
        XCTAssertEqual(
            LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200, tolerance: 15))?.kind, .synced,
            "a music video has an intro the album track does not"
        )
    }

    func testUnknownLengthNeverRulesARowOut() throws {
        let rows = [lrclibRow(id: 1, title: "Song", artist: "Band", duration: nil)]
        XCTAssertEqual(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", duration: 200))?.kind, .synced)
        let known = [lrclibRow(id: 1, title: "Song", artist: "Band", duration: 300)]
        XCTAssertEqual(LyricsCandidateSelector.select(rows: known, request: request("Song", "Band", duration: 0))?.kind, .synced)
    }

    func testOtherVersionsAreRejectedUnlessRequested() {
        let karaoke = lrclibRow(id: 1, title: "Song (Karaoke Version)", artist: "Band", duration: 200)
        let remix = lrclibRow(id: 2, title: "Song (Remix)", artist: "Band", duration: 200)
        XCTAssertNil(LyricsCandidateSelector.select(rows: [karaoke, remix], request: request("Song", "Band", duration: 200)))
        XCTAssertNotNil(LyricsCandidateSelector.select(rows: [remix], request: request("Song - Remix", "Band", duration: 200)))
    }

    func testAnotherArtistsCoverIsRejected() {
        let cover = lrclibRow(id: 1, title: "Somebody Else (The 1975 Cover)", artist: "V\u{00C9}RIT\u{00C9}", duration: 233)
        XCTAssertNil(LyricsCandidateSelector.select(rows: [cover], request: request("Somebody Else", "The 1975", duration: 233)))
        let other = lrclibRow(id: 2, title: "Somebody Else", artist: "Someone Else", duration: 233)
        XCTAssertNil(LyricsCandidateSelector.select(rows: [other], request: request("Somebody Else", "The 1975", duration: 233)))
    }

    func testPartialTitleMustBeMostOfTheTitle() {
        let long = lrclibRow(id: 1, title: "Hurt Me Tomorrow Forever Today", artist: "Johnny Cash", duration: 216)
        XCTAssertNil(LyricsCandidateSelector.select(rows: [long], request: request("Hurt", "Johnny Cash", duration: 216)))
    }

    func testDashSubtitleOnTheRowStillAgreesWithTheBareTitle() {
        let row = lrclibRow(id: 1, title: "Sunflower - Spider-Man: Into the Spider-Verse", artist: "Post Malone, Swae Lee", duration: 158)
        let pick = LyricsCandidateSelector.select(rows: [row], request: request("Sunflower", "Post Malone", duration: 158))
        XCTAssertEqual(pick?.kind, .synced)
    }

    func testInstrumentalNeedsAnExactTitleAndLength() {
        let instrumental = lrclibRow(id: 1, title: "Song", artist: "Band", duration: 201, synced: false, plain: false, instrumental: true)
        XCTAssertEqual(LyricsCandidateSelector.select(rows: [instrumental], request: request("Song", "Band", duration: 200))?.kind, .instrumental)
        let alternate = lrclibRow(id: 2, title: "Song", artist: "Band", duration: 76, synced: false, plain: false, instrumental: true)
        XCTAssertNil(LyricsCandidateSelector.select(rows: [alternate], request: request("Song", "Band", duration: 214)),
                     "a 76s instrumental alternate is not the 214s original")
    }

    func testLyricsBeatAnInstrumentalFlag() {
        let instrumental = lrclibRow(id: 1, title: "Song", artist: "Band", duration: 200, synced: false, plain: false, instrumental: true)
        let sung = lrclibRow(id: 2, title: "Song", artist: "Band", duration: 200)
        XCTAssertEqual(LyricsCandidateSelector.select(rows: [instrumental, sung], request: request("Song", "Band", duration: 200))?.row["id"] as? Int, 2)
    }

    func testAlbumBreaksTiesBetweenEquallyLongRows() throws {
        let rows = [
            lrclibRow(id: 1, title: "Song", artist: "Band", album: "Greatest Hits", duration: 200),
            lrclibRow(id: 2, title: "Song", artist: "Band", album: "The Album", duration: 200)
        ]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Song", "Band", album: "The Album", duration: 200)))
        XCTAssertEqual(pick.row["id"] as? Int, 2)
    }

    // MARK: Recorded pages

    func testRecordedBohemianRhapsodyPicksTheClosestOfTwentyRows() throws {
        let rows = fixtureRows(LyricsFixtures.bohemianSearch)
        XCTAssertEqual(rows.count, 20)
        // Apple Music reports 355.155s. Eight rows are within 4s; the first
        // listed (351s) is not the closest.
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Bohemian Rhapsody", "Queen", duration: 355.155)))
        XCTAssertEqual(pick.kind, .synced)
        XCTAssertEqual(try XCTUnwrap(pick.durationDelta), 0.155, accuracy: 0.001)
        XCTAssertNotEqual(pick.row["id"] as? Int, 36902193)
    }

    func testRecordedStructuredSearchPageHasNoRowOfTheRightLength() throws {
        let rows = fixtureRows(LyricsFixtures.worryChildStructuredSearch)
        XCTAssertEqual(rows.count, 20, "search is capped at twenty rows")
        let pick = LyricsCandidateSelector.select(rows: rows, request: request("Don't You Worry Child", "Swedish House Mafia", duration: 257.923))
        XCTAssertNotEqual(pick?.kind, .synced, "nothing within tolerance on this page")
    }

    func testRecordedFreeTextSearchFindsTheExactRow() throws {
        let rows = fixtureRows(LyricsFixtures.worryChildFreeTextSearch)
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Don't You Worry Child", "Swedish House Mafia", duration: 257.923)))
        XCTAssertEqual(pick.kind, .synced)
        XCTAssertLessThan(try XCTUnwrap(pick.durationDelta), 0.1)
    }

    func testClosestSyncedRowBeatsTheFirstListedOne() throws {
        // The previous ranking ignored length once rows were "within 3s", so
        // equally named rows tied and the first listed won. Here the first
        // listed row is 2.8s out and a 0.2s row follows it.
        let rows = [
            lrclibRow(id: 1, title: "Stairway to Heaven", artist: "Led Zeppelin", duration: 485.63),
            lrclibRow(id: 2, title: "Stairway to Heaven", artist: "Led Zeppelin", duration: 482.63)
        ]
        let pick = try XCTUnwrap(LyricsCandidateSelector.select(rows: rows, request: request("Stairway to Heaven", "Led Zeppelin", duration: 482.83)))
        XCTAssertEqual(pick.row["id"] as? Int, 2)
    }
}

// MARK: - Fetching with a scripted transport

private final class ScriptedTransport: @unchecked Sendable {
    typealias Reply = (status: Int, body: String)

    private let lock = NSLock()
    private var queue: [Reply]
    private let responder: (@Sendable (URL) -> Reply)?
    private(set) var urls: [URL] = []

    /// Replies in order, then 404.
    init(_ replies: [Reply]) {
        queue = replies
        responder = nil
    }

    init(responder: @escaping @Sendable (URL) -> Reply) {
        queue = []
        self.responder = responder
    }

    var transport: LyricsTransport {
        { [self] url in
            lock.lock()
            urls.append(url)
            let reply: Reply
            if let responder {
                reply = responder(url)
            } else if queue.isEmpty {
                reply = (404, #"{"name":"TrackNotFound"}"#)
            } else {
                reply = queue.removeFirst()
            }
            lock.unlock()
            return (Data(reply.body.utf8), reply.status)
        }
    }

    /// "get artist | title" and "search ..." per request, in order.
    var trace: [String] {
        urls.map { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
            if url.path.hasSuffix("/get") { return "get \(value("artist_name")) | \(value("track_name")) | \(value("duration"))" }
            if let query = items.first(where: { $0.name == "q" })?.value { return "q \(query)" }
            return "search \(value("artist_name")) | \(value("track_name"))"
        }
    }
}

private let overloaded: ScriptedTransport.Reply = (503, #"{"message":"The server is busy, please retry in a moment","name":"ServerOverloaded","statusCode":503}"#)
private let notFound: ScriptedTransport.Reply = (404, #"{"message":"Failed to find specified track","name":"TrackNotFound","statusCode":404}"#)

private func getBody(id: Int = 1, title: String = "Song", artist: String = "Band", duration: Double = 200, synced: Bool = true) -> String {
    let lyrics = synced ? #""[00:01.00]one\n[00:03.00]two""# : "null"
    return #"{"id":\#(id),"trackName":"\#(title)","artistName":"\#(artist)","albumName":"","duration":\#(duration),"instrumental":false,"plainLyrics":"one\ntwo","syncedLyrics":\#(lyrics)}"#
}

private func searchBody(_ rows: [String]) -> String { "[" + rows.joined(separator: ",") + "]" }

final class LRCLIBFetchTests: XCTestCase {

    private func fetch(
        _ script: ScriptedTransport,
        title: String = "Song", artist: String = "Band", duration: Double = 200,
        sleeps: SleepLog? = nil
    ) async throws -> LyricsFetchOutcome {
        let variants = LyricsQueryPlanner.variants(title: title, artist: artist, isWebSource: false)
        return try await LRCLIBLyrics.fetch(
            variants: variants, originalTitle: title, album: "", duration: duration, isWebSource: false,
            transport: script.transport, sleep: { await sleeps?.record($0) }
        )
    }

    actor SleepLog {
        private(set) var delays: [TimeInterval] = []
        func record(_ delay: TimeInterval) { delays.append(delay) }
    }

    func testAnExactSyncedGetIsOneRequest() async throws {
        let script = ScriptedTransport([(200, getBody(duration: 200.3))])
        let outcome = try await fetch(script)
        XCTAssertEqual(outcome.resolution.availability, .timed)
        XCTAssertEqual(script.urls.count, 1, "nothing further is worth asking")
        XCTAssertEqual(outcome.requestCount, 1)
        XCTAssertFalse(outcome.sawTransientFailure)
    }

    func testOverloadedGetIsRetriedWithBackoffAndSucceeds() async throws {
        let script = ScriptedTransport([overloaded, overloaded, (200, getBody())])
        let sleeps = SleepLog()
        let outcome = try await fetch(script, sleeps: sleeps)
        XCTAssertEqual(outcome.resolution.availability, .timed)
        XCTAssertEqual(script.urls.count, 3)
        let delays = await sleeps.delays
        XCTAssertEqual(delays, LyricsHTTP.retryDelays)
        XCTAssertFalse(outcome.sawTransientFailure)
    }

    func testRateLimitingIsRetriedToo() async throws {
        let script = ScriptedTransport([(429, "{}"), (200, getBody())])
        let outcome = try await fetch(script, sleeps: SleepLog())
        XCTAssertEqual(outcome.resolution.availability, .timed)
    }

    func testPersistentOverloadIsReportedAndIsNotAMiss() async throws {
        let script = ScriptedTransport(responder: { _ in overloaded })
        let outcome = try await fetch(script, sleeps: SleepLog())
        XCTAssertEqual(outcome.resolution.availability, .unavailable)
        XCTAssertTrue(outcome.sawTransientFailure)
        XCTAssertFalse(outcome.isDefinitiveMiss, "must not be remembered as 'no lyrics'")
    }

    func testTransportErrorsAreRetriedAndCancellationIsNot() async throws {
        let attempts = AttemptCounter()
        let transport: LyricsTransport = { _ in
            if attempts.next() < 2 { throw URLError(.timedOut) }
            return (Data(getBody().utf8), 200)
        }
        let variants = [LyricsQuery(artist: "Band", title: "Song")]
        let outcome = try await LRCLIBLyrics.fetch(
            variants: variants, originalTitle: "Song", album: "", duration: 200, isWebSource: false,
            transport: transport, sleep: { _ in }
        )
        XCTAssertEqual(outcome.resolution.availability, .timed)

        let cancelled: LyricsTransport = { _ in throw URLError(.cancelled) }
        do {
            _ = try await LRCLIBLyrics.fetch(
                variants: variants, originalTitle: "Song", album: "", duration: 200, isWebSource: false,
                transport: cancelled, sleep: { _ in }
            )
            XCTFail("cancellation must propagate")
        } catch is CancellationError {
        }
    }

    final class AttemptCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count - 1 }
    }

    func testConfirmedNotFoundEverywhereIsADefinitiveMiss() async throws {
        let script = ScriptedTransport(responder: { url in url.path.hasSuffix("/get") ? notFound : (200, "[]") })
        let outcome = try await fetch(script)
        XCTAssertEqual(outcome.resolution.availability, .unavailable)
        XCTAssertFalse(outcome.sawTransientFailure)
        XCTAssertTrue(outcome.isDefinitiveMiss)
    }

    func testVariantOrderIsGetThenSearchPerVariantThenFreeTextThenTitleOnly() async throws {
        let script = ScriptedTransport(responder: { url in url.path.hasSuffix("/get") ? notFound : (200, "[]") })
        _ = try await fetch(script, title: "Get Lucky (Radio Edit)", artist: "Daft Punk, Pharrell Williams")
        XCTAssertEqual(script.trace, [
            "get Daft Punk, Pharrell Williams | Get Lucky (Radio Edit) | 200",
            "search Daft Punk, Pharrell Williams | Get Lucky (Radio Edit)",
            "get Daft Punk | Get Lucky (Radio Edit) | 200",
            "search Daft Punk | Get Lucky (Radio Edit)",
            "get Daft Punk, Pharrell Williams | Get Lucky | 200",
            "search Daft Punk, Pharrell Williams | Get Lucky",
            "get Daft Punk | Get Lucky | 200",
            "search Daft Punk | Get Lucky",
            "q Daft Punk Get Lucky (Radio Edit)",
            "q Get Lucky (Radio Edit)"
        ])
    }

    func testRequestsAreCapped() async throws {
        let script = ScriptedTransport(responder: { url in url.path.hasSuffix("/get") ? notFound : (200, "[]") })
        _ = try await fetch(script, title: "Song (A) - B", artist: "The One, Two & Three")
        XCTAssertLessThanOrEqual(script.urls.count, LRCLIBLyrics.maximumRequests)
    }

    func testNoGetWithoutADuration() async throws {
        let script = ScriptedTransport(responder: { _ in (200, "[]") })
        _ = try await fetch(script, duration: 0)
        XCTAssertFalse(script.trace.contains { $0.hasPrefix("get ") })
    }

    func testPlainOnlyGetDoesNotStopTheSearchForATimedRow() async throws {
        let plainGet = getBody(id: 1, duration: 200, synced: false)
        let timed = searchBody([
            #"{"id":2,"trackName":"Song","artistName":"Band","albumName":"","duration":201.2,"instrumental":false,"plainLyrics":"one\ntwo","syncedLyrics":"[00:01.00]one\n[00:03.00]two"}"#
        ])
        let script = ScriptedTransport([(200, plainGet), (200, timed)])
        let outcome = try await fetch(script)
        XCTAssertEqual(outcome.resolution.availability, .timed)
        XCTAssertEqual(script.urls.count, 2)
    }

    func testPlainOnlyEverywhereIsShownAsUnsynced() async throws {
        let script = ScriptedTransport(responder: { url in
            url.path.hasSuffix("/get") ? (200, getBody(synced: false)) : (200, "[]")
        })
        let outcome = try await fetch(script)
        XCTAssertEqual(outcome.resolution.availability, .untimed)
        XCTAssertEqual(outcome.resolution.lines.map(\.text), ["one", "two"])
        XCTAssertTrue(script.urls.count > 1, "keeps looking for a timed version before settling")
    }

    func testFreeTextSearchFindsWhatTheStructuredOnesMiss() async throws {
        // Recorded: the structured page holds no row near 257.9s; the q page does.
        let script = ScriptedTransport(responder: { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if url.path.hasSuffix("/get") { return notFound }
            if items.contains(where: { $0.name == "q" }) { return (200, LyricsFixtures.worryChildFreeTextSearch) }
            return (200, LyricsFixtures.worryChildStructuredSearch)
        })
        let outcome = try await fetch(script, title: "Don't You Worry Child - Radio Edit", artist: "Swedish House Mafia", duration: 257.923)
        XCTAssertEqual(outcome.resolution.availability, .timed)
        XCTAssertLessThan(try XCTUnwrap(outcome.durationDelta), 0.1)
        XCTAssertEqual(script.trace.last?.hasPrefix("q "), true)
    }

    func testMultiArtistStringFallsBackToTheFirstPerformerForSearch() async throws {
        // Recorded behaviour: search finds nothing for "A, B" but finds the song for "A".
        let script = ScriptedTransport(responder: { url in
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let artist = items.first { $0.name == "artist_name" }?.value ?? ""
            if url.path.hasSuffix("/get") { return notFound }
            return artist == "Post Malone" ? (200, searchBody([#"{"id":9,"trackName":"Sunflower","artistName":"Post Malone","albumName":"","duration":158.0,"instrumental":false,"plainLyrics":"x","syncedLyrics":"[00:01.00]x"}"#])) : (200, "[]")
        })
        let outcome = try await fetch(script, title: "Sunflower", artist: "Post Malone, Swae Lee", duration: 158)
        XCTAssertEqual(outcome.resolution.availability, .timed)
    }
}

// MARK: - Provider fallback

final class LyricsFallbackPreferenceTests: XCTestCase {
    private let timed = LyricsResolution(lines: [LyricLine(timestamp: 1, text: "a")])
    private let plain = LyricsResolution(lines: LyricLine.untimedLines(from: "words"))

    func testPlainPrimaryAsksFallbackAndTimedFallbackWins() async {
        let result = await LyricsProviderFallback.resolve(primary: { self.plain }, fallback: { self.timed })
        XCTAssertEqual(result.availability, .timed)
    }

    func testPlainPrimaryStandsWhenFallbackHasNothingTimed() async {
        let none = await LyricsProviderFallback.resolve(primary: { self.plain }, fallback: { LyricsResolution() })
        XCTAssertEqual(none.availability, .untimed)
        let otherPlain = await LyricsProviderFallback.resolve(
            primary: { self.plain },
            fallback: { LyricsResolution(lines: LyricLine.untimedLines(from: "other")) }
        )
        XCTAssertEqual(otherPlain.lines.map(\.text), ["words"])
        let thrown = await LyricsProviderFallback.resolve(primary: { self.plain }, fallback: { throw URLError(.timedOut) })
        XCTAssertEqual(thrown.availability, .untimed)
    }

    func testTransientFailureIsCarriedThroughAndClearedByAnAnswer() async {
        var outcome = LyricsFetchOutcome()
        outcome.sawTransientFailure = true
        let stillEmpty = await LyricsProviderFallback.run(primary: { outcome }, fallback: { LyricsResolution() })
        XCTAssertTrue(stillEmpty.sawTransientFailure)
        XCTAssertFalse(stillEmpty.isDefinitiveMiss)
        let thrown = await LyricsProviderFallback.run(primary: { LyricsFetchOutcome() }, fallback: { throw URLError(.timedOut) })
        XCTAssertTrue(thrown.sawTransientFailure, "the fallback could not be asked either")
    }
}

// MARK: - LRC parsing

final class LRCParserEdgeCaseTests: XCTestCase {

    private func parse(_ lrc: String) -> [(Double, String)] {
        LRCParser.parse(lrc).map { ($0.timestamp, $0.text) }
    }

    func testRepeatedChorusWithSeveralLeadingTimestamps() {
        let lines = parse("[00:12.00][00:45.30]Sing along\n[00:20.00]Verse")
        XCTAssertEqual(lines.map(\.1), ["Sing along", "Verse", "Sing along"])
        XCTAssertEqual(lines.map(\.0), [12, 20, 45.3])
    }

    func testColonFractionCommaFractionAndNoFraction() {
        XCTAssertEqual(parse("[01:02:50]a")[0].0, 62.5, accuracy: 0.001)
        XCTAssertEqual(parse("[01:02,50]a")[0].0, 62.5, accuracy: 0.001)
        XCTAssertEqual(parse("[01:02]a")[0].0, 62, accuracy: 0.001)
    }

    func testFractionIsScaledByItsLength() {
        XCTAssertEqual(parse("[00:01.5]a")[0].0, 1.5, accuracy: 0.001)
        XCTAssertEqual(parse("[00:01.50]a")[0].0, 1.5, accuracy: 0.001)
        XCTAssertEqual(parse("[00:01.500]a")[0].0, 1.5, accuracy: 0.001)
        XCTAssertEqual(parse("[00:19.180]a")[0].0, 19.18, accuracy: 0.001)
    }

    func testOffsetTagShiftsEveryLine() {
        let shifted = parse("[offset:+500]\n[00:10.00]a\n[00:20.00]b")
        XCTAssertEqual(shifted.map(\.0), [9.5, 19.5])
        let delayed = parse("[offset:-1000]\n[00:10.00]a")
        XCTAssertEqual(delayed[0].0, 11, accuracy: 0.001)
        XCTAssertEqual(parse("[offset:0]\n[00:10.00]a")[0].0, 10, accuracy: 0.001)
    }

    func testOffsetCannotMakeATimestampNegative() {
        XCTAssertEqual(parse("[offset:5000]\n[00:02.00]a")[0].0, 0)
    }

    func testEnhancedWordTagsDoNotLeakIntoText() {
        let lines = parse("[00:12.00]<00:12.00>Hello <00:12.40>world<00:12.90>")
        XCTAssertEqual(lines.map(\.1), ["Hello world"])
        XCTAssertEqual(lines[0].0, 12, accuracy: 0.001)
    }

    func testMidLineBracketTagsAreNotLinesOfTheirOwn() {
        let lines = parse("[00:12.00]Hello [00:12.50]world")
        XCTAssertEqual(lines.map(\.1), ["Hello world"])
        XCTAssertEqual(lines.count, 1)
    }

    func testBlankTimestampsMarkGapsAndMetadataIsIgnored() {
        let lines = parse("[ar:Artist]\n[ti:Title]\n[00:05.00]sung\n[00:09.00]\n[00:30.00]again")
        XCTAssertEqual(lines.map(\.1), ["sung", "", "again"])
        XCTAssertEqual(lines.map(\.0), [5, 9, 30])
    }

    func testWindowsLineEndingsAndBlankLines() {
        XCTAssertEqual(parse("[00:01.00]a\r\n\r\n[00:02.00]b\r\n").map(\.1), ["a", "b"])
    }

    func testOutOfOrderLinesAreSortedAndEqualTimestampsKeepFileOrder() {
        let lines = parse("[00:20.00]late\n[00:10.00]first\n[00:10.00]second")
        XCTAssertEqual(lines.map(\.1), ["first", "second", "late"])
    }

    func testLargeMinuteFieldsAndWhitespaceAroundText() {
        XCTAssertEqual(parse("[100:00.00]  padded  ")[0].0, 6000)
        XCTAssertEqual(parse("[100:00.00]  padded  ")[0].1, "padded")
    }
}

// MARK: - Playback position

final class LyricsClockTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    private func position(
        elapsed: Double = 30, age: Double = 0, rate: Double = 1, playing: Bool = true,
        duration: Double = 200, timestamp: Date? = nil
    ) -> Double {
        LyricsClock.playbackPosition(
            elapsed: elapsed, timestamp: timestamp ?? anchor, rate: rate, isPlaying: playing,
            duration: duration, now: anchor.addingTimeInterval(age)
        )
    }

    func testPlayingExtrapolatesFromTheSample() {
        XCTAssertEqual(position(elapsed: 30, age: 2.5), 32.5, accuracy: 0.0001)
    }

    func testPausedIsFrozenWhateverTheAge() {
        XCTAssertEqual(position(elapsed: 30, age: 500, playing: false), 30)
    }

    func testRateScalesTheElapsedWallClock() {
        XCTAssertEqual(position(elapsed: 10, age: 4, rate: 1.5), 16, accuracy: 0.0001)
        XCTAssertEqual(position(elapsed: 10, age: 4, rate: 0.5), 12, accuracy: 0.0001)
    }

    func testZeroOrInvalidRateWhilePlayingMeansUnreported() {
        XCTAssertEqual(position(elapsed: 10, age: 4, rate: 0), 14, accuracy: 0.0001)
        XCTAssertEqual(position(elapsed: 10, age: 4, rate: -1), 14, accuracy: 0.0001)
        XCTAssertEqual(position(elapsed: 10, age: 4, rate: .nan), 14, accuracy: 0.0001)
    }

    func testStaleAnchorOfAPlayingTrackKeepsAdvancing() {
        // Spotify anchors once per track: elapsed 0 with a timestamp 141s old.
        XCTAssertEqual(position(elapsed: 0, age: 141, duration: 240), 141, accuracy: 0.0001)
    }

    func testAnchorCannotCarryThePositionPastTheEnd() {
        XCTAssertEqual(position(elapsed: 10, age: 9_000, duration: 200), 200)
    }

    func testUnknownDurationStillExtrapolates() {
        XCTAssertEqual(position(elapsed: 10, age: 5, duration: 0), 15, accuracy: 0.0001)
    }

    func testUnstampedSampleContributesNoAge() {
        // A source that never sets the timestamp leaves it at distantPast.
        XCTAssertEqual(position(elapsed: 42, age: 5, timestamp: .distantPast), 42)
        XCTAssertEqual(position(elapsed: 42, age: 5, timestamp: Date(timeIntervalSince1970: 0)), 42)
    }

    func testFutureTimestampIsClockSkewNotNegativeTime() {
        XCTAssertEqual(position(elapsed: 42, age: -3), 42)
    }

    func testNegativeOrNonFiniteElapsedIsZero() {
        XCTAssertEqual(position(elapsed: -5, playing: false), 0)
        XCTAssertEqual(position(elapsed: .nan, playing: false), 0)
    }

    func testSeekRebasesBecauseTheNewSampleReplacesTheOld() {
        let before = position(elapsed: 30, age: 10)
        XCTAssertEqual(before, 40, accuracy: 0.0001)
        let after = LyricsClock.playbackPosition(
            elapsed: 120, timestamp: anchor.addingTimeInterval(10), rate: 1, isPlaying: true,
            duration: 200, now: anchor.addingTimeInterval(10.4)
        )
        XCTAssertEqual(after, 120.4, accuracy: 0.0001)
    }

    func testResumeAfterPauseStartsFromTheFrozenPosition() {
        // The controller re-anchors on resume: elapsed 40 stamped at resume time.
        let resumed = LyricsClock.playbackPosition(
            elapsed: 40, timestamp: anchor.addingTimeInterval(100), rate: 1, isPlaying: true,
            duration: 200, now: anchor.addingTimeInterval(101)
        )
        XCTAssertEqual(resumed, 41, accuracy: 0.0001)
    }

    func testLyricPositionAddsLeadAndTheSongOffset() {
        let value = LyricsClock.lyricPosition(
            elapsed: 30, timestamp: anchor, rate: 1, isPlaying: true, duration: 200,
            now: anchor.addingTimeInterval(1), lead: 0.25, offset: 1.5
        )
        XCTAssertEqual(value, 32.75, accuracy: 0.0001)
        let negative = LyricsClock.lyricPosition(
            elapsed: 1, timestamp: anchor, rate: 1, isPlaying: false, duration: 200,
            now: anchor, lead: 0.25, offset: -5
        )
        XCTAssertEqual(negative, 0, "never before the start")
    }

    func testOffsetMovesTheActiveLine() {
        let lines = LRCParser.parse("[00:10.00]first\n[00:20.00]second")
        let at = { (offset: Double) -> Int in
            LyricsTimeline.activeIndex(in: lines, at: LyricsClock.lyricPosition(
                elapsed: 19, timestamp: self.anchor, rate: 1, isPlaying: false, duration: 100,
                now: self.anchor, lead: 0, offset: offset
            ))
        }
        XCTAssertEqual(at(0), 0)
        XCTAssertEqual(at(1), 1, "a positive offset shows the next line sooner")
        XCTAssertEqual(at(-10), -1)
    }
}

final class LyricsOffsetTests: XCTestCase {
    func testStepsSnapAndClamp() {
        XCTAssertEqual(LyricsOffset.adjusted(0, by: 0.5), 0.5)
        XCTAssertEqual(LyricsOffset.adjusted(0.5, by: -1.0), -0.5)
        XCTAssertEqual(LyricsOffset.adjusted(0.1 + 0.2, by: 0.5), 1.0, "float crumbs snap to the grid")
        XCTAssertEqual(LyricsOffset.adjusted(14.5, by: 5), LyricsOffset.limit)
        XCTAssertEqual(LyricsOffset.adjusted(-14.5, by: -5), -LyricsOffset.limit)
    }

    func testLabels() {
        XCTAssertEqual(LyricsOffset.label(0), "0.0s")
        XCTAssertEqual(LyricsOffset.label(0.5), "+0.5s")
        XCTAssertEqual(LyricsOffset.label(-1.5), "-1.5s")
    }
}

// MARK: - Cache: offsets, plain-only expiry, misses

final class LyricsCacheBehaviourTests: XCTestCase {

    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lyrics-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private let timed = LyricsResolution(lines: [LyricLine(timestamp: 1, text: "a")])
    private let plain = LyricsResolution(lines: LyricLine.untimedLines(from: "one\ntwo"))

    func testOffsetPersistsAcrossRelaunchAndZeroForgetsIt() {
        let dir = directory()
        let cache = LyricsDiskCache(directory: dir, capacity: 3)
        let key = LyricsDiskCache.key(artist: "Queen", title: "Bohemian Rhapsody", duration: 355)
        XCTAssertEqual(cache.offset(for: key), 0)
        cache.setOffset(1.5, for: key)
        cache.flush()
        XCTAssertEqual(LyricsDiskCache(directory: dir, capacity: 3).offset(for: key), 1.5)
        cache.setOffset(0, for: key)
        cache.flush()
        XCTAssertEqual(LyricsDiskCache(directory: dir, capacity: 3).offset(for: key), 0)
    }

    func testOffsetsSurviveClearingTheLyrics() {
        let dir = directory()
        let cache = LyricsDiskCache(directory: dir, capacity: 3)
        cache.setOffset(-2, for: "k")
        cache.store(timed, for: "k")
        cache.removeAll()
        XCTAssertNil(cache.lookup("k"))
        XCTAssertEqual(LyricsDiskCache(directory: dir, capacity: 3).offset(for: "k"), -2)
    }

    func testTimedAnswersNeverGoStale() {
        let cache = LyricsDiskCache(directory: directory(), capacity: 3)
        let longAgo = Date(timeIntervalSince1970: 0)
        cache.store(timed, for: "k", now: longAgo)
        guard case .fresh = cache.lookupDetailed("k", now: longAgo.addingTimeInterval(365 * 86_400)) else {
            return XCTFail("timed lyrics are final")
        }
    }

    func testPlainOnlyAnswersAreTrustedForADayThenRetried() {
        let cache = LyricsDiskCache(directory: directory(), capacity: 3)
        let stored = Date(timeIntervalSince1970: 1_000_000)
        cache.store(plain, for: "k", now: stored)
        guard case .fresh = cache.lookupDetailed("k", now: stored.addingTimeInterval(23 * 3600)) else {
            return XCTFail("fresh inside a day")
        }
        guard case .stale(let resolution) = cache.lookupDetailed("k", now: stored.addingTimeInterval(25 * 3600)) else {
            return XCTFail("stale after a day")
        }
        XCTAssertEqual(resolution.availability, .untimed, "still available as a fallback")
        XCTAssertNil(cache.lookup("k"), "lookup() trusts only fresh answers")
    }

    func testEntriesFromBeforeStorageTimesWereKeptDecodeAndPlainOnesCountAsStale() throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = #"{"version":1,"order":["a","b"],"entries":{"a":{"lines":[{"t":1,"text":"x","timed":true}],"instrumental":false},"b":{"lines":[{"t":0,"text":"y","timed":false}],"instrumental":false}}}"#
        try legacy.write(to: dir.appendingPathComponent("lyrics-cache.json"), atomically: true, encoding: .utf8)
        let cache = LyricsDiskCache(directory: dir, capacity: 5)
        guard case .fresh(let a) = cache.lookupDetailed("a") else { return XCTFail("timed legacy entry") }
        XCTAssertEqual(a.availability, .timed)
        guard case .stale = cache.lookupDetailed("b") else { return XCTFail("plain legacy entry is retried") }
        XCTAssertEqual(cache.offset(for: "a"), 0)
    }

    func testMissesExpireAfterTenMinutesAndAnAnswerClearsThem() {
        let cache = LyricsDiskCache(directory: directory(), capacity: 3)
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertFalse(cache.isRecentMiss("k", now: now))
        cache.storeMiss("k", now: now)
        XCTAssertTrue(cache.isRecentMiss("k", now: now.addingTimeInterval(9 * 60)))
        XCTAssertFalse(cache.isRecentMiss("k", now: now.addingTimeInterval(11 * 60)))

        cache.storeMiss("j", now: now)
        cache.store(timed, for: "j", now: now)
        XCTAssertFalse(cache.isRecentMiss("j", now: now))

        cache.storeMiss("f", now: now)
        cache.forgetMiss("f")
        XCTAssertFalse(cache.isRecentMiss("f", now: now))
    }

    func testMissesAreNeverWrittenToDisk() {
        let dir = directory()
        let cache = LyricsDiskCache(directory: dir, capacity: 3)
        cache.storeMiss("k")
        cache.store(timed, for: "other")
        cache.flush()
        XCTAssertFalse(LyricsDiskCache(directory: dir, capacity: 3).isRecentMiss("k"))
    }
}
/// Rows recorded from lrclib.net (names, albums and lengths as served; lyric bodies shortened).
enum LyricsFixtures {

    /// `search?track_name=Bohemian Rhapsody&artist_name=Queen`: twenty rows, as served.
    static let bohemianSearch = #"""
    [
    {"id":36902193,"trackName":"Bohemian rhapsody","artistName":"Queen","albumName":"The greatest hits","duration":351.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36925259,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Bohemian Rhapsody (The Original Soundtrack)","duration":317.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36978827,"trackName":"Bohemian rhapsody","artistName":"Queen","albumName":"Varie","duration":354.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37008539,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Greatest Hits I II & III (The Platinum Collection)","duration":263.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37482678,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Bubanee Music","duration":358.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37508135,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"[Unknown Album]","duration":359.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37519118,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Unknown","duration":356.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37520606,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Sun City","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37484182,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Rock You From Rio - Live (2009, Immortal, EU, Poland, IMA 104149)","duration":318.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37491333,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Flash Freddie (bootleg)","duration":338.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37174882,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"500 Greatest Songs - Rolling Stone Magazines 2010","duration":355.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37191821,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Rock Montreal 2","duration":329.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37160052,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Greatest Hits I II & III (The Platinum Collection) (CD I)","duration":358.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37176124,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Lulz: A Corruption of LOL (Over) #IX: Thousand","duration":355.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37146880,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Pop Giganten Hits der 70er 1-1","duration":355.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37050950,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Live In Tokyo 1985 (Live FM Broadcast Remastered)","duration":347.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37055703,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Mastermix - Number 1's - 1991","duration":415.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37104289,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Joe 70s 80s 90s Top 1000 2025","duration":356.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37289282,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Billboard Top 100 - 1976","duration":355.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37314855,"trackName":"Bohemian Rhapsody","artistName":"Queen","albumName":"Live At Wembley '86 - Disk2","duration":351.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"}
    ]
    """#

    /// `search?track_name=Don't You Worry Child&artist_name=Swedish House Mafia`: the page is capped at twenty rows and none is 258 seconds long.
    static let worryChildStructuredSearch = #"""
    [
    {"id":37114789,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Now That's What I Call Music 83 (CD1) hd24bit.com","duration":213.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37169337,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Ministry of Sound: Anthems Trance","duration":213.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37159068,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Billboard Hot 100 Charts (2013)","duration":238.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37316616,"trackName":"Don't you worry child","artistName":"Swedish House Mafia","albumName":"2-HOUR CALISTHENICS MIX","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":37252643,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Club Sounds Summer 2013","duration":212.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34659513,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":333.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34445946,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"DANCE POP HITS","duration":403.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34543418,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Until Now","duration":234.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34666469,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Until Now","duration":319.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":35159345,"trackName":"Don’t You Worry Child","artistName":"Swedish House Mafia","albumName":"RTL Frühlingshits 2013","duration":213.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":35247682,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Safe Space","duration":402.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34864094,"trackName":"Dont You Worry Child","artistName":"Swedish House Mafia","albumName":"NACHOMIX 07","duration":202.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":35054023,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Until Now","duration":352.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":33684645,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Future Trance - Festival Classics (CD-3)","duration":211.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36204657,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Clubland 100% Euphoric","duration":210.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36275556,"trackName":"Dont You Worry Child","artistName":"Swedish House Mafia","albumName":"None","duration":215.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36836185,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Beach & Pool Party by Digster Pop","duration":211.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36623577,"trackName":"Don’t You Worry Child","artistName":"Swedish House Mafia","albumName":"NOW That’s What I Call 30 Years","duration":212.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36649741,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"music","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":36452618,"trackName":"Dont You Worry Child","artistName":"Swedish House Mafia","albumName":"2012年09月欧美新歌速递","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"}
    ]
    """#

    /// `search?q=Swedish House Mafia Don't You Worry Child`: the same song, and this page does hold the 257.96-second row.
    static let worryChildFreeTextSearch = #"""
    [
    {"id":32249879,"trackName":"Swedish House Mafia ft. John Martin - Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia ft. John Martin - Don't You Worry Child","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34036025,"trackName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","duration":334.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":3209347,"trackName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","duration":403.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":9195185,"trackName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":34659513,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":333.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":17842221,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":257.9234304,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":17833332,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":257.959184,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":8916891,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":404.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":4407891,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":213.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":1906921,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":329.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":39533399,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Don't You Worry Child","duration":210.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":14273089,"trackName":"Swedish House Mafia ft. John Martin - Don't You Worry Child (Official Video)","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia Videos","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":18534609,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia","duration":233.038344,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":17583113,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia","duration":214.909388,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":23336157,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia","duration":334.944,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":30061995,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia","albumName":"Swedish House Mafia","duration":213.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":32629532,"trackName":"Don't You Worry Child","artistName":"Swedish House Mafia ft. John Martin","albumName":"Swedish House Mafia ft. John Martin - Don't You Worry Child","duration":335.0,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":22264102,"trackName":"Don’t You Worry Child (acoustic)","artistName":"Swedish House Mafia","albumName":"Don’t You Worry Child","duration":403.536,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":22821651,"trackName":"Don’t You Worry Child (extended)","artistName":"Swedish House Mafia","albumName":"Don’t You Worry Child","duration":403.536,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"},
    {"id":16902153,"trackName":"Don’t You Worry Child (acoustic)","artistName":"Swedish House Mafia","albumName":"Don’t You Worry Child","duration":256.8620288,"instrumental":false,"plainLyrics":"la\nla","syncedLyrics":"[00:01.00]la\n[00:03.00]la"}
    ]
    """#
}