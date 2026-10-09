/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import SwiftUI

// MARK: - Live container

/// Lyrics mode: the rolling lyrics card that takes the Hub's place in the open
/// notch. Reads the shared music state and hands a snapshot to
/// `LyricsStageContent`, which draws it (and which the tests render directly).
struct LyricsStageView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.fetchLyricsOnline) private var fetchOnline
    @Default(.lyricsTextSize) private var textSize
    @Default(.playerColorTinting) private var playerColorTinting
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var cornerRadius: CGFloat = NotchlyTheme.Radius.xl

    private var snapshot: LyricsStageSnapshot {
        let state = LyricsStageState.resolve(
            hasTrack: musicManager.hasActiveSession,
            isAdvertisement: musicManager.isAdvertisement,
            fetchOnline: fetchOnline,
            availability: musicManager.lyricsAvailability
        )
        let lines = state == .synced || state == .unsynced ? musicManager.syncedLyrics : []
        return LyricsStageSnapshot(
            state: state,
            lines: lines,
            rows: state == .synced ? LyricsStageWindow.displayRows(lines: lines, duration: musicManager.songDuration) : [],
            currentIndex: musicManager.currentLyricIndex,
            isPlaying: musicManager.isPlaying,
            canSeek: !musicManager.isLiveStream && musicManager.songDuration > 0,
            accent: playerColorTinting
                ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
                : NotchlyTheme.Palette.silver
        )
    }

    var body: some View {
        LyricsStageContent(
            snapshot: snapshot,
            textSize: textSize,
            cornerRadius: cornerRadius,
            // The sweep clock runs only while it can be seen and is moving.
            animatesSweep: vm.notchState == .open && musicManager.isPlaying,
            progress: { musicManager.currentLyricSweepProgress(at: $0) },
            onSeek: { musicManager.seek(to: $0) },
            onRetry: { musicManager.fetchLyrics() },
            onClose: {
                withAnimation(NotchlyTheme.Motion.spring) { LyricsModeController.shared.set(false) }
            },
            onScrollHover: updateSuppression(for:)
        )
        .onDisappear { updateSuppression(for: false) }
    }

    /// Scrolling the unsynced lyrics must not close the notch.
    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

// MARK: - Snapshot

struct LyricsStageSnapshot {
    var state: LyricsStageState
    var lines: [LyricLine]
    var rows: [LyricRow]
    var currentIndex: Int
    var isPlaying: Bool
    var canSeek: Bool
    var accent: Color
}

// MARK: - Content

struct LyricsStageContent: View {
    let snapshot: LyricsStageSnapshot
    let textSize: LyricsTextSize
    var cornerRadius: CGFloat = NotchlyTheme.Radius.xl
    var animatesSweep: Bool
    var progress: (Date) -> Double
    var onSeek: (TimeInterval) -> Void = { _ in }
    var onRetry: () -> Void = {}
    var onClose: () -> Void = {}
    var onScrollHover: (Bool) -> Void = { _ in }

    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            stateContent
                .id(stateIdentity)
                .transition(Self.stateTransition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(NotchlyTheme.Motion.spring, value: stateIdentity)
        .glassSurface(cornerRadius: cornerRadius)
        .clipShape(shape)
        .contentShape(shape)
        .overlay(alignment: .topTrailing) { closeButton }
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
    }

    /// Synced and unsynced share nothing but the card; every other state is a
    /// status message. Keyed so a change of state cross-fades.
    private var stateIdentity: String {
        switch snapshot.state {
        case .nothingPlaying: return "nothing"
        case .onlineLookupOff: return "off"
        case .searching: return "searching"
        case .synced: return "synced"
        case .unsynced: return "unsynced"
        case .instrumental: return "instrumental"
        case .notFound: return "notFound"
        }
    }

    static var stateTransition: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion { return .opacity }
        return .opacity
            .combined(with: .scale(scale: 0.97))
            .combined(with: .modifier(active: LyricBlurEffect(radius: 6), identity: LyricBlurEffect(radius: 0)))
    }

    @ViewBuilder
    private var stateContent: some View {
        switch snapshot.state {
        case .synced:
            RollingLyricsView(
                rows: snapshot.rows,
                lines: snapshot.lines,
                currentIndex: snapshot.currentIndex,
                isPlaying: snapshot.isPlaying,
                canSeek: snapshot.canSeek,
                accent: snapshot.accent,
                textSize: textSize,
                animatesSweep: animatesSweep,
                progress: progress,
                onSeek: onSeek
            )
        case .unsynced:
            UnsyncedLyricsView(lines: snapshot.lines, textSize: textSize, onScrollHover: onScrollHover)
        case .searching:
            LyricsStatusView(symbol: "text.magnifyingglass", title: "Searching…", detail: nil, animates: true)
        case .notFound:
            LyricsStatusView(symbol: "text.badge.xmark", title: "No lyrics found", detail: nil, actionTitle: "Try again", action: onRetry)
        case .instrumental:
            LyricsStatusView(symbol: "music.note", title: "Instrumental", detail: "No words in this one")
        case .onlineLookupOff:
            LyricsStatusView(
                symbol: "wifi.slash",
                title: "Online lyrics are off",
                detail: "Turn on Fetch lyrics online in Settings › Music"
            )
        case .nothingPlaying:
            LyricsStatusView(symbol: "music.note", title: "Nothing playing", detail: nil)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                .frame(width: 18, height: 18)
                .glassSurface(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.notchlyPress)
        .padding(7)
        .opacity(isHovering ? 1 : 0)
        .help("Back to the Hub")
        .accessibilityLabel("Close lyrics")
    }
}

// MARK: - Rolling (synced) lyrics

/// The current line sits a third of the way down the card, bright and full
/// size; the line before it above, dimmer and smaller; the next few below.
/// When the line changes, the whole column springs up by one row.
private struct RollingLyricsView: View {
    let rows: [LyricRow]
    let lines: [LyricLine]
    let currentIndex: Int
    let isPlaying: Bool
    let canSeek: Bool
    let accent: Color
    let textSize: LyricsTextSize
    let animatesSweep: Bool
    let progress: (Date) -> Double
    let onSeek: (TimeInterval) -> Void

    @State private var heights: [Int: CGFloat] = [:]

    private let spacing: CGFloat = 7
    private let horizontalInset: CGFloat = 16

    private static var rollAnimation: Animation {
        NotchlyTheme.Motion.reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(response: 0.55, dampingFraction: 0.84)
    }

    var body: some View {
        GeometryReader { geo in
            let window = LyricsStageWindow.window(rowIndices: rows.map(\.index), currentIndex: currentIndex)
            if let window {
                let visible = window.rows.map { rows[$0] }
                let anchorY = geo.size.height * 0.36
                let above = visible.prefix(window.anchor).reduce(CGFloat(0)) { $0 + height(of: $1) + spacing }
                let textWidth = max(40, geo.size.width - horizontalInset * 2)

                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { position, row in
                        let distance = position - window.anchor
                        rowView(
                            row,
                            distance: distance,
                            isCurrent: window.anchorIsCurrent && distance == 0,
                            textWidth: textWidth
                        )
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[row.index] = $0 }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, horizontalInset)
                .frame(width: geo.size.width, alignment: .topLeading)
                .offset(y: anchorY - above)
                .animation(Self.rollAnimation, value: currentIndex)
                .animation(Self.rollAnimation, value: textSize)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.2),
                    .init(color: .black, location: 0.8),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipped()
    }

    private func height(of row: LyricRow) -> CGFloat {
        heights[row.index] ?? textSize.fontSize * 1.25
    }

    @ViewBuilder
    private func rowView(_ row: LyricRow, distance: Int, isCurrent: Bool, textWidth: CGFloat) -> some View {
        let reduce = NotchlyTheme.Motion.reduceMotion
        let scale = isCurrent ? 1 : textSize.contextScale
        let opacity: Double = {
            if isCurrent { return isPlaying ? 1 : 0.72 }
            switch abs(distance) {
            case 0: return 0.62          // anchored but not yet sung / in a short gap
            case 1: return 0.42
            case 2: return 0.26
            default: return 0.14
            }
        }()
        let blur: CGFloat = reduce || isCurrent ? 0 : min(CGFloat(abs(distance)) * 0.6, 1.6)

        rowContent(row, isCurrent: isCurrent)
            .frame(width: textWidth, alignment: .leading)
            .scaleEffect(scale, anchor: .leading)
            .opacity(opacity)
            .blur(radius: blur)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canSeek, lines.indices.contains(row.index), lines[row.index].isTimed else { return }
                onSeek(lines[row.index].timestamp)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder
    private func rowContent(_ row: LyricRow, isCurrent: Bool) -> some View {
        switch row {
        case let .line(_, text):
            if isCurrent {
                // Only the line being sung redraws with the clock.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animatesSweep)) { timeline in
                    lyricText(text, isCurrent: true, progress: progress(timeline.date))
                }
            } else {
                lyricText(text, isCurrent: false, progress: 0)
            }
        case .instrumental:
            if isCurrent {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animatesSweep)) { timeline in
                    InstrumentalBreakNotes(fontSize: textSize.fontSize * 0.8, weight: .bold)
                        .lyricSweep(progress: progress(timeline.date), isCurrent: true, sung: .white,
                                    unsung: .white.opacity(0.35), idle: .white)
                }
            } else {
                InstrumentalBreakNotes(fontSize: textSize.fontSize * 0.8, weight: .bold)
                    .foregroundStyle(.white)
            }
        }
    }

    /// Every row is laid out with the same face so a line wraps the same way
    /// whether or not it is current; only scale, opacity and the sweep change.
    private func lyricText(_ text: String, isCurrent: Bool, progress: Double) -> some View {
        SweptLyricText(
            text: text,
            fontSize: textSize.fontSize,
            weight: .bold,
            progress: progress,
            isCurrent: isCurrent,
            sung: .white,
            unsung: .white.opacity(0.36),
            idle: .white,
            tint: accent
        )
    }
}

// MARK: - Unsynced lyrics

/// Plain lyrics have no timings, so nothing pretends to know which line is
/// being sung: the words are shown as a list to read and scroll, labelled.
private struct UnsyncedLyricsView: View {
    let lines: [LyricLine]
    let textSize: LyricsTextSize
    let onScrollHover: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "text.alignleft")
                Text("Unsynced lyrics")
            }
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(NotchlyTheme.Palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassSurface(in: Capsule())
            .padding(.top, 9)
            .padding(.leading, 12)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(.system(size: textSize.fontSize * 0.82, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onHover(perform: onScrollHover)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Status

private struct LyricsStatusView: View {
    let symbol: String
    let title: String
    let detail: String?
    var animates: Bool = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                .symbolEffect(.pulse, options: .repeating, isActive: animates && !NotchlyTheme.Motion.reduceMotion)
                .frame(height: 22)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary)

            if let detail {
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.notchlyGlass)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Lyrics button

/// The glass button that turns lyrics mode on and off.
struct LyricsModeButton: View {
    @ObservedObject private var mode = LyricsModeController.shared
    var size: CGFloat = 24

    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(NotchlyTheme.Motion.spring) { mode.toggle() }
        } label: {
            Image(systemName: mode.isActive ? "quote.bubble.fill" : "quote.bubble")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(mode.isActive ? NotchlyTheme.Palette.textPrimary : NotchlyTheme.Palette.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background {
                    Circle().fill(
                        mode.isActive
                            ? NotchlyTheme.Palette.glassFillSelected
                            : (isHovering ? NotchlyTheme.Palette.glassFillHover : NotchlyTheme.Palette.glassFill)
                    )
                }
                .overlay {
                    Circle().strokeBorder(
                        mode.isActive ? NotchlyTheme.Palette.glassStrokeStrong : NotchlyTheme.Palette.glassStroke,
                        lineWidth: NotchlyTheme.Stroke.hairline
                    )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.notchlyPress)
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .help(mode.isActive ? "Hide lyrics" : "Show lyrics")
        .accessibilityLabel(mode.isActive ? "Hide lyrics" : "Show lyrics")
        .accessibilityAddTraits(mode.isActive ? .isSelected : [])
    }
}

// MARK: - Transition

extension AnyTransition {
    /// The Hub and the lyrics card swapping places: one settles back and
    /// blurs out while the other rises out of a blur.
    static var lyricsStageSwap: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion { return .opacity }
        let blur = AnyTransition.modifier(active: LyricBlurEffect(radius: 8), identity: LyricBlurEffect(radius: 0))
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: blur),
            removal: .opacity.combined(with: .scale(scale: 1.04)).combined(with: blur)
        )
    }
}
