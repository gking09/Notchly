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


import AVFoundation
import CoreBluetooth
import Defaults
import Foundation

// MARK: - Steps

/// The three screens of the first-launch flow, in order.
enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case permissions
    case done

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var isFirst: Bool { self == Self.allCases.first }
    var isLast: Bool { self == Self.allCases.last }
    var number: Int { rawValue + 1 }
    static var count: Int { allCases.count }

    var title: String {
        switch self {
        case .welcome: return String(localized: "Welcome")
        case .permissions: return String(localized: "Permissions")
        case .done: return String(localized: "Done")
        }
    }
}

/// Words used on the screens, kept in one place so tests can hold them to the brief.
enum OnboardingCopy {
    static let tagline = String(localized: "Your notch, made useful: music, battery, a clock Hub and a drop-in stash.")
    static let permissionsTitle = String(localized: "A few optional permissions")
    static let permissionsSubtitle = String(localized: "Notchly works without any of these. Grant the ones you want now.")
    static let permissionsFooter = String(localized: "You can do this later in Settings.")
    static let tip = String(localized: "Hover over the notch to open it. Drag files or text onto it to stash them.")
}

// MARK: - Permissions

/// What a permission row can say about itself.
enum OnboardingPermissionStatus: Equatable {
    case granted
    case notGranted
    /// The user said no; only System Settings can change that now.
    case denied
    /// macOS asks the first time the feature is used, and Notchly cannot ask earlier.
    case onDemand

    var label: String {
        switch self {
        case .granted: return String(localized: "Granted")
        case .notGranted: return String(localized: "Not granted")
        case .denied: return String(localized: "Denied")
        case .onDemand: return String(localized: "On first use")
        }
    }

    var isGranted: Bool { self == .granted }

    init(accessibilityTrusted: Bool) {
        self = accessibilityTrusted ? .granted : .notGranted
    }

    init(camera status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined: self = .notGranted
        @unknown default: self = .notGranted
        }
    }

    init(bluetooth status: CBManagerAuthorization) {
        switch status {
        case .allowedAlways: self = .granted
        case .denied, .restricted: self = .denied
        case .notDetermined: self = .notGranted
        @unknown default: self = .notGranted
        }
    }
}

/// The permissions Notchly really uses today (see the usage strings in the project and the
/// code that asks for them). Screen recording and microphone are deliberately absent: the app
/// only *detects* those being used by other apps, and mutes through CoreAudio.
enum OnboardingPermission: String, CaseIterable, Identifiable {
    case accessibility
    case automation
    case camera
    case bluetooth
    case fullDiskAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return String(localized: "Accessibility")
        case .automation: return String(localized: "Automation")
        case .camera: return String(localized: "Camera")
        case .bluetooth: return String(localized: "Bluetooth")
        case .fullDiskAccess: return String(localized: "Full Disk Access")
        }
    }

    var detail: String {
        switch self {
        case .accessibility:
            return String(localized: "Replaces the system volume and brightness HUD by reading the media keys.")
        case .automation:
            return String(localized: "Controls Spotify and Apple Music, and toggles Dark Mode.")
        case .camera:
            return String(localized: "Only for the Mirror preview in the notch. Nothing is recorded.")
        case .bluetooth:
            return String(localized: "Shows connected audio devices and their battery level.")
        case .fullDiskAccess:
            return String(localized: "Detects custom Focus modes. Needs a manual switch in System Settings.")
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .automation: return "gearshape.2"
        case .camera: return "camera"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .fullDiskAccess: return "externaldrive"
        }
    }

    /// Whether Notchly can ask for it up front. Automation can't: the prompt belongs to
    /// the app being controlled, so it only appears the first time it is needed.
    var canRequest: Bool { self != .automation }

    var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .automation: pane = "Privacy_Automation"
        case .camera: pane = "Privacy_Camera"
        case .bluetooth: pane = "Privacy_Bluetooth"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    /// The status to show before anything has been checked.
    var initialStatus: OnboardingPermissionStatus {
        canRequest ? .notGranted : .onDemand
    }

    /// The button on the row: "Grant" to ask, "Open Settings" once macOS has been told no,
    /// nothing when it is already granted or cannot be asked for.
    func actionTitle(for status: OnboardingPermissionStatus) -> String? {
        guard canRequest else { return nil }
        switch status {
        case .granted, .onDemand: return nil
        case .notGranted: return String(localized: "Grant")
        case .denied: return String(localized: "Open Settings")
        }
    }
}

// MARK: - Defaults

enum OnboardingDefaults {
    /// What the removed "profile" step used to set for everyone, so a fresh install still
    /// starts sensibly: the menu-bar icon, haptics, no inline lyrics, and the notch shape
    /// that matches the Mac it is running on.
    static func applyFirstLaunchDefaults(hasNotch: Bool) {
        Defaults[.menubarIcon] = true
        Defaults[.enableHaptics] = true
        Defaults[.enableLyrics] = false
        Defaults[.externalDisplayStyle] = hasNotch ? .notch : .dynamicIsland
    }
}
