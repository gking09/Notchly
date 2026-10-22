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

/// The closed-notch alert for a new Foundry warning: the Foundry glyph (with a
/// small severity dot) in the left wing, a short title or the count on the right.
/// Wings are symmetric, so nothing is ever laid out across the hardware notch.
struct FoundryClosedActivity: View {
    let alert: FoundryAlert

    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var isHovering = false

    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    var body: some View {
        let iconSize = max(0, vm.effectiveClosedNotchHeight - 16)
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: vm.screen,
            leftContent: iconSize,
            rightContent: NotchWingLayout.textWidth(alert.label, font: Self.labelFont),
            isHovering: isHovering
        )

        NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)) {
            FoundryAlertGlyph(severity: alert.severity, size: iconSize)
        } right: {
            FoundryAlertLabel(text: alert.label)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Foundry: \(alert.projectName.map { "\($0), " } ?? "")\(alert.title)"))
    }
}

/// The left wing's content. Shared with the render test.
struct FoundryAlertGlyph: View {
    let severity: FoundrySeverity
    let size: CGFloat

    var body: some View {
        Image(systemName: "square.stack.3d.up.fill")
            .font(.system(size: max(10, size * 0.62), weight: .semibold))
            .foregroundStyle(NotchlyTheme.Palette.textPrimary)
            .symbolEffect(.bounce, value: severity)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                // A hint of colour, small enough to stay subtle on the black notch.
                Circle()
                    .fill(FoundryPalette.color(for: severity))
                    .frame(width: 5.5, height: 5.5)
                    .overlay { Circle().strokeBorder(Color.black, lineWidth: 1) }
                    .offset(x: 1, y: 1)
            }
    }
}

struct FoundryAlertLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(NotchlyTheme.Palette.textPrimary)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}
