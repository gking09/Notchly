import XCTest
@testable import Notchly

final class StaggerTimingTests: XCTestCase {
    func testFirstElementWaitsOnlyForTheBaseDelay() {
        XCTAssertEqual(StaggerTiming.delay(index: 0, base: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 0, base: 0.06), 0.06, accuracy: 0.0001)
    }

    func testEachPositionAddsOneStep() {
        XCTAssertEqual(StaggerTiming.delay(index: 1, base: 0), 0.04, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 3, base: 0.06), 0.06 + 3 * 0.04, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 2, base: 0, step: 0.1), 0.2, accuracy: 0.0001)
    }

    func testDelayIsCappedSoLongListsDoNotDrag() {
        XCTAssertEqual(StaggerTiming.delay(index: 500, base: 0.06), StaggerTiming.maximumDelay, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 10, base: 0, step: 0.1, maximum: 0.25), 0.25, accuracy: 0.0001)
    }

    func testNegativeAndNonFiniteInputsNeverProduceANegativeOrInfiniteDelay() {
        XCTAssertEqual(StaggerTiming.delay(index: -4, base: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 2, base: -1, step: -1), 0, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 2, base: .infinity), 0, accuracy: 0.0001)
        XCTAssertEqual(StaggerTiming.delay(index: 2, base: .nan), 0, accuracy: 0.0001)
    }

    func testDelaysNeverDecreaseWithIndex() {
        var last = -1.0
        for index in 0..<20 {
            let delay = StaggerTiming.delay(index: index, base: 0.06)
            XCTAssertGreaterThanOrEqual(delay, last)
            last = delay
        }
    }
}

final class TabSwitchMotionTests: XCTestCase {
    func testForwardBringsTheNewTabInFromTheTrailingSide() {
        XCTAssertGreaterThan(TabSwitchMotion.incomingOffset(forward: true), 0)
        XCTAssertLessThan(TabSwitchMotion.incomingOffset(forward: false), 0)
    }

    func testOutgoingTabLeavesTheOppositeWayToTheIncomingOne() {
        for forward in [true, false] {
            XCTAssertEqual(
                TabSwitchMotion.outgoingOffset(forward: forward),
                -TabSwitchMotion.incomingOffset(forward: forward)
            )
        }
    }
}

final class NotchStateClockTests: XCTestCase {
    func testChangesInsideTheWindowCountAsRecent() {
        let now = Date()
        XCTAssertTrue(NotchStateClock.isRecent(now: now, lastChange: now.addingTimeInterval(-0.1)))
        XCTAssertTrue(NotchStateClock.isRecent(now: now, lastChange: now))
    }

    func testOldChangesAndTheFutureDoNotCount() {
        let now = Date()
        XCTAssertFalse(NotchStateClock.isRecent(now: now, lastChange: now.addingTimeInterval(-NotchStateClock.window - 0.01)))
        XCTAssertFalse(NotchStateClock.isRecent(now: now, lastChange: now.addingTimeInterval(5)))
        XCTAssertFalse(NotchStateClock.isRecent(now: now, lastChange: .distantPast))
    }
}

final class ActivityArrivalLayoutTests: XCTestCase {
    private let notch: CGFloat = 185

    func testArrivalHasNoWingsAndStartsAtTheIdleNotchWidth() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 40, rightContent: 120, innerClearance: 4)
        let arrival = layout.arrival
        XCTAssertEqual(arrival.leftWing, 0)
        XCTAssertEqual(arrival.rightWing, 0)
        XCTAssertEqual(arrival.innerClearance, 0)
        // Matches the idle closed content (`closedNotchSize.width - 20`).
        XCTAssertEqual(arrival.centerGap, notch - NotchWingLayout.idleContentInset)
        XCTAssertEqual(arrival.notchWidth, notch)
    }

    func testArrivalNeverGoesNegativeOnATinyNotch() {
        let layout = NotchWingLayout.make(notchWidth: 10, leftContent: 5, rightContent: 5)
        XCTAssertEqual(layout.arrival.centerGap, 0)
    }

    func testArrivalIsSymmetricAndSmallerThanTheRealLayout() {
        let layout = NotchWingLayout.make(notchWidth: notch, leftContent: 30, rightContent: 30)
        XCTAssertEqual(layout.arrival.leftWing, layout.arrival.rightWing)
        XCTAssertLessThan(layout.arrival.totalWidth, layout.totalWidth)
    }
}

final class TimerWingMetricsTests: XCTestCase {
    private let notch: CGFloat = 185

    private func presentation(_ kind: TimerActivityPresentation.Kind, text: String, finished: Bool = false) -> TimerActivityPresentation {
        TimerActivityPresentation(kind: kind, text: text, progress: 0.5, isPaused: false, isFinished: finished)
    }

    func testTimerWingsAreSymmetricAroundTheNotch() {
        for text in ["00:05", "12:34", "1:02:03", "Done"] {
            let p = presentation(.timer, text: text)
            let layout = NotchWingLayout.make(
                notchWidth: notch,
                leftContent: TimerActivityMetrics.leftContentWidth(for: p, notchHeight: 26),
                rightContent: TimerActivityMetrics.rightContentWidth(for: p),
                innerClearance: NotchWingLayout.innerClearance
            )
            XCTAssertEqual(layout.leftWing, layout.rightWing, text)
            XCTAssertEqual(layout.centerGap, notch, text)
        }
    }

    func testTimeTextSetsTheWingBecauseItIsWiderThanTheRing() {
        let p = presentation(.timer, text: "12:34")
        XCTAssertGreaterThan(
            TimerActivityMetrics.rightContentWidth(for: p),
            TimerActivityMetrics.leftContentWidth(for: p, notchHeight: 26)
        )
    }

    func testDoneNeverNarrowsTheTextLane() {
        let digits = TimerActivityMetrics.trailingTextWidth(for: presentation(.timer, text: "00:00"))
        let done = TimerActivityMetrics.trailingTextWidth(for: presentation(.timer, text: "Done", finished: true))
        XCTAssertGreaterThanOrEqual(done, digits)
    }

    func testFinishedStateWidensBothWingsEqually() {
        let running = presentation(.timer, text: "00:05")
        let finished = presentation(.timer, text: "Done", finished: true)
        XCTAssertEqual(
            TimerActivityMetrics.leftContentWidth(for: finished, notchHeight: 26)
                - TimerActivityMetrics.leftContentWidth(for: running, notchHeight: 26),
            TimerActivityMetrics.finishedExpansion
        )
        XCTAssertGreaterThan(
            TimerActivityMetrics.rightContentWidth(for: finished),
            TimerActivityMetrics.rightContentWidth(for: running) - 0.001
        )
    }

    func testStopwatchLeadsWithASmallDotNotARing() {
        let p = presentation(.stopwatch, text: "0:12")
        XCTAssertEqual(TimerActivityMetrics.leadingGlyphWidth(for: p, notchHeight: 26), TimerActivityMetrics.dotSize)
    }
}
