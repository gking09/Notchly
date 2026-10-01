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

import AppKit
import AVFoundation
import Defaults
import SwiftUI

/// Live Activities: everything that pops out of the notch by itself, in one
/// scroll. Battery, volume and brightness, Bluetooth devices, Focus, Caps Lock,
/// screen recording and privacy, downloads and the lock screen. A bar of chips
/// above the cards jumps to each section.
struct NotchlyLiveActivitiesPage: View {
    typealias I = Item

    /// The sections of the page, in scroll order.
    enum Section: String, CaseIterable, Identifiable {
        case battery, controls, devices, focus, recording, downloads, lock

        var id: String { rawValue }

        var title: String {
            switch self {
            case .battery: return String(localized: "Battery & Charging")
            case .controls: return String(localized: "Volume & Brightness")
            case .devices: return String(localized: "Devices")
            case .focus: return String(localized: "Focus & Caps Lock")
            case .recording: return String(localized: "Recording & Privacy")
            case .downloads: return String(localized: "Downloads")
            case .lock: return String(localized: "Lock & Unlock")
            }
        }

        var symbol: String {
            switch self {
            case .battery: return "battery.100.bolt"
            case .controls: return "dial.medium"
            case .devices: return "headphones"
            case .focus: return "moon"
            case .recording: return "record.circle"
            case .downloads: return "arrow.down.circle"
            case .lock: return "lock"
            }
        }

        var anchorID: String { "liveActivities/section/\(rawValue)" }
    }

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @ObservedObject private var recordingManager = ScreenRecordingManager.shared
    @ObservedObject private var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject private var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.showCriticalBatteryHUD) private var showCriticalBatteryHUD
    @Default(.showChargeHeldHUD) private var showChargeHeldHUD
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle
    @Default(.showBluetoothLowBatteryAlert) private var showBluetoothLowBatteryAlert
    @Default(.progressBarStyle) private var progressBarStyle
    @Default(.useBluetoothHUD3DIcon) private var useBluetoothHUD3DIcon

    @Default(.enableScreenRecordingDetection) private var enableScreenRecordingDetection
    @Default(.showRecordingIndicator) private var showRecordingIndicator
    @Default(.recordingHoverStyle) private var recordingHoverStyle
    @Default(.recordingControlMode) private var recordingControlMode
    @Default(.enableDoNotDisturbDetection) private var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) private var focusIndicatorNonPersistent
    @Default(.enableCapsLockIndicator) private var enableCapsLockIndicator
    @Default(.capsLockIndicatorTintMode) private var capsLockTintMode

    @Default(.enableDownloadListener) private var enableDownloadListener
    @Default(.selectedDownloadIndicatorStyle) private var downloadIndicatorStyle

    @Default(.lockScreenLiveActivityIconStyle) private var lockIconStyle
    @Default(.siriResponsivenessMode) private var siriResponsivenessMode

    private var hasBattery: Bool { BatteryActivityManager.shared.hasBattery() }

    private var visibleSections: [Section] {
        Section.allCases.filter { $0 != .battery || hasBattery }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            jumpBar
            NotchlyPageScroll(page: .liveActivities) {
                if hasBattery {
                    batterySection.id(Section.battery.anchorID)
                } else {
                    noBatteryCard
                }
                NotchlyControlsCards().id(Section.controls.anchorID)
                devicesSection.id(Section.devices.anchorID)
                focusSection.id(Section.focus.anchorID)
                recordingSection.id(Section.recording.anchorID)
                downloadsSection.id(Section.downloads.anchorID)
                lockSection.id(Section.lock.anchorID)
            }
        }
        .animation(NotchlyTheme.Motion.snappy, value: showPowerStatusNotifications)
        .animation(NotchlyTheme.Motion.snappy, value: enableScreenRecordingDetection)
        .animation(NotchlyTheme.Motion.snappy, value: enableDoNotDisturbDetection)
        .animation(NotchlyTheme.Motion.snappy, value: enableCapsLockIndicator)
        .animation(NotchlyTheme.Motion.snappy, value: enableDownloadListener)
        .onAppear { fullDiskAccessPermission.refreshStatus() }
    }

    // MARK: Jump bar

    private var jumpBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleSections) { section in
                    Button {
                        highlightCoordinator.pendingScrollRequest = SettingsHighlightCoordinator.ScrollRequest(
                            id: section.anchorID,
                            scope: NotchlySettingsPage.liveActivities.rawValue,
                            anchor: .top
                        )
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(.notchly(.standard))
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 2)
        }
        .padding(.bottom, 12)
    }

    // MARK: Battery

    private var noBatteryCard: some View {
        NotchlySettingsCard("Battery & Charging") {
            NotchlyNoticeRow(text: "Battery and charging alerts are only available on MacBooks. Bluetooth device batteries are under Devices.")
        }
    }

    private var alertsOn: Bool { showPowerStatusNotifications }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard("Battery & Charging") {
                I.batteryIndicator.toggle("Show the battery in the notch.", key: .showBatteryIndicator)
                I.batteryPercentage.toggle("Print the percentage next to the battery.", key: .showBatteryPercentage)
                I.powerIcons.toggle("A bolt or plug icon while charging or on the adapter.", key: .showPowerStatusIcons)
            }

            NotchlySettingsCard(
                "Charging details",
                footer: "Each line appears only when macOS reports the data. Click the battery in the open notch for health and cycle count."
            ) {
                I.timeRemaining.toggle("Time left on battery, or time until full.", key: .showBatteryTimeRemaining)
                I.chargerWattage.toggle("How many watts the adapter is delivering.", key: .showChargerWattage)
                I.chargingStatus.toggle("Say when charging is fast or being held.", key: .showChargingStatusText)
                I.batteryHealth.toggle("Maximum capacity and cycle count.", key: .showBatteryHealthDetail)
            }

            NotchlySettingsCard(
                "Battery alerts",
                footer: "Short alerts that drop out of the notch when the power state changes."
            ) {
                I.powerNotifications.toggle("The master switch for every alert below.", key: .showPowerStatusNotifications)
                I.lowBatterySound.toggle("Play a sound when the battery gets low.", isEnabled: alertsOn, key: .playLowBatteryAlertSound)
                I.chargingHUD.toggle("When you plug in or unplug.", isEnabled: alertsOn, key: .showChargingBatteryHUD)
                I.lowBatteryHUD.toggle("When the battery drops below the low threshold.", isEnabled: alertsOn, key: .showLowBatteryHUD)
                I.criticalBatteryHUD.toggle("A stronger alert below the critical threshold.", isEnabled: alertsOn, key: .showCriticalBatteryHUD)
                I.fullBatteryHUD.toggle("When the battery reaches its full-charge level.", isEnabled: alertsOn, key: .showFullBatteryHUD)
                I.chargeLimitHUD.toggle("When macOS holds charging below 100%.", isEnabled: alertsOn, key: .showChargeHeldHUD)
            }

            NotchlySettingsCard("How long alerts stay") {
                I.chargingDuration.slider(
                    isEnabled: alertsOn && showChargingBatteryHUD,
                    key: .chargingBatteryHUDDuration, range: 1...10, valueLabel: { "\($0) s" }
                )
                I.lowDuration.slider(
                    isEnabled: alertsOn && showLowBatteryHUD,
                    key: .lowBatteryHUDDuration, range: 1...10, valueLabel: { "\($0) s" }
                )
                I.fullDuration.slider(
                    isEnabled: alertsOn && showFullBatteryHUD,
                    key: .fullBatteryHUDDuration, range: 1...10, valueLabel: { "\($0) s" }
                )
            }

            NotchlySettingsCard(
                "Thresholds",
                footer: "Critical is always kept below the low-battery level. Set the full-charge level to your charge limit; if macOS holds charging below 100% (Optimized Battery Charging or a limit), the charge limit alert tells you once per plug-in."
            ) {
                I.lowBatteryStyle.picker(
                    "Compact matches the charging alert. Standard is the larger card.",
                    isEnabled: alertsOn && showLowBatteryHUD,
                    selection: $lowBatteryHUDStyle,
                    options: Array(BatteryNotificationStyle.allCases),
                    style: .segmented,
                    label: { $0.title }
                )
                I.lowBatteryThreshold.slider(
                    isEnabled: alertsOn && showLowBatteryHUD,
                    key: .lowBatteryHUDThreshold, range: 5...30, valueLabel: { "\($0)%" }
                )
                I.criticalThreshold.slider(
                    isEnabled: alertsOn && showCriticalBatteryHUD,
                    key: .criticalBatteryHUDThreshold, range: 3...15, valueLabel: { "\($0)%" }
                )
                I.fullBatteryStyle.picker(
                    "Compact keeps it inline. Standard shows the taller card with the charging animation.",
                    isEnabled: alertsOn && showFullBatteryHUD,
                    selection: $fullBatteryHUDStyle,
                    options: Array(BatteryNotificationStyle.allCases),
                    style: .segmented,
                    label: { $0.title }
                )
                I.fullThreshold.slider(
                    isEnabled: alertsOn && showFullBatteryHUD,
                    key: .fullBatteryHUDThreshold, range: 80...100, valueLabel: { "\($0)%" }
                )
            }

            NotchlySettingsCard(
                "Try the alerts",
                footer: "Runs the real animation on the current display. If an external screen is is in pill mode, the alert goes there first."
            ) {
                testRow(I.testCharging, isEnabled: alertsOn && showChargingBatteryHUD) {
                    batteryStatusViewModel.triggerTestHUD(kind: .charging)
                }
                testRow(I.testLow, isEnabled: alertsOn && showLowBatteryHUD) {
                    batteryStatusViewModel.triggerTestHUD(kind: .lowBattery)
                }
                testRow(I.testCritical, isEnabled: alertsOn && showCriticalBatteryHUD) {
                    batteryStatusViewModel.triggerTestHUD(kind: .lowBattery, flavor: .critical)
                }
                testRow(I.testFull, isEnabled: alertsOn && showFullBatteryHUD) {
                    batteryStatusViewModel.triggerTestHUD(kind: .fullBattery)
                }
                testRow(I.testChargeLimit, isEnabled: alertsOn && showChargeHeldHUD) {
                    batteryStatusViewModel.triggerTestHUD(kind: .fullBattery, flavor: .chargeHeld)
                }
            }
        }
    }

    private func testRow(_ item: NotchlySettingItem, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        item.row(isEnabled: isEnabled) {
            Button("Try it", action: action)
                .buttonStyle(.notchly)
        }
    }

    // MARK: Devices

    private var colorCodingDisabled: Bool { progressBarStyle == .segmented }

    private var batteryColorFooter: String {
        if colorCodingDisabled {
            return "Color-coded fills are unavailable with Segmented bars. Switch to Hierarchical or Gradient under Volume & Brightness."
        }
        if Defaults[.useSmoothColorGradient] {
            return "Smooth transitions blend green (0-60%), yellow (60-85%) and red (85-100%) through the whole fill."
        }
        return "Discrete transitions snap between green (0-60%), yellow (60-85%) and red (85-100%)."
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard(
                "Devices",
                footer: "Shows a short alert when headphones, AirPods or speakers connect, with the device name and battery."
            ) {
                I.bluetoothConnections.toggle("Alert when a Bluetooth audio device connects.", key: .showBluetoothDeviceConnections)
                I.circularBattery.toggle("Show the battery as a ring instead of a bar.", key: .useCircularBluetoothBatteryIndicator)
                I.bluetoothBatteryText.toggle("Print the battery percentage in the alert.", key: .showBluetoothBatteryPercentageText)
                I.deviceNameMarquee.toggle("Scroll long device names.", key: .showBluetoothDeviceNameMarquee)
                I.airPodsListening.toggle("Alert when you switch between Noise Cancellation, Transparency and Off.", key: .showAirPodsListeningModeChanges)
                I.bluetoothIconStyle.tiles("The picture shown next to the device.") {
                    NotchlyChoiceTile(title: String(localized: "Symbol"), isSelected: !useBluetoothHUD3DIcon, size: CGSize(width: 96, height: 64)) {
                        useBluetoothHUD3DIcon = false
                    } preview: {
                        Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    NotchlyChoiceTile(title: String(localized: "3D"), isSelected: useBluetoothHUD3DIcon, size: CGSize(width: 96, height: 64)) {
                        useBluetoothHUD3DIcon = true
                    } preview: {
                        if let url = BluetoothAudioDeviceType.airpods.inlineHUDAnimationURL {
                            NotchlyLoopingVideoIcon(url: url, size: CGSize(width: 28, height: 28))
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                                .font(.system(size: 24, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
            }

            NotchlySettingsCard(
                "Device batteries",
                footer: "AirPods, headphones, mice, keyboards and trackpads that report a battery level. Each device alerts once per connection."
            ) {
                I.bluetoothLowAlert.toggle("Warn when a connected device is running low.", key: .showBluetoothLowBatteryAlert)
                I.bluetoothLowThreshold.slider(
                    "Alert at or below this level.",
                    isEnabled: showBluetoothLowBatteryAlert,
                    key: .bluetoothLowBatteryThreshold, range: 5...40, step: 5, valueLabel: { "\($0)%" }
                )
            }

            NotchlySettingsCard("Battery colors", footer: batteryColorFooter) {
                I.colorCodedBattery.toggle(
                    "Green, yellow and red as the battery level changes.",
                    isEnabled: !colorCodingDisabled,
                    key: .useColorCodedBatteryDisplay
                )
            }
        }
    }

    // MARK: Focus & Caps Lock

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard(
                "Focus",
                footer: "Listens for Focus changes through distributed notifications."
            ) {
                if !fullDiskAccessPermission.isAuthorized {
                    NotchlyPermissionRow(
                        title: String(localized: "Custom Focus metadata"),
                        message: String(localized: "Full Disk Access unlocks custom Focus icons, colors and labels. Standard Focus detection still works without it. Grant access only if you want personalized indicators."),
                        symbol: "externaldrive.fill",
                        tint: .purple,
                        requestTitle: String(localized: "Request Full Disk Access"),
                        openTitle: String(localized: "Open Privacy & Security"),
                        requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                        openAction: { fullDiskAccessPermission.openSystemSettings() }
                    )
                }
                I.focusDetection.toggle("Notice when a Focus turns on or off.", key: .enableDoNotDisturbDetection)
                I.focusIndicator.toggle("Show the Focus icon in the notch.", isEnabled: enableDoNotDisturbDetection, key: .showDoNotDisturbIndicator)
                I.focusLabel.toggle(
                    focusIndicatorNonPersistent
                        ? "Labels are forced to short on/off text in brief toast mode."
                        : "Show the name of the active Focus.",
                    isEnabled: enableDoNotDisturbDetection && !focusIndicatorNonPersistent,
                    key: .showDoNotDisturbLabel
                )
                I.focusToast.toggle(
                    "Show Focus briefly, then collapse instead of staying visible.",
                    isEnabled: enableDoNotDisturbDetection,
                    key: .focusIndicatorNonPersistent
                )
                focusStatusRow
            }

            NotchlySettingsCard(
                "Caps Lock",
                footer: "Adds a notch alert when Caps Lock is on, with an optional label and tint."
            ) {
                I.capsLock.toggle("Show an indicator while Caps Lock is on.", key: .enableCapsLockIndicator)
                I.capsLockLabel.toggle("Add the words Caps Lock to the indicator.", isEnabled: enableCapsLockIndicator, key: .showCapsLockLabel)
                I.capsLockColor.picker(
                    isEnabled: enableCapsLockIndicator,
                    selection: $capsLockTintMode,
                    options: Array(CapsLockIndicatorTintMode.allCases),
                    style: .segmented,
                    label: { $0.displayName }
                )
            }
        }
    }

    @ViewBuilder
    private var focusStatusRow: some View {
        if doNotDisturbManager.isMonitoring {
            if doNotDisturbManager.isDoNotDisturbActive {
                NotchlyStatusRow(
                    title: String(localized: "Focus status"),
                    status: doNotDisturbManager.currentFocusModeName.isEmpty ? String(localized: "Focus on") : doNotDisturbManager.currentFocusModeName,
                    tint: .purple
                )
            } else {
                NotchlyStatusRow(title: String(localized: "Focus status"), status: String(localized: "Listening, no Focus on"), tint: .green)
            }
        } else {
            NotchlyStatusRow(title: String(localized: "Focus status"), status: String(localized: "Off"), showsDot: false)
        }
    }

    // MARK: Recording & privacy

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard(
                "Screen recording",
                footer: "Uses an event-driven private API to notice recordings the moment they start."
            ) {
                I.recordingDetection.toggle("Notice when the screen is being recorded.", key: .enableScreenRecordingDetection)
                I.recordingIndicator.toggle("A red indicator in the notch while recording.", isEnabled: enableScreenRecordingDetection, key: .showRecordingIndicator)
                I.recordingControls.picker(
                    "Indicator only stays passive. With stop button adds native recording controls.",
                    isEnabled: enableScreenRecordingDetection,
                    selection: $recordingControlMode,
                    options: Array(RecordingControlMode.allCases),
                    style: .segmented,
                    label: { $0.title }
                )
                I.recordingHover.picker(
                    "Default uses the expanded HUD. Inline keeps the stop control inside the notch height.",
                    isEnabled: enableScreenRecordingDetection && showRecordingIndicator && recordingControlMode == .withStopButton,
                    selection: $recordingHoverStyle,
                    options: Array(RecordingHoverStyle.allCases),
                    style: .segmented,
                    label: { $0.title }
                )
                if recordingManager.isMonitoring {
                    NotchlyStatusRow(
                        title: String(localized: "Detection status"),
                        status: recordingManager.isRecording ? String(localized: "Recording detected") : String(localized: "Listening, no recording"),
                        tint: recordingManager.isRecording ? .red : .green
                    )
                }
            }

            NotchlySettingsCard(
                "Privacy indicators",
                footer: "A green camera and a yellow microphone appear while an app is using them. Uses event-driven CoreAudio and CoreMediaIO."
            ) {
                I.cameraDetection.toggle("Show a camera icon while the camera is on.", key: .enableCameraDetection)
                I.microphoneDetection.toggle("Show a microphone icon while the mic is on.", key: .enableMicrophoneDetection)
                if privacyManager.isMonitoring {
                    NotchlyStatusRow(
                        title: String(localized: "Camera status"),
                        status: privacyManager.cameraActive ? String(localized: "Camera active") : String(localized: "Inactive"),
                        tint: privacyManager.cameraActive ? .green : .secondary,
                        showsDot: privacyManager.cameraActive
                    )
                    NotchlyStatusRow(
                        title: String(localized: "Microphone status"),
                        status: privacyManager.microphoneActive ? String(localized: "Microphone active") : String(localized: "Inactive"),
                        tint: privacyManager.microphoneActive ? .yellow : .secondary,
                        showsDot: privacyManager.microphoneActive
                    )
                }
            }
        }
    }

    // MARK: Downloads

    private var downloadsSection: some View {
        NotchlySettingsCard(
            "Downloads",
            footer: "Works with Safari, Firefox, Chrome and browsers built on it: Edge, Brave, Arc, Vivaldi and Opera. Only your Downloads folder is watched, so a file saved anywhere else will not appear."
        ) {
            I.downloadDetection.toggle("Show a live activity in the notch while a file downloads.", key: .enableDownloadListener)
            I.downloadStyle.tiles(
                "A bar that fills as the download runs, or a ring around the notch's corner.",
                isEnabled: enableDownloadListener
            ) {
                NotchlyChoiceTile(title: DownloadIndicatorStyle.progress.rawValue, isSelected: downloadIndicatorStyle == .progress, size: CGSize(width: 96, height: 64)) {
                    downloadIndicatorStyle = .progress
                } preview: {
                    ProgressView().progressViewStyle(.linear).tint(.primary).frame(width: 40)
                }
                NotchlyChoiceTile(title: DownloadIndicatorStyle.circle.rawValue, isSelected: downloadIndicatorStyle == .circle, size: CGSize(width: 96, height: 64)) {
                    downloadIndicatorStyle = .circle
                } preview: {
                    SpinningCircleDownloadView()
                }
            }
            I.downloadSpeed.toggle(
                "Show the current rate, measured from how fast files in your Downloads folder are growing.",
                isEnabled: enableDownloadListener,
                key: .showDownloadSpeed
            )
        }
    }

    // MARK: Lock & unlock

    private var lockSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard(
                "Lock & Unlock",
                footer: "Pick the lock, the fingerprint, or both. With the fingerprint selected the activity stays open long enough to finish its unlock animation."
            ) {
                I.lockActivity.toggle("Show a live activity when the Mac locks and unlocks.", key: .enableLockScreenLiveActivity)
                I.lockIcon.tiles("What the activity shows.") {
                    NotchlyChoiceTile(title: String(localized: "Lock"), isSelected: lockIconStyle.showsLock, size: CGSize(width: 84, height: 58)) {
                        toggleLockIcon(lock: true)
                    } preview: {
                        Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold)).symbolRenderingMode(.hierarchical)
                    }
                    NotchlyChoiceTile(title: String(localized: "Fingerprint"), isSelected: lockIconStyle.showsFingerprint, size: CGSize(width: 84, height: 58)) {
                        toggleLockIcon(lock: false)
                    } preview: {
                        Image(systemName: "touchid").font(.system(size: 14, weight: .semibold)).symbolRenderingMode(.hierarchical)
                    }
                }
                I.lockSounds.toggle("A soft chime when locking and unlocking.", key: .enableLockSounds)
            }

            NotchlySettingsCard(
                "Siri",
                footer: "Faster detection hides the lock screen and HUD overlays almost instantly when Siri opens, but can cost battery when unplugged."
            ) {
                I.siriSpeed.picker(
                    siriResponsivenessMode.description,
                    selection: $siriResponsivenessMode,
                    options: Array(SiriResponsivenessMode.allCases),
                    label: { $0.displayName }
                )
            }

            NotchlySettingsCard(
                "Diagnostics",
                footer: "Collects the latest crash report so you can share it when reporting lock screen or overlay problems."
            ) {
                NotchlySettingRow(
                    I.crashReport.title,
                    subtitle: "Copies the newest Notchly crash report to the clipboard.",
                    highlightID: I.crashReport.rowHighlightID
                ) {
                    Button("Copy") { Self.copyLatestCrashReport() }
                        .buttonStyle(.notchly)
                }
            }
        }
    }

    /// Lock and fingerprint are two independent switches that share one setting;
    /// at least one of them always stays on.
    private func toggleLockIcon(lock: Bool) {
        let isOn = lock ? lockIconStyle.showsLock : lockIconStyle.showsFingerprint
        if isOn {
            let otherIsOn = lock ? lockIconStyle.showsFingerprint : lockIconStyle.showsLock
            if otherIsOn { lockIconStyle = lock ? .fingerprint : .lock }
        } else {
            lockIconStyle = .both
        }
    }

    private static func copyLatestCrashReport() {
        let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
        let fileManager = FileManager.default

        do {
            let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
            let crashFiles = files.filter { ($0.contains("Notchly") || $0.contains("DynamicIsland")) && $0.hasSuffix(".crash") }

            guard let latestCrash = crashFiles.sorted(by: >).first else {
                let alert = NSAlert()
                alert.messageText = String(localized: "No Crash Reports Found")
                alert.informativeText = String(localized: "No crash reports found for Notchly")
                alert.alertStyle = .informational
                alert.runModal()
                return
            }

            let crashPath = (crashReportsPath as NSString).appendingPathComponent(latestCrash)
            let crashContent = try String(contentsOfFile: crashPath, encoding: .utf8)

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(crashContent, forType: .string)

            let alert = NSAlert()
            alert.messageText = String(localized: "Crash Report Copied")
            alert.informativeText = String(localized: "Crash report '\(latestCrash)' has been copied to clipboard")
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Error")
            alert.informativeText = String(localized: "Failed to read crash reports: \(error.localizedDescription)")
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

// MARK: - Looping 3D icon

/// A muted, looping video used to preview the 3D Bluetooth icon.
private struct NotchlyLoopingVideoIcon: NSViewRepresentable {
    let url: URL
    let size: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true

        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)
        context.coordinator.attach(layer: layer, url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func attach(layer: AVPlayerLayer, url: URL) {
            let player = AVQueuePlayer()
            player.isMuted = true
            player.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
            layer.player = player
            self.player = player
        }

        deinit {
            player?.pause()
            looper = nil
        }
    }
}

// MARK: - Search items

extension NotchlyLiveActivitiesPage {
    enum Item {
        private static func item(_ title: String, _ keywords: [String], anchoredTo anchor: NotchlySettingItem? = nil) -> NotchlySettingItem {
            NotchlySettingItem(.liveActivities, title, keywords: keywords, anchoredTo: anchor)
        }

        // Battery & charging
        static let batteryIndicator = item("Show battery indicator", ["battery hud", "charge", "battery"])
        static let batteryPercentage = item("Show battery percentage", ["battery percent", "battery"])
        static let powerIcons = item("Show power status icons", ["power icons", "charging icon", "bolt", "plug"])
        static let timeRemaining = item("Show time remaining", ["battery", "time remaining", "time to full", "eta"])
        static let chargerWattage = item("Show charger wattage", ["battery", "charger", "watts", "adapter"])
        static let chargingStatus = item("Show charging status", ["battery", "fast charging", "optimized", "held"])
        static let batteryHealth = item("Show battery health", ["battery", "health", "cycle count", "capacity"])
        static let powerNotifications = item("Show power status notifications", ["notifications", "power", "battery alerts", "huds"])
        static let lowBatterySound = item("Play low battery alert sound", ["low battery", "alert", "sound"])
        static let chargingHUD = item("Charging HUD", ["battery", "charging", "temporary activity", "plug in"])
        static let lowBatteryHUD = item("Low battery HUD", ["battery", "low", "temporary activity"])
        static let criticalBatteryHUD = item("Critical battery HUD", ["battery", "critical", "alert"])
        static let fullBatteryHUD = item("Fully charged HUD", ["battery", "full", "temporary activity"])
        static let chargeLimitHUD = item("Charge limit reached HUD", ["battery", "charge limit", "optimized", "held"])
        static let chargingDuration = item("Charging duration", ["charging", "duration", "seconds", "alert length"])
        static let lowDuration = item("Low battery duration", ["low battery", "duration", "seconds"])
        static let fullDuration = item("Full battery duration", ["full battery", "duration", "seconds"])
        static let lowBatteryStyle = item("Low battery style", ["battery", "style", "compact", "standard"])
        static let lowBatteryThreshold = item("Low battery threshold", ["battery", "threshold", "percent"])
        static let criticalThreshold = item("Critical battery threshold", ["battery", "critical", "threshold", "percent"])
        static let fullBatteryStyle = item("Full battery style", ["battery", "style", "compact", "standard"])
        static let fullThreshold = item("Full charge threshold", ["battery", "threshold", "full", "charge limit"])
        static let testCharging = item("Test charging HUD", ["battery", "test", "charging", "preview", "try"])
        static let testLow = item("Test low battery HUD", ["battery", "test", "low", "preview", "try"])
        static let testCritical = item("Test critical battery HUD", ["battery", "test", "critical", "preview", "try"])
        static let testFull = item("Test full battery HUD", ["battery", "test", "full", "preview", "try"])
        static let testChargeLimit = item("Test charge limit HUD", ["battery", "test", "charge limit", "preview", "try"])

        // Volume & brightness
        static let displayStyle = item("Volume & brightness style", ["hud", "osd", "on-screen display", "custom osd", "enable custom osd", "vertical", "circular", "dynamic island", "notch", "volume", "brightness", "backlight"])
        static let showVolume = item("Show volume changes", ["volume hud", "volume osd", "volume", "hud", "osd", "sound"])
        static let showBrightness = item("Show brightness changes", ["brightness hud", "brightness osd", "brightness", "hud", "osd", "display"])
        static let showBacklight = item("Show keyboard backlight changes", ["keyboard backlight hud", "keyboard backlight osd", "backlight", "keyboard", "hud", "osd"])
        static let volumeFeedback = item("Play feedback when volume is changed", ["volume", "click", "sound", "feedback", "keys"])
        static let hudLayout = item("HUD style", ["inline", "compact", "default", "hud"])
        static let progressStyle = item("Progressbar style", ["progress", "style", "hierarchical", "gradient", "segmented"])
        static let glow = item("Enable glowing effect", ["glow", "indicator", "shadow"])
        static let hudAccent = item("Use accent color", ["accent", "color", "hud"])
        static let colorCodedVolume = item("Color-coded volume display", ["volume", "color", "green", "red"])
        static let smoothColors = item("Smooth color transitions", ["gradient", "smooth", "color"])
        static let percentages = item("Show percentages beside progress bars", ["percentages", "progress", "value"])
        static let osdMaterial = item("Material", ["material", "frosted", "liquid", "glass", "solid", "osd"], anchoredTo: displayStyle)
        static let osdGlassMode = item("Glass mode", ["liquid glass", "custom liquid", "osd"], anchoredTo: displayStyle)
        static let osdGlassVariant = item("Custom liquid variant", ["liquid glass", "variant", "osd"], anchoredTo: displayStyle)
        static let osdIconColor = item("Icon & Progress Color", ["color", "icon", "white", "black", "gray", "osd"], anchoredTo: displayStyle)
        static let verticalPercent = item("Vertical bar percentage", ["vertical", "bar", "percent", "value"], anchoredTo: displayStyle)
        static let verticalAccent = item("Vertical bar accent color", ["vertical", "bar", "accent", "color"], anchoredTo: displayStyle)
        static let verticalInteractive = item("Drag to change the vertical bar", ["vertical", "bar", "interactive", "drag"], anchoredTo: displayStyle)
        static let verticalMaterial = item("Vertical bar material", ["vertical", "bar", "frosted", "liquid", "glass", "solid"], anchoredTo: displayStyle)
        static let verticalGlassMode = item("Vertical bar glass mode", ["vertical", "liquid glass", "custom liquid"], anchoredTo: displayStyle)
        static let verticalGlassVariant = item("Vertical bar liquid variant", ["vertical", "liquid glass", "variant"], anchoredTo: displayStyle)
        static let verticalPosition = item("Vertical bar position", ["vertical", "bar", "left", "right", "side"], anchoredTo: displayStyle)
        static let verticalPadding = item("Vertical bar screen padding", ["vertical", "bar", "padding", "gap", "edge"], anchoredTo: displayStyle)
        static let verticalWidth = item("Vertical bar width", ["vertical", "bar", "width", "size"], anchoredTo: displayStyle)
        static let verticalHeight = item("Vertical bar height", ["vertical", "bar", "height", "size"], anchoredTo: displayStyle)
        static let circularPercent = item("Circular HUD percentage", ["circular", "ring", "percent", "value"], anchoredTo: displayStyle)
        static let circularAccent = item("Circular HUD accent color", ["circular", "ring", "accent", "color"], anchoredTo: displayStyle)
        static let circularSize = item("Circular HUD size", ["circular", "ring", "size", "diameter"], anchoredTo: displayStyle)
        static let circularStroke = item("Circular HUD line width", ["circular", "ring", "stroke", "thickness", "line width"], anchoredTo: displayStyle)
        static let volumeStep = item("Volume step", ["volume", "step", "percent"])
        static let volumeFineStep = item("Volume fine step", ["volume", "fine", "step", "percent"])
        static let brightnessStep = item("Brightness step", ["brightness", "step", "percent"])
        static let brightnessFineStep = item("Brightness fine step", ["brightness", "fine", "step", "percent"])
        static let ddcIntegration = item("Third-party DDC app integration", ["ddc", "third party", "external", "display", "betterdisplay", "lunar", "monitor"])
        static let ddcProvider = item("Third-party DDC provider", ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], anchoredTo: ddcIntegration)
        static let ddcVolumeListener = item("Enable external volume control listener", ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], anchoredTo: ddcIntegration)

        // Devices
        static let bluetoothConnections = item("Show Bluetooth device connections", ["bluetooth", "hud", "headphones", "airpods", "connect"])
        static let circularBattery = item("Use circular battery indicator", ["battery", "circular", "ring"])
        static let bluetoothBatteryText = item("Show battery percentage text in HUD", ["battery text", "bluetooth", "percent"])
        static let deviceNameMarquee = item("Scroll device name in HUD", ["marquee", "device name", "scroll"])
        static let airPodsListening = item("Show AirPods listening mode changes", ["airpods", "noise cancellation", "transparency", "listening mode"])
        static let bluetoothIconStyle = item("Bluetooth HUD icon style", ["use 3d bluetooth hud icon", "bluetooth", "3d", "animation", "symbol", "airpods"])
        static let bluetoothLowAlert = item("Bluetooth low battery alert", ["bluetooth", "airpods", "mouse", "keyboard", "low battery"])
        static let bluetoothLowThreshold = item("Bluetooth low battery threshold", ["bluetooth", "threshold", "low battery", "percent"])
        static let colorCodedBattery = item("Color-coded battery display", ["color", "battery", "green", "red"])

        // Focus & Caps Lock
        static let focusDetection = item("Enable Focus Detection", ["focus", "do not disturb", "dnd"])
        static let focusIndicator = item("Show Focus Indicator", ["focus icon", "moon", "do not disturb"])
        static let focusLabel = item("Show Focus Label", ["focus label", "text", "name"])
        static let focusToast = item("Show Focus as brief toast", ["focus", "toast", "brief", "temporary"])
        static let capsLock = item("Show Caps Lock Indicator", ["caps lock", "keyboard", "indicator"])
        static let capsLockLabel = item("Show Caps Lock label", ["caps lock", "label", "text"])
        static let capsLockColor = item("Caps Lock color", ["caps lock", "tint", "green", "accent", "white"])

        // Recording & privacy
        static let recordingDetection = item("Enable Screen Recording Detection", ["screen recording", "indicator", "record"])
        static let recordingIndicator = item("Show Recording Indicator", ["recording indicator", "red dot"])
        static let recordingControls = item("Recording Controls", ["screen recording", "stop button", "indicator"])
        static let recordingHover = item("Recording Hover Style", ["screen recording", "hover", "inline", "stop"])
        static let cameraDetection = item("Enable Camera Detection", ["camera", "privacy indicator", "webcam"])
        static let microphoneDetection = item("Enable Microphone Detection", ["microphone", "privacy", "mic"])

        // Downloads
        static let downloadDetection = item("Enable download detection", ["downloads", "download", "browser", "safari", "chrome"])
        static let downloadStyle = item("Download indicator style", ["download", "progress", "circle", "ring", "bar"])
        static let downloadSpeed = item("Show download speed", ["download", "speed", "rate", "mb/s"])

        // Lock & unlock
        static let lockActivity = item("Enable lock screen live activity", ["lock screen", "live activity", "lock", "unlock"])
        static let lockIcon = item("Live activity icon", ["lock", "fingerprint", "touch id", "unlock", "biometric", "icon style"])
        static let lockSounds = item("Play lock/unlock sounds", ["chime", "sound", "lock", "unlock"])
        static let siriSpeed = item("Siri detection speed", ["siri", "responsiveness", "performance", "battery", "overlay"])
        static let crashReport = item("Copy latest crash report", ["diagnostics", "crash", "bug", "report", "log"])
    }

    static let items: [NotchlySettingItem] = [
        Item.batteryIndicator, Item.batteryPercentage, Item.powerIcons,
        Item.timeRemaining, Item.chargerWattage, Item.chargingStatus, Item.batteryHealth,
        Item.powerNotifications, Item.lowBatterySound, Item.chargingHUD, Item.lowBatteryHUD, Item.criticalBatteryHUD, Item.fullBatteryHUD, Item.chargeLimitHUD,
        Item.chargingDuration, Item.lowDuration, Item.fullDuration,
        Item.lowBatteryStyle, Item.lowBatteryThreshold, Item.criticalThreshold, Item.fullBatteryStyle, Item.fullThreshold,
        Item.testCharging, Item.testLow, Item.testCritical, Item.testFull, Item.testChargeLimit,
        Item.displayStyle, Item.showVolume, Item.showBrightness, Item.showBacklight, Item.volumeFeedback,
        Item.hudLayout, Item.progressStyle, Item.glow, Item.hudAccent, Item.colorCodedVolume, Item.smoothColors, Item.percentages,
        Item.osdMaterial, Item.osdGlassMode, Item.osdGlassVariant, Item.osdIconColor,
        Item.verticalPercent, Item.verticalAccent, Item.verticalInteractive, Item.verticalMaterial, Item.verticalGlassMode, Item.verticalGlassVariant,
        Item.verticalPosition, Item.verticalPadding, Item.verticalWidth, Item.verticalHeight,
        Item.circularPercent, Item.circularAccent, Item.circularSize, Item.circularStroke,
        Item.volumeStep, Item.volumeFineStep, Item.brightnessStep, Item.brightnessFineStep,
        Item.ddcIntegration, Item.ddcProvider, Item.ddcVolumeListener,
        Item.bluetoothConnections, Item.circularBattery, Item.bluetoothBatteryText, Item.deviceNameMarquee, Item.airPodsListening, Item.bluetoothIconStyle,
        Item.bluetoothLowAlert, Item.bluetoothLowThreshold, Item.colorCodedBattery,
        Item.focusDetection, Item.focusIndicator, Item.focusLabel, Item.focusToast,
        Item.capsLock, Item.capsLockLabel, Item.capsLockColor,
        Item.recordingDetection, Item.recordingIndicator, Item.recordingControls, Item.recordingHover, Item.cameraDetection, Item.microphoneDetection,
        Item.downloadDetection, Item.downloadStyle, Item.downloadSpeed,
        Item.lockActivity, Item.lockIcon, Item.lockSounds, Item.siriSpeed, Item.crashReport,
    ]
}
