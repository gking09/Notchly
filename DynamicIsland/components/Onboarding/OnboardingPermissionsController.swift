/*
 * Notchly (forked from Atoll by Ebullioscopic)
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


import AppKit
import AVFoundation
import CoreBluetooth
import Foundation

/// Reads and requests the permissions listed in `OnboardingPermission`, using the same
/// calls the features themselves make. Statuses refresh once a second while the
/// permissions screen is up, so a switch flipped in System Settings shows straight away.
@MainActor
final class OnboardingPermissionsController: ObservableObject {
    @Published private(set) var statuses: [OnboardingPermission: OnboardingPermissionStatus]

    private let liveChecks: Bool
    private var pollTimer: Timer?
    /// Kept alive so the Bluetooth prompt can finish.
    private var bluetoothManager: CBCentralManager?

    /// `liveChecks: false` freezes the given statuses (previews and tests).
    init(statuses: [OnboardingPermission: OnboardingPermissionStatus]? = nil, liveChecks: Bool = true) {
        self.liveChecks = liveChecks
        if let statuses {
            self.statuses = statuses
        } else {
            self.statuses = Dictionary(
                uniqueKeysWithValues: OnboardingPermission.allCases.map { ($0, $0.initialStatus) }
            )
        }
        if liveChecks { refresh() }
    }

    deinit {
        pollTimer?.invalidate()
    }

    func status(for permission: OnboardingPermission) -> OnboardingPermissionStatus {
        statuses[permission] ?? permission.initialStatus
    }

    // MARK: Polling

    func startPolling() {
        guard liveChecks, pollTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        guard liveChecks else { return }
        var updated = statuses
        updated[.accessibility] = OnboardingPermissionStatus(accessibilityTrusted: AXIsProcessTrusted())
        updated[.camera] = OnboardingPermissionStatus(camera: AVCaptureDevice.authorizationStatus(for: .video))
        updated[.bluetooth] = OnboardingPermissionStatus(bluetooth: CBCentralManager.authorization)
        updated[.fullDiskAccess] = FullDiskAccessAuthorization.hasPermission() ? .granted : .notGranted
        updated[.automation] = .onDemand
        if updated != statuses { statuses = updated }
    }

    // MARK: Requests

    /// The row's button: ask when macOS has not been asked yet, otherwise point at System Settings.
    func performAction(for permission: OnboardingPermission) {
        guard permission.canRequest else { return }
        if status(for: permission) == .denied {
            openSettings(for: permission)
        } else {
            request(permission)
        }
    }

    func openSettings(for permission: OnboardingPermission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }

    private func request(_ permission: OnboardingPermission) {
        switch permission {
        case .accessibility:
            AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }
        case .bluetooth:
            // Creating a central manager is what makes macOS show the Bluetooth prompt.
            bluetoothManager = CBCentralManager(
                delegate: nil,
                queue: nil,
                options: [CBCentralManagerOptionShowPowerAlertKey: false]
            )
        case .fullDiskAccess:
            FullDiskAccessPermissionStore.shared.requestAccessPrompt()
        case .automation:
            break
        }
        refresh()
    }
}
