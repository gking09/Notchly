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
import Combine
import SwiftUI

/// The single stopwatch. Publishes whole seconds for the closed-notch live
/// activity; views that need finer resolution (the Quick Actions panel) read
/// `elapsed(at:)` from a `TimelineView` instead of forcing a fast publish here.
@MainActor
final class StopwatchManager: ObservableObject {
    static let shared = StopwatchManager()

    @Published private(set) var phase: ClockPhase = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    /// Duration of each completed lap, oldest first.
    @Published private(set) var lapSplits: [TimeInterval] = []

    private var clock = StopwatchClock()
    private var ticker: Timer?

    private init() {}

    var isActive: Bool { phase != .idle }
    var isRunning: Bool { phase == .running }

    func elapsed(at now: Date = Date()) -> TimeInterval {
        clock.elapsed(at: now)
    }

    // MARK: Controls

    func start() {
        guard phase != .running else { return }
        clock.start(at: Date())
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .running
        }
        startTicking()
    }

    func pause() {
        guard phase == .running else { return }
        clock.pause(at: Date())
        stopTicking()
        elapsedSeconds = Int(clock.elapsed(at: Date()))
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .paused
        }
    }

    func toggle() {
        if phase == .running {
            pause()
        } else {
            start()
        }
    }

    func lap() {
        guard phase == .running else { return }
        clock.lap(at: Date())
        lapSplits = clock.lapSplits
    }

    func reset() {
        stopTicking()
        clock.reset()
        lapSplits = []
        elapsedSeconds = 0
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .idle
        }
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running else { return }
        let seconds = Int(clock.elapsed(at: Date()))
        if seconds != elapsedSeconds {
            elapsedSeconds = seconds
        }
    }
}
