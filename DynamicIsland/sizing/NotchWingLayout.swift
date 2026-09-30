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
import Defaults
import SwiftUI

// MARK: - Wing layout (pure)

/// How a closed-notch live activity divides its width around the physical notch.
///
/// The closed notch is drawn centred on the screen, so the hardware cut-out is
/// always at the centre of the content. That only holds while the two wings are
/// the *same width*: give the left wing 44pt and the right 180pt and the middle
/// of the content -- where the activity reserves the notch -- sits 68pt to the
/// left of the real cut-out, which then covers the left wing and leaves the
/// right wing's labels overlapping the gap.
///
/// So the wings are always symmetric: each is as wide as the wider of the two
/// contents (or `minimumWing`), limited to what the screen leaves, and the gap
/// between them is exactly the notch. Nothing is ever laid out across the gap.
struct NotchWingLayout: Equatable {
    /// Width of the physical notch (or the fake notch on displays without one).
    let notchWidth: CGFloat
    /// Gap kept empty between the wings. `notchWidth` plus any hover flap.
    let centerGap: CGFloat
    let leftWing: CGFloat
    let rightWing: CGFloat
    /// Room kept free on the notch side of each wing so content never touches
    /// the cut-out edge. Included in the wing widths.
    let innerClearance: CGFloat

    /// Clearance between content and the notch edge.
    static let innerClearance: CGFloat = 4

    var totalWidth: CGFloat { leftWing + centerGap + rightWing }

    /// Width a wing has for content, after the clearance on the notch side.
    var contentWidth: CGFloat { max(0, min(leftWing, rightWing) - innerClearance) }

    /// `true` when the wings are as narrow as they can be, i.e. the requested
    /// content was wider than the room the screen allows.
    let isConstrained: Bool

    /// - Parameters:
    ///   - notchWidth: width of the notch cut-out.
    ///   - leftContent / rightContent: widths the two wings would like.
    ///   - minimumWing: floor for the wing width (e.g. artwork size).
    ///   - centerExtra: extra width added to the gap (hover flap).
    ///   - innerClearance: breathing room on the notch side of each wing.
    ///   - maximumTotalWidth: widest `left + gap + right` that fits; `nil` for no limit.
    static func make(
        notchWidth: CGFloat,
        leftContent: CGFloat,
        rightContent: CGFloat,
        minimumWing: CGFloat = 0,
        centerExtra: CGFloat = 0,
        innerClearance: CGFloat = 0,
        maximumTotalWidth: CGFloat? = nil
    ) -> NotchWingLayout {
        let notch = sanitized(notchWidth)
        let gap = notch + sanitized(centerExtra)
        let clearance = sanitized(innerClearance)
        let desired = max(sanitized(leftContent), sanitized(rightContent), sanitized(minimumWing)) + clearance

        let maxWing: CGFloat
        if let maximumTotalWidth, maximumTotalWidth.isFinite {
            maxWing = max(0, (maximumTotalWidth - gap) / 2)
        } else {
            maxWing = .greatestFiniteMagnitude
        }

        let wing = min(desired, maxWing)
        return NotchWingLayout(
            notchWidth: notch,
            centerGap: gap,
            leftWing: wing,
            rightWing: wing,
            innerClearance: min(clearance, wing),
            isConstrained: desired > maxWing
        )
    }

    private static func sanitized(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }

    /// How much narrower than the notch the idle closed-notch content is drawn
    /// (`closedNotchSize.width - 20`), so an arriving activity can start exactly
    /// where the idle notch already is.
    static let idleContentInset: CGFloat = 20

    /// The layout an activity arrives from: no wings, and a gap as wide as the
    /// idle closed-notch content. The wings then grow outward from the notch
    /// centre as the layout springs to its real size.
    var arrival: NotchWingLayout {
        NotchWingLayout(
            notchWidth: notchWidth,
            centerGap: max(0, centerGap - Self.idleContentInset),
            leftWing: 0,
            rightWing: 0,
            innerClearance: 0,
            isConstrained: false
        )
    }

    /// The widest closed-notch content that keeps clear of the screen edges and,
    /// when known, of the frontmost app's menus.
    ///
    /// Menus are the reason this exists: a left wing that reaches past the end of
    /// the last menu would paint over it. Shifting the whole notch sideways to
    /// dodge them (what the old clearance offset did) moves the gap off the
    /// hardware cut-out, so instead the wings stay centred and get narrower.
    ///
    /// - Parameters:
    ///   - screenFrame: the display the notch is on.
    ///   - menusRightEdge: right edge of the last app menu in screen coordinates.
    ///   - menuGap: space to leave between the menus and the notch surface.
    ///   - shapePadding: how far the notch surface extends past the content on each side.
    ///   - screenMargin: space to leave at each screen edge.
    static func availableContentWidth(
        screenFrame: CGRect,
        menusRightEdge: CGFloat?,
        menuGap: CGFloat,
        shapePadding: CGFloat,
        screenMargin: CGFloat = 16
    ) -> CGFloat {
        var limit = screenFrame.width - 2 * (screenMargin + shapePadding)
        if let menusRightEdge, menusRightEdge.isFinite {
            let reach = screenFrame.midX - (menusRightEdge + menuGap) - shapePadding
            limit = min(limit, 2 * reach)
        }
        return max(0, limit)
    }

    /// Width of single-line text in `font`, for sizing wings to their content.
    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

// MARK: - Live metrics

/// Reads the state `NotchWingLayout` needs that isn't pure: the screen and the
/// frontmost app's menus.
@MainActor
enum ClosedNotchMetrics {
    /// Widest closed-notch content allowed on `screenName` right now: what the
    /// screen leaves, what the frontmost app's menus leave, and what the notch
    /// window itself is wide enough to draw (the minimalistic notch's window is
    /// only 420pt, and anything wider would be cut off at its edge).
    static func maximumContentWidth(screenName: String?) -> CGFloat? {
        guard let frame = getScreenFrame(screenName) else { return nil }
        let shapePadding = cornerRadiusInsets.closed.bottom
        let byScreenAndMenus = NotchWingLayout.availableContentWidth(
            screenFrame: frame,
            menusRightEdge: MenuBarLayout.shared.appMenusRightEdge,
            menuGap: MenuBarLayout.clearanceGap,
            shapePadding: shapePadding
        )
        let windowWidth = Defaults[.enableMinimalisticUI]
            ? minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: screenName)).width
            : openNotchSize.width
        return min(byScreenAndMenus, max(0, windowWidth - 2 * shapePadding))
    }

    /// The standard wing layout for a closed-notch live activity: symmetric
    /// wings sized to the wider content, the hover flap in the gap, and the
    /// whole thing narrowed to keep clear of the screen edges and app menus.
    static func wingLayout(
        notchWidth: CGFloat,
        screenName: String?,
        leftContent: CGFloat,
        rightContent: CGFloat,
        minimumWing: CGFloat = 0,
        isHovering: Bool = false,
        innerClearance: CGFloat = NotchWingLayout.innerClearance,
        widthBudget: CGFloat? = nil
    ) -> NotchWingLayout {
        // The activity's own budget (what the notch's outer frame reserves for
        // it) can only tighten the screen limit, never loosen it.
        var limit = maximumContentWidth(screenName: screenName)
        if let widthBudget {
            limit = min(limit ?? widthBudget, widthBudget)
        }
        return NotchWingLayout.make(
            notchWidth: notchWidth,
            leftContent: leftContent,
            rightContent: rightContent,
            minimumWing: minimumWing,
            centerExtra: isHovering ? 8 : 0,
            innerClearance: innerClearance,
            maximumTotalWidth: limit
        )
    }
}

// MARK: - Notch state clock

/// When the notch last opened or closed, so views that appear as a *result* of
/// that can tell they are returning rather than arriving.
@MainActor
enum NotchStateClock {
    private(set) static var lastChange: Date = .distantPast

    /// How long after an open / close a newly appearing activity still counts
    /// as part of it.
    nonisolated static let window: TimeInterval = 0.7

    static func noteChange(at date: Date = Date()) {
        lastChange = date
    }

    nonisolated static func isRecent(now: Date, lastChange: Date) -> Bool {
        let elapsed = now.timeIntervalSince(lastChange)
        return elapsed >= 0 && elapsed < window
    }

    static var changedRecently: Bool {
        isRecent(now: Date(), lastChange: lastChange)
    }
}

// MARK: - Wings view

/// Two wings either side of an empty notch-sized gap.
///
/// Each wing is clipped to its own frame, so anything that slides, scales or
/// marquees inside it can never spill into the cut-out or the opposite wing.
///
/// On arrival the wings start at zero width and spring outward from the notch
/// centre; the content fades in a beat later and, while the wings grow, is
/// laid out at its final width so text never reflows or truncates mid-growth.
/// Under Reduce Motion the wings are simply there.
struct NotchWings<Left: View, Right: View>: View {
    let layout: NotchWingLayout
    let height: CGFloat
    let leftAlignment: Alignment
    let rightAlignment: Alignment
    let left: () -> Left
    let right: () -> Right

    private enum Phase {
        /// First frame: no wings yet.
        case arriving
        /// Wings growing; content laid out at its final width.
        case growing
        /// At rest: content tracks the wing frames directly.
        case settled
    }

    @State private var phase: Phase
    @State private var contentShown: Bool

    init(
        layout: NotchWingLayout,
        height: CGFloat,
        leftAlignment: Alignment = .leading,
        rightAlignment: Alignment = .trailing,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder right: @escaping () -> Right
    ) {
        self.layout = layout
        self.height = height
        self.leftAlignment = leftAlignment
        self.rightAlignment = rightAlignment
        self.left = left
        self.right = right
        // Wings that appear because the notch has just closed are returning to
        // their place (the artwork flies back to it), not arriving, so they skip
        // the grow-from-centre.
        let skipsArrival = NotchlyTheme.Motion.reduceMotion || NotchStateClock.changedRecently
        _phase = State(initialValue: skipsArrival ? .settled : .arriving)
        _contentShown = State(initialValue: skipsArrival)
    }

    private var shown: NotchWingLayout {
        phase == .arriving ? layout.arrival : layout
    }

    var body: some View {
        let shown = self.shown
        let pinned = phase != .settled
        let reduce = NotchlyTheme.Motion.reduceMotion

        HStack(spacing: 0) {
            left()
                .opacity(contentShown ? 1 : 0)
                .blur(radius: contentShown || reduce ? 0 : 4)
                .padding(.trailing, layout.innerClearance)
                .frame(width: pinned ? layout.leftWing : shown.leftWing, height: height, alignment: leftAlignment)
                // Anchored on the notch side, so growth reveals the content
                // from the notch outward instead of sliding it.
                .frame(width: shown.leftWing, height: height, alignment: .trailing)
                .clipped()
            Color.clear
                .frame(width: shown.centerGap, height: height)
            right()
                .opacity(contentShown ? 1 : 0)
                .blur(radius: contentShown || reduce ? 0 : 4)
                .padding(.leading, layout.innerClearance)
                .frame(width: pinned ? layout.rightWing : shown.rightWing, height: height, alignment: rightAlignment)
                .frame(width: shown.rightWing, height: height, alignment: .leading)
                .clipped()
        }
        .frame(height: height)
        // The wings grow and shrink together, so the gap never moves off the notch.
        .animation(NotchlyTheme.Motion.spring, value: shown)
        .onAppear(perform: arrive)
    }

    private func arrive() {
        guard phase == .arriving else { return }
        phase = .growing
        withAnimation(NotchlyTheme.Motion.spring(delay: 0.1)) {
            contentShown = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            phase = .settled
        }
    }
}
