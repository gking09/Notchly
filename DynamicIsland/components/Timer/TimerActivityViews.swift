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

import SwiftUI
import AppKit

// MARK: - Shared pieces

/// Thin white progress ring. Fills over the timer's run, then swaps to a
/// checkmark when the timer is done.
struct TimerProgressRing: View {
    var progress: Double
    var diameter: CGFloat
    var lineWidth: CGFloat = 3
    var isFinished = false
    var isDimmed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(NotchlyTheme.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.white, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // One step per second, so a one-second linear tween reads as
                // continuous motion.
                .animation(progress == 0 ? nil : .linear(duration: 1), value: progress)

            if isFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(Color.white)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(isDimmed ? 0.55 : 1)
        .animation(NotchlyTheme.Motion.spring, value: isFinished)
    }
}

/// Sizing shared by the standalone live activity and the music pairing.
enum TimerActivityMetrics {
    /// Outer padding on each wing, and the gap to the hardware notch.
    static let sideInset: CGFloat = 12
    static let notchGap: CGFloat = 8
    /// Extra width each wing gains while the "Done" state is showing.
    static let finishedExpansion: CGFloat = 14
    static let dotSize: CGFloat = 8

    static func ringDiameter(notchHeight: CGFloat) -> CGFloat {
        max(16, min(notchHeight - 2, 24))
    }

    private static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)

    static func textWidth(_ text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// Text lane width: never narrower than `00:00`, so "Done" and the digits
    /// swap without the wing resizing.
    static func trailingTextWidth(for presentation: TimerActivityPresentation) -> CGFloat {
        max(textWidth(presentation.text), textWidth("00:00")) + 2
    }

    static func leadingGlyphWidth(for presentation: TimerActivityPresentation, notchHeight: CGFloat) -> CGFloat {
        presentation.kind == .timer ? ringDiameter(notchHeight: notchHeight) : dotSize
    }

    static func leftWingWidth(for presentation: TimerActivityPresentation, notchHeight: CGFloat) -> CGFloat {
        leadingGlyphWidth(for: presentation, notchHeight: notchHeight)
            + sideInset + notchGap
            + (presentation.isFinished ? finishedExpansion : 0)
    }

    static func rightWingWidth(for presentation: TimerActivityPresentation) -> CGFloat {
        trailingTextWidth(for: presentation)
            + sideInset + notchGap
            + (presentation.isFinished ? finishedExpansion : 0)
    }

    /// Width of the trailing lane when it sits beside album art (music pairing).
    static func pairedRightWingWidth(
        for presentation: TimerActivityPresentation,
        notchHeight: CGFloat,
        baseWidth: CGFloat
    ) -> CGFloat {
        let glyph = leadingGlyphWidth(for: presentation, notchHeight: notchHeight)
        return max(baseWidth, glyph + 8 + trailingTextWidth(for: presentation) + 18)
    }

    @MainActor
    static func resolve(timer: TimerManager, stopwatch: StopwatchManager) -> TimerActivityPresentation? {
        TimerActivityPresentation.resolve(
            timerPhase: timer.phase,
            timerRemainingSeconds: timer.remainingSeconds,
            timerProgress: timer.progress,
            stopwatchPhase: stopwatch.phase,
            stopwatchElapsedSeconds: stopwatch.elapsedSeconds
        )
    }
}

// MARK: - Closed-notch live activity

/// Timer / stopwatch on the closed notch. Content sits in the wings either
/// side of the hardware cutout: the leading wing carries the progress ring
/// (timer) or a pulsing dot (stopwatch), the trailing wing the time. The
/// middle lane is black and exactly as wide as the physical notch, so nothing
/// is ever drawn behind it.
struct TimerActivityLiveActivity: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var stopwatch = StopwatchManager.shared
    @State private var isHovering = false
    @State private var bump = false

    private var presentation: TimerActivityPresentation? {
        TimerActivityMetrics.resolve(timer: timer, stopwatch: stopwatch)
    }

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var adjustedNotchHeight: CGFloat {
        vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
    }

    private var middleWidth: CGFloat {
        vm.closedNotchSize.width + (isHovering ? 8 : 0)
    }

    var body: some View {
        if let presentation {
            HStack(spacing: 0) {
                leadingWing(presentation)
                Rectangle()
                    .fill(.black)
                    .frame(width: middleWidth, height: notchContentHeight)
                trailingWing(presentation)
            }
            .frame(height: adjustedNotchHeight, alignment: .center)
            .contentShape(Rectangle())
            .scaleEffect(bump ? 1.06 : 1)
            .animation(NotchlyTheme.Motion.spring, value: presentation.isFinished)
            .onHover { hovering in
                withAnimation(NotchlyTheme.Motion.snappy) {
                    isHovering = hovering
                }
            }
            .onChange(of: presentation.isFinished) { _, finished in
                guard finished else { return }
                // A short overshoot as the wings widen for "Done".
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    bump = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(320))
                    withAnimation(NotchlyTheme.Motion.spring) {
                        bump = false
                    }
                }
            }
        }
    }

    // MARK: Wings

    private func leadingWing(_ presentation: TimerActivityPresentation) -> some View {
        Color.clear
            .frame(
                width: TimerActivityMetrics.leftWingWidth(for: presentation, notchHeight: notchContentHeight),
                height: notchContentHeight
            )
            .background(alignment: .leading) {
                leadingGlyph(presentation)
                    .padding(.leading, TimerActivityMetrics.sideInset)
                    .frame(maxHeight: .infinity)
            }
    }

    @ViewBuilder
    private func leadingGlyph(_ presentation: TimerActivityPresentation) -> some View {
        switch presentation.kind {
        case .timer:
            TimerProgressRing(
                progress: presentation.progress,
                diameter: TimerActivityMetrics.ringDiameter(notchHeight: notchContentHeight),
                lineWidth: 2.5,
                isFinished: presentation.isFinished,
                isDimmed: presentation.isPaused
            )
        case .stopwatch:
            StopwatchDot(isRunning: !presentation.isPaused)
        }
    }

    private func trailingWing(_ presentation: TimerActivityPresentation) -> some View {
        Color.clear
            .frame(
                width: TimerActivityMetrics.rightWingWidth(for: presentation),
                height: notchContentHeight
            )
            .background(alignment: .trailing) {
                ClosedTimerText(presentation: presentation)
                    .frame(width: TimerActivityMetrics.trailingTextWidth(for: presentation), alignment: .trailing)
                    .padding(.trailing, TimerActivityMetrics.sideInset)
                    .frame(maxHeight: .infinity)
            }
    }
}

/// The time read-out. Monospaced digits that roll with `numericText`.
struct ClosedTimerText: View {
    let presentation: TimerActivityPresentation

    var body: some View {
        Text(presentation.text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(presentation.isPaused ? 0.6 : 1))
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText(countsDown: presentation.kind == .timer))
            .animation(NotchlyTheme.Motion.snappy, value: presentation.text)
    }
}

/// White dot that pulses while the stopwatch runs and rests dim while paused.
struct StopwatchDot: View {
    let isRunning: Bool

    var body: some View {
        Group {
            if isRunning {
                Circle()
                    .fill(Color.white)
                    .modifier(PulsingModifier())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.45))
            }
        }
        .frame(width: TimerActivityMetrics.dotSize, height: TimerActivityMetrics.dotSize)
        .animation(NotchlyTheme.Motion.snappy, value: isRunning)
    }
}

/// Trailing lane for the music pairing: the same glyph + time, compact, beside
/// the album art instead of in a wing of its own.
struct MusicTimerSupplementView: View {
    let presentation: TimerActivityPresentation
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            switch presentation.kind {
            case .timer:
                TimerProgressRing(
                    progress: presentation.progress,
                    diameter: TimerActivityMetrics.ringDiameter(notchHeight: notchHeight),
                    lineWidth: 2.5,
                    isFinished: presentation.isFinished,
                    isDimmed: presentation.isPaused
                )
            case .stopwatch:
                StopwatchDot(isRunning: !presentation.isPaused)
            }
            ClosedTimerText(presentation: presentation)
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}
