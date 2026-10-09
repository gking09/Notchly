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
/// again. Only answers are cached ("no lyrics" is not: it may be a transport
/// blip, and a later lookup could succeed). At most `capacity` songs, kept in
/// one small JSON file in the Caches directory, written off the main thread.
final class LyricsDiskCache: @unchecked Sendable {

    struct StoredLine: Codable, Equatable {
        let t: Double
        let text: String
        let timed: Bool
    }

    struct Entry: Codable, Equatable {
        let lines: [StoredLine]
        let instrumental: Bool
    }

    private struct FileContents: Codable {
        var version = 1
        var order: [String]
        var entries: [String: Entry]
    }

    static let shared: LyricsDiskCache = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let bundle = Bundle.main.bundleIdentifier ?? "Notchly"
        return LyricsDiskCache(directory: caches.appendingPathComponent(bundle, isDirectory: true).appendingPathComponent("Lyrics", isDirectory: true))
    }()

    let fileURL: URL
    private let lock = NSLock()
    private var lru: LyricsLRU<String, Entry>
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
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        // Recency is updated in memory and written with the next store.
        guard let entry = lru.value(for: key) else { return nil }
        return Self.resolution(from: entry)
    }

    func store(_ resolution: LyricsResolution, for key: String) {
        guard resolution.availability != .unavailable, resolution.availability != .loading else { return }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        lru.insert(Self.entry(from: resolution), for: key)
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

    func removeAll() {
        lock.lock()
        lru = LyricsLRU(capacity: lru.capacity)
        loaded = true
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
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
        let contents = FileContents(order: lru.order, entries: lru.storage)
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
