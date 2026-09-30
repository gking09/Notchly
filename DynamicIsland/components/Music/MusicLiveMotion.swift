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

// MARK: - Wing sizing for the closed music activity

/// What each wing of the closed music live activity asks for. The two results
/// feed `NotchWingLayout.make`, which makes the wings symmetric.
enum MusicWingMetrics {
    /// Most a wing grows to for track info; longer text marquees instead.
    static let maxTrackInfoWidth: CGFloat = 150
    /// Space between the artwork / visualizer and the text beside it.
    static let spacing: CGFloat = 6

    /// Left wing: artwork, plus the title while track info is showing.
    static func leftContent(artworkWidth: CGFloat, titleWidth: CGFloat, showsTrackInfo: Bool) -> CGFloat {
        guard showsTrackInfo, titleWidth > 0 else { return artworkWidth }
        return min(artworkWidth + spacing + titleWidth, max(artworkWidth, maxTrackInfoWidth))
    }

    /// Right wing: the visualizer, plus the artist while track info is showing.
    static func rightContent(visualizerWidth: CGFloat, artistWidth: CGFloat, showsTrackInfo: Bool) -> CGFloat {
        guard showsTrackInfo, artistWidth > 0 else { return visualizerWidth }
        return min(artistWidth + spacing + visualizerWidth, max(visualizerWidth, maxTrackInfoWidth))
    }

    /// Room left for a text field sharing a wing with `reserved` points of other content.
    static func textFieldWidth(wingContentWidth: CGFloat, reserved: CGFloat) -> CGFloat {
        max(0, wingContentWidth - reserved - spacing)
    }
}

// MARK: - Crossfading artwork

/// Album art that dissolves into the next image rather than snapping to it.
struct CrossfadeArtwork: View {
    let image: NSImage
    var cornerRadius: CGFloat = 4
    var contentMode: ContentMode = .fit

    @State private var shown: NSImage?
    @State private var outgoing: NSImage?
    @State private var incomingOpacity: Double = 1

    var body: some View {
        ZStack {
            if let outgoing {
                artwork(outgoing)
            }
            artwork(shown ?? image)
                .opacity(incomingOpacity)
        }
        .onAppear { shown = image }
        .onChange(of: image) { old, new in
            guard old !== new else { return }
            if NotchlyTheme.Motion.reduceMotion {
                shown = new
                return
            }
            outgoing = shown ?? old
            shown = new
            incomingOpacity = 0
            withAnimation(.easeOut(duration: 0.38)) {
                incomingOpacity = 1
            } completion: {
                outgoing = nil
            }
        }
    }

    private func artwork(_ source: NSImage) -> some View {
        Image(nsImage: source)
            .resizable()
            .aspectRatio(contentMode: contentMode)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Track change pop

/// A small scale-and-tilt settle played each time `trigger` changes: the new
/// track's artwork lands instead of just appearing.
struct TrackChangePop<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger

    private struct Frame {
        var scale: CGFloat = 1
        var angle: Double = 0
    }

    func body(content: Content) -> some View {
        if NotchlyTheme.Motion.reduceMotion {
            content
        } else {
            content.keyframeAnimator(initialValue: Frame(), trigger: trigger) { view, frame in
                view
                    .scaleEffect(frame.scale)
                    .rotationEffect(.degrees(frame.angle))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.86, duration: 0.09)
                    SpringKeyframe(1, duration: 0.45, spring: Spring(response: 0.35, dampingRatio: 0.8))
                }
                KeyframeTrack(\.angle) {
                    CubicKeyframe(-7, duration: 0.09)
                    SpringKeyframe(0, duration: 0.45, spring: Spring(response: 0.35, dampingRatio: 0.8))
                }
            }
        }
    }
}

extension View {
    func trackChangePop<T: Equatable>(trigger: T) -> some View {
        modifier(TrackChangePop(trigger: trigger))
    }
}

// MARK: - Wing slide transition

/// Offset, blur and fade applied to text that slides in from (or out toward) the notch.
struct WingSlideEffect: ViewModifier {
    let offset: CGFloat
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: isActive ? offset : 0)
            .blur(radius: isActive ? 4 : 0)
            .opacity(isActive ? 0 : 1)
    }
}

extension AnyTransition {
    /// Text that emerges from beside the notch and tucks back toward it. The
    /// wing clips it, so it never draws over the cut-out.
    /// - Parameter edge: the side of the notch the text sits on.
    static func wingSlide(from edge: HorizontalEdge) -> AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        // Left-wing text starts toward the notch (+x) and rolls out to the left.
        let toward: CGFloat = edge == .leading ? 22 : -22
        return .asymmetric(
            insertion: .modifier(
                active: WingSlideEffect(offset: toward, isActive: true),
                identity: WingSlideEffect(offset: toward, isActive: false)
            ),
            removal: .modifier(
                active: WingSlideEffect(offset: -toward * 0.5, isActive: true),
                identity: WingSlideEffect(offset: -toward * 0.5, isActive: false)
            )
        )
    }
}

// MARK: - Lyric line transition

/// Blur applied while a lyric line slides in or out.
struct LyricBlurEffect: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: radius)
    }
}

extension AnyTransition {
    /// A lyric line rises in from below while un-blurring, and lifts away blurring
    /// out. Reduce Motion falls back to a short fade.
    static var lyricLine: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        let blurred = AnyTransition.modifier(
            active: LyricBlurEffect(radius: 5),
            identity: LyricBlurEffect(radius: 0)
        )
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: blurred),
            removal: .move(edge: .top).combined(with: .opacity).combined(with: blurred)
        )
    }
}
