import XCTest
@testable import Notchly

final class TimerClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Countdown

    func testCountdownReadsFullDurationAtStartAndFinishesAtDeadline() {
        let clock = CountdownClock(total: 600, startingAt: t0)
        XCTAssertEqual(clock.remainingSeconds(at: t0), 600)
        XCTAssertEqual(clock.progress(at: t0), 0, accuracy: 0.0001)
        XCTAssertFalse(clock.hasFinished(at: t0.addingTimeInterval(599.9)))
        XCTAssertTrue(clock.hasFinished(at: t0.addingTimeInterval(600)))
        XCTAssertEqual(clock.remainingSeconds(at: t0.addingTimeInterval(700)), 0)
        XCTAssertEqual(clock.progress(at: t0.addingTimeInterval(700)), 1, accuracy: 0.0001)
    }

    func testCountdownRoundsRemainingUpSoItHitsZeroOnlyWhenDone() {
        let clock = CountdownClock(total: 10, startingAt: t0)
        XCTAssertEqual(clock.remainingSeconds(at: t0.addingTimeInterval(0.4)), 10)
        XCTAssertEqual(clock.remainingSeconds(at: t0.addingTimeInterval(9.2)), 1)
    }

    func testPauseFreezesRemainingAndResumeMovesTheDeadline() {
        var clock = CountdownClock(total: 60, startingAt: t0)
        clock.pause(at: t0.addingTimeInterval(20))
        XCTAssertTrue(clock.isPaused)
        XCTAssertFalse(clock.isRunning)
        // Wall-clock time passing while paused changes nothing.
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(500)), 40, accuracy: 0.0001)
        XCTAssertFalse(clock.hasFinished(at: t0.addingTimeInterval(500)))

        clock.resume(at: t0.addingTimeInterval(500))
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(510)), 30, accuracy: 0.0001)
        XCTAssertTrue(clock.hasFinished(at: t0.addingTimeInterval(540)))
    }

    func testPausingTwiceOrResumingWhileRunningIsHarmless() {
        var clock = CountdownClock(total: 60, startingAt: t0)
        clock.resume(at: t0.addingTimeInterval(5))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(10)), 50, accuracy: 0.0001)
        clock.pause(at: t0.addingTimeInterval(10))
        clock.pause(at: t0.addingTimeInterval(30))
        XCTAssertEqual(clock.remaining(at: t0.addingTimeInterval(99)), 50, accuracy: 0.0001)
    }

    // MARK: Stopwatch

    func testStopwatchAccumulatesAcrossPauses() {
        var watch = StopwatchClock()
        XCTAssertEqual(watch.elapsed(at: t0), 0)
        watch.start(at: t0)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(5)), 5, accuracy: 0.0001)
        watch.pause(at: t0.addingTimeInterval(5))
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(100)), 5, accuracy: 0.0001)
        watch.start(at: t0.addingTimeInterval(100))
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(103)), 8, accuracy: 0.0001)
    }

    func testStopwatchLapsAreSplitsAndOnlyRecordWhileRunning() {
        var watch = StopwatchClock()
        watch.lap(at: t0) // not running: ignored
        watch.start(at: t0)
        watch.lap(at: t0.addingTimeInterval(4))
        watch.lap(at: t0.addingTimeInterval(10))
        XCTAssertEqual(watch.lapSplits.count, 2)
        XCTAssertEqual(watch.lapSplits[0], 4, accuracy: 0.0001)
        XCTAssertEqual(watch.lapSplits[1], 6, accuracy: 0.0001)
    }

    func testStopwatchResetClearsEverything() {
        var watch = StopwatchClock()
        watch.start(at: t0)
        watch.lap(at: t0.addingTimeInterval(3))
        watch.reset()
        XCTAssertFalse(watch.isRunning)
        XCTAssertEqual(watch.elapsed(at: t0.addingTimeInterval(50)), 0)
        XCTAssertTrue(watch.lapSplits.isEmpty)
    }

    // MARK: Formatting

    func testDigitalFormat() {
        XCTAssertEqual(ClockFormat.digital(seconds: 0), "00:00")
        XCTAssertEqual(ClockFormat.digital(seconds: 272), "04:32")
        XCTAssertEqual(ClockFormat.digital(seconds: 3599), "59:59")
        XCTAssertEqual(ClockFormat.digital(seconds: 3600), "1:00:00")
        XCTAssertEqual(ClockFormat.digital(seconds: 3725), "1:02:05")
        XCTAssertEqual(ClockFormat.digital(seconds: -5), "00:00")
    }

    func testStopwatchFormatShowsTenthsWithoutRounding() {
        XCTAssertEqual(ClockFormat.stopwatch(0), "00:00.0")
        XCTAssertEqual(ClockFormat.stopwatch(61.99), "01:01.9")
        XCTAssertEqual(ClockFormat.stopwatch(3600.5), "1:00:00.5")
    }

    // MARK: Stepper

    func testMinutesStepperUsesSingleMinutesThenFives() {
        XCTAssertEqual(TimerMinutesStepper.up(1), 2)
        XCTAssertEqual(TimerMinutesStepper.up(9), 10)
        XCTAssertEqual(TimerMinutesStepper.up(10), 15)
        XCTAssertEqual(TimerMinutesStepper.down(15), 10)
        XCTAssertEqual(TimerMinutesStepper.down(10), 9)
        XCTAssertEqual(TimerMinutesStepper.down(2), 1)
    }

    func testMinutesStepperClampsToRange() {
        XCTAssertEqual(TimerMinutesStepper.down(1), 1)
        XCTAssertEqual(TimerMinutesStepper.up(180), 180)
        XCTAssertEqual(TimerMinutesStepper.up(178), 180)
    }

    // MARK: Presentation

    func testTimerWinsOverStopwatchWhenBothRun() {
        let presentation = TimerActivityPresentation.resolve(
            timerPhase: .running, timerRemainingSeconds: 65, timerProgress: 0.5,
            stopwatchPhase: .running, stopwatchElapsedSeconds: 12
        )
        XCTAssertEqual(presentation?.kind, .timer)
        XCTAssertEqual(presentation?.text, "01:05")
        XCTAssertEqual(presentation?.progress, 0.5)
    }

    func testStopwatchShowsWhenTimerIsIdle() {
        let presentation = TimerActivityPresentation.resolve(
            timerPhase: .idle, timerRemainingSeconds: 0, timerProgress: 0,
            stopwatchPhase: .paused, stopwatchElapsedSeconds: 75
        )
        XCTAssertEqual(presentation?.kind, .stopwatch)
        XCTAssertEqual(presentation?.text, "01:15")
        XCTAssertEqual(presentation?.isPaused, true)
    }

    func testFinishedTimerShowsDoneAndNothingShowsWhenIdle() {
        let done = TimerActivityPresentation.resolve(
            timerPhase: .finished, timerRemainingSeconds: 0, timerProgress: 1,
            stopwatchPhase: .idle, stopwatchElapsedSeconds: 0
        )
        XCTAssertEqual(done?.isFinished, true)
        XCTAssertEqual(done?.progress, 1)

        XCTAssertNil(TimerActivityPresentation.resolve(
            timerPhase: .idle, timerRemainingSeconds: 0, timerProgress: 0,
            stopwatchPhase: .idle, stopwatchElapsedSeconds: 0
        ))
    }

    // MARK: Lifecycle

    func testStaleDismissalCannotAffectANewRun() {
        var lifecycle = TimerLifecycle()
        let first = lifecycle.beginSession()
        lifecycle.completeSession()
        let second = lifecycle.beginSession()
        XCTAssertFalse(lifecycle.isCurrent(first))
        XCTAssertTrue(lifecycle.isCurrent(second))
        XCTAssertNil(lifecycle.completedSessionID)
    }
}
