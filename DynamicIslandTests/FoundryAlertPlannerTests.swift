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

/// When a change in Foundry's feed earns a closed-notch alert, and when it doesn't.
final class FoundryAlertPlannerTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func feed(
        count: Int,
        title: String? = nil,
        severity: String? = nil,
        project: String? = "Placely"
    ) -> FoundryFeed {
        FoundryFeed(
            version: 1,
            updatedAt: nil,
            nextUp: nil,
            projects: [],
            attention: .init(count: count, topTitle: title, topSeverity: severity, topProjectName: project)
        )
    }

    private let calm = FoundryAlertPlannerTests.calmFeed
    private static let calmFeed = FoundryFeed(version: 1, updatedAt: nil, nextUp: nil, projects: [], attention: .none)

    private func plan(_ previous: FoundryFeed?, _ new: FoundryFeed, history: FoundryAlertHistory = FoundryAlertHistory(), at offset: TimeInterval = 0) -> FoundryAlert? {
        FoundryAlertPlanner.plan(previous: previous, new: new, history: history, now: now.addingTimeInterval(offset))
    }

    // MARK: First load

    func testTheFirstFeedOfASessionNeverAlerts() {
        XCTAssertNil(plan(nil, feed(count: 3, title: "Beta is overdue", severity: "critical")))
        XCTAssertNil(plan(nil, calm))
    }

    // MARK: News

    func testANewWarningWhereThereWasNoneAlerts() {
        let alert = plan(calm, feed(count: 1, title: "Beta is overdue", severity: "warning"))
        XCTAssertEqual(alert?.title, "Beta is overdue")
        XCTAssertEqual(alert?.severity, .warning)
        XCTAssertEqual(alert?.projectName, "Placely")
    }

    func testAWarningAfterOnlyNotesAlerts() {
        let before = feed(count: 1, title: "Quiet for 15 days", severity: "info")
        XCTAssertNotNil(plan(before, feed(count: 2, title: "Beta is overdue", severity: "warning")))
    }

    func testEscalationAlerts() {
        let before = feed(count: 1, title: "Beta is overdue", severity: "warning")
        let after = feed(count: 1, title: "Beta is overdue", severity: "critical")
        let alert = plan(before, after)
        XCTAssertEqual(alert?.severity, .critical)
    }

    func testADifferentWarningOnTopWithMoreItemsAlerts() {
        let before = feed(count: 1, title: "Beta is overdue", severity: "warning")
        let after = feed(count: 2, title: "Launch is blocked", severity: "warning")
        XCTAssertEqual(plan(before, after)?.title, "Launch is blocked")
        XCTAssertEqual(plan(before, after)?.count, 2)
    }

    // MARK: Not news

    func testInformationalNotesNeverAlert() {
        XCTAssertNil(plan(calm, feed(count: 1, title: "Quiet for 15 days", severity: "info")))
        XCTAssertNil(plan(calm, feed(count: 4, title: "Quiet", severity: "mystery")))
    }

    func testAnUnchangedFeedDoesNotRepeatItself() {
        let same = feed(count: 2, title: "Beta is overdue", severity: "warning")
        XCTAssertNil(plan(same, same))
    }

    func testTheSameWarningTickingUpTheCountIsNotNews() {
        // The note beneath the top warning grew; what the notch would say is unchanged.
        let before = feed(count: 1, title: "Beta is overdue", severity: "warning")
        let after = feed(count: 2, title: "Beta is overdue", severity: "warning")
        XCTAssertNil(plan(before, after))
    }

    func testAResolvedWarningMakingWayForTheNextIsNotNews() {
        let before = feed(count: 3, title: "Beta is overdue", severity: "warning")
        let after = feed(count: 2, title: "Launch is blocked", severity: "warning")
        XCTAssertNil(plan(before, after))
    }

    func testADifferentWarningWithTheSameCountIsNotNews() {
        let before = feed(count: 2, title: "Beta is 5 days overdue", severity: "warning")
        let after = feed(count: 2, title: "Beta is 6 days overdue", severity: "warning")
        XCTAssertNil(plan(before, after), "the text moving on by a day is not a new warning")
    }

    func testWarningsGoingAwayNeverAlert() {
        XCTAssertNil(plan(feed(count: 2, title: "Beta is overdue", severity: "critical"), calm))
    }

    func testDeEscalationDoesNotAlert() {
        let before = feed(count: 1, title: "Beta is overdue", severity: "critical")
        let after = feed(count: 1, title: "Beta is overdue", severity: "warning")
        XCTAssertNil(plan(before, after))
    }

    func testACountWithNoTitleHasNothingToSay() {
        XCTAssertNil(plan(calm, feed(count: 2, title: nil, severity: "critical")))
        XCTAssertNil(plan(calm, feed(count: 2, title: "   ", severity: "critical")))
    }

    func testAZeroCountMeansNoWarningWhateverTheTitle() {
        XCTAssertNil(plan(calm, feed(count: 0, title: "Stale title", severity: "critical")))
    }

    // MARK: Rate limiting

    func testTheSameWarningAlertsOncePerTenMinutes() throws {
        let warning = feed(count: 1, title: "Beta is overdue", severity: "warning")
        var history = FoundryAlertHistory()
        let first = try XCTUnwrap(plan(calm, warning))
        history.record(first, at: now)

        // It goes away and comes back five minutes later: quiet.
        XCTAssertNil(plan(calm, warning, history: history, at: 300))
        // Ten minutes on: alerts again.
        XCTAssertNotNil(plan(calm, warning, history: history, at: FoundryAlertPlanner.perWarningCooldown + 1))
    }

    func testDifferentWarningsHaveSeparateCooldownsButAlertsAreNeverBackToBack() throws {
        let first = feed(count: 1, title: "Beta is overdue", severity: "warning")
        let second = feed(count: 1, title: "Launch is blocked", severity: "warning")
        var history = FoundryAlertHistory()
        history.record(try XCTUnwrap(plan(calm, first)), at: now)

        XCTAssertNil(plan(calm, second, history: history, at: 5), "inside the global gap")
        XCTAssertNotNil(plan(calm, second, history: history, at: FoundryAlertPlanner.globalCooldown + 1))
    }

    func testEscalatingTheSameWarningIsNotSwallowedByItsEarlierAlert() throws {
        let warning = feed(count: 1, title: "Beta is overdue", severity: "warning")
        let critical = feed(count: 1, title: "Beta is overdue", severity: "critical")
        var history = FoundryAlertHistory()
        history.record(try XCTUnwrap(plan(calm, warning)), at: now)
        XCTAssertNotNil(plan(warning, critical, history: history, at: 60), "critical is a different level of news")
    }

    func testHistoryForgetsOldRecords() throws {
        var history = FoundryAlertHistory()
        let old = FoundryAlert(key: "a|old", severity: .warning, title: "old", projectName: nil, count: 1)
        history.record(old, at: now)
        history.record(FoundryAlert(key: "b|new", severity: .warning, title: "new", projectName: nil, count: 1),
                       at: now.addingTimeInterval(FoundryAlertHistory.retention + 1))
        XCTAssertNil(history.lastAlert(for: FoundryAlertPlanner.cooldownKey(for: old)))
        XCTAssertEqual(history.byWarning.count, 1)
    }

    func testAClockThatJumpsBackwardsDoesNotMuteAlertsForever() throws {
        let warning = feed(count: 1, title: "Beta is overdue", severity: "warning")
        var history = FoundryAlertHistory()
        history.record(try XCTUnwrap(plan(calm, warning)), at: now)
        XCTAssertNotNil(plan(calm, warning, history: history, at: -3600))
    }

    // MARK: Wording

    func testTheLabelIsTheTitleForOneWarningAndTheCountForMore() {
        let one = FoundryAlert(key: "k", severity: .warning, title: "Beta is overdue", projectName: nil, count: 1)
        XCTAssertEqual(one.label, "Beta is overdue")
        let several = FoundryAlert(key: "k", severity: .warning, title: "Beta is overdue", projectName: nil, count: 3)
        XCTAssertEqual(several.label, "3 to review")
    }

    func testLongTitlesAreCutShort() {
        let title = "Placely launch is blocked by the payment provider review"
        let short = FoundryAlert.shortTitle(title)
        XCTAssertLessThanOrEqual(short.count, FoundryAlert.maxTitleLength)
        XCTAssertTrue(short.hasSuffix("\u{2026}"))
        XCTAssertEqual(FoundryAlert.shortTitle("Short"), "Short")
        XCTAssertEqual(FoundryAlert.shortTitle("  padded  "), "padded")
    }

    func testDisplayDurationIsAboutThreeSeconds() {
        XCTAssertEqual(FoundryAlertPlanner.displayDuration, 3)
    }

    func testKeysIgnoreCaseSoARetitledWarningIsStillTheSameOne() {
        let a = FoundryAlertPlanner.topWarning(in: feed(count: 1, title: "Beta Overdue", severity: "warning", project: "Placely"))
        let b = FoundryAlertPlanner.topWarning(in: feed(count: 1, title: "beta overdue", severity: "warning", project: "placely"))
        XCTAssertEqual(a?.key, b?.key)
    }
}
