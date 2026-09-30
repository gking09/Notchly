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
import IOKit
import IOKit.ps

/// Lightweight helper for querying macOS battery charging status and ETA.
final class MacBatteryManager {
    static let shared = MacBatteryManager()

    private init() {}

    struct BatteryStatus {
        let timeRemainingMinutes: Int?
        let isCharging: Bool
        let percentage: Int?
    }

    func currentStatus() -> BatteryStatus {
        guard let sourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesList = IOPSCopyPowerSourcesList(sourcesInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryStatus(timeRemainingMinutes: nil, isCharging: false, percentage: nil)
        }

        for source in sourcesList {
            guard let description = IOPSGetPowerSourceDescription(sourcesInfo, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else {
                continue
            }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let timeRemaining = description[kIOPSTimeToFullChargeKey] as? Int
            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Int

            let percentage: Int?
            if let current = currentCapacity, let max = maxCapacity, max > 0 {
                percentage = (current * 100) / max
            } else {
                percentage = nil
            }

            return BatteryStatus(
                timeRemainingMinutes: timeRemaining,
                isCharging: isCharging,
                percentage: percentage
            )
        }

        return BatteryStatus(timeRemainingMinutes: nil, isCharging: false, percentage: nil)
    }

    func formattedTimeToFullCharge() -> String? {
        let status = currentStatus()
        guard status.isCharging, let minutes = status.timeRemainingMinutes, minutes > 0 else {
            return nil
        }
        return BatteryTimeFormatter.format(minutes: minutes)
    }

    // MARK: - Detail snapshot

    /// One read of everything the battery extras show: IOPS for level, charging
    /// flags and the OS time estimates, AppleSmartBattery for health, cycles,
    /// charger data and the adapter, and `IOPSCopyExternalPowerAdapterDetails`
    /// for the rated wattage. Interpretation lives in `BatteryDetailsInterpreter`.
    func currentDetails() -> BatteryDetails {
        guard let powerSource = internalBatteryDescription() else { return .empty }
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        return BatteryDetailsInterpreter.interpret(
            powerSource: powerSource,
            smartBattery: smartBatteryProperties(),
            adapter: adapter,
            estimateSeconds: IOPSGetTimeRemainingEstimate()
        )
    }

    private func internalBatteryDescription() -> [String: Any]? {
        guard let sourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesList = IOPSCopyPowerSourcesList(sourcesInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sourcesList {
            guard let description = IOPSGetPowerSourceDescription(sourcesInfo, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return description
        }
        return nil
    }

    private func smartBatteryProperties() -> [String: Any] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}
