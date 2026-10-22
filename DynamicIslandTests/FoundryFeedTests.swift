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

final class FoundryFeedTests: XCTestCase {

    /// The shape Foundry writes (see Foundry's NotchFeed.swift), including fields Notchly ignores.
    private func feedJSON(nextUp: Bool = true, attention: String = #"{"count":0}"#, version: Int = 1) -> Data {
        let next = nextUp ? #"""
        {"key":"task:abc","subject":"task","subjectId":"abc","title":"Finish payment tests","projectId":"p1","projectName":"Placely","reasons":["In progress"],"canComplete":true}
        """# : "null"
        return """
        {"version":\(version),"updatedAt":"2026-10-22T10:00:00.000Z","nextUp":\(next),
         "projects":[{"id":"p1","name":"Placely","health":"atRisk","healthLabel":"At risk","phase":"Building","scopeCompletion":0.4,"forecast":"12 Nov – 26 Nov"}],
         "attention":\(attention)}
        """.data(using: .utf8)!
    }

    func testDecodesFoundryFeed() throws {
        let feed = try XCTUnwrap(FoundryFeed.decode(feedJSON()))
        XCTAssertEqual(feed.nextUp?.title, "Finish payment tests")
        XCTAssertEqual(feed.projects.first?.name, "Placely")
    }

    func testRejectsNewerFeedVersionsAndGarbage() {
        XCTAssertNil(FoundryFeed.decode(feedJSON(version: 2)))
        XCTAssertNil(FoundryFeed.decode(Data("not json".utf8)))
    }

    func testNextUpBecomesANeutralChipThatCanBeCompleted() throws {
        let content = try XCTUnwrap(FoundryChipContent.make(from: FoundryFeed.decode(feedJSON())))
        XCTAssertEqual(content.kind, .nextUp)
        XCTAssertEqual(content.completableTaskId, "abc")
        XCTAssertEqual(content.projectId, "p1")

        var context = HubContext()
        context.foundry = content
        let chip = try XCTUnwrap(HubChipPlanner.model(for: .foundry, context: context))
        XCTAssertEqual(chip.tone, .neutral)
        XCTAssertEqual(chip.text, "Finish payment tests")
    }

    func testWarningsTakePrecedenceAndCarryTheirSeverity() throws {
        let attention = #"{"count":2,"topTitle":"“Beta” is 6 days overdue","topSeverity":"critical","topProjectName":"Placely"}"#
        let content = try XCTUnwrap(FoundryChipContent.make(from: FoundryFeed.decode(feedJSON(attention: attention))))
        XCTAssertEqual(content.kind, .attention(critical: true))
        XCTAssertNil(content.completableTaskId)
        XCTAssertEqual(content.projectId, "p1")
        XCTAssertTrue(content.detail.contains("+1 more"))

        var context = HubContext()
        context.foundry = content
        XCTAssertEqual(HubChipPlanner.model(for: .foundry, context: context)?.tone, .critical)
    }

    func testInformationalNotesDoNotTakeOverTheChip() throws {
        let attention = #"{"count":1,"topTitle":"Quiet for 15 days","topSeverity":"info","topProjectName":"Placely"}"#
        let content = try XCTUnwrap(FoundryChipContent.make(from: FoundryFeed.decode(feedJSON(attention: attention))))
        XCTAssertEqual(content.kind, .nextUp)
    }

    func testNoFeedOrNothingToSayHidesTheChip() {
        XCTAssertNil(FoundryChipContent.make(from: nil))
        XCTAssertNil(FoundryChipContent.make(from: FoundryFeed.decode(feedJSON(nextUp: false))))
        XCTAssertNil(HubChipPlanner.model(for: .foundry, context: HubContext()))
    }

    func testLinksOnlyCarrySafeCharacters() {
        XCTAssertEqual(FoundryLink.completeTask("abc")?.absoluteString, "foundry://task/abc/complete")
        XCTAssertEqual(FoundryLink.deferRecommendation("task:abc")?.absoluteString, "foundry://recommendation/task:abc/defer?days=1")
        XCTAssertNil(FoundryLink.project("a b"))
        XCTAssertNil(FoundryLink.project("x&y"))
    }

    // MARK: Tolerant decoding

    func testFullFeedKeepsEverythingNotchlyShows() throws {
        let feed = try XCTUnwrap(FoundryFeed.decode(feedJSON()))
        XCTAssertEqual(feed.nextUp?.reasons, ["In progress"])
        XCTAssertEqual(feed.projects.first?.healthLabel, "At risk")
        XCTAssertEqual(feed.projects.first?.phase, "Building")
        XCTAssertEqual(feed.projects.first?.scopeCompletion, 0.4)
        XCTAssertEqual(feed.projects.first?.forecast, "12 Nov \u{2013} 26 Nov")
        XCTAssertNotNil(feed.updatedAt)
    }

    func testEpochPlaceholderCountsAsNoTimestamp() throws {
        let data = Data(#"{"version":1,"updatedAt":"1970-01-01T00:00:00.000Z","projects":[],"attention":{"count":0}}"#.utf8)
        XCTAssertNil(try XCTUnwrap(FoundryFeed.decode(data)).updatedAt)
    }

    func testUnknownFieldsAreIgnored() {
        let data = Data(#"{"version":1,"future":{"a":1},"projects":[],"attention":{"count":0,"extra":true}}"#.utf8)
        XCTAssertNotNil(FoundryFeed.decode(data))
    }

    func testMalformedProjectIsDroppedNotTheWholeFeed() throws {
        let data = Data(#"""
        {"version":1,"projects":[{"id":"p1","name":"Good","health":"onTrack"},{"name":"No id"},{"id":7,"name":"Bad id"},{"id":"p2","name":"Also good","health":"blocked"}],
         "attention":{"count":0}}
        """#.utf8)
        let feed = try XCTUnwrap(FoundryFeed.decode(data))
        XCTAssertEqual(feed.projects.map(\.id), ["p1", "p2"])
    }

    func testMalformedNextUpAndAttentionFallBack() throws {
        let data = Data(#"{"version":1,"nextUp":{"title":"no key"},"projects":[],"attention":"nope"}"#.utf8)
        let feed = try XCTUnwrap(FoundryFeed.decode(data))
        XCTAssertNil(feed.nextUp)
        XCTAssertEqual(feed.attention, .none)
    }

    func testMissingOptionalFieldsGetDefaults() throws {
        let data = Data(#"{"version":1,"projects":[{"id":"p","name":"N"}],"attention":{"count":-4}}"#.utf8)
        let feed = try XCTUnwrap(FoundryFeed.decode(data))
        XCTAssertEqual(feed.projects.first?.health, "unknown")
        XCTAssertNil(feed.projects.first?.scopeCompletion)
        XCTAssertEqual(feed.attention.count, 0, "a negative count is clamped")
    }

    func testMoreThanFiveProjectsAreCapped() throws {
        let projects = (0..<9).map { #"{"id":"p\#($0)","name":"P\#($0)","health":"onTrack"}"# }.joined(separator: ",")
        let feed = try XCTUnwrap(FoundryFeed.decode(Data(#"{"version":1,"projects":[\#(projects)],"attention":{"count":0}}"#.utf8)))
        XCTAssertEqual(feed.projects.count, FoundryFeed.maxProjects)
    }

    func testVersionsAreChecked() {
        XCTAssertEqual(FoundryFeed.parse(feedJSON(version: 2)), .unsupportedVersion(2))
        XCTAssertEqual(FoundryFeed.parse(feedJSON(version: 0)), .unsupportedVersion(0))
        XCTAssertEqual(FoundryFeed.parse(Data(#"{"projects":[]}"#.utf8)), .invalid, "no version at all")
        XCTAssertEqual(FoundryFeed.parse(Data("[1,2".utf8)), .invalid)
        XCTAssertEqual(FoundryFeed.parse(Data()), .invalid)
        guard case .ok = FoundryFeed.parse(feedJSON()) else { return XCTFail("a valid feed should parse") }
    }

    // MARK: The file

    private func info(regular: Bool = true, owner: UInt32 = 501, mode: UInt16 = 0o600, size: Int = 400) -> FoundryFeedFileInfo {
        FoundryFeedFileInfo(isRegularFile: regular, ownerID: owner, permissions: mode, size: size, modified: nil)
    }

    func testPolicyAcceptsFoundrysOwnFile() {
        XCTAssertNil(FoundryFeedFilePolicy.problem(for: info(), currentUserID: 501))
        XCTAssertNil(FoundryFeedFilePolicy.problem(for: info(mode: 0o644), currentUserID: 501), "readable by others is fine")
    }

    func testPolicyRejectsFilesOthersCouldHaveWritten() {
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(owner: 0), currentUserID: 501), .wrongOwner)
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(mode: 0o666), currentUserID: 501), .writableByOthers)
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(mode: 0o620), currentUserID: 501), .writableByOthers)
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(mode: 0o602), currentUserID: 501), .writableByOthers)
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(regular: false), currentUserID: 501), .notAFile)
        XCTAssertEqual(FoundryFeedFilePolicy.problem(for: info(size: FoundryFeedFilePolicy.maxBytes + 1), currentUserID: 501), .tooLarge)
    }

    func testLoaderReadsRealFilesAndRefusesBadOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("foundry-feed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("notch.json")

        XCTAssertEqual(FoundryFeedLoader.load(at: url), .missing)
        XCTAssertFalse(FoundryFeedLoader.exists(at: url))

        try feedJSON().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard case .loaded(let feed, let modified) = FoundryFeedLoader.load(at: url) else { return XCTFail("should load") }
        XCTAssertEqual(feed.projects.count, 1)
        XCTAssertNotNil(modified)

        try FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: url.path)
        XCTAssertEqual(FoundryFeedLoader.load(at: url), .rejected(.writableByOthers))

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(FoundryFeedLoader.load(at: url, currentUserID: 12345), .rejected(.wrongOwner))

        try feedJSON(version: 9).write(to: url)
        XCTAssertEqual(FoundryFeedLoader.load(at: url), .unsupportedVersion(9))
        try Data("{ not json".utf8).write(to: url)
        XCTAssertEqual(FoundryFeedLoader.load(at: url), .invalid)

        // A link is not followed: the target may be anything.
        let link = dir.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
        XCTAssertEqual(FoundryFeedLoader.load(at: link), .rejected(.notAFile))
    }

    // MARK: Links

    func testIdsWithPathOrQueryCharactersAreRefused() {
        XCTAssertNil(FoundryLink.project("a/b"))
        XCTAssertNil(FoundryLink.project("a?b=c"))
        XCTAssertNil(FoundryLink.project(""))
        XCTAssertNil(FoundryLink.project(String(repeating: "a", count: 81)))
        XCTAssertNil(FoundryLink.completeTask("x/complete"))
        XCTAssertNil(FoundryLink.deferRecommendation("k?days=30"))
        XCTAssertNotNil(FoundryLink.project("3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        XCTAssertEqual(FoundryLink.deferRecommendation("task:abc", days: 7)?.absoluteString, "foundry://recommendation/task:abc/defer?days=7")
    }

    func testDeferDaysAreClampedToWhatFoundryAccepts() {
        XCTAssertEqual(FoundryLink.deferRecommendation("k", days: 0)?.absoluteString, "foundry://recommendation/k/defer?days=1")
        XCTAssertEqual(FoundryLink.deferRecommendation("k", days: 99)?.absoluteString, "foundry://recommendation/k/defer?days=30")
    }

    func testEveryLinkIsOneFoundryAccepts() {
        // The same grammar as Foundry's FoundryURLAction.
        for url in [FoundryLink.open, FoundryLink.project("p1")!, FoundryLink.completeTask("t1")!, FoundryLink.deferRecommendation("task:t1", days: 3)!] {
            XCTAssertEqual(url.scheme, "foundry")
            XCTAssertNil(url.user)
            XCTAssertNil(url.fragment)
        }
        XCTAssertEqual(FoundryLink.open.host, "open")
        XCTAssertEqual(FoundryLink.project("p1")?.host, "project")
        XCTAssertEqual(FoundryLink.completeTask("t1")?.pathComponents, ["/", "t1", "complete"])
    }
}
