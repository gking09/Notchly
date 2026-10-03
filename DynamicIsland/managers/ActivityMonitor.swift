import AppKit
import Combine
import Defaults
import Foundation
import IOKit.ps
import os

/// Keeps an `ActivityGate` current from the real system signals: display sleep,
/// Low Power Mode, the power source and the Efficiency mode setting.
///
/// Observing is cheap and event driven, so it never polls. Subscribe to `$gate`
/// to retime a poller; read `gate` when a view body or timer needs the value.
@MainActor
final class ActivityMonitor: ObservableObject {
    static let shared = ActivityMonitor()

    @Published private(set) var gate: ActivityGate {
        didSet { Self.publish(gate) }
    }

    private static let snapshot = OSAllocatedUnfairLock(initialState: ActivityGate())

    private nonisolated static func publish(_ gate: ActivityGate) {
        snapshot.withLock { $0 = gate }
    }

    /// The current gate, readable from any thread (timers, audio and poll queues).
    nonisolated static var currentGate: ActivityGate { snapshot.withLock { $0 } }

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var cancellables = Set<AnyCancellable>()
    private var powerSource: CFRunLoopSource?

    private init() {
        gate = ActivityGate(
            efficiencyModeEnabled: Defaults[.efficiencyMode],
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            onBattery: Self.isOnBattery(),
            screenAsleep: false
        )
        Self.publish(gate)

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.gate.screenAsleep = true }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.gate.screenAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.gate.screenAsleep = false }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.gate.screenAsleep = false }
        observe(.default, .NSProcessInfoPowerStateDidChange) {
            $0.gate.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }

        Defaults.publisher(.efficiencyMode, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.gate.efficiencyModeEnabled = change.newValue
            }
            .store(in: &cancellables)

        installPowerSourceObserver()
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ update: @escaping @MainActor (ActivityMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                update(self)
            }
        }
        observers.append((center, token))
    }

    /// IOPS posts a run-loop source callback whenever the power source or its
    /// state changes, so on-battery needs no timer.
    private func installPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<ActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.gate.onBattery = ActivityMonitor.isOnBattery() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSource = source
    }

    nonisolated static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        else { return false }
        return type == kIOPSBatteryPowerValue
    }
}
