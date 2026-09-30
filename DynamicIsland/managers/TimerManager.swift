/*
 * Atoll (DynamicIsland)
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
import AVFoundation
import AppKit

/// The single countdown timer. Started from the Quick Actions row and shown as
/// a closed-notch live activity while it runs.
///
/// Deadline based (see `CountdownClock`): the once-per-tick work is only to
/// notice the deadline and to publish whole-second changes.
@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    /// How long the "Done" state stays on the notch before it dismisses itself.
    static let doneDisplayDuration: TimeInterval = 4

    @Published private(set) var phase: ClockPhase = .idle
    @Published private(set) var totalDuration: TimeInterval = 0
    @Published private(set) var remainingSeconds: Int = 0
    /// 0...1, stepped once per second so the ring animates smoothly between steps.
    @Published private(set) var progress: Double = 0

    private var clock: CountdownClock?
    private var ticker: Timer?
    private var dismissWorkItem: DispatchWorkItem?
    private var soundPlayer: AVAudioPlayer?
    /// Gives each run an identity so the delayed "Done" dismissal of an earlier
    /// run can never cut a newer run short.
    private var lifecycle = TimerLifecycle()

    private init() {}

    var isTimerActive: Bool { phase != .idle }
    var isRunning: Bool { phase == .running }
    var formattedRemaining: String { ClockFormat.digital(seconds: remainingSeconds) }

    // MARK: Controls

    func start(duration: TimeInterval) {
        guard duration >= 1 else { return }
        stopSound()
        cancelDismissal()
        lifecycle.beginSession()

        let now = Date()
        clock = CountdownClock(total: duration, startingAt: now)
        totalDuration = duration
        remainingSeconds = Int(duration.rounded(.up))
        progress = 0
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .running
        }
        startTicking()
    }

    func pause() {
        guard phase == .running, var current = clock else { return }
        current.pause(at: Date())
        clock = current
        stopTicking()
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .paused
        }
    }

    func resume() {
        guard phase == .paused, var current = clock else { return }
        current.resume(at: Date())
        clock = current
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .running
        }
        startTicking()
    }

    func togglePause() {
        if phase == .running {
            pause()
        } else if phase == .paused {
            resume()
        }
    }

    /// Cancels a running or paused timer, or dismisses the "Done" state.
    func cancel() {
        stopTicking()
        stopSound()
        cancelDismissal()
        lifecycle.endSession()
        clock = nil
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .idle
        }
        totalDuration = 0
        remainingSeconds = 0
        progress = 0
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .running, let clock else { return }
        let now = Date()

        if clock.hasFinished(at: now) {
            finish()
            return
        }

        let seconds = clock.remainingSeconds(at: now)
        guard seconds != remainingSeconds else { return }
        remainingSeconds = seconds
        progress = totalDuration > 0 ? 1 - Double(seconds) / totalDuration : 0
    }

    private func finish() {
        stopTicking()
        remainingSeconds = 0
        progress = 1
        lifecycle.completeSession()
        withAnimation(NotchlyTheme.Motion.spring) {
            phase = .finished
        }
        playCompletionSound()
        scheduleDismissal()
    }

    private func scheduleDismissal() {
        guard let sessionID = lifecycle.sessionID else { return }
        cancelDismissal()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.lifecycle.isCurrent(sessionID), self.phase == .finished else { return }
            self.cancel()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.doneDisplayDuration, execute: item)
    }

    private func cancelDismissal() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    // MARK: Sound

    private func playCompletionSound() {
        var soundURL: URL?

        if let customPath = UserDefaults.standard.string(forKey: "customTimerSoundPath"),
           !customPath.isEmpty,
           FileManager.default.fileExists(atPath: customPath) {
            soundURL = URL(fileURLWithPath: customPath)
        }

        if soundURL == nil {
            soundURL = Bundle.main.url(forResource: "timer", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "dynamic", withExtension: "m4a")
        }

        guard let soundURL, let player = try? AVAudioPlayer(contentsOf: soundURL) else {
            NSSound.beep()
            return
        }
        player.numberOfLoops = 0
        player.play()
        soundPlayer = player
    }

    private func stopSound() {
        soundPlayer?.stop()
        soundPlayer = nil
    }
}
