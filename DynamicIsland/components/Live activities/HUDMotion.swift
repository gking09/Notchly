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

import SwiftUI

// MARK: - Pure logic

/// Which end of its range a HUD value is sitting on.
enum HUDEdge: Equatable {
    case minimum
    case maximum
}

/// Decisions behind the volume / brightness / backlight HUD animations, kept
/// free of SwiftUI so they can be tested.
enum HUDMotion {
    /// Values this close to 0 or 1 count as being on the edge.
    static let edgeTolerance: CGFloat = 0.001

    /// The edge `value` is on, if any.
    static func edge(for value: CGFloat) -> HUDEdge? {
        guard value.isFinite else { return nil }
        if value <= edgeTolerance { return .minimum }
        if value >= 1 - edgeTolerance { return .maximum }
        return nil
    }

    static func clamped(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// Whole-number percentage for display.
    static func percentage(_ value: CGFloat) -> Int {
        Int((clamped(value) * 100).rounded())
    }

    /// Volume glyph: the slashed speaker when muted, otherwise a speaker whose
    /// waves fill in with the level (via the symbol's variable value).
    static func volumeSymbol(level: CGFloat) -> (name: String, variableValue: Double?) {
        let v = clamped(level)
        if v <= edgeTolerance { return ("speaker.slash.fill", nil) }
        return ("speaker.wave.3.fill", Double(v))
    }

    /// Brightness glyph: a small sun that swells into a full one past half.
    static func brightnessSymbol(level: CGFloat) -> String {
        clamped(level) >= 0.5 ? "sun.max.fill" : "sun.min.fill"
    }

    /// Keyboard backlight glyph.
    static func backlightSymbol(level: CGFloat) -> String {
        clamped(level) >= 0.5 ? "light.max" : "light.min"
    }

    /// Scale applied to a brightness / backlight glyph so it visibly swells with
    /// the level even between symbol swaps.
    static func glyphScale(level: CGFloat) -> CGFloat {
        0.88 + 0.16 * clamped(level)
    }
}

// MARK: - Transitions

/// Scale-from-0.9 plus blur-to-0 reveal used by every HUD.
struct HUDRevealEffect: ViewModifier {
    let isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isRevealed ? 1 : 0.9)
            .blur(radius: isRevealed ? 0 : 6)
            .opacity(isRevealed ? 1 : 0)
    }
}

extension AnyTransition {
    /// Scale 0.9 + blur 6 fading in and out. A short ease-out fade under Reduce Motion.
    static var hudReveal: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .modifier(
            active: HUDRevealEffect(isRevealed: false),
            identity: HUDRevealEffect(isRevealed: true)
        )
    }
}

// MARK: - Bump

/// A quick squash-and-rebound that tells the user they hit the end of the range.
struct HUDBumpEffect: ViewModifier {
    let trigger: Int
    let edge: HUDEdge?

    private struct Frame {
        var scale: CGFloat = 1
        var nudge: CGFloat = 0
    }

    func body(content: Content) -> some View {
        if NotchlyTheme.Motion.reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: Frame(), trigger: trigger) { view, frame in
                view
                    .scaleEffect(frame.scale, anchor: edge == .minimum ? .leading : .trailing)
                    .offset(x: frame.nudge)
            } keyframes: { _ in
                let direction: CGFloat = edge == .minimum ? -1 : 1
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.07, duration: 0.07)
                    SpringKeyframe(1, duration: 0.32, spring: .bouncy)
                }
                KeyframeTrack(\.nudge) {
                    CubicKeyframe(2.5 * direction, duration: 0.07)
                    SpringKeyframe(0, duration: 0.32, spring: .bouncy)
                }
            }
        }
    }
}

extension View {
    func hudBump(trigger: Int, edge: HUDEdge?) -> some View {
        modifier(HUDBumpEffect(trigger: trigger, edge: edge))
    }
}

// MARK: - Shared HUD glyph

/// The HUD icon. The glyph morphs between levels instead of popping: volume's
/// waves fill with the value, mute swaps to the slashed speaker, brightness and
/// backlight swap between their small and large variants while swelling.
struct HUDGlyph: View {
    let type: SneakContentType
    let value: CGFloat
    let icon: String
    let bumpToken: Int
    var bluetoothConnected: Bool = false
    var size: CGSize = CGSize(width: 20, height: 15)

    private var resolved: (name: String, variable: Double?, scale: CGFloat) {
        switch type {
        case .volume:
            if !icon.isEmpty { return (icon, nil, value <= HUDMotion.edgeTolerance ? 0.85 : 1) }
            if bluetoothConnected { return ("headphones", nil, value <= HUDMotion.edgeTolerance ? 0.85 : 1) }
            let symbol = HUDMotion.volumeSymbol(level: value)
            return (symbol.name, symbol.variableValue, 1)
        case .brightness:
            let name = icon.isEmpty ? HUDMotion.brightnessSymbol(level: value) : icon
            return (name, nil, HUDMotion.glyphScale(level: value))
        case .backlight:
            return (HUDMotion.backlightSymbol(level: value), nil, HUDMotion.glyphScale(level: value))
        default:
            return (icon, nil, 1)
        }
    }

    var body: some View {
        let glyph = resolved
        Group {
            if let variable = glyph.variable {
                Image(systemName: glyph.name, variableValue: variable)
            } else {
                Image(systemName: glyph.name)
            }
        }
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, options: .nonRepeating, value: NotchlyTheme.Motion.reduceMotion ? 0 : bumpToken)
        .opacity(type == .volume && value <= HUDMotion.edgeTolerance ? 0.6 : 1)
        .scaleEffect(glyph.scale)
        .frame(width: size.width, height: size.height, alignment: .center)
        .animation(NotchlyTheme.Motion.spring, value: glyph.name)
        .animation(NotchlyTheme.Motion.spring, value: glyph.variable)
        .animation(NotchlyTheme.Motion.spring, value: glyph.scale)
    }
}

// MARK: - Bump source

/// Watches HUD events and hands its content a token (and the edge hit) each
/// time a volume / brightness / backlight key is pressed with the value already
/// pinned to 0 or 1. Content applies `hudBump` and feeds the token to `HUDGlyph`.
struct HUDBumpReader<Content: View>: View {
    let type: SneakContentType
    let value: CGFloat
    @ViewBuilder var content: (_ token: Int, _ edge: HUDEdge?) -> Content

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @State private var token = 0
    @State private var edge: HUDEdge?

    var body: some View {
        content(token, edge)
            .onChange(of: coordinator.sneakPeek.pulse) { _, _ in
                guard coordinator.sneakPeek.show else { return }
                switch type {
                case .volume, .brightness, .backlight:
                    if let hit = HUDMotion.edge(for: value) {
                        edge = hit
                        token &+= 1
                    }
                default:
                    break
                }
            }
    }
}
