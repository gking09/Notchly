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
import Defaults
import SwiftUI
import UniformTypeIdentifiers

/// Appearance: the mode, the shape and size of the notch, how the player is
/// coloured, the idle face, and the app icon.
struct NotchlyAppearancePage: View {
    typealias I = Item

    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showMinimalisticBatteryIndicator) private var showMinimalisticBatteryIndicator
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @Default(.notchHeightMode) private var notchHeightMode
    @Default(.notchHeight) private var notchHeight
    @Default(.nonNotchHeightMode) private var nonNotchHeightMode
    @Default(.nonNotchHeight) private var nonNotchHeight
    @Default(.customizePhysicalNotchWidth) private var customizePhysicalNotchWidth
    @Default(.closedNotchWidth) private var closedNotchWidth
    @Default(.openNotchWidth) private var openNotchWidth
    @Default(.sliderColor) private var sliderColor
    @Default(.showNotHumanFace) private var showNotHumanFace
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    var body: some View {
        NotchlyPageScroll(page: .appearance) {
            modeCard
            lookCard
            sizeCard
            widthCard
            colorCard
            idleCard
            iconCard
        }
        .onChange(of: enableMinimalisticUI) { _, newValue in
            // Minimalistic UI always pairs with the simpler close animation.
            if newValue { Defaults[.useModernCloseAnimation] = true }
        }
        .onChange(of: externalDisplayStyle) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: notchHeightMode) {
            switch notchHeightMode {
            case .matchRealNotchSize: notchHeight = 38
            case .matchMenuBar: notchHeight = 44
            case .custom: notchHeight = 38
            }
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: notchHeight) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: nonNotchHeightMode) {
            switch nonNotchHeightMode {
            case .matchMenuBar: nonNotchHeight = 24
            case .matchRealNotchSize: nonNotchHeight = 32
            case .custom: nonNotchHeight = 32
            }
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: nonNotchHeight) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: customizePhysicalNotchWidth) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onChange(of: closedNotchWidth) {
            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        }
        .onAppear { enforceMinimumNotchWidth() }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url): importCustomIcon(from: url)
            case .failure: iconImportError = "Icon import was canceled or failed."
            }
        }
    }

    // MARK: Mode

    private var modeCard: some View {
        NotchlySettingsCard(
            "Mode",
            footer: "Minimalistic mode keeps media controls and system HUDs and hides everything else, with simpler animations."
        ) {
            I.minimalistic.toggle("A calmer notch with only media controls and HUDs.", key: .enableMinimalisticUI)
            I.minimalBattery.toggle(
                "Show the battery in the closed notch.",
                isEnabled: enableMinimalisticUI,
                key: .showMinimalisticBatteryIndicator
            )
            // Draws inside whichever battery the notch shows, so it only needs one to exist.
            I.batteryPercentInside.toggle(
                "Put the percentage inside the battery icon.",
                isEnabled: showBatteryIndicator && (!enableMinimalisticUI || showMinimalisticBatteryIndicator),
                key: .showBatteryPercentInside
            )
        }
    }

    // MARK: Look

    private var lookCard: some View {
        NotchlySettingsCard("Look & feel") {
            I.alwaysShowTabs.toggle("Keep the tab bar visible while the notch is closed.", isOn: $coordinator.alwaysShowTabs)
            I.settingsIcon.toggle("Add a settings button to the open notch.", key: .settingsIconInNotch)
            I.shadow.toggle("A soft shadow under the notch.", key: .enableShadow)
            I.cornerScaling.toggle("Round the corners more as the notch grows.", key: .cornerRadiusScaling)
            I.simplerClose.toggle("Close with a quick fade instead of the full morph.", key: .useModernCloseAnimation)
        }
    }

    // MARK: Size

    private var sizeCard: some View {
        NotchlySettingsCard("Notch height") {
            if !mainScreenHasPhysicalNotch {
                I.mainScreenStyle.picker(
                    externalDisplayStyle.description,
                    key: .externalDisplayStyle,
                    options: ExternalDisplayStyle.allCases,
                    label: { $0.localizedName }
                )
            }
            I.notchHeight.picker(
                "On screens with a notch.",
                selection: $notchHeightMode,
                options: [.matchRealNotchSize, .matchMenuBar, .custom],
                label: Self.heightModeLabel(_:)
            )
            if notchHeightMode == .custom {
                I.notchCustomHeight.slider(
                    value: doubleBinding($notchHeight),
                    range: 15...45,
                    step: 1,
                    valueLabel: { "\(Int($0)) pt" }
                )
            }
            I.nonNotchHeight.picker(
                "On screens without a notch.",
                selection: $nonNotchHeightMode,
                options: [.matchMenuBar, .matchRealNotchSize, .custom],
                label: Self.heightModeLabel(_:)
            )
            if nonNotchHeightMode == .custom {
                I.nonNotchCustomHeight.slider(
                    value: doubleBinding($nonNotchHeight),
                    range: 0...40,
                    step: 1,
                    valueLabel: { "\(Int($0)) pt" }
                )
            }
        }
    }

    static func heightModeLabel(_ mode: WindowHeightMode) -> String {
        switch mode {
        case .matchRealNotchSize: return String(localized: "Match real notch")
        case .matchMenuBar: return String(localized: "Match menu bar")
        case .custom: return String(localized: "Custom")
        }
    }

    // MARK: Width

    private var widthCard: some View {
        let recommendedMin = currentRecommendedMinimumNotchWidth()
        let tabCount = enabledStandardTabCount()
        let openRange = Double(recommendedMin)...900
        let closedRange = 80.0...400.0

        let openBinding = Binding<Double>(
            get: { Double(openNotchWidth) },
            set: { newValue in
                let value = CGFloat(min(max(newValue, openRange.lowerBound), openRange.upperBound))
                if openNotchWidth != value { openNotchWidth = value }
            }
        )
        let closedBinding = Binding<Double>(
            get: { Double(closedNotchWidth) },
            set: { newValue in
                let value = CGFloat(min(max(newValue, closedRange.lowerBound), closedRange.upperBound))
                if closedNotchWidth != value { closedNotchWidth = value }
            }
        )

        return NotchlySettingsCard(
            "Notch width",
            footer: enableMinimalisticUI
                ? "Expanded width only applies to the standard layout. Turn off Minimalistic UI to change it."
                : "The minimum grows with the number of tabs you have switched on."
        ) {
            I.customPhysicalWidth.toggle("Override the width of the closed notch.", key: .customizePhysicalNotchWidth)
            I.closedWidth.slider(
                "Width of the closed notch or pill.",
                value: closedBinding,
                range: closedRange,
                step: 5,
                valueLabel: { "\(Int($0)) px" }
            )
            I.expandedWidth.slider(
                "\(tabCount) tab\(tabCount == 1 ? "" : "s") on, minimum \(Int(recommendedMin)) px.",
                isEnabled: !enableMinimalisticUI,
                value: openBinding,
                range: openRange,
                step: 10,
                valueLabel: { "\(Int($0)) px" }
            )
            NotchlySettingRow("Reset expanded width", subtitle: "Go back to the recommended minimum.", isEnabled: !enableMinimalisticUI) {
                Button("Reset") { openNotchWidth = recommendedMin }
                    .buttonStyle(.notchly(.standard))
                    .disabled(abs(openNotchWidth - recommendedMin) < 0.5)
            }
        }
    }

    // MARK: Colour

    private var colorCard: some View {
        NotchlySettingsCard("Player colors") {
            I.coloredSpectrogram.toggle("Tint the audio bars with the album's color.", key: .coloredSpectrogram)
            I.playerTinting.toggle("Tint titles and controls with the album's color.", key: .playerColorTinting)
            I.albumGlow.toggle("A soft blurred glow of the cover behind the player.", key: .lightingEffect)
            I.sliderColor.picker(
                "The color of the playback progress bar.",
                key: .sliderColor,
                options: SliderColorEnum.allCases,
                label: { $0.localizedName }
            )
        }
    }

    // MARK: Idle face

    private var idleCard: some View {
        NotchlySettingsCard("Idle face") {
            I.idleAnimation.toggle("Show a little animation in the closed notch when nothing is happening.", key: .showNotHumanFace)
            if showNotHumanFace {
                IdleAnimationsSettingsSection()
            }
        }
    }

    // MARK: App icon

    private var iconCard: some View {
        NotchlySettingsCard(
            "App icon",
            footer: iconImportError ?? "Drop a PNG, JPEG, TIFF or ICNS file onto the grid to add it to your library."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                    appIconCard(title: "Default", image: defaultAppIconImage(), isSelected: selectedAppIconID == nil) {
                        selectedAppIconID = nil
                        applySelectedAppIcon()
                    }
                    ForEach(customAppIcons) { icon in
                        appIconCard(
                            title: icon.name,
                            image: NSImage(contentsOf: icon.fileURL),
                            isSelected: selectedAppIconID == icon.id.uuidString
                        ) {
                            selectedAppIconID = icon.id.uuidString
                            applySelectedAppIcon()
                        }
                        .contextMenu {
                            Button("Remove") { removeCustomIcon(icon) }
                        }
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                        .fill(isIconDropTarget ? NotchlySettingsStyle.controlFillHover : NotchlySettingsStyle.controlFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                        .strokeBorder(NotchlySettingsStyle.accent.opacity(isIconDropTarget ? 0.7 : 0), lineWidth: 1.5)
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                    handleIconDrop(providers)
                }

                HStack(spacing: 8) {
                    Button("Add icon") {
                        iconImportError = nil
                        isIconImporterPresented = true
                    }
                    .buttonStyle(.notchly(.prominent))

                    Button("Remove selected") {
                        if let id = selectedAppIconID,
                           let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                            removeCustomIcon(icon)
                        }
                    }
                    .buttonStyle(.notchly(.standard))
                    .disabled(selectedAppIconID == nil)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NotchlySettingsStyle.divider)
                    .frame(height: NotchlyTheme.Stroke.hairline)
                    .padding(.leading, 14)
            }
            .settingsHighlight(id: I.appIcon.highlightID)
        }
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? NotchlySettingsStyle.accent : .clear, lineWidth: 2)
                }

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? NotchlySettingsStyle.onAccent : NotchlySettingsStyle.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background { Capsule().fill(isSelected ? NotchlySettingsStyle.accent : .clear) }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func defaultAppIconImage() -> NSImage? {
        NSImage(named: Bundle.main.iconFileName ?? "AppIcon")
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let direct = item as? URL {
                url = direct
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in importCustomIcon(from: url) }
        }
        return true
    }

    private func importCustomIcon(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            iconImportError = "That file could not be loaded as an image."
            return
        }
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let id = UUID()
        let fileName = "custom-icon-\(id.uuidString).\(ext)"
        let destination = CustomAppIcon.iconDirectory.appendingPathComponent(fileName)

        do {
            let data = try Data(contentsOf: url)
            try data.write(to: destination, options: [.atomic])
        } catch {
            iconImportError = "Unable to save the icon file."
            return
        }

        let newIcon = CustomAppIcon(id: id, name: name.isEmpty ? "Custom Icon" : name, fileName: fileName)
        if !customAppIcons.contains(newIcon) {
            customAppIcons.append(newIcon)
        }
        selectedAppIconID = newIcon.id.uuidString
        NSApp.applicationIconImage = image
        iconImportError = nil
    }

    private func removeCustomIcon(_ icon: CustomAppIcon) {
        if let index = customAppIcons.firstIndex(of: icon) {
            customAppIcons.remove(at: index)
        }
        if FileManager.default.fileExists(atPath: icon.fileURL.path) {
            try? FileManager.default.removeItem(at: icon.fileURL)
        }
        if selectedAppIconID == icon.id.uuidString {
            selectedAppIconID = nil
            applySelectedAppIcon()
        }
    }

    private func doubleBinding(_ binding: Binding<CGFloat>) -> Binding<Double> {
        Binding(get: { Double(binding.wrappedValue) }, set: { binding.wrappedValue = CGFloat($0) })
    }
}

// MARK: - Search items

extension NotchlyAppearancePage {
    enum Item {
        static let minimalistic = NotchlySettingItem(.appearance, "Minimalistic UI", keywords: ["minimalistic", "ui mode", "simple", "calm", "hud only"])
        static let minimalBattery = NotchlySettingItem(.appearance, "Show battery indicator", keywords: ["minimalistic", "battery", "closed notch"])
        static let batteryPercentInside = NotchlySettingItem(.appearance, "Show battery percentage inside icon", keywords: ["battery", "percent", "percentage", "icon"])
        static let alwaysShowTabs = NotchlySettingItem(.appearance, "Always show tabs", keywords: ["tab bar", "tabs", "header"])
        static let settingsIcon = NotchlySettingItem(.appearance, "Settings icon in notch", keywords: ["settings button", "toolbar", "gear"])
        static let shadow = NotchlySettingItem(.appearance, "Enable window shadow", keywords: ["shadow", "appearance", "drop shadow"])
        static let cornerScaling = NotchlySettingItem(.appearance, "Corner radius scaling", keywords: ["corner radius", "shape", "rounded"])
        static let simplerClose = NotchlySettingItem(.appearance, "Use simpler close animation", keywords: ["close animation", "notch", "fade", "morph"])
        static let mainScreenStyle = NotchlySettingItem(.appearance, "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"])
        static let notchHeight = NotchlySettingItem(.appearance, "Notch display height", keywords: ["display height", "menu bar size", "size", "real notch"])
        static let notchCustomHeight = NotchlySettingItem(.appearance, "Custom notch height", keywords: ["height", "size", "notch", "slider"])
        static let nonNotchHeight = NotchlySettingItem(.appearance, "Non-notch display height", keywords: ["external", "height", "menu bar", "size"])
        static let nonNotchCustomHeight = NotchlySettingItem(.appearance, "Custom non-notch height", keywords: ["external", "height", "size", "slider"])
        static let customPhysicalWidth = NotchlySettingItem(.appearance, "Customize physical notch width", keywords: ["notch width", "closed notch", "override"])
        static let closedWidth = NotchlySettingItem(.appearance, "Closed notch / pill width", keywords: ["closed notch", "pill", "width", "resize"])
        static let expandedWidth = NotchlySettingItem(.appearance, "Expanded notch width", keywords: ["notch width", "open notch", "resize", "wide", "tabs"])
        static let coloredSpectrogram = NotchlySettingItem(.appearance, "Colored spectrograms", keywords: ["spectrogram", "audio bars", "visualizer", "album color", "color"])
        static let playerTinting = NotchlySettingItem(.appearance, "Tint the player with album colors", keywords: ["tint", "player", "album art", "color", "minimalistic"])
        static let albumGlow = NotchlySettingItem(.appearance, "Blur effect behind album art", keywords: ["blur", "album art", "glow", "lighting"])
        static let sliderColor = NotchlySettingItem(.appearance, "Slider color", keywords: ["slider", "accent", "progress bar", "scrubber"])
        static let idleAnimation = NotchlySettingItem(.appearance, "Idle Animation", keywords: ["face animation", "idle", "cool face", "face", "lottie", "custom animation", "import"])
        static let appIcon = NotchlySettingItem(.appearance, "App icon", keywords: ["app icon", "custom icon", "dock icon"])
    }

    static let items: [NotchlySettingItem] = [
        Item.minimalistic, Item.minimalBattery, Item.batteryPercentInside,
        Item.alwaysShowTabs, Item.settingsIcon, Item.shadow, Item.cornerScaling, Item.simplerClose,
        Item.mainScreenStyle, Item.notchHeight, Item.notchCustomHeight, Item.nonNotchHeight, Item.nonNotchCustomHeight,
        Item.customPhysicalWidth, Item.closedWidth, Item.expandedWidth,
        Item.coloredSpectrogram, Item.playerTinting, Item.albumGlow, Item.sliderColor,
        Item.idleAnimation, Item.appIcon,
    ]
}
