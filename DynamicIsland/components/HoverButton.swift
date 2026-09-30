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

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .white
    var scale: Image.Scale = .medium
    var pressEffect: PressEffect? = nil
    var contentTransition: ContentTransition = .symbolEffect(.replace)
    var externalTriggerToken: Int? = nil
    var externalTriggerEffect: PressEffect? = nil
    /// When set, the button draws an animated skip glyph instead of `icon`:
    /// the chevrons march in this direction the way Apple's do, and the button
    /// itself stays put.
    var skipDirection: SkipTrackGlyph.Direction? = nil
    /// Marks a toggle as on (shuffle, repeat, lyrics, like): keeps a soft glass
    /// disc behind the glyph so state reads without colour.
    var isActive: Bool = false
    var action: () -> Void
    
    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var skipToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Circle()
                        .fill(glassFill)
                        .overlay {
                            Circle().strokeBorder(
                                NotchlyTheme.Palette.glassStroke,
                                lineWidth: NotchlyTheme.Stroke.hairline
                            )
                            .opacity(showsGlassChrome ? 1 : 0)
                        }
                        .frame(width: size, height: size)
                        .overlay {
                            if let skipDirection {
                                SkipTrackGlyph(
                                    direction: skipDirection,
                                    size: glyphPointSize,
                                    trigger: skipToken
                                )
                                .foregroundStyle(iconColor)
                            } else {
                                let baseImage = Image(systemName: icon)
                                    .foregroundColor(iconColor)
                                    .contentTransition(contentTransition)
                                    .font(scale == .large ? .largeTitle : .body)
                                    // play <-> pause and friends morph rather than swap
                                    .animation(NotchlyTheme.Motion.snappy, value: icon)

                                if case .wiggle = pressEffect {
                                    if #available(macOS 15.0, *) {
                                        baseImage
                                            .symbolEffect(
                                                .wiggle.byLayer,
                                                options: .nonRepeating,
                                                value: wiggleToken
                                            )
                                    } else {
                                        baseImage
                                    }
                                } else {
                                    baseImage
                                }
                            }
                        }
                }
        }
        .buttonStyle(.notchlyPress)
        .offset(x: pressOffset)
        .rotationEffect(.degrees(wiggleAngle))
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    /// Point sizes for the two text styles this button draws at, resolved once
    /// rather than on every body evaluation.
    private static let largeGlyphPointSize = NSFont.preferredFont(forTextStyle: .largeTitle).pointSize
    private static let regularGlyphPointSize = NSFont.preferredFont(forTextStyle: .body).pointSize

    /// Point size the skip glyph is drawn at, matched to the text style the
    /// symbol would otherwise use so it sits like the icon it replaces.
    private var glyphPointSize: CGFloat {
        scale == .large ? HoverButton.largeGlyphPointSize : HoverButton.regularGlyphPointSize
    }

    /// The large (play/pause) button is always a glass disc; smaller ones only
    /// show glass on hover or while toggled on.
    private var showsGlassChrome: Bool {
        scale == .large || isHovering || isActive
    }

    private var glassFill: Color {
        if isHovering { return NotchlyTheme.Palette.glassFillHover }
        if isActive { return NotchlyTheme.Palette.glassFillSelected }
        return scale == .large ? NotchlyTheme.Palette.glassFill : .clear
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        // Fires for taps and for gesture-driven pulses alike, and independently
        // of pressEffect — skip buttons no longer use one.
        if let skipDirection {
            skipToken += 1
            // The chevrons march; the button also gives a small shove the way
            // it is travelling, then springs back.
            if override == nil && pressEffect == nil {
                nudge(by: skipDirection == .forward ? 3 : -3)
                return
            }
        }

        guard let effect = override ?? pressEffect else { return }

        switch effect {
        case .nudge(let amount):
            nudge(by: amount)
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                wiggleAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    wiggleAngle = 0
                }
            }
        }
    }

    private func nudge(by amount: CGFloat) {
        guard !NotchlyTheme.Motion.reduceMotion else { return }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
            pressOffset = amount
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                pressOffset = 0
            }
        }
    }

    enum PressEffect {
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
