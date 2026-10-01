import XCTest
@testable import Notchly

final class HubLogicTests: XCTestCase {

    // MARK: Fixtures

    private func utcCalendar(locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = locale
        return calendar
    }

    /// Thursday 1 October 2026, 21:05:09 UTC.
    private var evening: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 1
        components.hour = 21; components.minute = 5; components.second = 9
        return utcCalendar(locale: Locale(identifier: "en_GB")).date(from: components)!
    }

    private func at(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 1
        components.hour = hour; components.minute = minute; components.second = 0
        return utcCalendar(locale: Locale(identifier: "en_GB")).date(from: components)!
    }

    private let british = Locale(identifier: "en_GB")
    private let american = Locale(identifier: "en_US")

    private func parts(_ date: Date, _ format: HubTimeFormat, seconds: Bool = false, locale: Locale? = nil) -> HubClockParts {
        let locale = locale ?? british
        return HubClockFormatter.parts(
            for: date,
            format: format,
            showSeconds: seconds,
            calendar: utcCalendar(locale: locale),
            locale: locale
        )
    }

    // MARK: Clock - hour cycle

    func testTwentyFourHourPadsTheHour() {
        let result = parts(at(hour: 9, minute: 7), .twentyFourHour)
        XCTAssertEqual(result.hours, "09")
        XCTAssertEqual(result.minutes, "07")
        XCTAssertNil(result.period)
        XCTAssertNil(result.seconds)
    }

    func testTwelveHourDropsTheLeadingZeroAndAddsAPeriod() {
        let morning = parts(at(hour: 9, minute: 7), .twelveHour)
        XCTAssertEqual(morning.hours, "9")
        XCTAssertEqual(morning.period, "AM")

        let evening = parts(self.evening, .twelveHour)
        XCTAssertEqual(evening.hours, "9")
        XCTAssertEqual(evening.minutes, "05")
        XCTAssertEqual(evening.period, "PM")
    }

    func testTwelveHourMidnightAndNoonRead12() {
        let midnight = parts(at(hour: 0, minute: 30), .twelveHour)
        XCTAssertEqual(midnight.hours, "12")
        XCTAssertEqual(midnight.period, "AM")

        let noon = parts(at(hour: 12, minute: 0), .twelveHour)
        XCTAssertEqual(noon.hours, "12")
        XCTAssertEqual(noon.period, "PM")
    }

    func testTwentyFourHourMidnightIs00() {
        XCTAssertEqual(parts(at(hour: 0, minute: 5), .twentyFourHour).hours, "00")
        XCTAssertEqual(parts(at(hour: 23, minute: 59), .twentyFourHour).hours, "23")
    }

    // MARK: Clock - system preference

    func testSystemFormatFollowsTheLocale() {
        XCTAssertTrue(HubClockFormatter.uses24Hour(format: .system, locale: british))
        XCTAssertFalse(HubClockFormatter.uses24Hour(format: .system, locale: american))

        XCTAssertEqual(parts(evening, .system, locale: british).hours, "21")
        let us = parts(evening, .system, locale: american)
        XCTAssertEqual(us.hours, "9")
        XCTAssertEqual(us.period, "PM")
    }

    func testExplicitFormatsIgnoreTheLocale() {
        XCTAssertFalse(HubClockFormatter.uses24Hour(format: .twelveHour, locale: british))
        XCTAssertTrue(HubClockFormatter.uses24Hour(format: .twentyFourHour, locale: american))
    }

    // MARK: Clock - seconds

    func testSecondsAppearOnlyWhenAsked() {
        XCTAssertNil(parts(evening, .twentyFourHour, seconds: false).seconds)
        XCTAssertEqual(parts(evening, .twentyFourHour, seconds: true).seconds, "09")
    }

    func testSpokenTextCoversEveryPart() {
        XCTAssertEqual(parts(evening, .twentyFourHour).spokenText, "21:05")
        XCTAssertEqual(parts(evening, .twentyFourHour, seconds: true).spokenText, "21:05:09")
        XCTAssertEqual(parts(evening, .twelveHour, seconds: true).spokenText, "9:05:09 PM")
    }

    // MARK: Clock - date line

    func testDateLineReadsThursdayFirstOct() {
        let line = HubClockFormatter.dateLine(for: evening, calendar: utcCalendar(locale: british), locale: british)
        XCTAssertEqual(line, "Thursday 1 Oct")
    }

    func testDateLineFollowsTheLocale() {
        let line = HubClockFormatter.dateLine(for: evening, calendar: utcCalendar(locale: american), locale: american)
        XCTAssertTrue(line.contains("Thursday"), line)
        XCTAssertTrue(line.contains("Oct"), line)
    }

    // MARK: Chips - relevance

    func testNothingRelevantMeansNoChips() {
        XCTAssertTrue(HubChipPlanner.chips(for: HubContext()).isEmpty)
    }

    func testBatteryIsQuietWhileHealthyOnBattery() {
        var context = HubContext()
        context.batteryLevel = 80
        XCTAssertTrue(HubChipPlanner.chips(for: context).isEmpty)
    }

    func testBatteryAppearsWhenLow() throws {
        var context = HubContext()
        context.batteryLevel = HubChipPlanner.lowBatteryThreshold
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertEqual(chip.kind, .battery)
        XCTAssertEqual(chip.text, "30%")
        XCTAssertEqual(chip.tone, .warning)

        context.batteryLevel = HubChipPlanner.criticalBatteryThreshold
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.tone, .critical)
    }

    func testBatteryShowsABoltAndTimeWhileCharging() throws {
        var context = HubContext()
        context.batteryLevel = 64
        context.isPluggedIn = true
        context.isCharging = true
        context.batteryTimeText = "1h 12m"
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertEqual(chip.symbol, "bolt.fill")
        XCTAssertEqual(chip.text, "64% · 1h 12m")
        XCTAssertEqual(chip.tone, .positive)
    }

    func testBatteryWithoutAnEstimateShowsJustThePercentage() throws {
        var context = HubContext()
        context.batteryLevel = 64
        context.isPluggedIn = true
        context.isCharging = true
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "64%")
    }

    func testPluggedInAndFullStaysQuietAboutTime() throws {
        var context = HubContext()
        context.batteryLevel = 100
        context.isPluggedIn = true
        context.batteryTimeText = "9h"
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "100%")
    }

    func testMacWithoutABatteryNeverShowsTheChip() {
        var context = HubContext()
        context.isPluggedIn = true
        context.isCharging = true
        XCTAssertTrue(HubChipPlanner.chips(for: context).isEmpty)
    }

    func testBatterySymbolSteps() {
        XCTAssertEqual(HubChipPlanner.batterySymbol(forLevel: 5), "battery.0")
        XCTAssertEqual(HubChipPlanner.batterySymbol(forLevel: 25), "battery.25")
        XCTAssertEqual(HubChipPlanner.batterySymbol(forLevel: 50), "battery.50")
        XCTAssertEqual(HubChipPlanner.batterySymbol(forLevel: 75), "battery.75")
        XCTAssertEqual(HubChipPlanner.batterySymbol(forLevel: 100), "battery.100")
    }

    func testRunningTimerShowsRemainingTime() throws {
        var context = HubContext()
        context.timerPhase = .running
        context.timerRemainingSeconds = 272
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertEqual(chip.kind, .timer)
        XCTAssertEqual(chip.text, "04:32")
        XCTAssertTrue(chip.isLive)
    }

    func testPausedTimerKeepsItsChipButStopsPulsing() throws {
        var context = HubContext()
        context.timerPhase = .paused
        context.timerRemainingSeconds = 60
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertFalse(chip.isLive)
        XCTAssertEqual(chip.symbol, "pause.fill")
    }

    func testFinishedTimerSaysDone() throws {
        var context = HubContext()
        context.timerPhase = .finished
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertEqual(chip.symbol, "bell.fill")
        XCTAssertEqual(chip.tone, .warning)
    }

    func testStopwatchShowsElapsedTimeWithHours() throws {
        var context = HubContext()
        context.stopwatchPhase = .running
        context.stopwatchElapsedSeconds = 3_725
        let chip = try XCTUnwrap(HubChipPlanner.chips(for: context).first)
        XCTAssertEqual(chip.kind, .stopwatch)
        XCTAssertEqual(chip.text, "1:02:05")
    }

    func testStashChipNeedsTheStashOnAndItemsInIt() throws {
        var context = HubContext()
        context.stashCount = 3
        XCTAssertTrue(HubChipPlanner.chips(for: context).isEmpty, "Stash is off")

        context.stashEnabled = true
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.kind, .stash)

        context.stashCount = 0
        XCTAssertTrue(HubChipPlanner.chips(for: context).isEmpty, "empty Stash")
    }

    func testStashChipPluralises() throws {
        var context = HubContext()
        context.stashEnabled = true
        context.stashCount = 1
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "1 item")
        context.stashCount = 4
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "4 items")
    }

    func testFocusChipUsesTheModeNameOrAFallback() throws {
        var context = HubContext()
        context.focusActive = true
        context.focusName = "Work"
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "Work")
        context.focusName = "  "
        XCTAssertEqual(HubChipPlanner.chips(for: context).first?.text, "Focus")
    }

    func testPausedMusicChipNeedsATitle() {
        var context = HubContext()
        context.musicIsPaused = true
        XCTAssertTrue(HubChipPlanner.chips(for: context).isEmpty)
        context.musicTitle = "Heroes"
        let chip = HubChipPlanner.chips(for: context).first
        XCTAssertEqual(chip?.kind, .music)
        XCTAssertEqual(chip?.text, "Heroes")
    }

    // MARK: Chips - ordering, hiding, limit

    private var busy: HubContext {
        var context = HubContext()
        context.batteryLevel = 50
        context.isCharging = true
        context.isPluggedIn = true
        context.timerPhase = .running
        context.timerRemainingSeconds = 90
        context.stopwatchPhase = .running
        context.stashEnabled = true
        context.stashCount = 2
        context.focusActive = true
        context.focusName = "Work"
        context.musicIsPaused = true
        context.musicTitle = "Heroes"
        return context
    }

    func testChipsComeOutMostImportantFirst() {
        let kinds = HubChipPlanner.chips(for: busy, limit: 10).map(\.kind)
        XCTAssertEqual(kinds, [.timer, .stopwatch, .focus, .battery, .music, .stash])
    }

    func testTheDefaultLimitLeavesTheLeastImportantChipsWaiting() {
        let kinds = HubChipPlanner.chips(for: busy).map(\.kind)
        XCTAssertEqual(kinds, [.timer, .stopwatch, .focus])
        XCTAssertEqual(kinds.count, HubChipPlanner.maxVisibleChips)
    }

    func testHiddenChipsNeverAppearAndFreeTheirPlace() {
        let kinds = HubChipPlanner.chips(for: busy, hidden: [.timer, .focus]).map(\.kind)
        XCTAssertEqual(kinds, [.stopwatch, .battery, .music])
    }

    func testEveryChipCanBeHidden() {
        XCTAssertTrue(HubChipPlanner.chips(for: busy, hidden: Set(HubChip.allCases)).isEmpty)
    }

    func testAZeroLimitShowsNothing() {
        XCTAssertTrue(HubChipPlanner.chips(for: busy, limit: 0).isEmpty)
    }

    func testPriorityListCoversEveryChipExactlyOnce() {
        XCTAssertEqual(Set(HubChip.priority), Set(HubChip.allCases))
        XCTAssertEqual(HubChip.priority.count, HubChip.allCases.count)
    }

    // MARK: Parallax

    func testNormalizedOffsetSpansMinusOneToOne() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(HubParallax.normalizedOffset(location: CGPoint(x: 100, y: 50), in: size), .zero)
        XCTAssertEqual(HubParallax.normalizedOffset(location: CGPoint(x: 0, y: 0), in: size), CGPoint(x: -1, y: -1))
        XCTAssertEqual(HubParallax.normalizedOffset(location: CGPoint(x: 200, y: 100), in: size), CGPoint(x: 1, y: 1))
    }

    func testNormalizedOffsetIsClampedAndSafeOnAnEmptySize() {
        XCTAssertEqual(
            HubParallax.normalizedOffset(location: CGPoint(x: 900, y: -900), in: CGSize(width: 200, height: 100)),
            CGPoint(x: 1, y: -1)
        )
        XCTAssertEqual(HubParallax.normalizedOffset(location: CGPoint(x: 5, y: 5), in: .zero), .zero)
    }

    func testTiltIsZeroAtTheCentreAndBoundedAtTheEdges() {
        let rest = HubParallax.tilt(for: .zero)
        XCTAssertEqual(rest.x, 0)
        XCTAssertEqual(rest.y, 0)

        let corner = HubParallax.tilt(for: CGPoint(x: 1, y: 1))
        XCTAssertEqual(corner.y, HubParallax.maximumTilt)
        XCTAssertEqual(corner.x, -HubParallax.maximumTilt)
    }

    // MARK: Home layout

    func testHubAndPlayerFitTheDefaultMinimumNotchWidth() {
        let needed = HomeLayoutBudget.requiredNotchWidth(hubVisible: true, playerVisible: true, mirrorVisible: false)
        XCTAssertLessThanOrEqual(needed, recommendedMinimumNotchWidth(forTabCount: 2))
    }

    func testMirrorBesideThePlayerAndHubNeedsAWiderNotch() {
        let without = HomeLayoutBudget.requiredNotchWidth(hubVisible: true, playerVisible: true, mirrorVisible: false)
        let with = HomeLayoutBudget.requiredNotchWidth(hubVisible: true, playerVisible: true, mirrorVisible: true)
        XCTAssertEqual(with - without, HomeLayoutBudget.minimumMirrorWidth + HomeLayoutBudget.columnSpacing)
    }

    func testNoHubMeansNoExtraWidth() {
        XCTAssertEqual(HomeLayoutBudget.requiredNotchWidth(hubVisible: false, playerVisible: true, mirrorVisible: true), 0)
    }

    func testHubAloneNeedsOnlyItsOwnWidthAndInsets() {
        let needed = HomeLayoutBudget.requiredNotchWidth(hubVisible: true, playerVisible: false, mirrorVisible: false)
        XCTAssertEqual(needed, HomeLayoutBudget.hubWidth + HomeLayoutBudget.combinedInset)
    }
}
