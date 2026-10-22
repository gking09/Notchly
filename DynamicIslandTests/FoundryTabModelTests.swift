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
import XCTest
@testable import Notchly

/// The Foundry tab's logic: what it shows for each kind of feed, how health is
/// drawn, the two-step Complete, and how much room it needs.
final class FoundryTabModelTests: XCTestCase {

    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func project(_ id: String, health: String = "onTrack", completion: Double? = 0.5, forecast: String? = "1 Dec") -> FoundryFeed.Project {
        FoundryFeed.Project(id: id, name: "Project \(id)", health: health, healthLabel: nil, phase: "Building", scopeCompletion: completion, forecast: forecast)
    }

    static func feed(
        nextUp: FoundryFeed.NextUp? = FoundryFeed.NextUp(
            key: "task:t1", subjectId: "t1", title: "Finish the lightbox", projectId: "p1", projectName: "Project p1",
            reasons: ["In progress", "Due soon", "Third"], canComplete: true),
        projects: [FoundryFeed.Project] = [project("p1")],
        attention: FoundryFeed.Attention = .none,
        updatedAt: Date? = now.addingTimeInterval(-300)
    ) -> FoundryFeed {
        FoundryFeed(version: 1, updatedAt: updatedAt, nextUp: nextUp, projects: projects, attention: attention)
    }

    static func loaded(_ feed: FoundryFeed, modified: Date? = nil) -> FoundryFeedState {
        .loaded(feed, modified: modified)
    }

    // MARK: Modes

    func testNormalFeedShowsHeroRowsAndNoBanner() {
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed()), now: Self.now)
        XCTAssertEqual(model.mode, .content)
        XCTAssertEqual(model.hero?.title, "Finish the lightbox")
        XCTAssertEqual(model.hero?.reasons, "In progress \u{00B7} Due soon", "two reasons at most")
        XCTAssertEqual(model.hero?.completableTaskId, "t1")
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertNil(model.banner)
        XCTAssertFalse(model.isStale)
    }

    func testAttentionBecomesABannerWithItsProject() {
        let attention = FoundryFeed.Attention(count: 3, topTitle: "Beta is 6 days overdue", topSeverity: "critical", topProjectName: "Project p1")
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(attention: attention)), now: Self.now)
        XCTAssertEqual(model.banner?.severity, .critical)
        XCTAssertEqual(model.banner?.count, 3)
        XCTAssertEqual(model.banner?.projectId, "p1")
        XCTAssertEqual(model.banner?.title, "Beta is 6 days overdue")
    }

    func testBannerWithoutATitleFallsBackToTheCount() {
        let attention = FoundryFeed.Attention(count: 2, topTitle: nil, topSeverity: nil, topProjectName: nil)
        let banner = FoundryTabModel.make(state: Self.loaded(Self.feed(attention: attention)), now: Self.now).banner
        XCTAssertEqual(banner?.severity, .info)
        XCTAssertTrue(banner?.title.contains("2") == true)
    }

    func testNextStepThatIsNotATaskCannotBeCompleted() {
        var next = Self.feed().nextUp!
        next.canComplete = false
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(nextUp: next)), now: Self.now)
        XCTAssertNil(model.hero?.completableTaskId)
        XCTAssertEqual(model.hero?.key, "task:t1", "Later still works")
    }

    func testEmptyFeedIsTheEmptyState() {
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(nextUp: nil, projects: [])), now: Self.now)
        XCTAssertEqual(model.mode, .empty)
        XCTAssertNil(model.hero)
        XCTAssertTrue(model.rows.isEmpty)
    }

    func testFeedWithOnlyProjectsIsStillContent() {
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(nextUp: nil)), now: Self.now)
        XCTAssertEqual(model.mode, .content)
        XCTAssertNil(model.hero)
    }

    func testEveryFailureBecomesAMessageWithAWayForward() {
        let states: [FoundryFeedState] = [.off, .notFound, .invalid, .unsupported(3), .rejected(.wrongOwner)]
        for state in states {
            let model = FoundryTabModel.make(state: state, now: Self.now)
            guard case .noFeed(let reason) = model.mode else { return XCTFail("\(state) should be a no-feed state") }
            XCTAssertFalse(reason.title.isEmpty)
            XCTAssertFalse(reason.detail.isEmpty)
            XCTAssertNil(model.hero)
            XCTAssertTrue(model.rows.isEmpty)
        }
        XCTAssertEqual(FoundryNoFeedReason.notFound.title, "Foundry isn't running or sharing a summary")
    }

    // MARK: Staleness

    func testQuietFeedGetsOldWithoutBeingWrongSoItIsOnlyLabelled() {
        let old = Self.now.addingTimeInterval(-3 * 86_400)
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(updatedAt: old), modified: old), now: Self.now)
        XCTAssertTrue(model.isStale)
        XCTAssertEqual(model.mode, .content, "stale content is still shown")
        XCTAssertEqual(model.updatedText(now: Self.now), "Updated 3 days ago")
    }

    func testFreshnessUsesWhicheverTimestampIsNewer() {
        let old = Self.now.addingTimeInterval(-5 * 86_400)
        let written = Self.now.addingTimeInterval(-600)
        // Data changed days ago but the file was rewritten ten minutes ago.
        let state = Self.loaded(Self.feed(updatedAt: old), modified: written)
        XCTAssertEqual(state.lastUpdated, written)
        XCTAssertFalse(FoundryTabModel.make(state: state, now: Self.now).isStale)
    }

    func testUnknownTimeIsNeverStale() {
        XCTAssertFalse(FoundryTime.isStale(lastUpdated: nil, now: Self.now))
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(updatedAt: nil)), now: Self.now)
        XCTAssertFalse(model.isStale)
        XCTAssertNil(model.updatedText(now: Self.now))
    }

    func testStalenessThresholdIsTwentyFourHours() {
        XCTAssertFalse(FoundryTime.isStale(lastUpdated: Self.now.addingTimeInterval(-86_399), now: Self.now))
        XCTAssertTrue(FoundryTime.isStale(lastUpdated: Self.now.addingTimeInterval(-86_401), now: Self.now))
    }

    func testRelativeTimeReadsNaturally() {
        func text(_ seconds: TimeInterval) -> String { FoundryTime.relative(from: Self.now.addingTimeInterval(-seconds), now: Self.now) }
        XCTAssertEqual(text(5), "just now")
        XCTAssertEqual(text(-30), "just now", "a clock slightly ahead is not the future")
        XCTAssertEqual(text(5 * 60), "5 min ago")
        XCTAssertEqual(text(3 * 3600), "3 h ago")
        XCTAssertEqual(text(30 * 3600), "yesterday")
        XCTAssertEqual(text(4 * 86_400), "4 days ago")
    }

    // MARK: Rows

    func testRowsAreCappedAndKeepTheirOrder() {
        let projects = (0..<8).map { Self.project("p\($0)") }
        let model = FoundryTabModel.make(state: Self.loaded(Self.feed(projects: projects)), now: Self.now)
        XCTAssertEqual(model.rows.count, 5)
        XCTAssertEqual(model.rows.map(\.id), ["p0", "p1", "p2", "p3", "p4"])
    }

    func testProgressIsClampedAndFormatted() {
        func row(_ completion: Double?) -> FoundryTabModel.Row {
            FoundryTabModel.make(state: Self.loaded(Self.feed(projects: [Self.project("p", completion: completion)])), now: Self.now).rows[0]
        }
        XCTAssertEqual(row(0.349).progressText, "35%")
        XCTAssertEqual(row(1.7).progress, 1)
        XCTAssertEqual(row(-0.2).progress, 0)
        XCTAssertEqual(row(.nan).progress, nil)
        XCTAssertNil(row(nil).progress)
        XCTAssertNil(row(nil).progressText)
    }

    func testBlankForecastAndPhaseAreOmitted() {
        var project = Self.project("p", forecast: "  ")
        project.phase = ""
        let row = FoundryTabModel.make(state: Self.loaded(Self.feed(projects: [project])), now: Self.now).rows[0]
        XCTAssertNil(row.forecast)
        XCTAssertNil(row.phase)
    }

    func testHealthLabelFallsBackToTheKind() {
        var project = Self.project("p", health: "blocked")
        project.healthLabel = "Waiting on design"
        var rows = FoundryTabModel.make(state: Self.loaded(Self.feed(projects: [project])), now: Self.now).rows
        XCTAssertEqual(rows[0].healthLabel, "Waiting on design")
        project.healthLabel = nil
        rows = FoundryTabModel.make(state: Self.loaded(Self.feed(projects: [project])), now: Self.now).rows
        XCTAssertEqual(rows[0].healthLabel, "Blocked")
    }

    // MARK: Health

    func testHealthMapsFoundrysVocabulary() {
        XCTAssertEqual(FoundryHealth(raw: "onTrack"), .healthy)
        XCTAssertEqual(FoundryHealth(raw: "atRisk"), .atRisk)
        XCTAssertEqual(FoundryHealth(raw: "behind"), .behind)
        XCTAssertEqual(FoundryHealth(raw: "blocked"), .blocked)
        XCTAssertEqual(FoundryHealth(raw: "onHold"), .paused)
        XCTAssertEqual(FoundryHealth(raw: "completed"), .done)
        XCTAssertEqual(FoundryHealth(raw: "notStarted"), .notStarted)
        XCTAssertEqual(FoundryHealth(raw: "somethingNew"), .unknown)
    }

    func testEveryHealthHasItsOwnRealGlyph() {
        let all: [FoundryHealth] = [.healthy, .atRisk, .behind, .blocked, .paused, .done, .notStarted, .unknown]
        XCTAssertEqual(Set(all.map(\.glyph)).count, all.count, "shape alone must tell them apart")
        for health in all {
            XCTAssertNotNil(NSImage(systemSymbolName: health.glyph, accessibilityDescription: nil), "\(health.glyph) is not an SF Symbol")
            XCTAssertFalse(health.fallbackLabel.isEmpty)
        }
    }

    func testOnlyHealthThatCarriesMeaningGetsColour() {
        XCTAssertEqual(FoundryHealth.healthy.tone, .good)
        XCTAssertEqual(FoundryHealth.atRisk.tone, .caution)
        XCTAssertEqual(FoundryHealth.behind.tone, .caution)
        XCTAssertEqual(FoundryHealth.blocked.tone, .bad)
        for neutral in [FoundryHealth.paused, .done, .notStarted, .unknown] {
            XCTAssertEqual(neutral.tone, .neutral)
        }
    }

    func testSeverityOrderingAndUnknownValues() {
        XCTAssertLessThan(FoundrySeverity.info, .warning)
        XCTAssertLessThan(FoundrySeverity.warning, .critical)
        XCTAssertEqual(FoundrySeverity(raw: "whatever"), .info)
        XCTAssertEqual(FoundrySeverity(raw: nil), .info)
        XCTAssertFalse(FoundrySeverity.info.isActionable)
        XCTAssertTrue(FoundrySeverity.warning.isActionable)
    }

    // MARK: Two-step complete

    func testFirstTapArmsAndSecondConfirms() {
        var step = FoundryTwoStep()
        let t0 = Self.now
        XCTAssertFalse(step.isArmed(at: t0))
        XCTAssertEqual(step.tap(at: t0), .armed)
        XCTAssertTrue(step.isArmed(at: t0.addingTimeInterval(1)))
        XCTAssertEqual(step.tap(at: t0.addingTimeInterval(1)), .confirmed)
        XCTAssertFalse(step.isArmed(at: t0.addingTimeInterval(1)), "confirming resets it")
    }

    func testArmedStateLapsesAfterThreeSeconds() {
        var step = FoundryTwoStep()
        _ = step.tap(at: Self.now)
        XCTAssertTrue(step.isArmed(at: Self.now.addingTimeInterval(2.99)))
        XCTAssertFalse(step.isArmed(at: Self.now.addingTimeInterval(3.01)))
        // A late second tap only arms again; it never confirms.
        XCTAssertEqual(step.tap(at: Self.now.addingTimeInterval(5)), .armed)
    }

    func testASingleTapNeverConfirms() {
        for offset in [0.0, 0.5, 2.9, 10, 1000] {
            var step = FoundryTwoStep()
            XCTAssertEqual(step.tap(at: Self.now.addingTimeInterval(offset)), .armed)
        }
    }

    func testCancelDisarms() {
        var step = FoundryTwoStep()
        _ = step.tap(at: Self.now)
        step.cancel()
        XCTAssertFalse(step.isArmed(at: Self.now))
        XCTAssertEqual(step.tap(at: Self.now), .armed)
    }

    // MARK: Later

    func testDeferOptionsAreOneDayThreeDaysOneWeek() {
        XCTAssertEqual(FoundryDeferOption.allCases.map(\.days), [1, 3, 7])
        XCTAssertEqual(FoundryDeferOption.oneWeek.link(forKey: "task:abc")?.absoluteString, "foundry://recommendation/task:abc/defer?days=7")
        XCTAssertNil(FoundryDeferOption.oneDay.link(forKey: "bad key"))
        for option in FoundryDeferOption.allCases { XCTAssertFalse(option.title.isEmpty) }
    }

    // MARK: Budget

    func testTabFitsTheOpenNotchBudget() {
        XCTAssertLessThanOrEqual(FoundryTabMetrics.contentHeight, FoundryTabMetrics.availableHeight)
        XCTAssertEqual(FoundryTabMetrics.rowsHeight, 5 * FoundryTabMetrics.rowHeight + 4 * FoundryTabMetrics.rowSpacing, accuracy: 0.001)
    }

    func testPhaseColumnOnlyShowsWhereThereIsRoom() {
        XCTAssertFalse(FoundryTabMetrics.showsPhase(rowsWidth: 338))
        XCTAssertTrue(FoundryTabMetrics.showsPhase(rowsWidth: 420))
    }

    // MARK: Status summary

    func testStatusSummaryForLoadedFeed() {
        let summary = FoundryStatusSummary.make(state: Self.loaded(Self.feed(), modified: Self.now.addingTimeInterval(-120)), installed: true, now: Self.now)
        XCTAssertTrue(summary.feedFound)
        XCTAssertEqual(summary.projectCount, 1)
        XCTAssertEqual(summary.versionSupported, true)
        XCTAssertEqual(summary.updatedText, "2 min ago")
    }

    func testStatusSummaryForUnsupportedVersion() {
        let summary = FoundryStatusSummary.make(state: .unsupported(4), installed: true, now: Self.now)
        XCTAssertTrue(summary.feedFound)
        XCTAssertEqual(summary.versionSupported, false)
        XCTAssertTrue(summary.versionText.contains("4"))
    }

    func testStatusSummaryWhenFoundryIsNotInstalled() {
        let off = FoundryStatusSummary.make(state: .off, installed: false, now: Self.now)
        XCTAssertFalse(off.feedFound)
        XCTAssertEqual(off.feedText, "Foundry isn't installed")
        let notFound = FoundryStatusSummary.make(state: .notFound, installed: true, now: Self.now)
        XCTAssertEqual(notFound.feedText, "No summary yet")
        let offWithFile = FoundryStatusSummary.make(state: .off, installed: true, feedExists: true, now: Self.now)
        XCTAssertTrue(offWithFile.feedFound)
    }

    // MARK: Menu

    func testMenuStateFollowsTheFeed() {
        let state = FoundryMenuState(feed: Self.feed(attention: .init(count: 2, topTitle: "x", topSeverity: "warning", topProjectName: nil)))
        XCTAssertEqual(state.nextUpTitle, "Finish the lightbox")
        XCTAssertEqual(state.attentionCount, 2)
        XCTAssertEqual(FoundryMenuState(feed: nil), FoundryMenuState())
    }
}
