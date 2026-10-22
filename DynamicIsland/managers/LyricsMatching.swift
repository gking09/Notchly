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

// MARK: - Text

/// Folding that makes two spellings of the same name comparable.
///
/// Players and catalogues disagree on small things: Apple Music writes
/// "Don’t Stop Believin’" with curly quotes where LRCLIB has straight ones,
/// Spotify writes "Beyoncé" and a tag editor wrote "Beyonce", a full-width
/// "Ｌｏｖｅ" is the same word as "Love". None of these may decide whether a
/// row is the song that is playing.
enum LyricsText {

    /// The name with typographic variants replaced by their plain forms, and
    /// nothing else changed. Safe to send to a catalogue.
    static func canonical(_ value: String) -> String {
        var text = value.precomposedStringWithCompatibilityMapping
        let replacements: [(String, String)] = [
            ("\u{2018}", "'"), ("\u{2019}", "'"), ("\u{201A}", "'"), ("\u{201B}", "'"), ("\u{02BC}", "'"), ("\u{2032}", "'"),
            ("\u{201C}", "\""), ("\u{201D}", "\""), ("\u{201E}", "\""), ("\u{00AB}", "\""), ("\u{00BB}", "\""),
            ("\u{2010}", "-"), ("\u{2011}", "-"), ("\u{2012}", "-"), ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2015}", "-"),
            ("\u{2026}", "..."), ("\u{00A0}", " "), ("\u{200B}", "")
        ]
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        return collapseWhitespace(text)
    }

    /// The form two names are compared in: canonical, accents removed,
    /// lowercase, "&" read as "and", apostrophes dropped, other punctuation
    /// turned into spaces, and a leading "The" ignored.
    static func comparable(_ value: String) -> String {
        var text = canonical(value)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: "'", with: "")
        let mapped = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
                || CharacterSet.nonBaseCharacters.contains(scalar)
                ? Character(scalar) : " "
        }
        text = collapseWhitespace(String(mapped))
        if text.hasPrefix("the ") { text.removeFirst(4) }
        return text
    }

    static func tokens(_ value: String) -> [String] {
        comparable(value).split(separator: " ").map(String.init)
    }

    static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A title cut after a quoted subtitle ends up with one quote left over
    /// (`Love Theme from "Titanic`), which lrclib answers with 400. An odd
    /// number of double quotes means one is stray; they are all dropped.
    static func balancingQuotes(_ value: String) -> String {
        guard value.filter({ $0 == "\"" }).count % 2 == 1 else { return value }
        return collapseWhitespace(value.replacingOccurrences(of: "\"", with: ""))
    }

    /// Every (...) and [...] group removed, unlike the cleaner, which keeps the
    /// ones that name the song. Used as a *retry* form of a title.
    static func removingBrackets(_ value: String) -> String {
        let stripped = value.replacingOccurrences(
            of: "\\s*[\\(\\[][^\\)\\]]*[\\)\\]]", with: "", options: .regularExpression
        )
        return collapseWhitespace(stripped)
    }

    /// The part of a title before " - ": Spotify writes "Song - Remastered 2011",
    /// "Song - From \"Movie\"" and "Song - Radio Edit" where Apple Music writes
    /// brackets, and nothing catalogued has the suffix.
    static func removingDashSuffix(_ value: String) -> String {
        for separator in [" - ", " – ", " — "] {
            if let range = value.range(of: separator) {
                let head = String(value[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !head.isEmpty { return head }
            }
        }
        return value
    }
}

// MARK: - Artists

enum LyricsArtistNames {

    /// The performers a player's artist field names. Spotify joins them with
    /// ", ", Apple Music with " & ", NetEase with "/", and a title may add
    /// "feat." ones; LRCLIB files the song under one of them, or under all.
    static func performers(_ raw: String) -> [String] {
        let separators = "\\s*(?:,|;|\\s/\\s|\\s&\\s|\\sx\\s|\\s×\\s|\\s+(?:feat\\.?|ft\\.?|featuring|with|and)\\s+)\\s*"
        let canonical = LyricsText.canonical(raw)
        guard let regex = try? NSRegularExpression(pattern: separators, options: .caseInsensitive) else { return [canonical] }
        let ns = canonical as NSString
        var parts: [String] = []
        var last = 0
        for match in regex.matches(in: canonical, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: last, length: match.range.location - last)))
            last = match.range.location + match.range.length
        }
        parts.append(ns.substring(from: last))
        let cleaned = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap(splitUnspacedSlash)
        return cleaned.isEmpty ? [canonical] : cleaned
    }

    /// NetEase joins collaborators as "A/B", but "AC/DC" is one band: an unspaced
    /// slash separates only when every side is four characters or more, or the
    /// names are not in Latin script (where three characters is a whole name).
    private static func splitUnspacedSlash(_ part: String) -> [String] {
        let pieces = part.components(separatedBy: "/")
        let trimmed = pieces.map { $0.trimmingCharacters(in: .whitespaces) }
        let wideEnough = trimmed.allSatisfy { $0.count >= 4 }
        let nonLatin = trimmed.contains { $0.unicodeScalars.contains { $0.value > 0x2FF } }
        guard pieces.count > 1, wideEnough || nonLatin else { return [part] }
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The first performer, when the field names several.
    static func primary(_ raw: String) -> String {
        performers(raw).first ?? raw
    }

    /// Whether a catalogue's artist field names the requested artist: the
    /// whole strings agree, or any performer on one side agrees with any on the
    /// other. "Post Malone, Swae Lee" agrees with "Post Malone".
    static func agree(request: String, row: String) -> Bool {
        let whole = (LyricsText.comparable(request), LyricsText.comparable(row))
        guard !whole.0.isEmpty, !whole.1.isEmpty else { return false }
        if whole.0 == whole.1 || contains(whole.0, whole.1) || contains(whole.1, whole.0) { return true }
        let lhs = performers(request).map(LyricsText.comparable).filter { !$0.isEmpty }
        let rhs = performers(row).map(LyricsText.comparable).filter { !$0.isEmpty }
        return lhs.contains { left in rhs.contains { right in left == right || contains(left, right) || contains(right, left) } }
    }

    /// Both artists name exactly the same thing.
    static func exact(request: String, row: String) -> Bool {
        let lhs = LyricsText.comparable(request)
        return !lhs.isEmpty && lhs == LyricsText.comparable(row)
    }

    /// Containment on word boundaries, so "ann" is not in "joanne".
    fileprivate static func contains(_ haystack: String, _ needle: String) -> Bool {
        guard !needle.isEmpty, !haystack.isEmpty else { return false }
        return (" " + haystack + " ").contains(" " + needle + " ")
    }
}

// MARK: - Query variants

/// The ordered artist/title pairs to look a track up with.
///
/// The cleaner's own queries come first -- they know about video titles and
/// channels. Each is then widened the way real metadata goes wrong:
///
/// * the title with every bracketed group removed ("Song (Radio Edit)");
/// * the title with a Spotify-style " - suffix" removed ("Song - Remastered 2011",
///   "Song - From \"Movie\"");
/// * the first performer alone, because "A, B" and "A & B" are filed under one
///   of them far more often than under the joined string;
/// * the name without a leading "The".
enum LyricsQueryPlanner {

    static let maximumVariants = 5

    static func variants(title: String, artist: String, isWebSource: Bool) -> [LyricsQuery] {
        let base = LyricsQueryCleaner.queries(title: title, artist: artist, isWebSource: isWebSource)
        return expand(base)
    }

    static func expand(_ base: [LyricsQuery]) -> [LyricsQuery] {
        var ordered: [LyricsQuery] = []
        var seen = Set<String>()

        func add(_ artist: String, _ title: String) {
            let artist = LyricsText.canonical(artist)
            let title = LyricsText.balancingQuotes(LyricsText.canonical(title))
            let query = LyricsQuery(artist: artist, title: title)
            guard query.isUsable, ordered.count < maximumVariants else { return }
            // Spelling-level key: "The Weeknd" and "Weeknd" are different requests
            // even though they compare equal.
            func literal(_ value: String) -> String {
                value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            }
            let key = literal(artist) + "\u{1F}" + literal(title)
            if seen.insert(key).inserted { ordered.append(query) }
        }

        for query in base.prefix(2) {
            let artists = artistForms(query.artist)
            let titles = titleForms(query.title)
            // The title as cleaned, under each artist form; then the stripped
            // titles under the full artist and the first performer.
            for artist in artists { add(artist, titles[0]) }
            for title in titles.dropFirst() {
                for artist in artists.prefix(2) { add(artist, title) }
            }
        }
        return ordered
    }

    /// Full artist, first performer, then the first without "The".
    static func artistForms(_ artist: String) -> [String] {
        var forms = [artist]
        let first = LyricsArtistNames.primary(artist)
        if LyricsText.comparable(first) != LyricsText.comparable(artist) { forms.append(first) }
        for form in forms where form.lowercased().hasPrefix("the ") {
            forms.append(String(form.dropFirst(4)))
            break
        }
        return forms
    }

    /// The title, then progressively barer forms of it.
    static func titleForms(_ title: String) -> [String] {
        var forms = [title]
        func append(_ candidate: String) {
            let trimmed = LyricsText.collapseWhitespace(candidate).trimmingCharacters(in: CharacterSet(charactersIn: " -–—"))
            guard !trimmed.isEmpty,
                  !forms.contains(where: { LyricsText.comparable($0) == LyricsText.comparable(trimmed) })
            else { return }
            forms.append(trimmed)
        }
        append(LyricsText.removingBrackets(title))
        append(LyricsText.removingDashSuffix(title))
        append(LyricsText.removingDashSuffix(LyricsText.removingBrackets(title)))
        return forms
    }
}

// MARK: - Candidate selection

/// What is being looked for, as far as ranking rows is concerned.
struct LyricsMatchRequest {
    /// Every acceptable spelling of the title (the variants being tried).
    var titles: [String]
    /// The title as the player wrote it, for version markers ("Remix").
    var originalTitle: String
    var artists: [String]
    var album: String = ""
    /// Seconds; zero when the player does not report one.
    var duration: TimeInterval = 0
    /// How far a synced row's length may sit from the track's.
    var tolerance: TimeInterval = LyricsCandidateSelector.defaultTolerance
}

/// The row chosen, and how it should be used.
struct LyricsSelection {
    enum Kind: Equatable {
        /// Timed lyrics from a row whose length agrees with the track's.
        case synced
        /// Words without timings.
        case plain
        case instrumental
        /// Timed lyrics of a different length. Their timings are wrong for this
        /// recording, so only the words are used.
        case syncedOffLength
    }

    let row: [String: Any]
    let kind: Kind
    /// |row length - track length|, nil when either is unknown.
    let durationDelta: TimeInterval?
    let score: Double
}

/// Picks the best row out of everything LRCLIB returned.
///
/// LRCLIB holds many rows per recording (fifteen is ordinary for a hit): other
/// masters, other edits, with and without timings. `search` returns at most
/// twenty of them in no useful order, and the first row that agrees on the
/// names is not the one whose timings fit. So rows are filtered to candidates
/// first, then synced beats plain, then the one whose length is *closest* to
/// the playing track's wins -- a master three seconds longer has every line
/// about three seconds out.
enum LyricsCandidateSelector {

    static let defaultTolerance: TimeInterval = 4

    static func select(rows: [[String: Any]], request: LyricsMatchRequest) -> LyricsSelection? {
        let candidates = rows.compactMap { candidate(for: $0, request: request) }
        guard !candidates.isEmpty else { return nil }

        let synced = candidates.filter { $0.hasSynced && $0.withinTolerance }
        if let best = synced.max(by: { $0.score < $1.score }) {
            return LyricsSelection(row: best.row, kind: .synced, durationDelta: best.delta, score: best.score)
        }

        let rest = candidates.filter { $0.isInstrumental || $0.hasPlain }
        if let best = rest.max(by: { $0.score < $1.score }) {
            return LyricsSelection(
                row: best.row,
                kind: best.isInstrumental ? .instrumental : .plain,
                durationDelta: best.delta,
                score: best.score
            )
        }

        let offLength = candidates.filter { $0.hasSynced }
        if let best = offLength.max(by: { $0.score < $1.score }) {
            return LyricsSelection(row: best.row, kind: .syncedOffLength, durationDelta: best.delta, score: best.score)
        }
        return nil
    }

    // MARK: Candidates

    private struct Candidate {
        let row: [String: Any]
        let hasSynced: Bool
        let hasPlain: Bool
        let isInstrumental: Bool
        let delta: TimeInterval?
        let withinTolerance: Bool
        let score: Double
    }

    private static func candidate(for row: [String: Any], request: LyricsMatchRequest) -> Candidate? {
        let rowTitle = (row["trackName"] as? String) ?? (row["name"] as? String) ?? ""
        let rowArtist = (row["artistName"] as? String) ?? ""
        guard let titleQuality = titleQuality(rowTitle, request: request),
              request.artists.contains(where: { LyricsArtistNames.agree(request: $0, row: rowArtist) })
        else { return nil }

        let comparableRowTitle = LyricsText.comparable(rowTitle)
        if LyricsSearchResults.carriesUnrequestedVersion(comparableRowTitle, requested: LyricsText.comparable(request.originalTitle)) {
            return nil
        }

        let rowDuration = (row["duration"] as? Double) ?? 0
        let delta: TimeInterval? = rowDuration > 0 && request.duration > 0 && rowDuration.isFinite && request.duration.isFinite
            ? abs(rowDuration - request.duration) : nil

        let isInstrumental = row["instrumental"] as? Bool == true
        if isInstrumental {
            // An instrumental flag ends the search, so it has to be earned: an
            // exact title and a length that agrees to rounding.
            guard titleQuality == 2, delta.map({ $0 <= 2 }) ?? true else { return nil }
        }

        let artistQuality = request.artists.contains { LyricsArtistNames.exact(request: $0, row: rowArtist) } ? 2.0 : 1.0
        var albumQuality = 0.0
        let album = LyricsText.comparable(request.album)
        let rowAlbum = LyricsText.comparable((row["albumName"] as? String) ?? "")
        if !album.isEmpty, !rowAlbum.isEmpty {
            albumQuality = album == rowAlbum ? 1 : (rowAlbum.contains(album) || album.contains(rowAlbum) ? 0.5 : 0)
        }

        let tolerance = max(request.tolerance, 0)
        let effectiveDelta = delta ?? tolerance / 2
        // Names count for more than a second of length; a second of length
        // counts for more than the album.
        let score = Double(titleQuality) * 10 + artistQuality * 4 + albumQuality * 2 - min(effectiveDelta, 60) * 4

        return Candidate(
            row: row,
            hasSynced: LyricsSearchResults.carriesSyncedLyrics(row) && !isInstrumental,
            hasPlain: !((row["plainLyrics"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isInstrumental,
            isInstrumental: isInstrumental,
            delta: delta,
            withinTolerance: delta.map { $0 <= tolerance } ?? true,
            score: score
        )
    }

    /// 2 when a title agrees exactly (after dropping brackets and a dash
    /// suffix from either side), 1 when one contains the other as whole words
    /// and is not much shorter, nil when they disagree.
    static func titleQuality(_ rowTitle: String, request: LyricsMatchRequest) -> Int? {
        let rowForms = LyricsQueryPlanner.titleForms(LyricsText.canonical(rowTitle)).map(LyricsText.comparable)
        var best: Int?
        for requested in request.titles {
            let forms = LyricsQueryPlanner.titleForms(LyricsText.canonical(requested)).map(LyricsText.comparable)
            for lhs in forms where !lhs.isEmpty {
                for rhs in rowForms where !rhs.isEmpty {
                    if lhs == rhs { return 2 }
                    if wordsContain(lhs, rhs) || wordsContain(rhs, lhs) { best = 1 }
                }
            }
        }
        return best
    }

    /// Whole-word containment where the shorter side is at least half the
    /// longer, so "Hurt" does not agree with "Hurt Me Tomorrow Forever Today".
    private static func wordsContain(_ lhs: String, _ rhs: String) -> Bool {
        let (longer, shorter) = lhs.count >= rhs.count ? (lhs, rhs) : (rhs, lhs)
        guard LyricsArtistNames.contains(longer, shorter) else { return false }
        let longWords = longer.split(separator: " ").count
        let shortWords = shorter.split(separator: " ").count
        return shortWords * 2 >= longWords
    }
}
