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
import AppKit
import Defaults

struct RecordingLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @Default(.recordingHoverStyle) private var recordingHoverStyle
    @Default(.recordingControlMode) private var recordingControlMode

    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat

    private static let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold)

    var body: some View {
        Group {
            if presentation == .expanded {
                // The tall hover panel: its content sits below the notch row.
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    expandedDetails
                        .frame(width: hudWidth, height: hudHeight)
                }
                .frame(width: hudWidth, height: hudHeight, alignment: .bottom)
                .transition(.opacity)
            } else {
                wings
                    .transition(.opacity)
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: presentation)
        .accessibilityElement(children: .contain)
    }

    /// Record badge on one side, elapsed time (and, on hover, the stop button)
    /// on the other. The wings are the same width with the notch-sized gap
    /// between them; the budget is what the notch's outer frame reserves.
    private var wings: some View {
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: rowHeight + gestureProgress / 2,
            rightContent: trailingContentWidth + gestureProgress / 2,
            isHovering: hoverAnimation,
            widthBudget: hudWidth
        )

        return NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (hoverAnimation ? 8 : 0)) {
            recordingBadge
        } right: {
            trailingStatus
        }
    }

    private var presentation: RecordingHUDPresentation {
        guard !recordingManager.isScreenSharingAppActive else { return .compact }
        guard hoverAnimation, stopControlsEnabled else { return .compact }
        return effectiveRecordingHoverStyle == .default ? .expanded : .inline
    }

    private var stopControlsEnabled: Bool {
        recordingControlMode == .withStopButton && recordingManager.shouldShowStopControlsInHUD
    }

    private var effectiveRecordingHoverStyle: RecordingHoverStyle {
        recordingHoverStyle
    }

    private var hudWidth: CGFloat {
        vm.closedNotchSize.width + presentation.extraWidth
    }

    private var hudHeight: CGFloat {
        vm.effectiveClosedNotchHeight + presentation.extraHeight
    }

    private var rowHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var statusText: String {
        recordingManager.stopFailureMessage == nil ? recordingManager.formattedDuration : String(localized: "Failed")
    }

    private var statusTextWidth: CGFloat {
        // Never narrower than `0:00`, so the digits roll without the wing resizing.
        max(
            NotchWingLayout.textWidth(statusText, font: Self.statusFont),
            NotchWingLayout.textWidth("0:00", font: Self.statusFont)
        ) + 2
    }

    private var inlineStopButtonSize: CGFloat {
        min(max(vm.effectiveClosedNotchHeight - 8, 22), 30)
    }

    /// What the trailing wing asks for: the time, plus the stop button on hover.
    private var trailingContentWidth: CGFloat {
        presentation == .inline ? statusTextWidth + 10 + inlineStopButtonSize : statusTextWidth
    }

    private var recordingStatusText: String {
        recordingManager.stopFailureMessage ?? String(localized: "Recording in progress.")
    }

    @ViewBuilder
    private var recordingBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.15))

            recordingDot(size: 10)
        }
        .frame(width: rowHeight, height: rowHeight)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
                .animation(NotchlyTheme.Motion.snappy, value: statusText)

            if presentation == .inline {
                stopButton(size: inlineStopButtonSize, lineWidth: 1.6)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: presentation)
    }

    private var expandedDetails: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: String(localized: "Screen Recording"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)

                    Text(recordingManager.formattedDuration)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                Text(recordingStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(recordingManager.stopFailureMessage == nil ? .gray.opacity(0.6) : .red.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            stopButton(size: 54, lineWidth: 2.4)
        }
        .padding(.leading, 35)
        .padding(.trailing, 40)
        .padding(.top, 29)
        .padding(.bottom, 20)
    }

    private func recordingDot(size: CGFloat) -> some View {
        Circle()
            .fill(Color.red)
            .frame(width: size, height: size)
            .modifier(PulsingModifier())
    }

    private func stopButton(size: CGFloat, lineWidth: CGFloat) -> some View {
        Button {
            recordingManager.stopActiveRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(recordingManager.isSendingStopRequest ? 0.5 : 0.95), lineWidth: lineWidth)

                RoundedRectangle(cornerRadius: max(3, size * 0.1), style: .continuous)
                    .fill(Color.red)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .scaleEffect(recordingManager.isSendingStopRequest ? 0.84 : 1.0)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!recordingManager.canStopFromHUD)
        .help(String(localized: "Stop recording"))
        .accessibilityLabel(String(localized: "Stop recording"))
    }
}
