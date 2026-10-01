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

struct DynamicIslandLargeButtons: View {
    var action: () -> Void
    var icon: Image
    var title: String
    var body: some View {
        Button (
            action:action,
            label: {
                NotchlyMenuTile(icon: icon, title: title)
            }).buttonStyle(.notchlyPress)
    }
}

/// Glass tile used by the extras menu buttons.
struct NotchlyMenuTile: View {
    var icon: Image
    var title: String

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            icon.resizable()
                .aspectRatio(contentMode: .fit).frame(width: 20)
            Text(title).font(.body)
        }
        .foregroundStyle(NotchlyTheme.Palette.textPrimary)
        .frame(width: 70, height: 70)
        .glassSurface(
            cornerRadius: NotchlyTheme.Radius.md,
            fill: isHovering ? NotchlyTheme.Palette.glassFillHover : NotchlyTheme.Palette.glassFill
        )
        .contentShape(RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous))
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
    }
}

struct DynamicIslandExtrasMenu : View {
    @ObservedObject var vm: DynamicIslandViewModel
    
    var body: some View {
        VStack{
            HStack(spacing: 20)  {
                hide
                settings
                close
            }
        }
    }
    
    var settings: some View {
        Button(action: {
            SettingsWindowController.shared.showWindow()
        }) {
            NotchlyMenuTile(icon: Image(systemName: "gear"), title: "Settings")
        }
        .buttonStyle(.notchlyPress)
    }
    
    var hide: some View {
        DynamicIslandLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    //vm.openMusic()
                }
            },
            icon: Image(systemName: "arrow.down.forward.and.arrow.up.backward"),
            title: "Hide"
        )
    }
    
    var close: some View {
        DynamicIslandLargeButtons(
            action: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        NSApp.terminate(nil)
                    }
                }
            },
            icon: Image(systemName: "xmark"),
            title: "Exit"
        )
    }
}


#Preview {
    DynamicIslandExtrasMenu(vm: DynamicIslandViewModel())
}
