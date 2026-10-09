/*
 * Notchly (forked from Atoll by Ebullioscopic)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Defaults
import Foundation

// MARK: - Timeline

/// Which lyric line is being sung at a given moment.
enum LyricsTimeline {
    /// Index of the last line whose timestamp is at or before `time`, or -1
    /// before the first line. Lines are sorted by timestamp (the parser sorts
    /// them); lines sharing a timestamp resolve to the last of them, as the
    /// linear scan this replaces did. O(log n).
    static func activeIndex(timestamps: [TimeInterval], at time: TimeInterval) -> Int {
        guard !timestamps.isEmpty, time.isFinite else { return -1 }
        var low = 0
        var high = timestamps.count          // first index with timestamp > time
        while low < high {
            let mid = (low + high) / 2
            if timestamps[mid] <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low - 1
    }

    static func activeIndex(in lines: [LyricLine], at time: TimeInterval) -> Int {
        activeIndex(timestamps: lines.map(\.timestamp), at: time)
    }
}

// MARK: - Stage state

/// What the lyrics view in the open notch shows.
enum LyricsStageState: Equatable {
    case nothingPlaying
    /// "Fetch lyrics online" is switched off.
    case onlineLookupOff
    case searching
    case synced
    case unsynced
    case instrumental
    case notFound

    static func resolve(
        hasTrack: Bool,
        isAdvertisement: Bool,
        fetchOnline: Bool,
        availability: LyricsAvailability
    ) -> LyricsStageState {
        guard hasTrack, !isAdvertisement else { return .nothingPlaying }
        guard fetchOnline else { return .onlineLookupOff }
        switch availability {
        case .loading: return .searching
        case .timed: return .synced
        case .untimed: return .unsynced
        case .instrumental: return .instrumental
        case .unavailable: return .notFound
        }
    }
}

/// The rows the rolling view draws around the current line.
enum LyricsStageWindow {
    struct Window: Equatable {
        /// Rows to draw, in order.
        let rows: [Int]                 // row positions into the row list
        /// Position (into `rows`) of the row the view is anchored on.
        let anchor: Int
        /// Whether the anchored row is the one being sung (false before the
        /// first line, or in a short gap with no row of its own).
        let anchorIsCurrent: Bool
    }

    /// Credits ("作词 : ...", "Producer: ...") and blank lines are not drawn.
    static func displayRows(lines: [LyricLine], duration: TimeInterval) -> [LyricRow] {
        SyncedLyricsRows.rows(for: lines, duration: duration).filter { row in
            if case let .line(_, text) = row { return LyricTextSemantics.isLyric(text) }
            return true
        }
    }

    /// The anchor is the row for `currentIndex`; failing that the last row
    /// before it (a short gap keeps the last line in place), or the first row
    /// before anything has been sung.
    static func window(rowIndices: [Int], currentIndex: Int, before: Int = 2, after: Int = 4) -> Window? {
        guard !rowIndices.isEmpty else { return nil }
        let anchorPosition: Int
        let isCurrent: Bool
        if let exact = rowIndices.firstIndex(of: currentIndex) {
            anchorPosition = exact
            isCurrent = true
        } else if let preceding = rowIndices.lastIndex(where: { $0 < currentIndex }) {
            anchorPosition = preceding
            isCurrent = false
        } else {
            anchorPosition = 0
            isCurrent = false
        }
        let lower = max(0, anchorPosition - before)
        let upper = min(rowIndices.count - 1, anchorPosition + after)
        return Window(rows: Array(lower...upper), anchor: anchorPosition - lower, anchorIsCurrent: isCurrent)
    }
}

// MARK: - Text size

enum LyricsTextSize: String, CaseIterable, Identifiable, Defaults.Serializable {
    case small, medium, large

    var id: String { rawValue }

    /// Point size every line is laid out at; lines away from the current one
    /// are scaled down from it.
    var fontSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 16
        case .large: return 19
        }
    }

    /// Scale of the lines around the current one.
    var contextScale: CGFloat {
        switch self {
        case .small: return 0.86
        case .medium: return 0.82
        case .large: return 0.76
        }
    }

    var localizedName: String {
        switch self {
        case .small: return String(localized: "S")
        case .medium: return String(localized: "M")
        case .large: return String(localized: "L")
        }
    }
}

// MARK: - Lyrics mode

/// Whether the open notch shows rolling lyrics in place of the Hub.
///
/// Lives for the session: toggling it in the notch survives closing and
/// reopening the notch, and a fresh launch starts from the
/// "Open lyrics mode by default" setting.
final class LyricsModeController: ObservableObject {
    static let shared = LyricsModeController()

    @Published private(set) var isActive: Bool

    init(initial: Bool = Defaults[.lyricsModeOnByDefault]) {
        isActive = initial
    }

    func toggle() {
        isActive.toggle()
    }

    func set(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
    }
}
