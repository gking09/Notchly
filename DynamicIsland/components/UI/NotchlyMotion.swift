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

// MARK: - Stagger timing (pure)

/// The delays behind staggered appearances. Kept free of SwiftUI so the maths
/// can be tested.
enum StaggerTiming {
    /// Gap between one element's entrance and the next.
    static let step: Double = 0.04
    /// Longest any element waits, however far down the list it is.
    static let maximumDelay: Double = 0.32

    /// How long element `index` waits before it enters.
    ///
    /// - Parameters:
    ///   - index: position in the stagger, 0 first. Negative counts as 0.
    ///   - base: wait before the first element (e.g. to let the notch shell
    ///     expand before its content starts to arrive).
    ///   - step: extra wait per position.
    ///   - maximum: ceiling for the whole delay, so a long list never drags.
    static func delay(
        index: Int,
        base: Double = 0,
        step: Double = StaggerTiming.step,
        maximum: Double = StaggerTiming.maximumDelay
    ) -> Double {
        let position = Double(max(index, 0))
        let raw = max(base, 0) + position * max(step, 0)
        guard raw.isFinite else { return 0 }
        return min(raw, max(maximum, 0))
    }
}

/// How far a tab's content travels while switching, and which way.
enum TabSwitchMotion {
    /// Distance content slides when a tab changes.
    static let travel: CGFloat = 26

    /// Horizontal offset of the *incoming* tab's starting position. Switching
    /// forward brings the new tab in from the trailing side (positive x).
    static func incomingOffset(forward: Bool) -> CGFloat {
        forward ? travel : -travel
    }

    /// Horizontal offset the *outgoing* tab drifts to: the opposite side.
    static func outgoingOffset(forward: Bool) -> CGFloat {
        -incomingOffset(forward: forward)
    }
}

// MARK: - Shared animations

extension NotchlyTheme.Motion {
    /// Opening morph of the notch shell. Damped enough that the size never
    /// visibly overshoots the window it is drawn in.
    static var notchOpen: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.9)
    }

    /// Closing morph: critically damped, so the shell tucks away without a bounce.
    static var notchClose: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.42, dampingFraction: 1.0)
    }

    /// Hovering the closed notch: the small swell of its flap.
    static var hover: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.72)
    }

    /// A springier variant for things that should pop: quick actions arriving,
    /// a button rebounding after a press.
    static var pop: Animation {
        reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.32, dampingFraction: 0.66)
    }

    /// `spring` held back by `delay`. Under Reduce Motion the delay is dropped:
    /// waiting to fade something in is motion too.
    static func spring(delay: Double) -> Animation {
        reduceMotion ? spring : spring.delay(delay)
    }
}

// MARK: - Staggered appearance

/// Fades, lifts and un-blurs its content in a beat after it appears. Give each
/// sibling the next `index` and they arrive one after the other.
struct StaggeredAppearance: ViewModifier {
    let index: Int
    var base: Double
    var offset: CGFloat
    var blur: CGFloat
    /// `false` keeps the content fully visible and only settles its scale; for
    /// views that are already travelling into place (matched geometry).
    var fades: Bool = true

    @State private var shown = false

    func body(content: Content) -> some View {
        let reduce = NotchlyTheme.Motion.reduceMotion
        content
            .opacity(shown || !fades ? 1 : 0)
            .offset(y: shown || reduce ? 0 : offset)
            .scaleEffect(shown || reduce ? 1 : 0.96, anchor: .top)
            // Small, short-lived blur on the elements themselves; never on a container.
            .blur(radius: shown || reduce ? 0 : min(blur, 8))
            .onAppear {
                guard !shown else { return }
                let delay = StaggerTiming.delay(index: index, base: base)
                withAnimation(NotchlyTheme.Motion.spring(delay: delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Enters after the previous `index` siblings, ~40ms apart. `base` holds the
    /// whole sequence back (for instance until the notch shell has expanded).
    func staggered(index: Int, base: Double = 0.06, offset: CGFloat = 8, blur: CGFloat = 4, fades: Bool = true) -> some View {
        modifier(StaggeredAppearance(index: index, base: base, offset: offset, blur: blur, fades: fades))
    }
}

// MARK: - Pop-in

/// Scales up from small with a springy overshoot, a beat after it appears.
/// For small controls arriving one after another (the Quick Actions row).
struct PopInAppearance: ViewModifier {
    let index: Int
    var base: Double

    @State private var shown = false

    func body(content: Content) -> some View {
        let reduce = NotchlyTheme.Motion.reduceMotion
        content
            .scaleEffect(shown || reduce ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                let delay = StaggerTiming.delay(index: index, base: base)
                let animation = reduce ? NotchlyTheme.Motion.spring : NotchlyTheme.Motion.pop.delay(delay)
                withAnimation(animation) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Pops in with a springy overshoot, `index` places after the first.
    func popIn(index: Int, base: Double = 0.1) -> some View {
        modifier(PopInAppearance(index: index, base: base))
    }
}

// MARK: - Transitions

private struct ContentRevealEffect: ViewModifier {
    let isRevealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .scaleEffect(isRevealed ? 1 : 0.97, anchor: .top)
            .blur(radius: isRevealed ? 0 : 6)
    }
}

private struct TabSlideEffect: ViewModifier {
    let offset: CGFloat
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: isActive ? offset : 0)
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? 6 : 0)
    }
}

private struct ActivityArrivalEffect: ViewModifier {
    let isRevealed: Bool
    let squeeze: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: isRevealed ? 1 : squeeze, y: isRevealed ? 1 : 0.94, anchor: .center)
            .opacity(isRevealed ? 1 : 0)
    }
}

extension AnyTransition {
    /// The open notch's content arriving a beat after the shell: fades, settles
    /// from 0.97 and un-blurs; on the way out it just gets out of the way fast.
    static var notchContentReveal: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .asymmetric(
            insertion: .modifier(
                active: ContentRevealEffect(isRevealed: false),
                identity: ContentRevealEffect(isRevealed: true)
            )
            .animation(NotchlyTheme.Motion.spring(delay: 0.08)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// Direction-aware tab change: the new tab slides in from the side it
    /// "comes from" while un-blurring, the old one drifts off the other way.
    static func tabSlide(forward: Bool) -> AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .asymmetric(
            insertion: .modifier(
                active: TabSlideEffect(offset: TabSwitchMotion.incomingOffset(forward: forward), isActive: true),
                identity: TabSlideEffect(offset: TabSwitchMotion.incomingOffset(forward: forward), isActive: false)
            ),
            removal: .modifier(
                active: TabSlideEffect(offset: TabSwitchMotion.outgoingOffset(forward: forward), isActive: true),
                identity: TabSlideEffect(offset: TabSwitchMotion.outgoingOffset(forward: forward), isActive: false)
            )
        )
    }

    /// A closed-notch live activity arriving or leaving. The wings do their own
    /// growing from the notch centre (see `NotchWings`); this squeezes the whole
    /// activity toward the centre on the way out and fades it, so a departure is
    /// the arrival played backwards.
    static var closedActivity: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .asymmetric(
            insertion: .modifier(
                active: ActivityArrivalEffect(isRevealed: false, squeeze: 0.96),
                identity: ActivityArrivalEffect(isRevealed: true, squeeze: 0.96)
            )
            .animation(.spring(response: 0.34, dampingFraction: 0.88)),
            removal: .modifier(
                active: ActivityArrivalEffect(isRevealed: false, squeeze: 0.6),
                identity: ActivityArrivalEffect(isRevealed: true, squeeze: 0.6)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.9))
        )
    }
}

extension AnyTransition {
    /// A settings section swapping in: fades and lifts a few points. Kept
    /// subtle -- it is a window, not the notch.
    static var settingsPage: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .opacity.combined(with: .offset(y: 6))
    }
}
