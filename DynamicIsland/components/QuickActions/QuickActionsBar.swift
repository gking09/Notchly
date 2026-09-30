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
import Defaults

// MARK: - Transition

private struct MorphBlur: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// Scale + fade + a touch of blur: how panel contents arrive and leave.
    static var notchlyMorph: AnyTransition {
        .modifier(active: MorphBlur(radius: 6), identity: MorphBlur(radius: 0))
            .combined(with: .scale(scale: 0.92))
            .combined(with: .opacity)
    }
}

// MARK: - Bar

/// The Quick Actions row on the Home tab: small glass circles that can each
/// grow into an inline panel (timer picker, stopwatch) in the same strip.
struct QuickActionsBar: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var actions = QuickActionsManager.shared
    @Default(.quickActionsOrder) private var order
    @Default(.quickActionsHidden) private var hidden
    @Default(.quickActionsShortcutName) private var shortcutName
    @Namespace private var morph

    private var visibleActions: [QuickAction] {
        QuickActionsLayout.visibleActions(order: order, hidden: hidden, shortcutName: shortcutName)
    }

    var body: some View {
        ZStack {
            if let message = actions.feedback {
                FeedbackToast(message: message)
                    .transition(.notchlyMorph)
            } else if let panel = actions.openPanel {
                panelView(for: panel)
            } else {
                row
                    .transition(.notchlyMorph)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: QuickActionsMetrics.barHeight)
        .animation(NotchlyTheme.Motion.spring, value: actions.openPanel)
        .animation(NotchlyTheme.Motion.spring, value: actions.feedback)
        .onAppear { actions.refreshSystemState() }
        .onChange(of: vm.notchState) { _, state in
            if state == .closed {
                actions.closePanel()
            }
        }
    }

    // MARK: Row

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(visibleActions) { action in
                QuickActionButton(
                    action: action,
                    isActive: actions.isActive(action),
                    morph: morph
                ) {
                    actions.perform(action) {
                        withAnimation(NotchlyTheme.Motion.spring) {
                            vm.close()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Panels

    @ViewBuilder
    private func panelView(for panel: QuickActionsManager.Panel) -> some View {
        let backgroundID = QuickActionButton.morphID(for: panel == .timer ? .timer : .stopwatch)

        ZStack {
            Group {
                switch panel {
                case .timer:
                    TimerQuickPanel()
                case .stopwatch:
                    StopwatchQuickPanel()
                }
            }
            .transition(.notchlyMorph)
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .frame(height: QuickActionsMetrics.buttonSize + 8)
        .background {
            Capsule()
                .fill(NotchlyTheme.Palette.glassFill)
                .overlay {
                    Capsule().fill(
                        LinearGradient(
                            colors: [NotchlyTheme.Palette.glassHighlight, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.6)
                        )
                    )
                }
                .overlay {
                    Capsule().strokeBorder(
                        NotchlyTheme.Palette.glassStroke,
                        lineWidth: NotchlyTheme.Stroke.hairline
                    )
                }
                .matchedGeometryEffect(id: backgroundID, in: morph, isSource: false)
        }
    }
}

// MARK: - Row button

private struct QuickActionButton: View {
    let action: QuickAction
    let isActive: Bool
    let morph: Namespace.ID
    let onTap: () -> Void

    static func morphID(for action: QuickAction) -> String {
        "notchly.quickaction.\(action.rawValue)"
    }

    private var participatesInMorph: Bool {
        action == .timer || action == .stopwatch
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isActive ? action.activeSymbolName : action.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? Color.black : Color.white.opacity(0.9))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: QuickActionsMetrics.buttonSize, height: QuickActionsMetrics.buttonSize)
                .background {
                    ZStack {
                        if participatesInMorph {
                            // Invisible anchor the panel's glass grows out of.
                            Circle()
                                .fill(Color.white.opacity(0.001))
                                .matchedGeometryEffect(id: Self.morphID(for: action), in: morph, isSource: true)
                        }
                        Circle()
                            .fill(Color.white)
                            .scaleEffect(isActive ? 1 : 0.6)
                            .opacity(isActive ? 1 : 0)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.notchlyGlassCircle)
        .animation(NotchlyTheme.Motion.snappy, value: isActive)
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}

// MARK: - Feedback

private struct FeedbackToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
        .padding(.horizontal, 14)
        .frame(height: QuickActionsMetrics.buttonSize)
        .glassSurface(in: Capsule())
    }
}

// MARK: - Panel controls

/// Round glass icon button used inside the panels.
private struct PanelIconButton: View {
    let symbol: String
    var filled = false
    var isEnabled = true
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Color.white.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .background {
                    if filled {
                        Circle().fill(Color.white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.notchlyGlassCircle)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Capsule text button; `filled` is the white primary variant.
private struct PanelPillButton: View {
    let title: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? Color.black : Color.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background {
                    if filled {
                        Capsule().fill(Color.white)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.notchlyGlass)
    }
}

// MARK: - Timer panel

private struct TimerQuickPanel: View {
    @ObservedObject private var actions = QuickActionsManager.shared
    @ObservedObject private var timer = TimerManager.shared

    var body: some View {
        HStack(spacing: 10) {
            PanelIconButton(symbol: "xmark", help: String(localized: "Close")) {
                actions.closePanel()
            }

            switch timer.phase {
            case .idle:
                picker
            case .running, .paused:
                runningControls
            case .finished:
                finishedControls
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: timer.phase)
    }

    // MARK: Picker

    private var picker: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                PanelIconButton(
                    symbol: "minus",
                    isEnabled: actions.timerMinutes > TimerMinutesStepper.range.lowerBound,
                    help: String(localized: "Shorter")
                ) {
                    withAnimation(NotchlyTheme.Motion.snappy) {
                        actions.timerMinutes = TimerMinutesStepper.down(actions.timerMinutes)
                    }
                }

                Text(ClockFormat.digital(seconds: actions.timerMinutes * 60))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                    .contentTransition(.numericText(value: Double(actions.timerMinutes)))
                    .frame(minWidth: 62)

                PanelIconButton(
                    symbol: "plus",
                    isEnabled: actions.timerMinutes < TimerMinutesStepper.range.upperBound,
                    help: String(localized: "Longer")
                ) {
                    withAnimation(NotchlyTheme.Motion.snappy) {
                        actions.timerMinutes = TimerMinutesStepper.up(actions.timerMinutes)
                    }
                }
            }

            Rectangle()
                .fill(NotchlyTheme.Palette.divider)
                .frame(width: 1, height: 16)

            HStack(spacing: 6) {
                ForEach(TimerMinutesStepper.presets, id: \.self) { minutes in
                    presetChip(minutes)
                }
            }

            Spacer(minLength: 4)

            PanelPillButton(title: String(localized: "Start"), filled: true) {
                timer.start(duration: TimeInterval(actions.timerMinutes * 60))
                actions.closePanel()
            }
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        let selected = actions.timerMinutes == minutes
        return Button {
            withAnimation(NotchlyTheme.Motion.snappy) {
                actions.timerMinutes = minutes
            }
        } label: {
            Text("\(minutes)m")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background {
                    if selected {
                        Capsule().fill(Color.white)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.notchlyGlass)
    }

    // MARK: Running

    private var runningControls: some View {
        HStack(spacing: 10) {
            TimerProgressRing(progress: timer.progress, diameter: 22, lineWidth: 2.5)

            Text(timer.formattedRemaining)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(timer.phase == .paused ? 0.6 : 1))
                .contentTransition(.numericText(countsDown: true))
                .animation(NotchlyTheme.Motion.snappy, value: timer.remainingSeconds)

            Spacer(minLength: 4)

            PanelIconButton(
                symbol: timer.phase == .paused ? "play.fill" : "pause.fill",
                help: timer.phase == .paused ? String(localized: "Resume") : String(localized: "Pause")
            ) {
                timer.togglePause()
            }

            PanelPillButton(title: String(localized: "Cancel")) {
                timer.cancel()
            }
        }
    }

    // MARK: Finished

    private var finishedControls: some View {
        HStack(spacing: 10) {
            TimerProgressRing(progress: 1, diameter: 22, lineWidth: 2.5, isFinished: true)

            Text("Done")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary)

            Spacer(minLength: 4)

            PanelPillButton(title: String(localized: "Dismiss"), filled: true) {
                timer.cancel()
            }
        }
    }
}

// MARK: - Stopwatch panel

private struct StopwatchQuickPanel: View {
    @ObservedObject private var actions = QuickActionsManager.shared
    @ObservedObject private var stopwatch = StopwatchManager.shared

    var body: some View {
        HStack(spacing: 10) {
            PanelIconButton(symbol: "xmark", help: String(localized: "Close")) {
                actions.closePanel()
            }

            TimelineView(.animation(minimumInterval: 0.1, paused: !stopwatch.isRunning)) { context in
                Text(ClockFormat.stopwatch(stopwatch.elapsed(at: context.date)))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(stopwatch.phase == .paused ? 0.6 : 1))
                    .frame(minWidth: 84, alignment: .leading)
            }

            if let lastLap = stopwatch.lapSplits.last {
                Text("Lap \(stopwatch.lapSplits.count)  \(ClockFormat.stopwatch(lastLap))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .transition(.notchlyMorph)
            }

            Spacer(minLength: 4)

            PanelIconButton(
                symbol: "flag.fill",
                isEnabled: stopwatch.phase == .running,
                help: String(localized: "Lap")
            ) {
                withAnimation(NotchlyTheme.Motion.snappy) {
                    stopwatch.lap()
                }
            }

            PanelIconButton(
                symbol: stopwatch.phase == .running ? "pause.fill" : "play.fill",
                filled: true,
                help: stopwatch.phase == .running ? String(localized: "Pause") : String(localized: "Start")
            ) {
                stopwatch.toggle()
            }

            PanelIconButton(
                symbol: "arrow.counterclockwise",
                isEnabled: stopwatch.phase != .idle,
                help: String(localized: "Reset")
            ) {
                stopwatch.reset()
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: stopwatch.lapSplits.count)
    }
}
