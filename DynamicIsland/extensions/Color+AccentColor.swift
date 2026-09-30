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

#if os(macOS)
import SwiftUI
import Defaults

extension Color {
    /// Returns the accent color configured in settings, falling back to the system accent color.
    static var effectiveAccent: Color {
        Defaults[.accentColor]
    }
    
    /// Legible foreground for text drawn on top of `effectiveAccent`
    /// (the default accent is a light silver, so the text has to be dark).
    static var effectiveAccentForeground: Color {
        let ns = NSColor(Defaults[.accentColor]).usingColorSpace(.sRGB) ?? .white
        let luminance = 0.2126 * ns.redComponent + 0.7152 * ns.greenComponent + 0.0722 * ns.blueComponent
        return luminance > 0.6 ? Color.black.opacity(0.88) : Color.white
    }

    /// Returns a subtle background variant of the accent color.
    static var effectiveAccentBackground: Color {
        Defaults[.accentColor].opacity(0.25)
    }
}
#endif
