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

struct DownloadLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var downloadManager = DownloadManager.shared

    @State private var isHovering: Bool = false

    @Default(.showDownloadSpeed) private var showDownloadSpeed
    @Default(.selectedDownloadIndicatorStyle) private var indicatorStyle

    /// Shown only while there is a rate to show: the figure needs two samples
    /// a second apart, and a finished download has no rate at all.
    private var speedText: String? {
        guard showDownloadSpeed,
              !downloadManager.isDownloadCompleted,
              let speed = downloadManager.downloadSpeed else { return nil }
        return Self.speedFormatter.string(fromByteCount: Int64(speed)) + "/s"
    }

    /// How much room the rate needs beside the indicator (figure plus gap).
    /// A fixed allowance rather than the measured text, so the wings do not
    /// breathe every time the figure gains a digit.
    private static let speedAllowance: CGFloat = 58

    private var speedAllowance: CGFloat { speedText == nil ? 0 : Self.speedAllowance }

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()

    private var tint: Color {
        .accentColor
    }

    private var badgeSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var indicatorWidth: CGFloat {
        if downloadManager.isDownloadCompleted { return 16 }
        return indicatorStyle == .circle ? 16 : 40
    }

    var body: some View {
        // Symmetric wings: the indicator (and speed) side sets both, the gap is the notch.
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: badgeSize,
            rightContent: indicatorWidth + speedAllowance + 6,
            isHovering: isHovering
        )

        NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)) {
            // Download icon capsule
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.14))

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: !downloadManager.isDownloadCompleted && !NotchlyTheme.Motion.reduceMotion)
            }
            .frame(width: badgeSize, height: badgeSize)
        } right: {
            HStack(spacing: 6) {
                if downloadManager.isDownloadCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16, weight: .semibold))
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    if let speedText {
                        Text(speedText)
                            // Monospaced digits so the figure
                            // does not jitter as it changes.
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: Self.speedAllowance - 6, alignment: .trailing)
                            .transition(.opacity)
                    }

                    if indicatorStyle == .circle {
                        SpinningCircleDownloadView()
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    }
                }
            }
            .animation(NotchlyTheme.Motion.spring, value: downloadManager.isDownloadCompleted)
            .animation(NotchlyTheme.Motion.spring, value: speedText != nil)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) {
                isHovering = hovering
            }
        }
    }
}
