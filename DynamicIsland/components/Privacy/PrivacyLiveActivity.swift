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

struct PrivacyLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @State private var isHovering: Bool = false

    private static let iconWidth: CGFloat = 24
    private static let iconSpacing: CGFloat = 4

    // Calculate if both camera and mic are active
    private var bothIndicatorsActive: Bool {
        privacyManager.indicatorLayout.showsCameraIndicator &&
        privacyManager.indicatorLayout.showsMicrophoneIndicator
    }

    /// Icons shown in the trailing wing, in order.
    ///
    /// - recording and both active: microphone and camera (the badge takes the left)
    /// - both active, no recording: camera only (the microphone takes the left)
    /// - otherwise: whichever of the two is active
    private var trailingIcons: [PrivacyIndicatorType] {
        if bothIndicatorsActive && recordingManager.isRecording {
            return [.microphone, .camera]
        } else if bothIndicatorsActive {
            return [.camera]
        }
        var icons: [PrivacyIndicatorType] = []
        if privacyManager.indicatorLayout.showsMicrophoneIndicator { icons.append(.microphone) }
        if privacyManager.indicatorLayout.showsCameraIndicator { icons.append(.camera) }
        return icons
    }

    private var rowHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var leadingContentWidth: CGFloat {
        if recordingManager.isRecording { return rowHeight }
        return bothIndicatorsActive ? Self.iconWidth : 0
    }

    private var trailingContentWidth: CGFloat {
        let count = CGFloat(trailingIcons.count)
        guard count > 0 else { return 0 }
        return count * Self.iconWidth + (count - 1) * Self.iconSpacing
    }

    var body: some View {
        // Wings are symmetric: the busier side sets both, the gap is the notch.
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: leadingContentWidth,
            rightContent: trailingContentWidth,
            isHovering: isHovering
        )

        NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)) {
            HStack {
                if recordingManager.isRecording {
                    // Recording pulsator
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.15))

                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .modifier(PulsingModifier())
                    }
                    .frame(width: rowHeight, height: rowHeight)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if bothIndicatorsActive {
                    // Microphone on the left when both are active and nothing is recording
                    PrivacyIcon(type: .microphone)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(NotchlyTheme.Motion.spring, value: recordingManager.isRecording)
            .animation(NotchlyTheme.Motion.spring, value: bothIndicatorsActive)
        } right: {
            HStack(spacing: Self.iconSpacing) {
                ForEach(trailingIcons, id: \.self) { type in
                    PrivacyIcon(type: type)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(NotchlyTheme.Motion.spring, value: trailingIcons)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) {
                isHovering = hovering
            }
        }
    }
}

// Individual privacy icon component
struct PrivacyIcon: View {
    let type: PrivacyIndicatorType

    // Color based on type: camera = #26CC41, mic = #FF9402
    private var iconColor: Color {
        type == .camera ? Color(red: 0.152, green: 0.804, blue: 0.256) : Color(red: 1.000, green: 0.584, blue: 0.010)
    }
    
    @State private var appeared = false

    var body: some View {
        // Simple icon without blur/glow effects
        Image(systemName: type.icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(iconColor)
            .frame(width: 24, height: 24)
            // A single bounce as the indicator lights up.
            .symbolEffect(.bounce, options: .nonRepeating, value: NotchlyTheme.Motion.reduceMotion ? false : appeared)
            .task {
                try? await Task.sleep(for: .milliseconds(280))
                appeared = true
            }
    }
}
