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
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews

    init(label: String, icon: String, view: NotchViews) {
        self.id = "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        return tabsArray
    }
    var body: some View {
        HStack(spacing: NotchlyTheme.Spacing.xs) {
            ForEach(tabs) { tab in
                let isSelected = isSelected(tab)

                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    withAnimation(NotchlyTheme.Motion.spring) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .background {
                    if isSelected {
                        // One glass capsule that glides from tab to tab.
                        Capsule()
                            .fill(NotchlyTheme.Palette.glassFillSelected)
                            .overlay {
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [NotchlyTheme.Palette.glassHighlight, .clear],
                                        startPoint: .top,
                                        endPoint: UnitPoint(x: 0.5, y: 0.65)
                                    )
                                )
                            }
                            .overlay {
                                Capsule().strokeBorder(
                                    NotchlyTheme.Palette.glassStroke,
                                    lineWidth: NotchlyTheme.Stroke.hairline
                                )
                            }
                            .matchedGeometryEffect(id: "notchly.tab.highlight", in: animation)
                    }
                }
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: coordinator.currentView)
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
