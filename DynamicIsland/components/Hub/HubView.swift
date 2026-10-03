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
import Defaults
import SwiftUI

// MARK: - Hub

/// The centrepiece of the Home tab: a large glass clock card with a slowly
/// breathing glow, which leans toward the pointer, and a row of chips under the
/// time for whatever is relevant right now (a running timer, the battery while
/// it charges, Stash items...). With nothing to report, only the clock shows.
///
/// What is on the chips and how the clock is written are decided by the pure
/// types in `HubLogic.swift`; this file only draws them.
struct HubView: View {
    @State private var pointer: CGPoint = .zero

    var body: some View {
        let reduce = NotchlyTheme.Motion.reduceMotion
        let lean = reduce ? CGPoint.zero : pointer
        let tilt = HubParallax.tilt(for: lean)
        let shape = RoundedRectangle(cornerRadius: NotchlyTheme.Radius.xl, style: .continuous)

        ZStack {
            HubAmbientGlow(pointer: lean)

            VStack(spacing: 0) {
                HubClockFace()
                HubChipRow()
            }
            .padding(.horizontal, 12)
            // The content drifts a little with the pointer too, against the
            // card's own lean, which is what gives it depth.
            .offset(x: lean.x * 3, y: lean.y * 2)
        }
        .frame(width: HomeLayoutBudget.hubWidth, height: HomeLayoutBudget.hubHeight)
        .glassSurface(cornerRadius: NotchlyTheme.Radius.xl)
        .clipShape(shape)
        .contentShape(shape)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                pointer = HubParallax.normalizedOffset(
                    location: location,
                    in: CGSize(width: HomeLayoutBudget.hubWidth, height: HomeLayoutBudget.hubHeight)
                )
            case .ended:
                pointer = .zero
            }
        }
        .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .animation(NotchlyTheme.Motion.spring, value: pointer)
        .staggered(index: 2)
    }
}

// MARK: - Glow

/// A soft white bloom behind the clock that swells and settles every few
/// seconds, and slides a touch away from the pointer. Monochrome, like
/// everything else on the notch. Stands still under Reduce Motion.
private struct HubAmbientGlow: View {
    let pointer: CGPoint
    @ObservedObject private var activity = ActivityMonitor.shared

    /// Seconds for one full breath.
    private let period: Double = 7

    var body: some View {
        let reduce = NotchlyTheme.Motion.reduceMotion
        // A seven-second breath does not need 20 frames a second; thin it out
        // on battery, and stop drawing while the display sleeps.
        let frameInterval = activity.gate.frameInterval(20, minimum: 10)
        TimelineView(.animation(minimumInterval: frameInterval, paused: reduce || activity.gate.isSuspended)) { context in
            let breath = reduce
                ? 0.5
                : 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / period)
            RadialGradient(
                colors: [Color.white.opacity(0.05 + 0.10 * breath), .clear],
                center: UnitPoint(x: 0.5 - pointer.x * 0.14, y: 0.36 - pointer.y * 0.14),
                startRadius: 2,
                endRadius: 118 + 16 * breath
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Clock

private struct HubClockFace: View {
    @Default(.hubShowSeconds) private var showSeconds
    @Default(.hubTimeFormat) private var timeFormat
    @Default(.hubShowDate) private var showDate
    @ObservedObject private var activity = ActivityMonitor.shared

    var body: some View {
        // Ticks on the second, aligned to the wall clock, so the digits turn
        // over exactly when the time does. With seconds hidden and activity
        // reduced, once a minute is enough (the colon then stays lit).
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: tickInterval)) { context in
            face(for: context.date)
        }
    }

    private var tickInterval: TimeInterval {
        HubClockFormatter.tickInterval(showSeconds: showSeconds, reducedActivity: activity.gate.reducedActivity)
    }

    private func face(for date: Date) -> some View {
        let parts = HubClockFormatter.parts(for: date, format: timeFormat, showSeconds: showSeconds)
        let blinks = tickInterval < 60
        let colonLit = !blinks || Int(date.timeIntervalSince1970) % 2 == 0
        let colonOpacity = NotchlyTheme.Motion.reduceMotion ? 0.7 : (colonLit ? 0.9 : 0.35)
        let dateLine = HubClockFormatter.dateLine(for: date)

        return VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                digits(parts.hours, size: 46)
                colon(size: 46, opacity: colonOpacity)
                digits(parts.minutes, size: 46)

                if let seconds = parts.seconds {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        colon(size: 24, opacity: colonOpacity * 0.8)
                        digits(seconds, size: 24, dimmed: true)
                    }
                    .transition(.scale(scale: 0.7, anchor: .leading).combined(with: .opacity))
                }

                if let period = parts.period {
                    Text(period)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                        .padding(.leading, 4)
                        .contentTransition(.opacity)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .animation(NotchlyTheme.Motion.spring, value: showSeconds)

            if showDate {
                Text(dateLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .transition(.opacity.combined(with: .offset(y: 4)))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(NotchlyTheme.Motion.spring, value: showDate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showDate ? "\(parts.spokenText), \(dateLine)" : parts.spokenText)
    }

    /// A numeral that rolls to its next value rather than swapping.
    private func digits(_ text: String, size: CGFloat, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(
                dimmed
                    ? AnyShapeStyle(NotchlyTheme.Palette.textSecondary)
                    : AnyShapeStyle(LinearGradient(
                        colors: [NotchlyTheme.Palette.textPrimary, NotchlyTheme.Palette.silver],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
            )
            .contentTransition(.numericText())
            .animation(NotchlyTheme.Motion.spring, value: text)
    }

    private func colon(size: CGFloat, opacity: Double) -> some View {
        Text(":")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .foregroundStyle(NotchlyTheme.Palette.silver)
            .baselineOffset(size * 0.1)
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.45), value: opacity)
    }
}

// MARK: - Chips

/// The chips under the clock. Reads the live state of everything a chip can
/// speak for, hands it to `HubChipPlanner`, and draws what comes back.
private struct HubChipRow: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var battery = BatteryStatusViewModel.shared
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var stopwatch = StopwatchManager.shared
    @ObservedObject private var focus = DoNotDisturbManager.shared
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var stash = StashManager.shared.store
    @Default(.hubHiddenChips) private var hidden
    @Default(.enableStash) private var stashEnabled

    /// Asked once: a Mac does not gain or lose its battery while the app runs.
    private static let hasBattery = BatteryActivityManager.shared.hasBattery()

    private var context: HubContext {
        var context = HubContext()
        if Self.hasBattery {
            context.batteryLevel = battery.details.level ?? Int(battery.levelBattery.rounded())
            context.isPluggedIn = battery.isPluggedIn
            context.isCharging = battery.isCharging
            context.isLowPowerMode = battery.isInLowPowerMode
            if let time = battery.details.time, !time.isCalculating {
                context.batteryTimeText = time.compactText
            }
        }
        context.timerPhase = timer.phase
        context.timerRemainingSeconds = timer.remainingSeconds
        context.stopwatchPhase = stopwatch.phase
        context.stopwatchElapsedSeconds = stopwatch.elapsedSeconds
        context.stashEnabled = stashEnabled
        context.stashCount = stash.items.count
        context.focusActive = focus.isDoNotDisturbActive
        context.focusName = focus.currentFocusModeName
        context.musicIsPaused = music.hasActiveSession && !music.isPlaying
        context.musicTitle = music.songTitle
        return context
    }

    var body: some View {
        let chips = HubChipPlanner.chips(for: context, hidden: Set(hidden))
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                HubChipView(chip: chip, action: action(for: chip.kind))
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
        }
        .frame(height: chips.isEmpty ? 0 : 26)
        .padding(.top, chips.isEmpty ? 0 : 9)
        // Chips spring in and out as they become relevant; their text changing
        // underneath (a ticking timer) must not.
        .animation(NotchlyTheme.Motion.pop, value: chips.map(\.id))
    }

    /// What tapping a chip does, or `nil` for one that only informs.
    private func action(for kind: HubChip) -> (() -> Void)? {
        switch kind {
        case .timer:
            return {
                if timer.phase == .finished {
                    timer.cancel()
                } else if quickActionsBarVisible() {
                    QuickActionsManager.shared.showPanel(.timer)
                } else {
                    timer.togglePause()
                }
            }
        case .stopwatch:
            return {
                if quickActionsBarVisible() {
                    QuickActionsManager.shared.showPanel(.stopwatch)
                } else {
                    stopwatch.toggle()
                }
            }
        case .stash:
            return {
                withAnimation(NotchlyTheme.Motion.spring) {
                    coordinator.currentView = .stash
                }
            }
        case .music:
            return { music.togglePlay() }
        case .focus, .battery:
            return nil
        }
    }
}

private struct HubChipView: View {
    let chip: HubChipModel
    let action: (() -> Void)?

    private var tint: Color {
        switch chip.tone {
        case .neutral: return NotchlyTheme.Palette.textPrimary.opacity(0.92)
        case .positive: return Color(.sRGB, red: 0.56, green: 0.92, blue: 0.68, opacity: 1)
        case .warning: return Color(.sRGB, red: 1.0, green: 0.80, blue: 0.42, opacity: 1)
        case .critical: return Color(.sRGB, red: 1.0, green: 0.46, blue: 0.44, opacity: 1)
        }
    }

    private static let textFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    /// Longest a chip's text gets before it is cut with an ellipsis.
    private static let maxTextWidth: CGFloat = 84

    /// Sized to the text rather than stretched: a frame with only a maximum
    /// would grow to fill the row.
    private var textWidth: CGFloat {
        min(NotchWingLayout.textWidth(chip.text, font: Self.textFont) + 1, Self.maxTextWidth)
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: chip.symbol)
                .font(.system(size: 10, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: chip.isLive && !NotchlyTheme.Motion.reduceMotion)
            Text(chip.text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: textWidth, alignment: .leading)
                .contentTransition(.numericText())
                .animation(NotchlyTheme.Motion.snappy, value: chip.text)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .contentShape(Capsule())
    }

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(GlassButtonStyle(variant: .capsule, alwaysVisible: true, isActive: chip.isLive))
                .help(chip.kind.title)
        } else {
            label
                .glassSurface(in: Capsule())
                .help(chip.kind.title)
        }
    }
}
