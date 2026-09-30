/*
 * Atoll (DynamicIsland)
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

import Foundation

// Pure, IOKit-free logic for the battery extras: time formatting, reading a
// dictionary of IOKit values, the low / critical / full alert state machine and
// the Bluetooth once-per-session low-battery tracker. Everything here takes plain
// values so it can be unit tested without hardware.

// MARK: - Time formatting

enum BatteryTimeFormatter {
    /// Estimates beyond this are a firmware sentinel rather than a real ETA
    /// (AppleSmartBattery reports 65535 for "unknown").
    static let maxPlausibleMinutes = 99 * 60

    /// "1h 12m", "45m", "2h", "<1m".
    static func format(minutes: Int) -> String {
        let clamped = max(minutes, 0)
        if clamped < 1 { return "<1m" }
        let hours = clamped / 60
        let mins = clamped % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }
}

enum BatteryTimeKind: Equatable {
    case toFull
    case remaining
}

enum BatteryTimeEstimate: Equatable {
    /// macOS has not produced an estimate yet (it reports -1 / 0 right after a
    /// plug or unplug).
    case calculating
    case minutes(Int)
}

struct BatteryTimeInfo: Equatable {
    var kind: BatteryTimeKind
    var estimate: BatteryTimeEstimate

    var minutes: Int? {
        if case .minutes(let value) = estimate { return value }
        return nil
    }

    var isCalculating: Bool { estimate == .calculating }

    /// "1h 12m", or "…" while macOS is still working it out.
    var compactText: String {
        switch estimate {
        case .calculating: return "…"
        case .minutes(let value): return BatteryTimeFormatter.format(minutes: value)
        }
    }

    /// "1h 12m to full", "45m left", "Calculating…".
    var captionText: String {
        switch estimate {
        case .calculating:
            return String(localized: "Calculating…")
        case .minutes(let value):
            let time = BatteryTimeFormatter.format(minutes: value)
            switch kind {
            case .toFull: return String(localized: "\(time) to full")
            case .remaining: return String(localized: "\(time) left")
            }
        }
    }
}

// MARK: - Charging state

enum BatteryChargingState: Equatable {
    case onBattery
    case charging
    /// Measured charge power is at or above `BatteryDetails.fastChargeWattsThreshold`.
    case fastCharging
    /// The charger firmware reports a slow-charging reason.
    case slowCharging
    /// On AC, not charging, below 100% and the charger reports a not-charging
    /// reason: Optimized Battery Charging or a charge limit. The exact cause is
    /// not exposed by IOKit, so the UI never names one.
    case held(atPercent: Int)
    case full
    /// On AC, not charging and no reason reported.
    case pluggedNotCharging
}

struct BatteryDetails: Equatable {
    /// Measured charge power that counts as "fast". Laptop batteries are ~50-100 Wh,
    /// so 35 W is roughly half a C; below that the pack is trickling or tapering.
    static let fastChargeWattsThreshold = 35.0

    var level: Int?
    var isPluggedIn = false
    var isCharging = false
    var state: BatteryChargingState = .onBattery
    var time: BatteryTimeInfo?
    /// Rated adapter power (AdapterDetails.Watts).
    var adapterWatts: Int?
    /// Power actually flowing into the pack (Amperage x Voltage), only while charging.
    var chargingPowerWatts: Double?
    /// Maximum capacity as a percentage of design capacity.
    var healthPercent: Int?
    var cycleCount: Int?
    var designCycleCount: Int?

    static let empty = BatteryDetails()
}

// MARK: - Interpreting IOKit dictionaries

enum BatteryDetailsInterpreter {

    /// - Parameters:
    ///   - powerSource: the IOPS description of the internal battery.
    ///   - smartBattery: the AppleSmartBattery registry properties (may be empty).
    ///   - adapter: `IOPSCopyExternalPowerAdapterDetails()` (may be nil).
    ///   - estimateSeconds: `IOPSGetTimeRemainingEstimate()` (-1 unknown, -2 unlimited).
    static func interpret(
        powerSource: [String: Any],
        smartBattery: [String: Any],
        adapter: [String: Any]?,
        estimateSeconds: Double? = nil
    ) -> BatteryDetails {
        var details = BatteryDetails()

        // Level
        if let current = int(powerSource["Current Capacity"]), let max = int(powerSource["Max Capacity"]), max > 0 {
            details.level = Swift.min(Swift.max(current * 100 / max, 0), 100)
        } else if let smartLevel = int(smartBattery["CurrentCapacity"]), smartLevel <= 100 {
            details.level = smartLevel
        }

        // Power state
        let externalConnected: Bool = {
            if let state = powerSource["Power Source State"] as? String { return state == "AC Power" }
            return bool(smartBattery["ExternalConnected"]) ?? false
        }()
        let isCharging = bool(powerSource["Is Charging"]) ?? bool(smartBattery["IsCharging"]) ?? false
        let isCharged = bool(powerSource["Is Charged"]) ?? bool(smartBattery["FullyCharged"]) ?? false
        details.isPluggedIn = externalConnected
        details.isCharging = isCharging

        // Adapter
        if externalConnected {
            let adapterDict = adapter ?? (smartBattery["AdapterDetails"] as? [String: Any])
            if let watts = int(adapterDict?["Watts"]), watts > 0 {
                details.adapterWatts = watts
            }
        }

        // Charge power (only while charging; Amperage is signed and stored unsigned)
        if isCharging,
           let amperage = signedInt(smartBattery["Amperage"]),
           let voltage = int(smartBattery["Voltage"]),
           amperage > 0, voltage > 0 {
            details.chargingPowerWatts = Double(amperage) * Double(voltage) / 1_000_000
        }

        // State
        let level = details.level ?? 0
        if !externalConnected {
            details.state = .onBattery
        } else if isCharged || (!isCharging && level >= 100) {
            details.state = .full
        } else if isCharging {
            let chargerData = smartBattery["ChargerData"] as? [String: Any]
            if let slow = int(chargerData?["SlowChargingReason"]), slow != 0 {
                details.state = .slowCharging
            } else if let power = details.chargingPowerWatts, power >= BatteryDetails.fastChargeWattsThreshold {
                details.state = .fastCharging
            } else {
                details.state = .charging
            }
        } else {
            let chargerData = smartBattery["ChargerData"] as? [String: Any]
            if let reason = int(chargerData?["NotChargingReason"]), reason != 0, details.level != nil {
                details.state = .held(atPercent: level)
            } else {
                details.state = .pluggedNotCharging
            }
        }

        // Time estimate
        details.time = timeInfo(
            externalConnected: externalConnected,
            isCharging: isCharging,
            level: details.level,
            powerSource: powerSource,
            smartBattery: smartBattery,
            estimateSeconds: estimateSeconds
        )

        // Health and cycles
        details.healthPercent = healthPercent(smartBattery: smartBattery)
        if let cycles = int(smartBattery["CycleCount"]), cycles >= 0 {
            details.cycleCount = cycles
        }
        details.designCycleCount = int(powerSource["DesignCycleCount"]) ?? int(smartBattery["DesignCycleCount9C"])

        return details
    }

    // MARK: Time

    static func timeInfo(
        externalConnected: Bool,
        isCharging: Bool,
        level: Int?,
        powerSource: [String: Any],
        smartBattery: [String: Any],
        estimateSeconds: Double?
    ) -> BatteryTimeInfo? {
        if isCharging {
            if let level, level >= 100 { return nil }
            // IOPS first; AppleSmartBattery only when IOPS has no key at all.
            // AvgTimeToFull lingers after charging stops, so it is never used
            // while not charging.
            let raw = int(powerSource["Time to Full Charge"]) ?? int(smartBattery["AvgTimeToFull"])
            guard let raw else { return nil }
            return BatteryTimeInfo(kind: .toFull, estimate: estimate(fromMinutes: raw))
        }

        if !externalConnected {
            if let raw = int(powerSource["Time to Empty"]) {
                return BatteryTimeInfo(kind: .remaining, estimate: estimate(fromMinutes: raw))
            }
            if let seconds = estimateSeconds {
                if seconds > 0 {
                    return BatteryTimeInfo(kind: .remaining, estimate: estimate(fromMinutes: Int((seconds / 60).rounded(.up))))
                }
                if seconds == -1 {
                    return BatteryTimeInfo(kind: .remaining, estimate: .calculating)
                }
            }
            if let raw = int(smartBattery["TimeRemaining"]) ?? int(smartBattery["AvgTimeToEmpty"]) {
                return BatteryTimeInfo(kind: .remaining, estimate: estimate(fromMinutes: raw))
            }
        }
        return nil
    }

    /// Negative or zero means macOS is still working it out; an implausibly large
    /// value is the "unknown" sentinel and is treated the same way.
    static func estimate(fromMinutes raw: Int) -> BatteryTimeEstimate {
        if raw <= 0 || raw > BatteryTimeFormatter.maxPlausibleMinutes { return .calculating }
        return .minutes(raw)
    }

    // MARK: Health

    /// Nominal full-charge capacity over design capacity. Apple Silicon reports
    /// `MaxCapacity` as a percentage (100), so the raw mAh keys come first and
    /// `MaxCapacity` is only used when it is clearly mAh (Intel).
    static func healthPercent(smartBattery: [String: Any]) -> Int? {
        guard let design = int(smartBattery["DesignCapacity"]), design > 0 else { return nil }
        let raw: Int? = {
            if let nominal = int(smartBattery["NominalChargeCapacity"]), nominal > 0 { return nominal }
            if let rawMax = int(smartBattery["AppleRawMaxCapacity"]), rawMax > 0 { return rawMax }
            if let max = int(smartBattery["MaxCapacity"]), max > 100 { return max }
            return nil
        }()
        guard let raw else { return nil }
        let percent = Int((Double(raw) * 100 / Double(design)).rounded())
        guard percent >= 1, percent <= 150 else { return nil }
        return Swift.min(percent, 100)
    }

    // MARK: Value helpers

    static func int(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? 1 : 0 }
            // Unsigned values above Int.max are firmware sentinels, not data.
            if number.doubleValue >= Double(Int.max) { return nil }
            return number.intValue
        }
        return value as? Int
    }

    /// AppleSmartBattery stores signed currents as unsigned 64-bit.
    static func signedInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return value as? Int }
        return Int(number.int64Value)
    }

    static func bool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return nil
    }
}

// MARK: - Mac low / critical / full alerts

enum BatteryAlertKind: Equatable {
    case low
    case critical
    case full
    /// Charging stopped below 100% while on AC (Optimized Battery Charging or a
    /// charge limit).
    case chargeHeld
}

struct BatteryAlertConfig: Equatable {
    var lowEnabled = true
    var lowThreshold = 20
    var criticalEnabled = true
    var criticalThreshold = 10
    var fullEnabled = true
    var fullThreshold = 100
    var chargeHeldEnabled = true
}

struct BatteryAlertReading: Equatable {
    var level: Int
    var isPluggedIn: Bool
    /// `BatteryChargingState.held`.
    var isHeld: Bool
}

/// Decides when to raise an alert. One alert per crossing: a level that stays low
/// does not repeat, and the thresholds re-arm only after the level has moved
/// `rearmMargin` points clear of them. The first reading never alerts (launching
/// the app at 15% is not news) but does arm or disarm the machine.
struct BatteryAlertStateMachine: Equatable {
    static let rearmMargin = 3

    private(set) var hasReading = false
    private(set) var lowFired = false
    private(set) var criticalFired = false
    /// Set once a below-limit reading has been seen while plugged in, so the
    /// "charged" alert fires on the way up, not when plugging in at 100%.
    private(set) var fullArmed = false
    private(set) var holdFired = false

    mutating func update(_ reading: BatteryAlertReading, config: BatteryAlertConfig) -> BatteryAlertKind? {
        let isInitial = !hasReading
        hasReading = true
        let level = reading.level
        var result: BatteryAlertKind?

        if !reading.isPluggedIn {
            fullArmed = false
            holdFired = false

            var criticalCrossed = false
            var lowCrossed = false

            if level <= config.criticalThreshold {
                if !criticalFired { criticalFired = true; criticalCrossed = true }
            } else if level > config.criticalThreshold + Self.rearmMargin {
                criticalFired = false
            }

            if level <= config.lowThreshold {
                if !lowFired { lowFired = true; lowCrossed = true }
            } else if level > config.lowThreshold + Self.rearmMargin {
                lowFired = false
            }

            if !isInitial {
                if criticalCrossed && config.criticalEnabled {
                    result = .critical
                } else if (lowCrossed || criticalCrossed) && config.lowEnabled {
                    result = .low
                }
            }
            return result
        }

        // Plugged in.
        if level < config.fullThreshold {
            fullArmed = true
        } else if fullArmed {
            fullArmed = false
            holdFired = true
            if config.fullEnabled { result = .full }
        }

        if reading.isHeld && level < 100 {
            if !holdFired {
                holdFired = true
                if !isInitial && config.chargeHeldEnabled && result == nil { result = .chargeHeld }
            }
        } else if !reading.isHeld {
            holdFired = false
        }
        return result
    }
}

// MARK: - Bluetooth low battery

struct BluetoothBatteryReading: Equatable {
    /// Stable per-device key (normalized address, else normalized name).
    var id: String
    var name: String
    var level: Int
    var symbol: String?
}

/// Raises at most one low-battery alert per device per connection session. A
/// session ends when the device disappears from `connectedIDs`; the next connect
/// can alert again.
struct BluetoothLowBatteryTracker: Equatable {
    private(set) var alerted: Set<String> = []

    mutating func update(
        connectedIDs: Set<String>,
        readings: [BluetoothBatteryReading],
        threshold: Int,
        enabled: Bool
    ) -> [BluetoothBatteryReading] {
        alerted.formIntersection(connectedIDs)
        guard enabled else { return [] }

        var fresh: [BluetoothBatteryReading] = []
        for reading in readings {
            guard connectedIDs.contains(reading.id),
                  // 0 is what several devices report while they have not read
                  // their gauge yet; a flat device would have disconnected.
                  reading.level >= 1,
                  reading.level <= threshold,
                  !alerted.contains(reading.id) else { continue }
            alerted.insert(reading.id)
            fresh.append(reading)
        }
        return fresh
    }
}
