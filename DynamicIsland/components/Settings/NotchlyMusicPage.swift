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

/// Music: where playback comes from, how the player behaves in the notch,
/// the control layout, lyrics, artwork and the visualizer.
struct NotchlyMusicPage: View {
    typealias I = Item

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    @Default(.mediaController) private var mediaController
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableHub) private var enableHub
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.enableLyrics) private var enableLyrics
    @Default(.pinLyricsWhenClosed) private var pinLyricsWhenClosed
    @Default(.lyricHighlightStyle) private var lyricHighlightStyle
    @Default(.hideNotchOption) private var hideNotchOption
    @Default(.sneakPeekStyles) private var sneakPeekStyles
    @Default(.pinnedLyricContext) private var pinnedLyricContext
    @Default(.lyricsPanelWidth) private var lyricsPanelWidth
    @Default(.lyricsPanelOffset) private var lyricsPanelOffset

    /// The standard notch player is switched off (and Minimalistic UI is not
    /// providing a player of its own).
    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    private var lyricsAvailable: Bool {
        !enableMinimalisticUI && showStandardMediaControls
    }

    var body: some View {
        NotchlyPageScroll(page: .music) {
            sourceCard
            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
                SpotifyLikeButtonSettingsSection()
            }
            if mediaController == .cider {
                CiderFavoritingSettingsSection()
            }
            playerCard
            controlsCard
            sneakPeekCard
            lyricsCard
            artworkCard
            visualizerCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: mediaController)
        .animation(NotchlyTheme.Motion.snappy, value: showShuffleAndRepeat)
        .animation(NotchlyTheme.Motion.snappy, value: enableLyrics)
        .animation(NotchlyTheme.Motion.snappy, value: enableSneakPeek)
        .animation(NotchlyTheme.Motion.snappy, value: pinLyricsWhenClosed)
    }

    // MARK: Source

    /// Only the sources that work on this macOS version.
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        }
        return MediaControllerType.allCases
    }

    private var sourceFooter: String {
        if MusicManager.shared.isNowPlayingDeprecated {
            return "YouTube Music needs the third-party YouTube Music app (github.com/th-ch/youtube-music) installed."
        }
        var text = "Now Playing works with every media app."
        if mediaController == .amazonMusic || mediaController == .tidal || mediaController == .cider {
            text += " " + mediaController.description
        }
        return text
    }

    private var sourceCard: some View {
        NotchlySettingsCard("Source", footer: sourceFooter) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(I.source.title)
                        .font(.system(size: 13, weight: .medium))
                    MediaSourceCapabilitiesButton(controllers: availableMediaControllers)
                    Spacer()
                    ScrollHintIndicator()
                }
                MusicSourceSelector(selection: $mediaController, controllers: availableMediaControllers)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsHighlight(id: I.source.highlightID)
            .onChange(of: mediaController) { _, _ in
                NotificationCenter.default.post(name: Notification.Name.mediaControllerChanged, object: nil)
            }
        }
    }

    // MARK: Player in the notch

    private var playerCard: some View {
        NotchlySettingsCard(
            "In the notch",
            footer: standardControlsSuppressed
                ? "The music player is switched off on the Home tab (Home & Hub), so these are unavailable."
                : "Where the player lives on the Home tab is set under Home & Hub."
        ) {
            I.liveActivity.toggle(
                "Show what is playing in the closed notch.",
                isEnabled: !standardControlsSuppressed,
                isOn: $coordinator.musicLiveActivityEnabled.animation()
            )
            I.floatingControls.toggle(
                "Play/pause and skip buttons beside the notch while music plays.",
                isEnabled: coordinator.musicLiveActivityEnabled && !standardControlsSuppressed,
                key: .musicControlWindowEnabled
            )
            I.songOnExternal.toggle(
                "Show the title and artist next to the pill on screens without a notch.",
                key: .showSongMetadataInClosedNotch
            )
            I.inactivityTimeout.slider(
                "How long to keep the player after playback stops.",
                key: .waitInterval,
                range: 0...10,
                step: 1,
                valueLabel: { "\(Int($0)) s" }
            )
            I.hideInFullscreen.picker(
                "Get out of the way of full screen apps.",
                selection: $hideNotchOption,
                options: [.nowPlayingOnly, .always, .never],
                label: Self.hideOptionLabel(_:)
            )
            .onChange(of: hideNotchOption) {
                Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
            }
        }
    }

    static func hideOptionLabel(_ option: HideNotchOption) -> String {
        switch option {
        case .always: return String(localized: "Always in full screen")
        case .nowPlayingOnly: return String(localized: "Only for the playing app")
        case .never: return String(localized: "Never")
        }
    }

    // MARK: Controls

    private var controlsCard: some View {
        NotchlySettingsCard(
            "Controls",
            footer: "Skip behavior applies everywhere the transport controls appear: the notch player and the floating controls."
        ) {
            I.skipButtons.picker(
                musicSkipBehavior.description,
                key: .musicSkipBehavior,
                options: Array(MusicSkipBehavior.allCases),
                label: { $0.displayName }
            )
            I.customControls.toggle(
                "Rearrange the media buttons into slots you choose.",
                key: .showShuffleAndRepeat
            )
            if showShuffleAndRepeat {
                I.mediaOutput.toggle(
                    "Adds the AirPlay route picker to the palette of controls.",
                    key: .showMediaOutputControl
                )
                MusicSlotConfigurationView()
            }
        }
    }

    // MARK: Sneak peek

    private var sneakPeekCard: some View {
        NotchlySettingsCard(
            "Sneak peek",
            footer: "A quick look at the title and artist under the notch for a few seconds."
        ) {
            I.sneakPeek.toggle("Show the track briefly under the notch.", key: .enableSneakPeek)
            I.sneakPeekOnChange.toggle(
                "Also when you play, pause or skip.",
                isEnabled: enableSneakPeek,
                key: .showSneakPeekOnTrackChange
            )
            I.sneakPeekStyle.picker(
                sneakPeekStyles == .inline ? "Slides out beside the notch." : "Drops down under the notch.",
                isEnabled: enableSneakPeek,
                key: .sneakPeekStyles,
                options: SneakPeekStyle.allCases,
                style: .segmented,
                label: { $0.localizedName }
            )
        }
    }

    // MARK: Lyrics

    private var lyricsCard: some View {
        NotchlySettingsCard(
            "Lyrics",
            footer: lyricsFooter
        ) {
            I.lyrics.toggle(
                lyricsAvailable
                    ? "Synced lyrics for the song that is playing."
                    : (enableMinimalisticUI ? "Turn off Minimalistic UI to use lyrics." : "Turn on the music player (Home & Hub) to use lyrics."),
                isEnabled: lyricsAvailable,
                key: .enableLyrics
            )
            if enableLyrics && lyricsAvailable {
                I.lyricHighlight.picker(
                    lyricHighlightStyle.explanation,
                    key: .lyricHighlightStyle,
                    options: Array(LyricHighlightStyle.allCases),
                    label: { $0.localizedName }
                )
                I.pinLyrics.toggle(
                    "Show timed lyrics under the closed notch. Also on the pin in the lyrics panel.",
                    key: .pinLyricsWhenClosed
                )
                I.pinnedContext.picker(
                    "How many lines to show.",
                    isEnabled: pinLyricsWhenClosed,
                    key: .pinnedLyricContext,
                    options: Array(PinnedLyricContext.allCases),
                    style: .segmented,
                    label: { $0.localizedName }
                )
                if !enableHub {
                    I.lyricsWidth.slider(
                        "Width of the lyrics panel beside the player.",
                        value: doubleBinding($lyricsPanelWidth),
                        range: 180...420,
                        step: 10,
                        valueLabel: { "\(Int($0)) px" }
                    )
                    I.lyricsOffset.slider(
                        "Nudge the panel left or right.",
                        value: doubleBinding($lyricsPanelOffset),
                        range: -100...100,
                        step: 1,
                        valueLabel: { "\($0 >= 0 ? "+" : "")\(Int($0)) px" }
                    )
                }
            }
        }
    }

    private func doubleBinding(_ binding: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(binding.wrappedValue) }, set: { binding.wrappedValue = CGFloat($0) })
    }

    private var lyricsFooter: String {
        enableHub
            ? "Lyrics sit on one line under the artist name because the Hub is using the rest of the notch. Turn the Hub off to give them a panel beside the player."
            : "Lyrics get their own panel beside the player. Turn the Hub on to move them under the artist name instead."
    }

    // MARK: Artwork

    private var artworkCard: some View {
        NotchlySettingsCard("Artwork") {
            I.liveCanvas.toggle(
                "Use the moving Canvas instead of the cover when the app provides one, and for the glow around it.",
                key: .showLiveCanvasInDynamicIsland
            )
            I.parallax.slider(
                "How far the cover moves as you move the pointer.",
                key: .parallaxEffectIntensity,
                range: 0...12,
                step: 1,
                valueLabel: { "\(Int($0))" }
            )
        }
    }

    // MARK: Visualizer

    private var visualizerCard: some View {
        NotchlySettingsCard(
            "Visualizer",
            footer: "The real-time waveform shows live audio from your Mac. Needs macOS 14.2 or later and uses very little CPU and GPU."
        ) {
            I.realTimeWaveform.toggle("Bars that follow the audio instead of a loop. Beta.", key: .enableRealTimeWaveform)
            I.barCount.picker(
                "How many bars to draw.",
                key: .visualizerBarCount,
                options: [4, 5, 6],
                style: .segmented,
                label: { "\($0)" }
            )
            I.colorExtraction.picker(
                "How the accent color is picked from the cover.",
                key: .colorExtractionMode,
                options: [.vibrant, .legacy],
                style: .segmented,
                label: { $0 == .vibrant ? String(localized: "Vibrant") : String(localized: "Legacy") }
            )
            I.waveformScrubber.toggle("Drag along the waveform to seek.", key: .enableWaveformScrubber)
        }
    }
}

// MARK: - Source picker

private struct MusicSourceSelector: View {
    @Binding var selection: MediaControllerType
    let controllers: [MediaControllerType]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(controllers) { controller in
                        MusicSourceCard(controller: controller, isSelected: selection == controller) {
                            withAnimation(NotchlyTheme.Motion.snappy) { selection = controller }
                        }
                        .id(controller)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) { _, controller in
                withAnimation(NotchlyTheme.Motion.snappy) { proxy.scrollTo(controller, anchor: .center) }
            }
        }
        .frame(height: 104)
    }
}

private struct MusicSourceCard: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                // Every source shows the app's own icon; the bundled logo is
                // the fallback for when the app is not installed.
                AppIconImage(
                    bundleIdentifiers: controller.applicationBundleIdentifiers,
                    assetFallback: controller.officialLogoAssetName,
                    symbolFallback: controller.fallbackSymbol,
                    symbolColor: controller.fallbackColor,
                    size: 38
                )
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 38, height: 38)

                Text(controller.localizedName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 108, height: 88)
            .background {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                    .fill(isSelected || isHovering ? NotchlySettingsStyle.controlFillHover : NotchlySettingsStyle.controlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? NotchlySettingsStyle.accent : NotchlySettingsStyle.cardStroke,
                        lineWidth: isSelected ? 2 : NotchlyTheme.Stroke.hairline
                    )
            }
            .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .accessibilityLabel(controller.localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension MediaControllerType {
    var officialLogoAssetName: String? {
        switch self {
        case .youtubeMusic: return "YouTubeMusicLogo"
        case .amazonMusic: return "AmazonMusicLogo"
        case .tidal: return "TidalLogo"
        case .cider: return "CiderLogo"
        default: return nil
        }
    }

    var applicationBundleIdentifiers: [String] {
        switch self {
        case .nowPlaying: return []
        case .appleMusic: return ["com.apple.Music"]
        case .spotify: return ["com.spotify.client"]
        case .youtubeMusic: return ["com.github.th-ch.youtube-music"]
        case .amazonMusic: return ["com.amazon.music"]
        case .tidal: return [TidalController.bundleIdentifier]
        case .cider: return ["sh.cider.genten.mac"]
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .nowPlaying: return "waveform"
        case .appleMusic: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .youtubeMusic: return "play.rectangle.fill"
        case .amazonMusic: return "music.note.list"
        case .tidal: return "waveform.path"
        case .cider: return "cup.and.saucer.fill"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .nowPlaying: return NotchlySettingsStyle.accent
        case .appleMusic: return .pink
        case .spotify: return .green
        case .youtubeMusic: return .red
        case .amazonMusic: return .cyan
        case .tidal: return .primary
        case .cider: return .orange
        }
    }
}

// MARK: - Search items

extension NotchlyMusicPage {
    enum Item {
        static let source = NotchlySettingItem(.music, "Music Source", keywords: ["media source", "controller", "apple music", "spotify", "tidal", "cider", "youtube music", "amazon music", "now playing"])
        static let liveActivity = NotchlySettingItem(.music, "Music live activity", keywords: ["music", "now playing", "closed notch", "live activity"])
        static let floatingControls = NotchlySettingItem(.music, "Floating media controls", keywords: ["play pause", "skip", "beside notch", "window"])
        static let songOnExternal = NotchlySettingItem(.music, "Song title and artist on non-notch displays", keywords: ["closed notch", "metadata", "external", "pill", "title", "artist"])
        static let inactivityTimeout = NotchlySettingItem(.music, "Media inactivity timeout", keywords: ["wait", "seconds", "idle", "timeout", "inactive"])
        static let hideInFullscreen = NotchlySettingItem(.music, "Hide in full screen", keywords: ["fullscreen", "full screen", "hide notch", "video", "options"])
        static let skipButtons = NotchlySettingItem(.music, "Skip buttons", keywords: ["skip", "controls", "±10", "ten seconds", "track skip", "behavior"])
        static let customControls = NotchlySettingItem(.music, "Customizable controls", keywords: ["controls", "slots", "layout", "shuffle", "repeat", "palette", "rearrange"])
        static let mediaOutput = NotchlySettingItem(.music, "Change Media Output control", keywords: ["airplay", "route picker", "media output"], anchoredTo: customControls)
        static let sneakPeek = NotchlySettingItem(.music, "Sneak peek", keywords: ["sneak peek", "preview", "title", "artist"])
        static let sneakPeekOnChange = NotchlySettingItem(.music, "Sneak peek on playback changes", keywords: ["sneak peek", "play", "pause", "track change"])
        static let sneakPeekStyle = NotchlySettingItem(.music, "Sneak peek style", keywords: ["sneak peek", "inline", "standard", "default", "style"])
        static let lyrics = NotchlySettingItem(.music, "Show lyrics", keywords: ["lyrics", "song text", "side panel", "hub", "inline"])
        static let lyricHighlight = NotchlySettingItem(.music, "Lyric highlight", keywords: ["lyrics", "highlight", "sweep", "gradient", "solid", "karaoke", "animation"], anchoredTo: lyrics)
        static let pinLyrics = NotchlySettingItem(.music, "Keep lyrics under the closed notch", keywords: ["lyrics", "pin", "pinned", "closed notch", "always show"], anchoredTo: lyrics)
        static let pinnedContext = NotchlySettingItem(.music, "Pinned lyric context", keywords: ["pinned lyrics", "lyric context", "lyrics lines", "closed notch", "lyrics height"], anchoredTo: lyrics)
        static let lyricsWidth = NotchlySettingItem(.music, "Side lyrics width", keywords: ["lyrics", "width", "panel"], anchoredTo: lyrics)
        static let lyricsOffset = NotchlySettingItem(.music, "Side lyrics horizontal offset", keywords: ["lyrics", "offset", "panel", "position"], anchoredTo: lyrics)
        static let liveCanvas = NotchlySettingItem(.music, "Show live canvas in Notchly", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"])
        static let parallax = NotchlySettingItem(.music, "Album art parallax effect", keywords: ["parallax", "parallax effect", "album art", "artwork", "intensity"])
        static let realTimeWaveform = NotchlySettingItem(.music, "Real-time waveform", keywords: ["visualizer", "audio", "spectrum", "waveform", "beta"])
        static let barCount = NotchlySettingItem(.music, "Visualizer bars", keywords: ["visualizer", "candles", "bars", "count"])
        static let colorExtraction = NotchlySettingItem(.music, "Color extraction", keywords: ["colour", "color", "vibrant", "legacy", "album art", "accent"])
        static let spotifySignIn = NotchlySettingItem(.music, "Spotify sign in", keywords: ["spotify", "canvas", "sp_dc", "cookie", "login", "session"], anchoredTo: source)
        static let spotifyLike = NotchlySettingItem(.music, "Spotify like button", keywords: ["spotify", "like", "liked songs", "client id", "developer", "oauth"], anchoredTo: source)
        static let ciderToken = NotchlySettingItem(.music, "Cider favorite song token", keywords: ["cider", "favorite", "favourite", "api token"], anchoredTo: source)
        static let waveformScrubber = NotchlySettingItem(.music, "Scrubbable waveform", keywords: ["scrub", "seek", "waveform", "visualizer"])
    }

    static let items: [NotchlySettingItem] = [
        Item.source, Item.spotifySignIn, Item.spotifyLike, Item.ciderToken,
        Item.liveActivity, Item.floatingControls, Item.songOnExternal, Item.inactivityTimeout, Item.hideInFullscreen,
        Item.skipButtons, Item.customControls, Item.mediaOutput,
        Item.sneakPeek, Item.sneakPeekOnChange, Item.sneakPeekStyle,
        Item.lyrics, Item.lyricHighlight, Item.pinLyrics, Item.pinnedContext, Item.lyricsWidth, Item.lyricsOffset,
        Item.liveCanvas, Item.parallax,
        Item.realTimeWaveform, Item.barCount, Item.colorExtraction, Item.waveformScrubber,
    ]
}
