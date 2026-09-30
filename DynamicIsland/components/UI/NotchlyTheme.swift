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

// MARK: - Design tokens
//
// Notchly's visual language is "soft glass, monochrome": the notch itself stays
// pure black so it melts into the hardware, and everything drawn on it is white
// or silver at varying opacity. Colour is reserved for things that carry meaning
// (battery state, recording, camera/microphone privacy).

enum NotchlyTheme {

    // MARK: Palette

    enum Palette {
        /// The notch surface. Never anything but black -- it has to blend with the hardware.
        static let notch = Color.black

        // Content
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.62)
        static let textTertiary = Color.white.opacity(0.38)
        /// Slightly cool silver, used where pure white would feel harsh.
        static let silver = Color(.sRGB, red: 0.85, green: 0.86, blue: 0.90, opacity: 1)
        static let silverDim = Color(.sRGB, red: 0.85, green: 0.86, blue: 0.90, opacity: 0.6)

        // Glass
        static let glassFill = Color.white.opacity(0.08)
        static let glassFillHover = Color.white.opacity(0.14)
        static let glassFillPressed = Color.white.opacity(0.19)
        static let glassFillSelected = Color.white.opacity(0.16)
        static let glassStroke = Color.white.opacity(0.14)
        static let glassStrokeStrong = Color.white.opacity(0.2)
        static let glassHighlight = Color.white.opacity(0.12)

        // Tracks / fills
        static let track = Color.white.opacity(0.16)
        static let trackFill = Color.white
        static let divider = Color.white.opacity(0.1)
    }

    // MARK: Geometry

    enum Radius {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
    }

    enum Stroke {
        /// Inner hairline on every glass surface.
        static let hairline: CGFloat = 0.5
    }

    // MARK: Motion

    enum Motion {
        /// Honours System Settings > Accessibility > Display > Reduce motion.
        static var reduceMotion: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }

        /// The one spring every interaction uses.
        static var spring: Animation {
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.35, dampingFraction: 0.8)
        }

        /// A quicker variant for press / hover feedback.
        static var snappy: Animation {
            reduceMotion
                ? .easeOut(duration: 0.1)
                : .spring(response: 0.3, dampingFraction: 0.8)
        }

        static let pressedScale: CGFloat = 0.96
    }
}

// MARK: - Glass surface

/// A translucent white panel that sits on the black notch: a faint white fill,
/// a soft highlight fading down from the top edge, and a 0.5pt inner hairline.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var fill: Color = NotchlyTheme.Palette.glassFill
    var strokeOpacity: Double = 1

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(fill)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [NotchlyTheme.Palette.glassHighlight, .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.6)
                            )
                        )
                    }
                    .overlay {
                        shape.strokeBorder(
                            NotchlyTheme.Palette.glassStroke.opacity(strokeOpacity),
                            lineWidth: NotchlyTheme.Stroke.hairline
                        )
                    }
            }
    }
}

extension View {
    /// Soft-glass panel with continuous rounded corners.
    func glassSurface(
        cornerRadius: CGFloat = NotchlyTheme.Radius.md,
        fill: Color = NotchlyTheme.Palette.glassFill
    ) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), fill: fill))
    }

    /// Soft-glass panel in an arbitrary shape (Capsule, Circle, ...).
    func glassSurface<S: InsettableShape>(in shape: S, fill: Color = NotchlyTheme.Palette.glassFill) -> some View {
        modifier(GlassSurface(shape: shape, fill: fill))
    }
}

// MARK: - Button styles

/// Capsule (or circle) glass button. Brightens on hover, dips to 0.96 on press.
struct GlassButtonStyle: ButtonStyle {
    enum Variant {
        case capsule
        case circle
    }

    var variant: Variant = .capsule
    /// Draws the glass even at rest. When false the glass only appears on hover.
    var alwaysVisible: Bool = true
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(
            configuration: configuration,
            variant: variant,
            alwaysVisible: alwaysVisible,
            isActive: isActive
        )
    }

    private struct GlassButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let alwaysVisible: Bool
        let isActive: Bool

        @State private var isHovering = false

        private var fill: Color {
            if configuration.isPressed { return NotchlyTheme.Palette.glassFillPressed }
            if isHovering { return NotchlyTheme.Palette.glassFillHover }
            if isActive { return NotchlyTheme.Palette.glassFillSelected }
            return alwaysVisible ? NotchlyTheme.Palette.glassFill : .clear
        }

        private var showsStroke: Bool {
            alwaysVisible || isHovering || isActive || configuration.isPressed
        }

        var body: some View {
            Group {
                switch variant {
                case .capsule:
                    configuration.label
                        .background { glass(in: Capsule()) }
                case .circle:
                    configuration.label
                        .background { glass(in: Circle()) }
                }
            }
            .scaleEffect(configuration.isPressed ? NotchlyTheme.Motion.pressedScale : 1)
            .animation(NotchlyTheme.Motion.snappy, value: configuration.isPressed)
            .animation(NotchlyTheme.Motion.snappy, value: isHovering)
            .onHover { isHovering = $0 }
        }

        @ViewBuilder
        private func glass<S: InsettableShape>(in shape: S) -> some View {
            shape
                .fill(fill)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [NotchlyTheme.Palette.glassHighlight, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.6)
                        )
                    )
                    .opacity(showsStroke ? 1 : 0)
                }
                .overlay {
                    shape.strokeBorder(
                        NotchlyTheme.Palette.glassStroke,
                        lineWidth: NotchlyTheme.Stroke.hairline
                    )
                    .opacity(showsStroke ? 1 : 0)
                }
        }
    }
}

/// Tab button: dimmed white at rest, full white when selected, gentle press scale.
/// The selected glass capsule itself is drawn by the tab row (see `TabSelectionView`)
/// so it can slide between tabs with `matchedGeometryEffect`.
struct NotchlyTabButtonStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        TabBody(configuration: configuration, isSelected: isSelected)
    }

    private struct TabBody: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovering = false

        private var foreground: Color {
            if isSelected { return NotchlyTheme.Palette.textPrimary }
            return isHovering ? Color.white.opacity(0.78) : Color.white.opacity(0.46)
        }

        var body: some View {
            configuration.label
                .foregroundStyle(foreground)
                .scaleEffect(configuration.isPressed ? NotchlyTheme.Motion.pressedScale : 1)
                .animation(NotchlyTheme.Motion.snappy, value: configuration.isPressed)
                .animation(NotchlyTheme.Motion.snappy, value: isHovering)
                .animation(NotchlyTheme.Motion.snappy, value: isSelected)
                .onHover { isHovering = $0 }
        }
    }
}

/// Invisible-chrome button that only gives the gentle 0.96 press dip. For icon
/// buttons that already draw their own background.
struct NotchlyPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? NotchlyTheme.Motion.pressedScale : 1)
            .animation(NotchlyTheme.Motion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static var notchlyGlass: GlassButtonStyle { GlassButtonStyle() }
    static var notchlyGlassCircle: GlassButtonStyle { GlassButtonStyle(variant: .circle) }
    /// Glass that only appears on hover, for transport buttons that sit flat at rest.
    static var notchlyGlassOnHover: GlassButtonStyle {
        GlassButtonStyle(variant: .circle, alwaysVisible: false)
    }
}

extension ButtonStyle where Self == NotchlyPressButtonStyle {
    static var notchlyPress: NotchlyPressButtonStyle { NotchlyPressButtonStyle() }
}

// MARK: - Progress bar

/// Slim rounded white capsule progress bar.
struct NotchlyProgressBar: View {
    var progress: Double
    var height: CGFloat = 4
    var fill: Color = NotchlyTheme.Palette.trackFill
    var track: Color = NotchlyTheme.Palette.track

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(progress.isFinite ? progress : 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(height, geo.size.width * clamped))
                    .opacity(clamped > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
    }
}
