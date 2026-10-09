/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// One artist + title pair to look lyrics up with.
struct LyricsQuery: Hashable, Sendable {
    let artist: String
    let title: String

    var isUsable: Bool {
        !artist.isEmpty && !title.isEmpty
            && !LyricsMetadata.namesNoParticularTrack(title: title, artist: artist)
    }
}

/// Turns the metadata a player publishes into search terms a lyrics catalogue
/// will recognise.
///
/// Music apps publish clean tags. A browser playing YouTube publishes the
/// *video* title and the *channel* name instead: "Rick Astley - Never Gonna Give
/// You Up (Official Music Video)" by "RickAstleyVEVO", or "Blinding Lights" by
/// "The Weeknd - Topic". None of that matches a lyrics row as it stands, so the
/// noise is stripped, the "Artist - Title" convention is split, and channel
/// suffixes are dropped. Pure and deterministic, so it is unit tested.
enum LyricsQueryCleaner {

    // MARK: Sources

    /// Browsers whose Now Playing entry is a web page (YouTube, SoundCloud...).
    private static let browserBundlePrefixes: [String] = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "org.chromium.Chromium",
        "company.thebrowser", "com.microsoft.edgemac", "org.mozilla.firefox",
        "com.brave.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "app.zen-browser.zen", "com.kagi.kagimacOS", "com.sigmaos.sigmaos",
        "net.imput.helium", "ai.perplexity.comet", "com.openai.atlas"
    ]

    static func isWebSource(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return browserBundlePrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }

    // MARK: Matching tolerance

    /// How far a catalogue row's length may sit from the playing track's and
    /// still count as the same recording. A music video often carries an intro
    /// or outro the album track does not, so web sources get more slack.
    static func durationTolerance(isWebSource: Bool) -> TimeInterval {
        isWebSource ? 15 : 3
    }

    /// Whether two durations plausibly belong to one recording. Zero on either
    /// side means "not reported", which never rules a row out.
    static func durationsAgree(_ lhs: TimeInterval, _ rhs: TimeInterval, tolerance: TimeInterval) -> Bool {
        guard lhs > 0, rhs > 0, lhs.isFinite, rhs.isFinite else { return true }
        return abs(lhs - rhs) <= tolerance
    }

    // MARK: Queries

    /// Search terms to try, best first, de-duplicated and never empty-fielded.
    static func queries(title rawTitle: String, artist rawArtist: String, isWebSource: Bool = false) -> [LyricsQuery] {
        let title = collapseWhitespace(rawTitle)
        let artist = collapseWhitespace(rawArtist)
        var candidates: [LyricsQuery] = []

        let channel = cleanArtist(artist)
        let channelLooksLikeChannel = looksLikeChannel(artist)
        let cleanedTitle = cleanTitle(title, aggressive: isWebSource || channelLooksLikeChannel)

        var didSplit = false
        // "Artist - Title" in the title field. Split it when the artist field
        // is empty, is a channel rather than a person, already appears on one
        // side, or the source is a web page (where this is the convention).
        if let split = splitArtistTitle(cleanedTitle) {
            let left = cleanArtist(split.artist)
            let right = cleanTitle(split.title, aggressive: true)
            let leftMatchesArtist = !channel.isEmpty && overlaps(normalized(left), normalized(channel))
            let rightMatchesArtist = !channel.isEmpty && !leftMatchesArtist
                && normalized(cleanArtist(split.title)) == normalized(channel)
            if rightMatchesArtist {
                // "Hurt - Johnny Cash" by Johnny Cash: written the other way round.
                candidates.append(LyricsQuery(artist: channel, title: cleanTitle(split.artist, aggressive: true)))
                didSplit = true
            } else if channel.isEmpty || channelLooksLikeChannel || leftMatchesArtist || isWebSource {
                candidates.append(LyricsQuery(artist: left, title: right))
                if !channel.isEmpty, !leftMatchesArtist, !channelLooksLikeChannel {
                    // A performer's own upload titled "Song - Version" by "Band".
                    candidates.append(LyricsQuery(artist: channel, title: right))
                }
                didSplit = true
            }
        } else if let quoted = splitQuotedTitle(normalizeBrackets(stripEmoji(title))),
                  channel.isEmpty || channelLooksLikeChannel || isWebSource {
            // K-pop and J-pop uploads: BTS (방탄소년단) 'Dynamite' Official MV,
            // YOASOBI「アイドル」 Official Music Video.
            candidates.append(LyricsQuery(artist: quoted.artist, title: quoted.title))
            if !channel.isEmpty, !channelLooksLikeChannel {
                candidates.append(LyricsQuery(artist: channel, title: quoted.title))
            }
            didSplit = true
        }

        // Unsplit forms only when no split was trusted: once the title has
        // been read as "Artist - Title", asking for the whole string again
        // just spends a request on something no catalogue holds.
        if !didSplit {
            candidates.append(LyricsQuery(artist: channel, title: cleanedTitle))
            if channel != artist, !channelLooksLikeChannel {
                candidates.append(LyricsQuery(artist: artist, title: cleanedTitle))
            }
        }

        var seen = Set<String>()
        return candidates.filter { query in
            guard query.isUsable else { return false }
            return seen.insert(normalized(query.artist) + "\u{1F}" + normalized(query.title)).inserted
        }
    }

    // MARK: Titles

    /// Marks a bracketed group as packaging rather than part of the song's
    /// name. Matched on word boundaries, so "(Defeated)" is not a "feat".
    private static let noiseGroupPattern = "\\b(official|video|audio|lyrics?|letra|visuali[sz]er|m/?v|hd|hq|4k|8k|1080p|720p|60fps|explicit|clean version|videoclip|clip officiel|remaster(ed)?|full song|colou?r coded|eng sub|sub espa\u{00F1}ol|subtitulado|out now|premiere|animated|performance video|live session|directed by|shot by|feat\\.?|ft\\.?|featuring)\\b|^\\s*(with|prod\\.?|prod by|produced by|dir\\.?)\\b|^\\s*(19|20)\\d{2}\\s*(remaster(ed)?)?\\s*$|^\\s*(live|mono|stereo)\\b"

    /// Unbracketed packaging at the end of a title, after a separator or not.
    private static let trailingNoisePatterns: [String] = [
        "\\s*[-–—|:]?\\s*(official\\s+)?(music\\s+|lyrics?\\s+|audio\\s+|hd\\s+|4k\\s+)?(video|audio|visuali[sz]er)(\\s+oficial)?\\s*$",
        "\\s*[-–—|:]?\\s*official\\s*$",
        "\\s*[-–—|:]?\\s*(official\\s+)?(music\\s+)?m/?v\\s*$",
        "\\s*[-–—|:]?\\s*(with\\s+)?lyrics\\s*$",
        "\\s*[-–—|:]?\\s*\\b(hd|hq|4k|8k|1080p|720p)\\b\\s*$",
        "\\s*[-–—|:]?\\s*(video|audio)\\s+oficial\\s*$"
    ]

    /// Strips video packaging, featured artists and version noise from a title.
    /// `aggressive` also removes trailing "Lyrics"/"HD" words and "| channel"
    /// tails, which only ever come from video titles.
    static func cleanTitle(_ raw: String, aggressive: Bool = true) -> String {
        var title = stripEmoji(collapseWhitespace(raw))

        title = normalizeBrackets(title)

        if aggressive {
            // "Title | Official Video" / "Artist - Title | Channel": the first
            // segment carries the song.
            for separator in [" | ", " // ", " ｜ "] {
                if let range = title.range(of: separator) {
                    let head = String(title[..<range.lowerBound])
                    if !head.trimmingCharacters(in: .whitespaces).isEmpty { title = head }
                }
            }
        }

        title = removeNoiseGroups(from: title)

        // Unbracketed featuring: "Title ft. Someone", "Title feat Someone".
        title = title.replacingOccurrences(
            of: "\\s+(feat\\.?|ft\\.?|featuring)\\s+.*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // Remaster / live / mono / stereo suffixes, bracketed or after a dash.
        title = title.replacingOccurrences(
            of: "\\s*[-–—]\\s*((\\d{4}\\s+)?remaster(ed)?(\\s+\\d{4})?(\\s+version)?|live|mono|stereo|single version|radio edit)\\s*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        if aggressive {
            var previous = ""
            while previous != title {
                previous = title
                for pattern in trailingNoisePatterns {
                    title = title.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
                }
            }
        }

        title = trimDecorations(title)
        // A title that was nothing but packaging is better left as it came.
        return title.isEmpty ? trimDecorations(collapseWhitespace(raw)) : title
    }

    /// Removes every (...) and [...] group whose contents are packaging. Groups
    /// that name the song ("(Don't Fear) The Reaper") or a version ("(Remix)")
    /// are kept.
    private static func removeNoiseGroups(from title: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\s*[\\(\\[]([^\\)\\]]*)[\\)\\]]") else { return title }
        var result = title
        let ns = title as NSString
        for match in regex.matches(in: title, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: match.range(at: 1)).lowercased()
            let isNoise = inner.range(of: noiseGroupPattern, options: .regularExpression) != nil
            if isNoise, let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: "")
            }
        }
        return collapseWhitespace(result)
    }

    // MARK: Artists

    /// Turns a channel name into an artist name: drops " - Topic", "VEVO",
    /// "Official" and featured artists, and splits a run-together VEVO name.
    static func cleanArtist(_ raw: String) -> String {
        var artist = stripEmoji(collapseWhitespace(raw))
        artist = artist.replacingOccurrences(of: "\\s*-\\s*topic\\s*$", with: "", options: [.regularExpression, .caseInsensitive])

        if artist.range(of: "vevo\\s*$", options: [.regularExpression, .caseInsensitive]) != nil {
            artist = artist.replacingOccurrences(of: "\\s*vevo\\s*$", with: "", options: [.regularExpression, .caseInsensitive])
            if !artist.contains(" ") { artist = splitCamelCase(artist) }
        }

        artist = artist.replacingOccurrences(
            of: "\\s*[-–]?\\s*(official(\\s+(channel|artist channel|youtube channel))?|music|tv)\\s*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        artist = artist.replacingOccurrences(
            of: "\\s+(feat\\.?|ft\\.?|featuring|with)\\s+.*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        artist = removeNoiseGroups(from: artist)
        let cleaned = trimDecorations(artist)
        return cleaned.isEmpty ? trimDecorations(collapseWhitespace(raw)) : cleaned
    }

    /// Whether an artist field is a YouTube channel rather than a performer.
    static func looksLikeChannel(_ artist: String) -> Bool {
        let lowered = artist.lowercased()
        return lowered.hasSuffix("vevo")
            || lowered.range(of: "-\\s*topic\\s*$", options: .regularExpression) != nil
            || lowered.hasSuffix(" official") || lowered.hasSuffix("official")
            || lowered.hasSuffix(" music") || lowered.hasSuffix(" records") || lowered.hasSuffix(" tv")
            || lowered.contains("lyrics") || lowered.contains("lyric")
    }

    /// "Artist - Title" (hyphen, en or em dash with spaces around it).
    static func splitArtistTitle(_ title: String) -> (artist: String, title: String)? {
        for separator in [" - ", " – ", " — ", " ~ "] {
            guard let range = title.range(of: separator) else { continue }
            let left = trimDecorations(String(title[..<range.lowerBound]))
            let right = trimDecorations(String(title[range.upperBound...]))
            guard !left.isEmpty, !right.isEmpty else { continue }
            return (left, right)
        }
        return nil
    }

    /// Fullwidth and CJK brackets used on Asian uploads, as ASCII.
    static func normalizeBrackets(_ value: String) -> String {
        value
            .replacingOccurrences(of: "【", with: "[").replacingOccurrences(of: "】", with: "]")
            .replacingOccurrences(of: "「", with: "\"").replacingOccurrences(of: "」", with: "\"")
            .replacingOccurrences(of: "『", with: "\"").replacingOccurrences(of: "』", with: "\"")
            .replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
    }

    /// `Artist 'Title'`, `Artist "Title"`, `Artist “Title”`, `Artist「Title」`.
    static func splitQuotedTitle(_ title: String) -> (artist: String, title: String)? {
        let pattern = "^(.+?)\\s*['\"“‘「]([^'\"”’」]+)['\"”’」]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = title as NSString
        guard let match = regex.firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var artist = ns.substring(with: match.range(at: 1))
        // A bracketed alias after the name ("BTS (방탄소년단)") is not part of it.
        artist = artist.replacingOccurrences(of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]\\s*$", with: "", options: .regularExpression)
        let song = trimDecorations(ns.substring(with: match.range(at: 2)))
        let name = cleanArtist(artist)
        guard !name.isEmpty, song.count >= 2 else { return nil }
        return (name, song)
    }

    // MARK: Helpers

    static func normalized(_ value: String) -> String {
        LyricsSearchResults.normalizedForMatching(collapseWhitespace(value))
    }

    private static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }

    static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops emoji and pictographs (🔥, ✨, ♪ decorations) but keeps letters in
    /// every script, digits and ordinary punctuation.
    static func stripEmoji(_ value: String) -> String {
        let kept = value.unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation { return false }
            if scalar.properties.isEmoji && scalar.value > 0x238C { return false }
            switch scalar.value {
            case 0xFE0F, 0x200D, 0x20E3: return false     // variation selector, ZWJ, keycap
            case 0x2600...0x27BF: return false            // misc symbols, dingbats
            case 0x266A, 0x266B, 0x266C: return false     // ♪ ♫ ♬
            default: return true
            }
        }
        return collapseWhitespace(String(String.UnicodeScalarView(kept)))
    }

    /// Trims separators, quotes and stray brackets left at either end.
    private static func trimDecorations(_ value: String) -> String {
        var result = collapseWhitespace(value)
        let edge = CharacterSet(charactersIn: " -–—|:~·•*\"'“”‘’«»")
        result = result.trimmingCharacters(in: edge)
        // An unmatched bracket at an end ("Title (" after a cut) is debris.
        while let last = result.last, "([{".contains(last) { result.removeLast() }
        while let first = result.first, ")]}".contains(first) { result.removeFirst() }
        return collapseWhitespace(result.trimmingCharacters(in: edge))
    }

    /// "RickAstley" -> "Rick Astley". Only splits lower->upper boundaries, so
    /// "AC/DC" and "ABBA" stay as they are.
    private static func splitCamelCase(_ value: String) -> String {
        var output = ""
        var previous: Character?
        for character in value {
            if let previous, previous.isLowercase, character.isUppercase { output.append(" ") }
            output.append(character)
            previous = character
        }
        return output
    }
}
