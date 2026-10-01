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
import Combine
import Defaults
import SwiftUI

// MARK: - Live preview model

/// Feeds the HUD style tiles with the real volume / brightness / backlight so
/// they move when the keys are pressed.
final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private static func volumeIcon(for volume: Float) -> String {
        if volume <= 0.01 { return "speaker.slash.fill" }
        if volume < 0.33 { return "speaker.wave.1.fill" }
        if volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        let vol = SystemVolumeController.shared.currentVolume
        level = vol
        iconName = Self.volumeIcon(for: vol)

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self, let vol = info["value"] as? Float else { return }
                self.level = vol
                self.iconName = Self.volumeIcon(for: vol)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self, let val = info["value"] as? Float else { return }
                self.level = val
                self.iconName = "sun.max.fill"
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self, let val = info["value"] as? Float else { return }
                self.level = val
                self.iconName = val > 0.5 ? "light.max" : "light.min"
            }
            .store(in: &cancellables)
    }
}

// MARK: - Volume & brightness cards

/// Everything about how volume, brightness and keyboard-backlight changes are
/// shown: which style, which controls, how it looks, step sizes and external
/// display apps.
struct NotchlyControlsCards: View {
    typealias I = NotchlyLiveActivitiesPage.Item

    /// The four ways a change can be shown. Exactly one is on; the flags keep
    /// their old meaning so the rest of the app is untouched.
    enum DisplayStyle: CaseIterable, Hashable {
        case notch, osd, vertical, circular

        var title: String {
            switch self {
            case .notch: return String(localized: "Notch")
            case .osd: return String(localized: "Custom OSD")
            case .vertical: return String(localized: "Vertical Bar")
            case .circular: return String(localized: "Circular")
            }
        }
    }

    @Default(.enableSystemHUD) private var enableSystemHUD
    @Default(.enableCustomOSD) private var enableCustomOSD
    @Default(.enableVerticalHUD) private var enableVerticalHUD
    @Default(.enableCircularHUD) private var enableCircularHUD
    @Default(.enableVolumeHUD) private var enableVolumeHUD
    @Default(.enableBrightnessHUD) private var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) private var enableKeyboardBacklightHUD
    @Default(.enableOSDVolume) private var enableOSDVolume
    @Default(.enableOSDBrightness) private var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) private var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) private var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) private var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) private var enableExternalVolumeControlListener
    @Default(.progressBarStyle) private var progressBarStyle
    @Default(.inlineHUD) private var inlineHUD
    @Default(.useColorCodedVolumeDisplay) private var useColorCodedVolume
    @Default(.useColorCodedBatteryDisplay) private var useColorCodedBattery
    @Default(.useSmoothColorGradient) private var useSmoothColorGradient

    @Default(.verticalHUDMaterial) private var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) private var verticalGlassMode
    @Default(.verticalHUDLiquidGlassVariant) private var verticalGlassVariant

    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    // MARK: Derived state

    private var style: DisplayStyle {
        if enableSystemHUD { return .notch }
        if enableCustomOSD { return .osd }
        if enableVerticalHUD { return .vertical }
        if enableCircularHUD { return .circular }
        return .notch
    }

    private var hasAccess: Bool {
        accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration
    }

    private var colorCodingDisabled: Bool {
        style == .notch && progressBarStyle == .segmented
    }

    private var ddcProviderRunning: Bool {
        switch thirdPartyDDCProvider {
        case .betterDisplay: return betterDisplayManager.isRunning
        case .lunar: return lunarManager.isRunning
        }
    }

    /// Ownership of the keys only moves to the external app while integration is
    /// on *and* the provider is running; quitting it hands the keys back.
    private var externalOwnsBrightness: Bool { enableThirdPartyDDCIntegration && ddcProviderRunning }
    private var externalOwnsVolume: Bool { externalOwnsBrightness && enableExternalVolumeControlListener }

    private var availableMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) { return OSDMaterial.allCases }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            styleCard
            controlsCard
            switch style {
            case .notch: notchLookCard
            case .osd: osdCards
            case .vertical: verticalCards
            case .circular: circularCards
            }
            stepCard
            externalCard
        }
        .animation(NotchlyTheme.Motion.snappy, value: style)
        .animation(NotchlyTheme.Motion.snappy, value: hasAccess)
        .animation(NotchlyTheme.Motion.snappy, value: enableThirdPartyDDCIntegration)
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalGlassMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            // Without Accessibility access the keys cannot be intercepted, so the
            // two styles that depend on it switch themselves off.
            if !granted {
                enableSystemHUD = false
                enableCustomOSD = false
            }
        }
        .onChange(of: inlineHUD) { _, inline in
            if inline {
                withAnimation {
                    Defaults[.systemEventIndicatorShadow] = false
                    Defaults[.progressBarStyle] = .hierarchical
                }
            }
        }
    }

    // MARK: Style

    private func select(_ newStyle: DisplayStyle) {
        enableSystemHUD = newStyle == .notch
        enableCustomOSD = newStyle == .osd
        enableVerticalHUD = newStyle == .vertical
        enableCircularHUD = newStyle == .circular
    }

    private var styleFooter: String {
        switch style {
        case .notch: return "Volume, brightness and backlight changes grow out of the notch."
        case .osd: return "A floating panel at the bottom centre of the screen, like the native one."
        case .vertical: return "A slim bar on the side of the screen."
        case .circular: return "A ring that fades in over the screen."
        }
    }

    private var accessMessage: String {
        switch style {
        case .notch: return "Accessibility permission lets Notchly replace the native volume, brightness and keyboard HUDs."
        case .osd: return "Accessibility permission is needed to intercept system controls for the Custom OSD."
        case .vertical: return "Accessibility permission is needed to intercept system controls for the Vertical HUD."
        case .circular: return "Accessibility permission is needed to intercept system controls for the Circular HUD."
        }
    }

    private var styleCard: some View {
        NotchlySettingsCard("Volume & Brightness", footer: styleFooter) {
            if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                NotchlyPermissionRow(
                    message: accessMessage,
                    requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                    openAction: { accessibilityPermission.openSystemSettings() }
                )
            }
            I.displayStyle.tiles("Where volume, brightness and keyboard backlight changes show up.") {
                ForEach(DisplayStyle.allCases, id: \.self) { option in
                    NotchlyChoiceTile(title: option.title, isSelected: style == option, size: CGSize(width: 108, height: 72)) {
                        select(option)
                    } preview: {
                        tilePreview(option)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tilePreview(_ option: DisplayStyle) -> some View {
        switch option {
        case .notch:
            Capsule()
                .fill(Color.black)
                .frame(width: 64, height: 20)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .overlay {
                    HStack(spacing: 6) {
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 12)
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: geo.size.width * CGFloat(previewModel.level))
                                        .animation(.spring(response: 0.3), value: previewModel.level)
                                }
                        }
                        .frame(height: 4)
                    }
                    .padding(.horizontal, 8)
                }
        case .osd:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .overlay {
                    VStack(spacing: 5) {
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.secondary.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary)
                                        .frame(width: geo.size.width * CGFloat(previewModel.level))
                                        .animation(.spring(response: 0.3), value: previewModel.level)
                                }
                        }
                        .frame(width: 32, height: 4)
                    }
                }
                .frame(width: 44, height: 44)
        case .vertical:
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .overlay {
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.85))
                                    .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                    .animation(.spring(response: 0.3), value: previewModel.level)
                            }
                        }
                        .mask(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(4)
                }
                .frame(width: 22, height: 54)
        case .circular:
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(previewModel.level))
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.3), value: previewModel.level)
                Image(systemName: previewModel.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 42, height: 42)
        }
    }

    // MARK: Which controls

    private var controlsCard: some View {
        let osd = style == .osd
        return NotchlySettingsCard(
            "Show changes for",
            footer: hasAccess ? nil : "Grant Accessibility access above to choose which controls are shown."
        ) {
            I.showVolume.toggle(
                "Volume key and slider changes.",
                isEnabled: hasAccess,
                isOn: osd ? $enableOSDVolume : $enableVolumeHUD
            )
            I.showBrightness.toggle(
                "Display brightness changes.",
                isEnabled: hasAccess,
                isOn: osd ? $enableOSDBrightness : $enableBrightnessHUD
            )
            I.showBacklight.toggle(
                externalOwnsBrightness
                    ? "Handled by your external display app while it is running."
                    : "Keyboard backlight changes.",
                isEnabled: hasAccess && !externalOwnsBrightness,
                isOn: osd ? $enableOSDKeyboardBacklight : $enableKeyboardBacklightHUD
            )
            I.volumeFeedback.toggle(
                "Play a soft click when you press the volume keys.",
                help: "Plays the supplied feedback clip whenever you press the hardware volume keys. Needs Accessibility permission so Notchly can intercept the keys.",
                key: .playVolumeChangeFeedback
            )
        }
    }

    // MARK: Notch look

    private var colorFooter: String {
        if colorCodingDisabled {
            return "Color-coded fills and smooth gradients are unavailable with Segmented bars. Switch to Hierarchical or Gradient to use them."
        }
        if useSmoothColorGradient {
            return "Smooth transitions blend green (0-60%), yellow (60-85%) and red (85-100%) through the whole fill."
        }
        return "Discrete transitions snap between green (0-60%), yellow (60-85%) and red (85-100%)."
    }

    private var notchLookCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard("Notch look") {
                I.hudLayout.picker(
                    "Default is the tall expanded HUD. Inline keeps it inside the notch height.",
                    selection: $inlineHUD,
                    options: [false, true],
                    style: .segmented,
                    label: { $0 ? String(localized: "Inline") : String(localized: "Default") }
                )
                I.progressStyle.picker(
                    "How the progress bar is drawn.",
                    selection: $progressBarStyle,
                    options: ProgressBarStyle.allCases,
                    label: { $0.rawValue }
                )
                I.glow.toggle("A soft glow behind the progress bar.", key: .systemEventIndicatorShadow)
                I.hudAccent.toggle("Tint the bar with your accent color.", key: .systemEventIndicatorUseAccent)
            }
            NotchlySettingsCard("Progress bars", footer: colorFooter) {
                colorRows
                I.percentages.toggle("Print the value beside every progress bar.", key: .showProgressPercentages)
            }
        }
    }

    /// Color-coding of the volume bar, shared by the notch, vertical and circular looks.
    @ViewBuilder
    private var colorRows: some View {
        I.colorCodedVolume.toggle(
            "Green, yellow and red as the volume rises.",
            isEnabled: !colorCodingDisabled,
            key: .useColorCodedVolumeDisplay
        )
        I.smoothColors.toggle(
            "Blend between the colors instead of snapping.",
            isEnabled: !colorCodingDisabled && (useColorCodedVolume || useColorCodedBattery),
            key: .useSmoothColorGradient
        )
    }

    // MARK: Custom OSD

    @ViewBuilder
    private var osdCards: some View {
        if #available(macOS 15.0, *) {
            NotchlyOSDLookCards()
        } else {
            NotchlySettingsCard("Custom OSD") {
                NotchlyNoticeRow(text: "Custom OSD needs macOS 15 or later.", isError: true)
            }
        }
    }

    // MARK: Vertical bar

    private var verticalGlassVariantBinding: Binding<Int> {
        Binding(get: { verticalGlassVariant.rawValue }, set: { verticalGlassVariant = LiquidGlassVariant.clamped($0) })
    }

    private var verticalCards: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard("Vertical bar") {
                I.verticalPercent.toggle("Show the value on the bar.", key: .verticalHUDShowValue)
                I.verticalAccent.toggle("Tint the bar with your accent color.", key: .verticalHUDUseAccentColor)
                I.verticalInteractive.toggle("Drag the bar to change the level.", key: .verticalHUDInteractive)
                I.verticalMaterial.picker(
                    "The background of the bar.",
                    selection: $verticalHUDMaterial,
                    options: availableMaterials,
                    label: { $0.rawValue }
                )
                if verticalHUDMaterial == .liquid {
                    if #available(macOS 26.0, *) {
                        I.verticalGlassMode.picker(
                            "Standard follows the system glass. Custom Liquid lets you pick a variant.",
                            selection: $verticalGlassMode,
                            options: Array(LockScreenGlassCustomizationMode.allCases),
                            style: .segmented,
                            label: { $0.rawValue }
                        )
                        if verticalGlassMode == .customLiquid {
                            I.verticalGlassVariant.slider(
                                value: verticalGlassVariantBinding,
                                range: LiquidGlassVariant.supportedRange,
                                valueLabel: { "v\($0)" }
                            )
                        }
                    } else {
                        NotchlyNoticeRow(text: "Custom Liquid is available on macOS 26 or later.")
                    }
                }
                colorRows
            }
            NotchlySettingsCard("Position & size", footer: "Choose which side of the screen the bar sits on.") {
                I.verticalPosition.picker(
                    "Which edge of the screen.",
                    key: .verticalHUDPosition,
                    options: ["left", "right"],
                    style: .segmented,
                    label: { $0 == "left" ? String(localized: "Left") : String(localized: "Right") }
                )
                I.verticalPadding.slider("Gap between the bar and the screen edge.", key: .verticalHUDPadding, range: 0...100, step: 4, valueLabel: { "\(Int($0)) px" })
                I.verticalWidth.slider(key: .verticalHUDWidth, range: 24...80, step: 2, valueLabel: { "\(Int($0)) px" })
                I.verticalHeight.slider(key: .verticalHUDHeight, range: 100...500, step: 10, valueLabel: { "\(Int($0)) px" })
                NotchlySettingRow("Reset size and position") {
                    Button("Reset") {
                        Defaults[.verticalHUDWidth] = 36
                        Defaults[.verticalHUDHeight] = 160
                        Defaults[.verticalHUDPadding] = 24
                    }
                    .buttonStyle(.notchly)
                }
            }
        }
    }

    // MARK: Circular

    private var circularCards: some View {
        VStack(alignment: .leading, spacing: 22) {
            NotchlySettingsCard("Circular") {
                I.circularPercent.toggle("Show the value inside the ring.", key: .circularHUDShowValue)
                I.circularAccent.toggle("Tint the ring with your accent color.", key: .circularHUDUseAccentColor)
                colorRows
            }
            NotchlySettingsCard("Size") {
                I.circularSize.slider(key: .circularHUDSize, range: 40...200, step: 5, valueLabel: { "\(Int($0)) px" })
                I.circularStroke.slider(key: .circularHUDStrokeWidth, range: 2...16, step: 1, valueLabel: { "\(Int($0)) px" })
                NotchlySettingRow("Reset size") {
                    Button("Reset") {
                        Defaults[.circularHUDSize] = 65
                        Defaults[.circularHUDStrokeWidth] = 4
                    }
                    .buttonStyle(.notchly)
                }
            }
        }
    }

    // MARK: Step sizes

    private var stepCard: some View {
        NotchlySettingsCard(
            "Step size",
            footer: "Percent change per key press. The fine step applies while holding Shift + Option."
        ) {
            I.volumeStep.slider(
                externalOwnsVolume ? "Handled by your external display app while it listens for volume." : nil,
                isEnabled: !externalOwnsVolume,
                key: .volumeStepPercent, range: 1...25, valueLabel: { "\($0)%" }
            )
            I.volumeFineStep.slider(isEnabled: !externalOwnsVolume, key: .volumeFineStepPercent, range: 1...25, valueLabel: { "\($0)%" })
            I.brightnessStep.slider(
                externalOwnsBrightness ? "Handled by your external display app while it is running." : nil,
                isEnabled: !externalOwnsBrightness,
                key: .brightnessStepPercent, range: 1...25, valueLabel: { "\($0)%" }
            )
            I.brightnessFineStep.slider(isEnabled: !externalOwnsBrightness, key: .brightnessFineStepPercent, range: 1...25, valueLabel: { "\($0)%" })
        }
    }

    // MARK: External displays

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if ddcProviderRunning { return String(localized: "Running") }
            if betterDisplayManager.isDetected { return String(localized: "Not running") }
            return String(localized: "Not detected")
        case .lunar:
            if lunarManager.isConnected { return String(localized: "Connected") }
            if ddcProviderRunning { return String(localized: "Running") }
            if lunarManager.isDetected { return String(localized: "Not running") }
            return String(localized: "Not detected")
        }
    }

    private var providerStatusColor: Color {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if ddcProviderRunning { return .green }
            if betterDisplayManager.isDetected { return .orange }
            return .secondary
        case .lunar:
            if lunarManager.isConnected { return .green }
            if ddcProviderRunning || lunarManager.isDetected { return .orange }
            return .secondary
        }
    }

    private var providerStatusDescription: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if !betterDisplayManager.isDetected {
                return "Install [BetterDisplay](https://betterdisplay.pro) to control external display brightness (and optional volume) through Notchly's HUD."
            }
            if !ddcProviderRunning {
                return "BetterDisplay is installed but not currently running. Launch BetterDisplay to enable integration."
            }
            return "BetterDisplay OSD events are routed through Notchly's active style. Brightness is always routed; volume is routed when the volume listener below is on. Make sure BetterDisplay's OSD integration is enabled in Settings > Application > Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast and optional volume through Notchly's HUD via DDC."
            }
            if !ddcProviderRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast changes show through Notchly's HUD; volume follows when the volume listener is on."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay: betterDisplayManager.refreshDetectionStatus()
        case .lunar: lunarManager.refreshDetectionStatus()
        }
    }

    private var externalCard: some View {
        NotchlySettingsCard(
            "External displays",
            footer: enableThirdPartyDDCIntegration
                ? "Notchly always listens for the provider's brightness events, and for volume events only when the volume listener is on."
                : nil
        ) {
            I.ddcIntegration.toggle(
                "Show BetterDisplay or Lunar adjustments through Notchly's active style.",
                isOn: $enableThirdPartyDDCIntegration
            )
            if enableThirdPartyDDCIntegration {
                I.ddcProvider.picker(
                    "Which app drives your external displays.",
                    key: .thirdPartyDDCProvider,
                    options: Array(ThirdPartyDDCProvider.allCases),
                    label: { $0.displayName }
                )
                I.ddcVolumeListener.toggle(
                    enableExternalVolumeControlListener
                        ? "Notchly's own volume keys are off. The HUD follows \(thirdPartyDDCProvider.displayName)."
                        : "Notchly keeps its own volume keys and ignores the provider's volume events.",
                    key: .enableExternalVolumeControlListener
                )
                NotchlyStatusRow(title: String(localized: "Status"), status: providerStatusText, tint: providerStatusColor)
                NotchlyNoticeRow(text: providerStatusDescription, markdown: true)
                NotchlyActionRow(title: String(localized: "Refresh detection"), symbol: "arrow.clockwise", action: refreshDetectionStatus)
            }
        }
    }
}

// MARK: - Custom OSD look

@available(macOS 15.0, *)
private struct NotchlyOSDLookCards: View {
    typealias I = NotchlyLiveActivitiesPage.Item

    @Default(.enableCustomOSD) private var enableCustomOSD
    @Default(.osdMaterial) private var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) private var glassMode
    @Default(.osdLiquidGlassVariant) private var glassVariant
    @Default(.osdIconColorStyle) private var iconColorStyle

    @State private var previewValue: CGFloat = 0.65
    @State private var previewKind: PreviewKind = .volume

    private enum PreviewKind: Hashable {
        case volume, brightness, backlight

        var content: SneakContentType {
            switch self {
            case .volume: return .volume
            case .brightness: return .brightness
            case .backlight: return .backlight
            }
        }

        var title: String {
            switch self {
            case .volume: return String(localized: "Volume")
            case .brightness: return String(localized: "Brightness")
            case .backlight: return String(localized: "Backlight")
            }
        }
    }

    private var availableMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) { return OSDMaterial.allCases }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var glassVariantBinding: Binding<Int> {
        Binding(get: { glassVariant.rawValue }, set: { glassVariant = LiquidGlassVariant.clamped($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            appearanceCard
            previewCard
        }
        .onAppear {
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                glassMode = .standard
            }
        }
    }

    private var appearanceCard: some View {
        NotchlySettingsCard(
            "Custom OSD look",
            footer: "Frosted and Liquid Glass are translucent; Solid is opaque. Color options change the icon and progress bar, and Auto follows the system theme. Liquid Glass needs macOS 26."
        ) {
            I.osdMaterial.picker(
                "The panel's background.",
                selection: $osdMaterial,
                options: availableMaterials,
                label: { $0.rawValue }
            )
            if osdMaterial == .liquid {
                if #available(macOS 26.0, *) {
                    I.osdGlassMode.picker(
                        "Standard follows the system glass. Custom Liquid lets you pick a variant.",
                        selection: $glassMode,
                        options: Array(LockScreenGlassCustomizationMode.allCases),
                        style: .segmented,
                        label: { $0.rawValue }
                    )
                    if glassMode == .customLiquid {
                        I.osdGlassVariant.slider(
                            value: glassVariantBinding,
                            range: LiquidGlassVariant.supportedRange,
                            valueLabel: { "v\($0)" }
                        )
                    }
                } else {
                    NotchlyNoticeRow(text: "Custom Liquid is available on macOS 26 or later.")
                }
            }
            I.osdIconColor.picker(
                "Color of the icon and the progress bar.",
                selection: $iconColorStyle,
                options: Array(OSDIconColorStyle.allCases),
                label: { $0.rawValue }
            )
        }
        .onChange(of: osdMaterial) { _, _ in nudgePreview() }
        .onChange(of: iconColorStyle) { _, _ in nudgePreview() }
    }

    /// The preview only redraws when its value changes.
    private func nudgePreview() {
        previewValue = previewValue == 0.65 ? 0.651 : 0.65
    }

    private var previewCard: some View {
        NotchlySettingsCard(
            "Preview",
            footer: "Changes above show up here straight away. The real OSD appears at the bottom centre of your screen."
        ) {
            VStack(spacing: 14) {
                CustomOSDView(
                    type: .constant(previewKind.content),
                    value: .constant(previewValue),
                    icon: .constant("")
                )
                .frame(width: 200, height: 200)

                NotchlySegmentedControl(
                    selection: $previewKind,
                    options: [PreviewKind.volume, .brightness, .backlight],
                    label: { $0.title }
                )

                NotchlySlider(value: Binding(get: { Double(previewValue) }, set: { previewValue = CGFloat($0) }), range: 0...1)
                    .frame(width: 180)
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}
