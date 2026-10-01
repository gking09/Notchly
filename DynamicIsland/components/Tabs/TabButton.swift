/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    /// A count shown beside the icon; hidden at zero.
    var badge: Int = 0
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(minWidth: 30)
            .padding(.horizontal, NotchlyTheme.Spacing.sm)
            .frame(maxHeight: .infinity)
            .contentShape(Capsule())
            .animation(NotchlyTheme.Motion.spring, value: badge)
        }
        .buttonStyle(NotchlyTabButtonStyle(isSelected: selected))
        .help(label)
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true, badge: 3) {
        print("Tapped")
    }
}
