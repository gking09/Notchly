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

/// Where in the song the lyrics should be, as a pure function of what the
/// player last reported.
///
/// Every source reports a *sample*: the position at one instant. Between
/// samples the position is extrapolated, and getting that wrong shows up
/// directly as lyrics that are early, late, or running away:
///
/// * the position is `elapsed + (now - timestamp) * rate` while playing, and
///   exactly `elapsed` while paused;
/// * a sample with no real timestamp (`distantPast`, the value of a source
///   that never stamps) has no age to add;
/// * a rate of zero or less on a player that says it is playing is a source
///   that does not report one, not a stopped track;
/// * a stale anchor cannot carry the position past the end of the song.
///
/// Kept free of the manager so the arithmetic is tested directly.
enum LyricsClock {

    /// Timestamps older than this are "never stamped", not "a very old sample".
    static let implausibleAge: TimeInterval = 60 * 60 * 24

    /// Playback position in seconds, with no lead or offset applied.
    static func playbackPosition(
        elapsed: TimeInterval,
        timestamp: Date,
        rate: Double,
        isPlaying: Bool,
        duration: TimeInterval,
        now: Date
    ) -> TimeInterval {
        let base = elapsed.isFinite ? max(0, elapsed) : 0
        guard isPlaying else { return clamp(base, duration: duration) }

        let age = now.timeIntervalSince(timestamp)
        // A timestamp in the future is clock skew; one from another era is a
        // source that never sets it. Neither contributes elapsed time.
        guard age.isFinite, age > 0, age < implausibleAge else { return clamp(base, duration: duration) }

        let effectiveRate = rate.isFinite && rate > 0 ? rate : 1
        return clamp(base + age * effectiveRate, duration: duration)
    }

    /// The position lyric lines are looked up at: playback position, plus the
    /// lead that lets a line be read before it is sung, plus the listener's own
    /// correction for this song.
    static func lyricPosition(
        elapsed: TimeInterval,
        timestamp: Date,
        rate: Double,
        isPlaying: Bool,
        duration: TimeInterval,
        now: Date,
        lead: TimeInterval,
        offset: TimeInterval
    ) -> TimeInterval {
        let position = playbackPosition(
            elapsed: elapsed, timestamp: timestamp, rate: rate,
            isPlaying: isPlaying, duration: duration, now: now
        )
        return max(0, position + lead + offset)
    }

    private static func clamp(_ position: TimeInterval, duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return position }
        return min(position, duration)
    }
}

/// The per-song correction the listener dials in when a lyrics version runs
/// early or late. Positive values show lines earlier.
enum LyricsOffset {
    static let step: TimeInterval = 0.5
    static let limit: TimeInterval = 15

    /// `current` moved by `delta`, kept within bounds and on the step grid, so
    /// repeated taps never accumulate floating-point crumbs.
    static func adjusted(_ current: TimeInterval, by delta: TimeInterval) -> TimeInterval {
        let moved = (current + delta) / step
        let snapped = moved.rounded() * step
        return min(max(snapped, -limit), limit)
    }

    static func label(_ offset: TimeInterval) -> String {
        if abs(offset) < 0.001 { return "0.0s" }
        return String(format: "%+.1fs", offset)
    }
}
