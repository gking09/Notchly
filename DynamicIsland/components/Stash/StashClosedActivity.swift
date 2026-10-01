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
import SwiftUI

/// The closed-notch confirmation after something is stashed: a tray in the
/// left wing and "+1" (or the new total) in the right. Wings are symmetric, so
/// nothing is ever laid out across the hardware notch.
struct StashClosedActivity: View {
    let notice: StashClosedNotice

    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var isHovering = false

    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    var body: some View {
        let iconSize = max(0, vm.effectiveClosedNotchHeight - 16)
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: iconSize,
            rightContent: NotchWingLayout.textWidth(notice.label, font: Self.labelFont),
            isHovering: isHovering
        )

        NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)) {
            Image(systemName: notice.symbol)
                .font(.system(size: max(10, iconSize * 0.62), weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                .symbolEffect(.bounce, value: notice.id)
                .frame(width: iconSize, height: iconSize)
        } right: {
            Text(notice.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
    }
}
