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

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
private typealias ReminderFont = NSFont
#elseif canImport(UIKit)
import UIKit
private typealias ReminderFont = UIFont
#endif

struct ReminderLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = ReminderLiveActivityManager.shared

    @Default(.reminderPresentationStyle) private var presentationStyle

    @State private var isHovering = false

    private let ringStrokeWidth: CGFloat = 3
    /// Breathing room between a wing's content and its outer edge.
    private let outerInset: CGFloat = 2

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight)
    }

    var body: some View {
        if let reminder = manager.activeReminder {
            content(for: reminder, now: manager.currentDate)
        }
    }

    /// Icon on one side, countdown on the other. The wings are the same width
    /// -- whichever of the two is wider -- with the notch-sized gap dead centre,
    /// so neither is ever drawn behind the cut-out.
    @ViewBuilder
    private func content(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: iconDiameter + outerInset,
            rightContent: rightContentWidth(for: reminder, now: now) + outerInset,
            isHovering: isHovering
        )

        NotchWings(layout: layout, height: notchContentHeight + (isHovering ? 8 : 0)) {
            iconSection(for: reminder, now: now)
                .padding(.leading, outerInset)
        } right: {
            rightSection(for: reminder, now: now)
                .padding(.trailing, outerInset)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) {
                isHovering = hovering
            }
        }
    }

    private func iconSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        let diameter = iconDiameter
        let accent = accentColor(for: reminder, now: now)

        let critical = isCritical(for: reminder, now: now)

        return Image(systemName: iconName(for: reminder, now: now))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(accent)
            .contentTransition(.symbolEffect(.replace))
            // Turning critical (inside the sneak-peek window) gives the bell a nudge.
            .symbolEffect(.bounce, options: .nonRepeating, value: NotchlyTheme.Motion.reduceMotion ? false : critical)
            .animation(NotchlyTheme.Motion.spring, value: critical)
            .frame(width: diameter, height: diameter)
            .frame(width: iconDiameter, height: notchContentHeight, alignment: .center)
    }

    @ViewBuilder
    private func rightSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> some View {
        let accent = accentColor(for: reminder, now: now)
        switch presentationStyle {
        case .ringCountdown:
            ringCountdownSection(for: reminder, now: now, accent: accent)
        case .digital:
            digitalSection(for: reminder, now: now, accent: accent)
        case .minutes:
            minutesSection(for: reminder, now: now, accent: accent)
        }
    }

    private func ringCountdownSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        let progressValue = progress(for: reminder, now: now)
        let diameter = ringDiameter

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(accent, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progressValue)
        }
        .frame(width: diameter, height: diameter)
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func digitalSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        let countdown = digitalCountdown(for: reminder, now: now)
        return Text(countdown)
            .font(.system(size: 16, weight: .semibold, design: .monospaced))
            .foregroundColor(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.numericText(countsDown: true))
            .animation(NotchlyTheme.Motion.snappy, value: countdown)
            .frame(height: notchContentHeight, alignment: .center)
    }

    private func minutesSection(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date, accent: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(minutesCountdown(for: reminder, now: now))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: true))
                .animation(NotchlyTheme.Motion.snappy, value: minutesCountdown(for: reminder, now: now))
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func progress(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Double {
        guard reminder.leadTime > 0 else { return 1 }
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let elapsed = reminder.leadTime - remaining
        let ratio = elapsed / reminder.leadTime
        return min(max(ratio, 0), 1)
    }

    private func digitalCountdown(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func minutesCountdown(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(reminder.event.start.timeIntervalSince(now), 0)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    private func accentColor(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Color {
        if isCritical(for: reminder, now: now) {
            return .red
        }
        return NotchlyTheme.Palette.silver
    }

    /// What the countdown side asks for.
    private func rightContentWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        switch presentationStyle {
        case .ringCountdown:
            return ringDiameter
        case .digital:
            return countdownWidth(for: reminder, now: now)
        case .minutes:
            return minutesWidth(for: reminder, now: now)
        }
    }

    private func countdownWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        let text = digitalCountdown(for: reminder, now: now)
        let font = monospacedFont(size: 16, weight: ReminderFont.Weight.semibold)
        // Never narrower than `00:00`, so the digits roll without the wing resizing.
        return max(measureTextWidth(text, font: font), measureTextWidth("00:00", font: font)) + 2
    }

    private func minutesWidth(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> CGFloat {
        let text = minutesCountdown(for: reminder, now: now)
        let width = measureTextWidth(text, font: systemFont(size: 13, weight: ReminderFont.Weight.semibold))
        return width + 2
    }

    private var iconDiameter: CGFloat {
        max(notchContentHeight - 8, 26)
    }

    private var ringDiameter: CGFloat {
        max(min(notchContentHeight - 12, 22), 16)
    }

    private func measureTextWidth(_ text: String, font: ReminderFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return ceil(NSAttributedString(string: text, attributes: attributes).size().width)
    }

    private func systemFont(size: CGFloat, weight: ReminderFont.Weight) -> ReminderFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #else
        return UIFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    private func monospacedFont(size: CGFloat, weight: ReminderFont.Weight) -> ReminderFont {
        #if canImport(AppKit)
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        #endif
    }

    private func iconName(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        isCritical(for: reminder, now: now) ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName
    }

    private func isCritical(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = reminder.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }
}
