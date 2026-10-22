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

// MARK: - Transport

/// One HTTP round trip: the body and the status code. Injectable, so the
/// retry and variant logic is tested against recorded responses.
typealias LyricsTransport = @Sendable (URL) async throws -> (Data, Int)

enum LyricsHTTP {
    /// The transport every real request goes through.
    static func transport(session: URLSession) -> LyricsTransport {
        { url in
            let (data, response) = try await session.data(from: url)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    enum Result {
        case ok(Data)
        /// 404 or 400: the catalogue answered, and the answer is "no".
        case none
        /// Overloaded, rate limited, timed out or unreachable, even after
        /// retrying. Says nothing about whether the track exists.
        case transientFailure
    }

    /// LRCLIB answers `503 ServerOverloaded` for a large share of requests
    /// (about one `get` in five and more `search`es when measured for this
    /// change), and a retry a moment later usually succeeds. Treating the first
    /// 503 as "no such track" is how songs the catalogue has were shown as
    /// "No lyrics found".
    static let retryDelays: [TimeInterval] = [0.6, 1.5]

    static func perform(
        _ url: URL,
        transport: LyricsTransport,
        sleep: (TimeInterval) async -> Void,
        deadline: Date?
    ) async throws -> Result {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let (data, status) = try await transport(url)
                switch status {
                case 200: return .ok(data)
                case 400, 404: return .none
                default: break   // 429, 5xx and anything unexpected are retried
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            }
            guard attempt < retryDelays.count else { return .transientFailure }
            if let deadline, Date().addingTimeInterval(retryDelays[attempt]) >= deadline { return .transientFailure }
            await sleep(retryDelays[attempt])
            attempt += 1
        }
    }
}

/// What one lookup found, and whether "found nothing" can be trusted.
struct LyricsFetchOutcome {
    var resolution: LyricsResolution = LyricsResolution()
    /// Some request failed even after retrying, so an empty result may only
    /// mean the catalogue could not be asked.
    var sawTransientFailure = false
    var requestCount = 0
    /// How far the chosen row's length is from the track's, for diagnostics.
    var durationDelta: TimeInterval?

    /// Nothing found and every request was answered: safe to remember for a while.
    var isDefinitiveMiss: Bool {
        resolution.availability == .unavailable && !sawTransientFailure
    }
}

/// LRCLIB (lrclib.net), a free keyless catalogue of synced lyrics.
///
/// The lookup is a plan, not a single query. Each ordered variant of the
/// artist and title is asked of `/api/get` (exact artist, title and length, the
/// most reliable answer there is) and then `/api/search`; after the variants,
/// a free-text `q` search and a title-only search catch what the structured
/// ones miss. Every row seen goes into one pool and `LyricsCandidateSelector`
/// picks from the pool, so the answer is the best of everything found rather
/// than the first thing that was acceptable. Only the artist, title and
/// duration are ever sent.
enum LRCLIBLyrics {

    static let baseURL = "https://lrclib.net/api"

    /// Requests per lookup, not counting retries.
    static let maximumRequests = 10
    /// Wall-clock allowance for the whole lookup.
    static let lookupBudget: TimeInterval = 24

    private static let queryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=/?#")
        return allowed
    }()

    /// Sent as written: `get` and `search` both ignore accents, and folding
    /// would turn a Cyrillic "й" into "и".
    private static func encode(_ value: String) -> String? {
        LyricsText.canonical(value).addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
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

    /// Free-text search over title and artist together.
    static func searchURL(query: String) -> URL? {
        guard let query = encode(query) else { return nil }
        return URL(string: "\(baseURL)/search?q=\(query)")
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

    // MARK: Resolutions

    /// Whatever the row carries, preferring timings. Used for a row that was
    /// not chosen by the selector (tests, tooling).
    static func resolution(for row: [String: Any], query: LyricsQuery, duration: TimeInterval) -> LyricsResolution {
        let resolution = LyricsResolution.lrclib(row)
        if resolution.availability == .instrumental,
           !LyricsSearchResults.isReliableInstrumentalMatch(row, title: query.title, duration: duration) {
            return LyricsResolution()
        }
        return resolution
    }

    /// The lyrics a selection stands for, honouring *why* it was chosen: a row
    /// picked as plain text is shown as plain text even when it also carries
    /// timings of the wrong length.
    static func resolution(for selection: LyricsSelection) -> LyricsResolution {
        let row = selection.row
        let synced = (row["syncedLyrics"] as? String) ?? ""
        let plain = (row["plainLyrics"] as? String) ?? ""
        switch selection.kind {
        case .instrumental:
            return LyricsResolution(instrumental: true)
        case .synced:
            return LyricsResolution(lines: LRCParser.parse(synced))
        case .plain:
            return LyricsResolution(lines: LyricLine.untimedLines(from: plain))
        case .syncedOffLength:
            let words = LRCParser.parse(synced)
                .filter { !$0.text.isEmpty }
                .map { LyricLine(timestamp: 0, text: $0.text, isTimed: false) }
            return LyricsResolution(lines: words)
        }
    }

    // MARK: Fetching

    /// Looks the track up and returns the best lyrics found. Throws only for
    /// cancellation: a failed request is reported in the outcome so the caller
    /// can still ask another provider and knows not to remember a miss.
    static func fetch(
        variants: [LyricsQuery],
        originalTitle: String,
        album: String,
        duration: TimeInterval,
        isWebSource: Bool,
        transport: LyricsTransport = LyricsHTTP.transport(session: LyricsNetwork.lrclibSession),
        sleep: (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        budget: TimeInterval = lookupBudget
    ) async throws -> LyricsFetchOutcome {
        guard !variants.isEmpty else { return LyricsFetchOutcome() }

        let request = LyricsMatchRequest(
            titles: variants.map(\.title) + [originalTitle],
            originalTitle: originalTitle,
            artists: variants.map(\.artist),
            album: album,
            duration: duration,
            tolerance: LyricsQueryCleaner.durationTolerance(isWebSource: isWebSource)
        )

        var outcome = LyricsFetchOutcome()
        var pool: [[String: Any]] = []
        var poolIDs = Set<Int>()
        let deadline = Date().addingTimeInterval(budget)

        func ingest(_ rows: [[String: Any]]) {
            for row in rows {
                if let id = row["id"] as? Int {
                    guard poolIDs.insert(id).inserted else { continue }
                }
                pool.append(row)
            }
        }

        func ask(_ url: URL?) async throws -> Data? {
            guard let url, outcome.requestCount < maximumRequests, Date() < deadline else { return nil }
            outcome.requestCount += 1
            switch try await LyricsHTTP.perform(url, transport: transport, sleep: sleep, deadline: deadline) {
            case .ok(let data): return data
            case .none: return nil
            case .transientFailure:
                outcome.sawTransientFailure = true
                return nil
            }
        }

        func best() -> LyricsSelection? {
            LyricsCandidateSelector.select(rows: pool, request: request)
        }

        /// A synced row whose length is within a second or so of the track's:
        /// nothing a further request could find is worth waiting for.
        func isSettled(_ selection: LyricsSelection?) -> Bool {
            guard let selection, selection.kind == .synced else { return false }
            return (selection.durationDelta ?? 0) <= 1.5
        }

        search: do {
            for variant in variants {
                if let data = try await ask(getURL(artist: variant.artist, title: variant.title, duration: duration)),
                   let row = parseGetResponse(data) {
                    ingest([row])
                }
                if isSettled(best()) { break search }

                if let data = try await ask(searchURL(artist: variant.artist, title: variant.title)) {
                    ingest(parseSearchResponse(data))
                }
                // Any timed row of the right length ends the search: the
                // variants after this one only differ in spelling.
                if best()?.kind == .synced { break search }
            }

            // Nothing timed yet. Free text finds rows the structured search
            // does not, notably when the artist field is a list.
            if let first = variants.first {
                if let data = try await ask(searchURL(query: "\(LyricsArtistNames.primary(first.artist)) \(first.title)")) {
                    ingest(parseSearchResponse(data))
                }
                if best()?.kind == .synced { break search }
                // Title alone: the artist is filtered by the selector, so a
                // wrong artist string costs nothing here.
                if let data = try await ask(searchURL(query: first.title)) {
                    ingest(parseSearchResponse(data))
                }
            }
        }

        if let selection = best() {
            outcome.resolution = resolution(for: selection)
            outcome.durationDelta = selection.durationDelta
        }
        return outcome
    }
}
