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

/// Network settings shared by the lyrics providers.
enum LyricsNetwork {
    /// LRCLIB asks clients to identify themselves.
    static let userAgent = "Notchly (https://github.com/Ebullioscopic/Atoll fork)"
    /// Upper bound on any single lyrics request.
    static let requestTimeout: TimeInterval = 8

    /// Ephemeral (no cookies, no URL cache: the disk cache below is ours) with
    /// short timeouts, so a slow catalogue never holds the lyrics view on
    /// "Searching…" for long.
    static func makeSession(userAgent: String?) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = requestTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        if let userAgent {
            configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        }
        return URLSession(configuration: configuration)
    }

    static let lrclibSession = makeSession(userAgent: userAgent)
    /// NetEase keeps the system user agent it has always been sent.
    static let neteaseSession = makeSession(userAgent: nil)
}

/// LRCLIB (lrclib.net), a free keyless catalogue of synced lyrics.
///
/// `/api/get` is asked first: it matches artist, title and duration exactly
/// (the server allows a couple of seconds either way), which is the most
/// reliable answer there is. When it has nothing, `/api/search` is ranked with
/// `LyricsSearchResults`, preferring rows whose length agrees with the track.
/// Only the artist, title and duration are ever sent.
enum LRCLIBLyrics {

    static let baseURL = "https://lrclib.net/api"

    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=/?#")
        return allowed
    }()

    private static func encode(_ value: String) -> String? {
        value
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
    }

    static func getURL(artist: String, title: String, duration: TimeInterval) -> URL? {
        guard duration > 0, duration.isFinite,
              let artist = encode(artist), let title = encode(title) else { return nil }
        return URL(string: "\(baseURL)/get?artist_name=\(artist)&track_name=\(title)&duration=\(Int(duration.rounded()))")
    }

    static func searchURL(artist: String, title: String) -> URL? {
        guard let artist = encode(artist), let title = encode(title) else { return nil }
        return URL(string: "\(baseURL)/search?track_name=\(title)&artist_name=\(artist)")
    }

    // MARK: Parsing

    /// The single row `/api/get` answers with, or nil for anything else.
    static func parseGetResponse(_ data: Data) -> [String: Any]? {
        guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              row["trackName"] != nil || row["syncedLyrics"] != nil || row["plainLyrics"] != nil
        else { return nil }
        return row
    }

    static func parseSearchResponse(_ data: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    }

    /// Picks the best search row for a query: the usual title/artist ranking,
    /// with rows whose length agrees with the track tried before rows whose
    /// length does not (a different edit times every line wrong).
    static func bestSearchMatch(
        in rows: [[String: Any]],
        query: LyricsQuery,
        album: String,
        duration: TimeInterval,
        tolerance: TimeInterval
    ) -> [String: Any]? {
        let agreeing = rows.filter {
            LyricsQueryCleaner.durationsAgree(($0["duration"] as? Double) ?? 0, duration, tolerance: tolerance)
        }
        if let match = LyricsSearchResults.bestMatch(
            in: agreeing, artist: query.artist, title: query.title, album: album, duration: duration
        ) {
            return match
        }
        // Nothing of the right length. A plain-text row is still worth showing
        // (no timing to be wrong), a timed one from another edit is not.
        let untimed = rows.filter { !LyricsSearchResults.carriesSyncedLyrics($0) }
        return LyricsSearchResults.bestMatch(
            in: untimed, artist: query.artist, title: query.title, album: album, duration: duration
        )
    }

    static func resolution(for row: [String: Any], query: LyricsQuery, duration: TimeInterval) -> LyricsResolution {
        let resolution = LyricsResolution.lrclib(row)
        if resolution.availability == .instrumental,
           !LyricsSearchResults.isReliableInstrumentalMatch(row, title: query.title, duration: duration) {
            return LyricsResolution()
        }
        return resolution
    }

    // MARK: Fetching

    /// Tries each query in order and returns the first timed lyrics found, or
    /// the first untimed/instrumental answer when no query has timings.
    /// Throws only when every request failed in transport, so the caller can
    /// still fall back to another provider.
    static func fetch(
        queries: [LyricsQuery],
        album: String,
        duration: TimeInterval,
        isWebSource: Bool,
        session: URLSession = LyricsNetwork.lrclibSession
    ) async throws -> LyricsResolution {
        var fallback: LyricsResolution?
        var lastError: Error?
        var anyRequestSucceeded = false
        let tolerance = LyricsQueryCleaner.durationTolerance(isWebSource: isWebSource)

        for query in queries.prefix(3) {
            try Task.checkCancellation()
            do {
                let result = try await fetch(query: query, album: album, duration: duration, tolerance: tolerance, session: session)
                anyRequestSucceeded = true
                switch result.availability {
                case .timed:
                    return result
                case .untimed, .instrumental:
                    if fallback == nil { fallback = result }
                case .loading, .unavailable:
                    break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                lastError = error
            }
        }

        if let fallback { return fallback }
        if !anyRequestSucceeded, let lastError { throw lastError }
        return LyricsResolution()
    }

    private static func fetch(
        query: LyricsQuery,
        album: String,
        duration: TimeInterval,
        tolerance: TimeInterval,
        session: URLSession
    ) async throws -> LyricsResolution {
        var untimed: LyricsResolution?

        if let url = getURL(artist: query.artist, title: query.title, duration: duration) {
            let (data, response) = try await session.data(from: url)
            if (response as? HTTPURLResponse)?.statusCode == 200, let row = parseGetResponse(data) {
                let resolution = resolution(for: row, query: query, duration: duration)
                if resolution.availability == .timed || resolution.availability == .instrumental {
                    return resolution
                }
                if resolution.availability == .untimed { untimed = resolution }
            }
        }

        try Task.checkCancellation()
        guard let url = searchURL(artist: query.artist, title: query.title) else {
            return untimed ?? LyricsResolution()
        }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return untimed ?? LyricsResolution() }

        let rows = parseSearchResponse(data)
        guard let row = bestSearchMatch(in: rows, query: query, album: album, duration: duration, tolerance: tolerance) else {
            return untimed ?? LyricsResolution()
        }
        let resolution = resolution(for: row, query: query, duration: duration)
        if resolution.availability == .unavailable || (resolution.availability == .untimed && untimed != nil) {
            return untimed ?? resolution
        }
        return resolution
    }
}
