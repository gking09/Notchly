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

// MARK: - Pure timekeeping
//
// The timer and stopwatch engines are deadline based: they remember *when*
// something started or ends and derive the value from the wall clock, rather
// than counting ticks. That keeps them correct across display sleep, a busy
// main thread, or a coarse UI refresh rate. Everything here is a value type
// with an explicit `now`, so it is deterministic and unit-testable.

/// Lifecycle shared by the timer and the stopwatch. The stopwatch never
/// reaches `.finished`.
enum ClockPhase: Equatable {
    case idle
    case running
    case paused
    case finished
}

/// A countdown that ends at a fixed deadline while running and freezes its
/// remaining time while paused.
struct CountdownClock: Equatable {
    let total: TimeInterval
    private var endDate: Date?
    private var frozenRemaining: TimeInterval?

    init(total: TimeInterval, startingAt now: Date) {
        self.total = max(0, total)
        self.endDate = now.addingTimeInterval(self.total)
        self.frozenRemaining = nil
    }

    var isRunning: Bool { endDate != nil }
    var isPaused: Bool { endDate == nil && frozenRemaining != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate {
            return max(0, endDate.timeIntervalSince(now))
        }
        return frozenRemaining ?? total
    }

    /// Whole seconds left, rounded up so a 10:00 timer reads 10:00 at the
    /// instant it starts and reaches 0:00 only when it is actually done.
    func remainingSeconds(at now: Date) -> Int {
        Int(remaining(at: now).rounded(.up))
    }

    func hasFinished(at now: Date) -> Bool {
        isRunning && remaining(at: now) <= 0
    }

    /// 0 at the start, 1 when done.
    func progress(at now: Date) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: now) / total))
    }

    mutating func pause(at now: Date) {
        guard isRunning else { return }
        frozenRemaining = remaining(at: now)
        endDate = nil
    }

    mutating func resume(at now: Date) {
        guard let frozenRemaining, endDate == nil else { return }
        endDate = now.addingTimeInterval(frozenRemaining)
        self.frozenRemaining = nil
    }
}

/// Elapsed-time counter with pause, resume and lap splits.
struct StopwatchClock: Equatable {
    private var startDate: Date?
    private var accumulated: TimeInterval = 0
    /// Elapsed time at the moment each lap was taken.
    private var lapMarks: [TimeInterval] = []

    var isRunning: Bool { startDate != nil }

    func elapsed(at now: Date) -> TimeInterval {
        if let startDate {
            return accumulated + max(0, now.timeIntervalSince(startDate))
        }
        return accumulated
    }

    /// Duration of each lap: the gap between consecutive marks.
    var lapSplits: [TimeInterval] {
        var previous: TimeInterval = 0
        return lapMarks.map { mark in
            defer { previous = mark }
            return mark - previous
        }
    }

    mutating func start(at now: Date) {
        guard startDate == nil else { return }
        startDate = now
    }

    mutating func pause(at now: Date) {
        guard startDate != nil else { return }
        accumulated = elapsed(at: now)
        startDate = nil
    }

    mutating func lap(at now: Date) {
        guard isRunning else { return }
        lapMarks.append(elapsed(at: now))
    }

    mutating func reset() {
        startDate = nil
        accumulated = 0
        lapMarks = []
    }
}

// MARK: - Formatting

enum ClockFormat {
    /// `04:32`, or `1:04:32` once an hour is reached.
    static func digital(seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    /// `04:32.7` -- the stopwatch face, with tenths.
    static func stopwatch(_ elapsed: TimeInterval) -> String {
        let clamped = max(0, elapsed)
        let tenths = Int((clamped * 10).rounded(.down)) % 10
        return digital(seconds: Int(clamped)) + "." + String(tenths)
    }
}

// MARK: - Minutes stepper

/// Adaptive step for the timer picker's +/- buttons: single minutes while the
/// value is small, five-minute jumps above that, so 45 minutes is not
/// forty-five clicks. `up` and `down` mirror each other (15 -> 10 -> 9).
enum TimerMinutesStepper {
    static let range: ClosedRange<Int> = 1...180

    static func up(_ minutes: Int) -> Int {
        let next = minutes < 10 ? minutes + 1 : minutes + 5
        return min(range.upperBound, max(range.lowerBound, next))
    }

    static func down(_ minutes: Int) -> Int {
        let next = minutes <= 10 ? minutes - 1 : minutes - 5
        return min(range.upperBound, max(range.lowerBound, next))
    }

    static let presets: [Int] = [1, 5, 10, 15, 25]
}

// MARK: - Closed-notch presentation

/// What the closed notch shows for the running timer / stopwatch. Timer wins
/// when both are active -- it is the one with a deadline.
struct TimerActivityPresentation: Equatable {
    enum Kind: Equatable {
        case timer
        case stopwatch
    }

    var kind: Kind
    var text: String
    /// Timer only: 0...1.
    var progress: Double
    var isPaused: Bool
    var isFinished: Bool

    var symbolName: String {
        kind == .timer ? "timer" : "stopwatch"
    }

    static func resolve(
        timerPhase: ClockPhase,
        timerRemainingSeconds: Int,
        timerProgress: Double,
        stopwatchPhase: ClockPhase,
        stopwatchElapsedSeconds: Int
    ) -> TimerActivityPresentation? {
        switch timerPhase {
        case .running, .paused:
            return TimerActivityPresentation(
                kind: .timer,
                text: ClockFormat.digital(seconds: timerRemainingSeconds),
                progress: timerProgress,
                isPaused: timerPhase == .paused,
                isFinished: false
            )
        case .finished:
            return TimerActivityPresentation(
                kind: .timer,
                text: String(localized: "Done"),
                progress: 1,
                isPaused: false,
                isFinished: true
            )
        case .idle:
            break
        }

        switch stopwatchPhase {
        case .running, .paused:
            return TimerActivityPresentation(
                kind: .stopwatch,
                text: ClockFormat.digital(seconds: stopwatchElapsedSeconds),
                progress: 0,
                isPaused: stopwatchPhase == .paused,
                isFinished: false
            )
        case .idle, .finished:
            return nil
        }
    }
}
