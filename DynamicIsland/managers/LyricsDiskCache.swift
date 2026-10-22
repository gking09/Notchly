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

/// A small least-recently-used map. Reading an entry makes it the newest;
/// inserting past `capacity` drops the oldest. Pure value type, unit tested.
struct LyricsLRU<Key: Hashable, Value> {
    let capacity: Int
    private(set) var order: [Key] = []          // oldest first
    private(set) var storage: [Key: Value] = [:]

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { storage.count }

    /// Looks a key up and marks it as the most recently used.
    mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    /// Looks a key up without changing its age.
    func peek(_ key: Key) -> Value? { storage[key] }

    /// Inserts or replaces, returning the keys evicted to make room.
    @discardableResult
    mutating func insert(_ value: Value, for key: Key) -> [Key] {
        storage[key] = value
        touch(key)
        var evicted: [Key] = []
        while order.count > capacity {
            let oldest = order.removeFirst()
            storage.removeValue(forKey: oldest)
            evicted.append(oldest)
        }
        return evicted
    }

    mutating func removeValue(for key: Key) {
        storage.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) { order.remove(at: index) }
        order.append(key)
    }
}

/// Found lyrics, kept on disk so replaying a song does not ask the network
/// again, and the per-song timing corrections the listener has made.
///
/// Answers are cached; "no lyrics" is only remembered in memory, for ten
/// minutes, and only when every request was answered -- a transport blip must
/// not hide a song for long. Plain-only answers are trusted for a day: a timed
/// version may be contributed to the catalogue later, and timed beats plain.
/// At most `capacity` songs, kept in one small JSON file in the Caches
/// directory, written off the main thread.
final class LyricsDiskCache: @unchecked Sendable {

    struct StoredLine: Codable, Equatable {
        let t: Double
        let text: String
        let timed: Bool
    }

    struct Entry: Codable, Equatable {
        let lines: [StoredLine]
        let instrumental: Bool
        /// Seconds since 1970 when the answer was stored; nil for entries
        /// written before this was recorded.
        var storedAt: Double?

        init(lines: [StoredLine], instrumental: Bool, storedAt: Double? = nil) {
            self.lines = lines
            self.instrumental = instrumental
            self.storedAt = storedAt
        }

        /// Words with no timings at all.
        var isPlainOnly: Bool {
            !instrumental && !lines.isEmpty && !lines.contains { $0.timed }
        }
    }

    /// What a lookup found.
    enum Lookup {
        case fresh(LyricsResolution)
        /// A plain-only answer old enough that a timed one should be looked
        /// for. Still better than nothing if that lookup fails.
        case stale(LyricsResolution)
        case absent
    }

    private struct FileContents: Codable {
        var version = 2
        var order: [String]
        var entries: [String: Entry]
        var offsets: [String: Double]?
    }

    /// How long a plain-only answer is trusted.
    static let plainOnlyLifetime: TimeInterval = 24 * 60 * 60
    /// How long a confirmed miss is trusted.
    static let missLifetime: TimeInterval = 10 * 60
    private static let offsetCapacity = 500

    static let shared: LyricsDiskCache = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "Notchly"
        return LyricsDiskCache(directory: caches.appendingPathComponent(bundle, isDirectory: true).appendingPathComponent("Lyrics", isDirectory: true))
    }()

    let fileURL: URL
    private let lock = NSLock()
    private var lru: LyricsLRU<String, Entry>
    private var offsets: [String: Double] = [:]
    private var offsetOrder: [String] = []
    private var misses: [String: Date] = [:]
    private var loaded = false
    private var saveScheduled = false
    private let ioQueue = DispatchQueue(label: "notchly.lyrics-cache", qos: .utility)

    init(directory: URL, capacity: Int = 200) {
        self.fileURL = directory.appendingPathComponent("lyrics-cache.json")
        self.lru = LyricsLRU(capacity: capacity)
    }

    // MARK: Keys

    /// Normalised artist + title + whole-second duration.
    static func key(artist: String, title: String, duration: TimeInterval) -> String {
        let seconds = duration.isFinite && duration > 0 ? Int(duration.rounded()) : 0
        return "\(LyricsQueryCleaner.normalized(artist))|\(LyricsQueryCleaner.normalized(title))|\(seconds)"
    }

    // MARK: Access

    func lookup(_ key: String) -> LyricsResolution? {
        if case .fresh(let resolution) = lookupDetailed(key) { return resolution }
        return nil
    }

    /// Like `lookup`, but says when an entry is present and too old to trust.
    func lookupDetailed(_ key: String, now: Date = Date()) -> Lookup {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        // Recency is updated in memory and written with the next store.
        guard let entry = lru.value(for: key) else { return .absent }
        let resolution = Self.resolution(from: entry)
        if entry.isPlainOnly {
            // An entry from before storage times were kept counts as old.
            let age = entry.storedAt.map { now.timeIntervalSince1970 - $0 } ?? .infinity
            if age > Self.plainOnlyLifetime { return .stale(resolution) }
        }
        return .fresh(resolution)
    }

    func store(_ resolution: LyricsResolution, for key: String, now: Date = Date()) {
        guard resolution.availability != .unavailable, resolution.availability != .loading else { return }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        var entry = Self.entry(from: resolution)
        entry.storedAt = now.timeIntervalSince1970
        lru.insert(entry, for: key)
        misses.removeValue(forKey: key)
        scheduleSaveLocked()
    }

    // MARK: Misses

    /// Remembers, in memory only, that every request for this track was
    /// answered and none had lyrics.
    func storeMiss(_ key: String, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        misses[key] = now
        if misses.count > 200, let oldest = misses.min(by: { $0.value < $1.value })?.key {
            misses.removeValue(forKey: oldest)
        }
    }

    func isRecentMiss(_ key: String, now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let date = misses[key] else { return false }
        if now.timeIntervalSince(date) > Self.missLifetime {
            misses.removeValue(forKey: key)
            return false
        }
        return true
    }

    func forgetMiss(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        misses.removeValue(forKey: key)
    }

    // MARK: Offsets

    /// The listener's timing correction for this song, in seconds.
    func offset(for key: String) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return offsets[key] ?? 0
    }

    func setOffset(_ value: TimeInterval, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        if value == 0 {
            offsets.removeValue(forKey: key)
            offsetOrder.removeAll { $0 == key }
        } else {
            offsets[key] = value
            offsetOrder.removeAll { $0 == key }
            offsetOrder.append(key)
            while offsetOrder.count > Self.offsetCapacity {
                offsets.removeValue(forKey: offsetOrder.removeFirst())
            }
        }
        scheduleSaveLocked()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return lru.count
    }

    /// Writes pending changes now (tests, app termination).
    func flush() {
        ioQueue.sync { self.writeNow() }
    }

    /// Forgets every stored lyric and remembered miss. The timing corrections
    /// the listener made are theirs and are kept.
    func removeAll() {
        lock.lock()
        loadIfNeeded()
        lru = LyricsLRU(capacity: lru.capacity)
        misses = [:]
        saveScheduled = true
        lock.unlock()
        flush()
    }

    // MARK: Conversion

    static func entry(from resolution: LyricsResolution) -> Entry {
        Entry(
            lines: resolution.lines.map { StoredLine(t: $0.timestamp, text: $0.text, timed: $0.isTimed) },
            instrumental: resolution.availability == .instrumental && resolution.lines.isEmpty
        )
    }

    static func resolution(from entry: Entry) -> LyricsResolution {
        LyricsResolution(
            lines: entry.lines.map { LyricLine(timestamp: $0.t, text: $0.text, isTimed: $0.timed) },
            instrumental: entry.instrumental
        )
    }

    // MARK: Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let contents = try? JSONDecoder().decode(FileContents.self, from: data)
        else { return }
        for key in contents.order {
            if let entry = contents.entries[key] { lru.insert(entry, for: key) }
        }
        offsets = contents.offsets ?? [:]
        offsetOrder = Array(offsets.keys)
    }

    private func scheduleSaveLocked() {
        guard !saveScheduled else { return }
        saveScheduled = true
        ioQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.writeNow(onlyIfScheduled: true)
        }
    }

    private func writeNow(onlyIfScheduled: Bool = false) {
        lock.lock()
        if onlyIfScheduled && !saveScheduled {
            lock.unlock()
            return
        }
        saveScheduled = false
        let contents = FileContents(order: lru.order, entries: lru.storage, offsets: offsets.isEmpty ? nil : offsets)
        lock.unlock()

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(contents)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.log("Lyrics cache write failed: \(error)", category: .debug)
        }
    }
}
