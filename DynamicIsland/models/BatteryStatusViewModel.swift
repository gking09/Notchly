/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

enum BatteryTemporaryHUDKind: Equatable {
    case charging
    case lowBattery
    case fullBattery
}

/// Which variant of a temporary battery HUD is showing. The low-battery kind
/// also carries the critical alert, and the full-battery kind carries the
/// "charging held at N%" alert, so the layout code has one set of sizes.
enum BatteryHUDFlavor: Equatable {
    case standard
    case critical
    case chargeHeld
}

/// Extra lines the HUD may show. Every field is nil unless IOKit actually
/// reported the data and the matching setting is on.
struct BatteryHUDExtras: Equatable {
    var flavor: BatteryHUDFlavor = .standard
    /// "Charging", "Fast charging"... only for the charging HUD.
    var statusTitle: String?
    /// "1h 12m to full" / "45m left" / "Calculating…".
    var timeText: String?
    /// "67W" adapter rating.
    var wattsText: String?
    var isFastCharging = false
    var heldAtPercent: Int?

    static let none = BatteryHUDExtras()
}

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?
    var animations: DynamicIslandAnimations = DynamicIslandAnimations()
    private let lowBatteryAlertSoundPlayer = AudioPlayer()
    private var alertMachine = BatteryAlertStateMachine()
    private var detailsTimer: Timer?

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""
    /// Time estimate, charger wattage, charging state, health and cycles.
    @Published private(set) var details: BatteryDetails = .empty
    @Published private(set) var activeTemporaryHUDKind: BatteryTemporaryHUDKind?
    @Published private(set) var activeTemporaryHUDFlavor: BatteryHUDFlavor = .standard
    @Published private(set) var activeTemporaryHUDToken: UUID = UUID()
    @Published private(set) var activeTemporaryHUDTargetScreenName: String?
    @Published private(set) var activeTemporaryHUDLevelOverride: Int?
    @Published private(set) var activeTemporaryHUDLowPowerModeOverride: Bool?

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
        setupDetailsRefresh()
    }

    // MARK: - Details

    /// IOPS only pushes changes to the level and the charging flags; the time
    /// estimate and charge power drift on their own, so refresh on a slow timer
    /// as well as on every battery event.
    private func setupDetailsRefresh() {
        guard details.level != nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            // Nothing is visible while the display sleeps.
            guard !ActivityMonitor.currentGate.isSuspended else { return }
            self?.refreshDetails()
        }
        timer.tolerance = ActivityGate.tolerance(for: 30, minimum: 3)
        RunLoop.main.add(timer, forMode: .common)
        detailsTimer = timer
    }

    func refreshDetails() {
        let fresh = MacBatteryManager.shared.currentDetails()
        guard fresh != details else { return }
        withAnimation(NotchlyTheme.Motion.spring) {
            details = fresh
        }
        evaluateAlerts()
    }

    /// What the temporary HUD should add to its base layout.
    var activeTemporaryHUDExtras: BatteryHUDExtras {
        guard let kind = activeTemporaryHUDKind else { return .none }
        return hudExtras(for: kind, flavor: activeTemporaryHUDFlavor)
    }

    func hudExtras(for kind: BatteryTemporaryHUDKind, flavor: BatteryHUDFlavor) -> BatteryHUDExtras {
        var extras = BatteryHUDExtras(flavor: flavor)
        switch kind {
        case .charging:
            if Defaults[.showBatteryTimeRemaining], let time = details.time, time.kind == .toFull {
                extras.timeText = time.captionText
            }
            if Defaults[.showChargerWattage], let watts = details.adapterWatts {
                extras.wattsText = "\(watts)W"
            }
            if Defaults[.showChargingStatusText] {
                switch details.state {
                case .fastCharging:
                    extras.statusTitle = String(localized: "Fast charging")
                    extras.isFastCharging = true
                case .slowCharging:
                    extras.statusTitle = String(localized: "Charging slowly")
                case .held(let percent):
                    extras.statusTitle = String(localized: "Held at \(percent)%")
                    extras.heldAtPercent = percent
                default:
                    break
                }
            }
        case .lowBattery:
            if Defaults[.showBatteryTimeRemaining], let time = details.time, time.kind == .remaining {
                extras.timeText = time.captionText
            }
        case .fullBattery:
            if flavor == .chargeHeld {
                extras.heldAtPercent = Int(levelBattery.rounded())
            }
        }
        return extras
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            let wasPluggedIn = self.isPluggedIn
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.statusText = isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
            }
            if !wasPluggedIn && isPluggedIn {
                presentTemporaryBatteryHUDIfNeeded(kind: .charging)
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            let wasEnabled = self.isInLowPowerMode
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.statusText = String(localized: "Low Power: \(self.isInLowPowerMode ? String(localized: "On") : String(localized: "Off"))")
            }
            if !wasEnabled && isEnabled {
                presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery)
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? String(localized: "Charging battery")
                    : (self.levelBattery < self.maxCapacity ? String(localized: "Not charging") : String(localized: "Full charge"))
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }

        refreshDetails()
        evaluateAlerts()
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? String(localized: "Plugged In") : String(localized: "Unplugged")
        }
        self.details = MacBatteryManager.shared.currentDetails()
        evaluateAlerts()
    }

    private func presentTemporaryBatteryHUDIfNeeded(kind: BatteryTemporaryHUDKind) {
        presentTemporaryBatteryHUDIfNeeded(kind: kind, force: false)
    }

    func triggerTestHUD(kind: BatteryTemporaryHUDKind, flavor: BatteryHUDFlavor = .standard) {
        let previewLevel: Int

        switch (kind, flavor) {
        case (.charging, _):
            previewLevel = max(12, min(95, Int(levelBattery.rounded())))
        case (.lowBattery, .critical):
            previewLevel = max(1, min(Defaults[.criticalBatteryHUDThreshold], 15))
        case (.lowBattery, _):
            previewLevel = max(5, min(20, Defaults[.lowBatteryHUDThreshold]))
        case (.fullBattery, .chargeHeld):
            previewLevel = details.level ?? 80
        case (.fullBattery, _):
            previewLevel = 100
        }

        presentTemporaryBatteryHUDIfNeeded(
            kind: kind,
            flavor: flavor,
            force: true,
            levelOverride: previewLevel,
            lowPowerModeOverride: kind == .lowBattery ? isInLowPowerMode : nil
        )
    }

    private func presentTemporaryBatteryHUDIfNeeded(
        kind: BatteryTemporaryHUDKind,
        flavor: BatteryHUDFlavor = .standard,
        force: Bool,
        levelOverride: Int? = nil,
        lowPowerModeOverride: Bool? = nil
    ) {
        guard force || Defaults[.showPowerStatusNotifications] else { return }

        let duration: Int
        let isEnabled: Bool

        switch (kind, flavor) {
        case (.charging, _):
            duration = Defaults[.chargingBatteryHUDDuration]
            isEnabled = Defaults[.showChargingBatteryHUD]
        case (.lowBattery, .critical):
            // The critical alert lingers a little longer than an ordinary low one.
            duration = Defaults[.lowBatteryHUDDuration] + 2
            isEnabled = Defaults[.showCriticalBatteryHUD]
        case (.lowBattery, _):
            duration = Defaults[.lowBatteryHUDDuration]
            isEnabled = Defaults[.showLowBatteryHUD]
        case (.fullBattery, .chargeHeld):
            duration = Defaults[.fullBatteryHUDDuration]
            isEnabled = Defaults[.showChargeHeldHUD]
        case (.fullBattery, _):
            duration = Defaults[.fullBatteryHUDDuration]
            isEnabled = Defaults[.showFullBatteryHUD]
        }

        guard force || isEnabled else { return }

        activeTemporaryHUDKind = kind
        activeTemporaryHUDFlavor = flavor
        activeTemporaryHUDToken = UUID()
        activeTemporaryHUDTargetScreenName = resolvedTemporaryHUDTargetScreenName()
        activeTemporaryHUDLevelOverride = levelOverride
        activeTemporaryHUDLowPowerModeOverride = lowPowerModeOverride
        coordinator.toggleExpandingView(
            status: true,
            type: .battery,
            autoHideDuration: TimeInterval(max(1, duration))
        )
    }

    private func resolvedTemporaryHUDTargetScreenName() -> String? {
        if Defaults[.showOnAllDisplays] {
            return nil
        }

        let preferredNames = [
            coordinator.selectedScreen,
            coordinator.preferredScreen,
            NSScreen.main?.localizedName
        ]
        .compactMap { $0 }

        for candidate in preferredNames where NSScreen.screens.contains(where: { $0.localizedName == candidate }) {
            return candidate
        }

        return NSScreen.screens.first?.localizedName
    }

    private func preferredDynamicIslandTargetScreenName() -> String? {
        let mainScreenName = NSScreen.main?.localizedName
        let preferredNames = [coordinator.selectedScreen, coordinator.preferredScreen]

        for candidate in preferredNames where shouldUseDynamicIslandMode(for: candidate) {
            return candidate
        }

        if let externalDynamicIslandScreen = NSScreen.screens.first(where: {
            $0.localizedName != mainScreenName && shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return externalDynamicIslandScreen.localizedName
        }

        if let anyDynamicIslandScreen = NSScreen.screens.first(where: {
            shouldUseDynamicIslandMode(for: $0.localizedName)
        }) {
            return anyDynamicIslandScreen.localizedName
        }

        return nil
    }

    // MARK: - Alerts

    /// Low, critical, full and "charging held" alerts, all decided by
    /// `BatteryAlertStateMachine`. Runs after every battery event and every
    /// detail refresh.
    private func evaluateAlerts() {
        // No internal battery (desktop Mac): nothing to alert about.
        guard details.level != nil else { return }

        let isHeld: Bool = {
            if case .held = details.state { return true }
            return false
        }()
        let reading = BatteryAlertReading(
            level: Int(levelBattery.rounded()),
            isPluggedIn: isPluggedIn,
            isHeld: isHeld
        )
        let config = BatteryAlertConfig(
            lowEnabled: Defaults[.showLowBatteryHUD],
            lowThreshold: Defaults[.lowBatteryHUDThreshold],
            criticalEnabled: Defaults[.showCriticalBatteryHUD],
            criticalThreshold: min(Defaults[.criticalBatteryHUDThreshold], Defaults[.lowBatteryHUDThreshold] - 1),
            fullEnabled: Defaults[.showFullBatteryHUD],
            fullThreshold: Defaults[.fullBatteryHUDThreshold],
            chargeHeldEnabled: Defaults[.showChargeHeldHUD]
        )

        guard let alert = alertMachine.update(reading, config: config) else { return }

        switch alert {
        case .low:
            statusText = String(localized: "Low battery")
            presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery, flavor: .standard, force: false)
            if Defaults[.playLowBatteryAlertSound] { playLowBatteryAlertSound() }
        case .critical:
            statusText = String(localized: "Critical battery")
            presentTemporaryBatteryHUDIfNeeded(kind: .lowBattery, flavor: .critical, force: false)
            if Defaults[.playLowBatteryAlertSound] { playLowBatteryAlertSound() }
        case .full:
            statusText = String(localized: "Full charge")
            presentTemporaryBatteryHUDIfNeeded(kind: .fullBattery, flavor: .standard, force: false)
        case .chargeHeld:
            statusText = String(localized: "Charging held")
            presentTemporaryBatteryHUDIfNeeded(kind: .fullBattery, flavor: .chargeHeld, force: false)
        }
    }

    private func playLowBatteryAlertSound() {
        lowBatteryAlertSoundPlayer.play(fileName: "lowbattery", fileExtension: "mp3")
    }

    deinit {
        detailsTimer?.invalidate()
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
