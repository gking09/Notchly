import Foundation

/// A snapshot of "how much background work is worth doing right now", kept
/// free of AppKit and IOKit so the policy can be unit tested. Pollers, timers
/// and animation clocks ask the gate how often to run instead of each carrying
/// their own low-power flags.
struct ActivityGate: Equatable, Sendable {
    /// The "Efficiency mode" setting.
    var efficiencyModeEnabled: Bool = true
    /// `ProcessInfo.isLowPowerModeEnabled`.
    var lowPowerMode: Bool = false
    /// Running from the battery rather than an adapter.
    var onBattery: Bool = false
    /// The display is asleep (or the machine is about to sleep); nothing can be seen.
    var screenAsleep: Bool = false

    /// True when polling and animation should be thinned out: the user opted in
    /// and the Mac is either on battery or in Low Power Mode.
    var reducedActivity: Bool {
        efficiencyModeEnabled && (lowPowerMode || onBattery)
    }

    /// Nothing on screen can be seen, so visual updates are pure waste.
    var isSuspended: Bool { screenAsleep }

    /// Stretches `base` while activity is reduced.
    func interval(_ base: TimeInterval, reducedMultiplier: Double = 2) -> TimeInterval {
        reducedActivity ? base * max(1, reducedMultiplier) : base
    }

    /// Frame rate for continuous visual updates. Low Power Mode halves it
    /// (floored at `minimum`) when efficiency mode is on; plain battery trims a
    /// third, since the visualizer is the main thing drawing while on battery.
    func frameRate(_ base: Int, minimum: Int = 12) -> Int {
        guard reducedActivity else { return base }
        let factor = lowPowerMode ? 0.5 : 0.67
        return max(min(base, minimum), Int((Double(base) * factor).rounded()))
    }

    /// Seconds between frames at `frameRate(_:)`.
    func frameInterval(_ baseFPS: Int, minimum: Int = 12) -> TimeInterval {
        1.0 / Double(max(1, frameRate(baseFPS, minimum: minimum)))
    }

    /// Timer tolerance that lets the kernel coalesce wakeups: 20% of the
    /// interval, at least `minimum`, so slow timers can slide by a second or so
    /// while fast ones stay crisp.
    static func tolerance(for interval: TimeInterval, fraction: Double = 0.2, minimum: TimeInterval = 0) -> TimeInterval {
        max(minimum, interval * min(max(fraction, 0), 0.5))
    }
}
