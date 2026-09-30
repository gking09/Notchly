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
    /// Widest closed-notch content allowed on `screenName` right now.
    static func maximumContentWidth(screenName: String?) -> CGFloat? {
        guard let frame = getScreenFrame(screenName) else { return nil }
        return NotchWingLayout.availableContentWidth(
            screenFrame: frame,
            menusRightEdge: MenuBarLayout.shared.appMenusRightEdge,
            menuGap: MenuBarLayout.clearanceGap,
            shapePadding: cornerRadiusInsets.closed.bottom
        )
    }
}

// MARK: - Wings view

/// Two wings either side of an empty notch-sized gap.
///
/// Each wing is clipped to its own frame, so anything that slides, scales or
/// marquees inside it can never spill into the cut-out or the opposite wing.
struct NotchWings<Left: View, Right: View>: View {
    let layout: NotchWingLayout
    let height: CGFloat
    var leftAlignment: Alignment = .leading
    var rightAlignment: Alignment = .trailing
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(spacing: 0) {
            left()
                .padding(.trailing, layout.innerClearance)
                .frame(width: layout.leftWing, height: height, alignment: leftAlignment)
                .clipped()
            Color.clear
                .frame(width: layout.centerGap, height: height)
            right()
                .padding(.leading, layout.innerClearance)
                .frame(width: layout.rightWing, height: height, alignment: rightAlignment)
                .clipped()
        }
        .frame(height: height)
        // The wings grow and shrink together, so the gap never moves off the notch.
        .animation(NotchlyTheme.Motion.spring, value: layout)
    }
}
