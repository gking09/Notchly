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

import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {
    @Default(.showPowerStatusIcons) var showPowerStatusIcons
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool
    var showPercentInside: Bool = false

    var animationStyle: DynamicIslandAnimations = DynamicIslandAnimations()

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        if showPercentInside {
            filledBody
        } else {
            outlinedBody
        }
    }

    // MARK: - Filled body

    /// Apple draws the battery as a filled shape with the figure sitting on it:
    /// a light body, the charge as a coloured fill running from the left, and
    /// the percentage in dark type centred over the whole body — not over the
    /// fill, so it does not move as the charge does.
    ///
    /// The outlined drawing below puts a thin `battery.0` symbol around a small
    /// inner bar, which is the older treatment and leaves the figure competing
    /// with the outline for the same few points.
    private var filledBody: some View {
        let height = batteryWidth * 0.52
        let inset: CGFloat = 1.5
        let bodyRadius = height * 0.34
        let fraction = min(max(CGFloat(levelBattery) / 100, 0), 1)

        return HStack(spacing: height * 0.11) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: bodyRadius, style: .continuous)
                    .fill(bodyFill)

                RoundedRectangle(cornerRadius: bodyRadius - inset * 0.5, style: .continuous)
                    .fill(batteryColor)
                    // Proportional, with a floor only above zero and only wide
                    // enough to be visible. Flooring it at the body's height
                    // instead -- reasoning that a fill wants to be at least as
                    // wide as it is round -- put the floor at 12.6pt of a 27pt
                    // track on a 30pt battery, so an empty one drew as 47% full
                    // and every level below that was overstated.
                    .frame(width: fillWidth(fraction: fraction, inset: inset))
                    .padding(inset)

                HStack(spacing: height * 0.04) {
                    Text("\(Int(levelBattery))")
                        .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    if let statusSymbol {
                        Image(systemName: statusSymbol)
                            .font(.system(size: height * 0.42, weight: .bold))
                            .symbolEffect(.pulse, options: .repeating, isActive: isCharging && !NotchlyTheme.Motion.reduceMotion)
                    }
                }
                .foregroundStyle(Color.black.opacity(0.82))
                .frame(width: batteryWidth, alignment: .center)
            }
            .frame(width: batteryWidth, height: height)

            // The terminal. Apple keeps it detached from the body.
            RoundedRectangle(cornerRadius: height * 0.1, style: .continuous)
                .fill(bodyFill)
                .frame(width: height * 0.11, height: height * 0.36)
        }
        .animation(.smooth(duration: 0.3), value: levelBattery)
        .animation(.smooth(duration: 0.3), value: batteryColor)
    }

    private func fillWidth(fraction: CGFloat, inset: CGFloat) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max((batteryWidth - inset * 2) * fraction, 2)
    }

    /// The unfilled part of the battery, and its terminal. Light enough that
    /// the dark figure reads against it even at a very low charge, when there
    /// is almost no coloured fill behind the number.
    private var bodyFill: Color {
        .white.opacity(0.45)
    }

    private var statusSymbol: String? {
        guard iconStatus != "", isForNotification || showPowerStatusIcons else { return nil }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    // MARK: - Outlined body

    private var outlinedBody: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || showPowerStatusIcons) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

/// Pill battery for the minimalist notch, matching the charging HUD style.
struct MinimalisticBatteryView: View {
    @Default(.showPowerStatusIcons) var showPowerStatusIcons
    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var bodyWidth: CGFloat = 28
    var bodyHeight: CGFloat = 16
    var isForNotification: Bool
    var showPercentInside: Bool = false

    private var clamped: CGFloat {
        max(0, min(CGFloat(levelBattery), 100))
    }

    private var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if clamped <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || clamped == 100 {
            return .green
        } else {
            return .white
        }
    }

    private var showsStatusGlyph: Bool {
        (isCharging || isPluggedIn) && (isForNotification || showPowerStatusIcons)
    }

    private var statusSymbol: String? {
        guard showsStatusGlyph else { return nil }
        if isCharging { return "bolt.fill" }
        if isPluggedIn { return "powerplug.fill" }
        return nil
    }

    private var glyphColor: Color {
        isCharging ? .white : .black
    }

    private var terminalHeight: CGFloat {
        max(4, bodyHeight * 0.38)
    }

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(batteryColor.opacity(0.3))

                GeometryReader { geo in
                    Rectangle()
                        .fill(batteryColor.gradient)
                        .frame(width: max(0, (clamped / 100) * geo.size.width))
                }

                if showPercentInside {
                    HStack(spacing: 0.5) {
                        Text("\(Int(clamped))")
                            .font(.system(size: bodyHeight * 0.6, weight: .heavy, design: .rounded))
                            .foregroundStyle(glyphColor)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let statusSymbol {
                            Image(systemName: statusSymbol)
                                .font(.system(size: bodyHeight * 0.42, weight: .black))
                                .foregroundStyle(glyphColor)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 2)
                } else if let statusSymbol {
                    Image(systemName: statusSymbol)
                        .font(.system(size: bodyHeight * 0.6, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .frame(width: bodyWidth, height: bodyHeight)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(clamped == 100 ? batteryColor.gradient : batteryColor.opacity(0.4).gradient)
                .frame(width: 2, height: terminalHeight)
        }
        .animation(.smooth(duration: 0.18), value: clamped)
        .animation(.smooth(duration: 0.18), value: isCharging)
        .animation(.smooth(duration: 0.18), value: isPluggedIn)
    }
}

/// A view that displays detailed battery information and settings.
///
/// Every row beyond the level is shown only when IOKit actually reported the
/// data behind it and the matching setting is on.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var details: BatteryDetails = .empty
    var onDismiss: () -> Void

    @Default(.showBatteryTimeRemaining) private var showTimeRemaining
    @Default(.showChargerWattage) private var showWattage
    @Default(.showChargingStatusText) private var showStatusText
    @Default(.showBatteryHealthDetail) private var showHealth

    @Environment(\.openURL) private var openURL

    private var statusRow: (text: String, symbol: String)? {
        switch details.state {
        case .onBattery:
            return nil
        case .charging:
            return (String(localized: "Charging"), "bolt.fill")
        case .fastCharging:
            return showStatusText ? (String(localized: "Fast charging"), "bolt.fill") : (String(localized: "Charging"), "bolt.fill")
        case .slowCharging:
            return showStatusText ? (String(localized: "Charging slowly"), "bolt.fill") : (String(localized: "Charging"), "bolt.fill")
        case .held(let percent):
            return (String(localized: "Charging held at \(percent)%"), "pause.circle")
        case .full:
            return (String(localized: "Fully charged"), "battery.100percent")
        case .pluggedNotCharging:
            return (String(localized: "Plugged in, not charging"), "powerplug.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .contentTransition(.numericText(value: Double(levelBattery)))
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if let statusRow {
                    Label(statusRow.text, systemImage: statusRow.symbol)
                        .font(.subheadline)
                        .fontWeight(.regular)
                } else if isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if showTimeRemaining, let time = details.time {
                    Label {
                        Text(time.captionText)
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.subheadline)
                    .fontWeight(.regular)
                }
                if showWattage, let watts = details.adapterWatts {
                    Label("\(watts)W power adapter", systemImage: "powerplug")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
                if showWattage, let power = details.chargingPowerWatts {
                    Label("Charging at \(Int(power.rounded()))W", systemImage: "gauge.with.dots.needle.33percent")
                        .font(.subheadline)
                        .fontWeight(.regular)
                }
            }
            .animation(NotchlyTheme.Motion.spring, value: details)
            .padding(.vertical, 4)

            if showHealth, details.healthPercent != nil || details.cycleCount != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if let health = details.healthPercent {
                        HStack {
                            Text("Maximum capacity")
                            Spacer()
                            Text("\(health)%")
                                .contentTransition(.numericText(value: Double(health)))
                        }
                        .font(.subheadline)

                        NotchlyProgressBar(progress: Double(health) / 100, height: 4)
                            .animation(NotchlyTheme.Motion.spring, value: health)
                    }
                    if let cycles = details.cycleCount {
                        HStack {
                            Text("Cycle count")
                            Spacer()
                            if let design = details.designCycleCount, design > 0 {
                                Text("\(cycles) of \(design)")
                            } else {
                                Text("\(cycles)")
                            }
                        }
                        .font(.subheadline)
                    }
                }
            }

            Divider()

            Button(action: openBatteryPreferences) {
                Label("Battery Settings", systemImage: "gearshape")
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.plain)
            .padding(.vertical, 6)
        }
        .padding()
        .frame(width: 280)
        .foregroundStyle(.primary)
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}


/// Small "1h 12m" chip shown beside the battery in the open notch header.
/// Renders nothing unless the setting is on and macOS supplied an estimate.
struct BatteryTimeChip: View {
    let info: BatteryTimeInfo?
    @Default(.showBatteryTimeRemaining) private var showTimeRemaining

    var body: some View {
        Group {
            if showTimeRemaining, let info {
                HStack(spacing: 3) {
                    Image(systemName: info.kind == .toFull ? "bolt.fill" : "clock")
                        .font(.system(size: 9, weight: .bold))
                    Text(info.isCalculating ? String(localized: "Calculating…") : info.compactText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .glassSurface(in: Capsule())
                .help(info.captionText)
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: info)
    }
}

/// A view that displays the battery status and allows interaction to show detailed information.
struct DynamicIslandBatteryView: View {
    
    @Default(.showBatteryPercentage) var showBatteryPercentage
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    var details: BatteryDetails = .empty
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringPopover: Bool = false

    @EnvironmentObject var vm: DynamicIslandViewModel

    var body: some View {
        HStack {
            BatteryTimeChip(info: details.time)

            // The number goes in one place or the other, never both.
            if showBatteryPercentage && !showBatteryPercentInside {
                ZStack(alignment: .trailing) {
                    Text("100%")
                        .font(.callout)
                        .hidden()
                    
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .contentTransition(.numericText(value: Double(levelBattery)))
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            BatteryView(
                levelBattery: levelBattery,
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                isInLowPowerMode: isInLowPowerMode,
                batteryWidth: batteryWidth,
                isForNotification: isForNotification,
                showPercentInside: showBatteryPercentInside
            )
        }
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation {
                        isPressed = false
                        showPopupMenu.toggle()
                    }
                }
        )
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                details: details,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
            }
        }
        .onChange(of: showPopupMenu) { _, _ in
            updateBatteryPopoverActiveState()
        }
        .onChange(of: isHoveringPopover) { _, _ in
            updateBatteryPopoverActiveState()
        }
    }

    private func updateBatteryPopoverActiveState() {
        vm.isBatteryPopoverActive = showPopupMenu && isHoveringPopover
    }
}


private struct BatteryTemporaryHUDMetrics {
    let width: CGFloat
    let height: CGFloat
    let topRadius: CGFloat
    let bottomRadius: CGFloat
}

private extension BatteryTemporaryHUDKind {
    func metrics(
        style: BatteryNotificationStyle,
        closedNotchWidth: CGFloat,
        baseHeight: CGFloat
    ) -> BatteryTemporaryHUDMetrics {
        let compactBaseRadius = max(baseHeight / 2, 16)
        let compactTopRadius = max(12, compactBaseRadius - 4)

        switch (self, style) {
        case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 180,
                height: baseHeight,
                topRadius: compactTopRadius,
                bottomRadius: compactBaseRadius
            )
        case (.lowBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 150,
                height: baseHeight + 75,
                topRadius: 22,
                bottomRadius: 40
            )
        case (.fullBattery, .standard):
            return BatteryTemporaryHUDMetrics(
                width: closedNotchWidth + 140,
                height: baseHeight + 70,
                topRadius: 18,
                bottomRadius: 36
            )
        }
    }
}

/// The compact battery HUD. Content sits in the two wings either side of the
/// hardware notch (`wingWidth` each); the middle is left empty so nothing is
/// hidden behind the notch. With enough height each wing gets a second line:
/// left carries the adapter wattage, right the time estimate.
private struct BatteryCompactStatusRow: View {
    let title: String
    let subtitle: String?
    let caption: String?
    let glyph: String?
    let glyphPulseDuration: Double
    let batteryLevel: Int
    let tint: Color
    let wingWidth: CGFloat
    let notchWidth: CGFloat
    let height: CGFloat
    let twoLine: Bool

    @State private var shownLevel = 0
    @State private var glyphPulse = false

    /// Wings of equal width (the HUD's budget) either side of the notch-sized gap.
    private var layout: NotchWingLayout {
        NotchWingLayout.make(notchWidth: notchWidth, leftContent: wingWidth, rightContent: wingWidth)
    }

    var body: some View {
        NotchWings(layout: layout, height: height) {
            leadingWing
        } right: {
            trailingWing
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                shownLevel = batteryLevel
            }
            guard glyph != nil, !NotchlyTheme.Motion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: glyphPulseDuration).repeatForever(autoreverses: true)) {
                glyphPulse = true
            }
        }
        .onChange(of: batteryLevel) { _, newValue in
            withAnimation(NotchlyTheme.Motion.spring) { shownLevel = newValue }
        }
    }

    private var leadingWing: some View {
        VStack(alignment: .leading, spacing: 0) {
            // When menus (or a small screen) narrow the wing, the glyph is the
            // first thing to go, then the title scales down.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    if let glyph { glyphView(glyph) }
                    titleText.fixedSize(horizontal: true, vertical: false)
                }
                titleText
            }
            if twoLine, let subtitle {
                Text(verbatim: subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
        }
        .padding(.leading, 14)
        .animation(NotchlyTheme.Motion.spring, value: title)
        .animation(NotchlyTheme.Motion.spring, value: subtitle)
    }

    private func glyphView(_ glyph: String) -> some View {
        Image(systemName: glyph)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .opacity(glyphPulse ? 1 : 0.55)
            .scaleEffect(glyphPulse ? 1.08 : 0.94)
            .contentTransition(.symbolEffect(.replace))
    }

    private var titleText: some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.85))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.interpolate)
    }

    private var percentText: some View {
        Text("\(shownLevel)%")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .contentTransition(.numericText(value: Double(shownLevel)))
    }

    private var trailingWing: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // The battery glyph drops out before the percentage ever clips.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    percentText
                    batteryGlyph
                }
                percentText
            }
            if twoLine, let caption {
                Text(verbatim: caption)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())
            }
        }
        .padding(.trailing, 14)
        .animation(NotchlyTheme.Motion.spring, value: caption)
    }

    private var batteryGlyph: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.3))

                GeometryReader { geo in
                    let clamped = max(0, min(shownLevel, 100))
                    let width = CGFloat(clamped) / 100 * geo.size.width
                    Rectangle()
                        .fill(tint.gradient)
                        .frame(width: max(0, width))
                }
            }
            .frame(width: 28, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(shownLevel >= 100 ? tint.gradient : tint.opacity(0.3).gradient)
                .frame(width: 2, height: 6)
        }
    }
}

struct BatteryTemporaryActivityView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    let kind: BatteryTemporaryHUDKind
    let batteryLevel: Int
    let isLowPowerMode: Bool
    let closedNotchWidth: CGFloat
    let baseHeight: CGFloat
    let isDynamicIslandMode: Bool
    let topCornerRadius: CGFloat
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    var styleOverride: BatteryNotificationStyle? = nil
    var extras: BatteryHUDExtras = .none

    private var flavor: BatteryHUDFlavor { extras.flavor }

    @State private var pulse = false
    @State private var showBatteryIndicator = false
    @State private var changeBatteryIndicator = true

    private var style: BatteryNotificationStyle {
        if kind == .charging {
            return .compact
        }
        if let styleOverride {
            return styleOverride
        }
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }

    private var metrics: BatteryTemporaryHUDMetrics {
        let base = kind.metrics(
            style: style,
            closedNotchWidth: closedNotchWidth,
            baseHeight: baseHeight
        )
        // The compact HUD is all wings, so like every other closed-notch
        // activity it narrows (rather than slides) to clear the app menus and
        // the screen edges. The tall standard panels have no wings to narrow.
        guard style == .compact,
              let limit = ClosedNotchMetrics.maximumContentWidth(screenName: vm.screen) else { return base }
        return BatteryTemporaryHUDMetrics(
            width: max(closedNotchWidth, min(base.width, limit)),
            height: base.height,
            topRadius: base.topRadius,
            bottomRadius: base.bottomRadius
        )
    }

    private var batteryTint: Color {
        switch kind {
        case .charging:
            if isLowPowerMode {
                return .yellow
            } else if batteryLevel <= 20 {
                return .red
            }
            return .green
        case .lowBattery:
            if flavor == .critical { return .red }
            return isLowPowerMode ? .yellow : .red
        case .fullBattery:
            // Held below 100% is neither "full" nor a problem, so it stays neutral.
            if flavor == .chargeHeld { return NotchlyTheme.Palette.silver }
            return isLowPowerMode ? .yellow : .green
        }
    }


    private var surfaceShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(DynamicIslandPillShape(cornerRadius: dynamicIslandPillCornerRadiusInsets.opened))
        } else {
            return AnyShape(NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: metrics.bottomRadius))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .bottom)
        .clipShape(surfaceShape)
        .onAppear(perform: prepareAnimations)
    }

    @ViewBuilder
    private var content: some View {
        if style == .compact {
            BatteryCompactStatusRow(
                title: compactTitle,
                subtitle: kind == .charging ? extras.wattsText : nil,
                caption: extras.timeText,
                glyph: compactGlyph,
                glyphPulseDuration: flavor == .critical ? 0.5 : 0.9,
                batteryLevel: batteryLevel,
                tint: batteryTint,
                wingWidth: max((metrics.width - closedNotchWidth) / 2, 0),
                notchWidth: closedNotchWidth,
                height: baseHeight,
                twoLine: baseHeight >= 32
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            VStack {
                Spacer()

                HStack {
                    VStack(alignment: .leading, spacing: kind == .lowBattery ? 2 : 3) {
                        standardTitle
                        standardDescription
                    }

                    Spacer()

                    standardIndicator
                }
                .padding(.leading, kind == .lowBattery ? 40 : 35)
                .padding(.trailing, kind == .lowBattery ? 45 : 40)
                .padding(.bottom, 20)
            }
        }
    }

    private var compactTitle: String {
        switch kind {
        case .charging:
            return extras.statusTitle ?? String(localized: "Charging")
        case .lowBattery:
            return flavor == .critical ? String(localized: "Critical") : String(localized: "Low Battery")
        case .fullBattery:
            return flavor == .chargeHeld ? String(localized: "Charge held") : String(localized: "Full Battery")
        }
    }

    /// The pulsing glyph beside the title: the charging bolt, or a warning
    /// triangle for a critical level. Nothing for a held charge.
    private var compactGlyph: String? {
        switch kind {
        case .charging:
            return extras.heldAtPercent == nil ? "bolt.fill" : nil
        case .lowBattery:
            return flavor == .critical ? "exclamationmark.triangle.fill" : nil
        case .fullBattery:
            return nil
        }
    }

    @ViewBuilder
    private var standardTitle: some View {
        HStack(spacing: 5) {
            Text(verbatim: standardTitleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)

            Text("\(batteryLevel)%")
                .font(.system(size: kind == .lowBattery ? 12 : 13, weight: .semibold))
                .foregroundStyle(batteryTint)
                .contentTransition(.numericText(value: Double(batteryLevel)))
        }
    }

    private var standardTitleText: String {
        switch kind {
        case .lowBattery:
            return flavor == .critical ? String(localized: "Battery Critical") : String(localized: "Battery Low")
        case .fullBattery:
            return flavor == .chargeHeld ? String(localized: "Charge Limit") : String(localized: "Full Battery")
        case .charging:
            return String(localized: "Charging")
        }
    }

    @ViewBuilder
    private var standardDescription: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery where flavor == .critical:
            VStack(alignment: .leading, spacing: 2) {
                if let timeText = extras.timeText {
                    Text(verbatim: timeText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .contentTransition(.numericText())
                }
                Text(verbatim: String(localized: "Plug in now to avoid\nshutting down."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .lowBattery where extras.timeText != nil && !isLowPowerMode:
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: extras.timeText ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
                Text(verbatim: String(localized: "Plug in soon."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
            }
        case .lowBattery:
            if isLowPowerMode {
                (
                    Text(verbatim: String(localized: "Low Power Mode enabled"))
                        .foregroundColor(.yellow)
                        .font(.system(size: 10, weight: .medium))
                    +
                    Text(verbatim: String(localized: ", it is recommended to charge it."))
                        .foregroundColor(.gray.opacity(0.6))
                        .font(.system(size: 10, weight: .medium))
                )
            } else {
                Text(verbatim: String(localized: "Turn on Low Power Mode or it\nis recommended to charge it."))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.6))
                    .lineLimit(2)
            }
        case .fullBattery where flavor == .chargeHeld:
            Text(verbatim: String(localized: "Charging held at \(extras.heldAtPercent ?? batteryLevel)%."))
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.6))
                .fontWeight(.medium)
                .lineLimit(1)
        case .fullBattery:
            Text(verbatim: String(localized: "Your Mac is fully charged."))
                .font(.system(size: 10))
                .foregroundStyle(.gray.opacity(0.6))
                .fontWeight(.medium)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var standardIndicator: some View {
        switch kind {
        case .charging:
            EmptyView()
        case .lowBattery:
            if isLowPowerMode && flavor != .critical {
                yellowLowIndicator
            } else {
                redLowIndicator
            }
        case .fullBattery where flavor == .chargeHeld:
            heldIndicator
        case .fullBattery:
            if showBatteryIndicator {
                if isLowPowerMode {
                    yellowFullIndicator
                        .transition(.opacity.combined(with: .scale))
                } else {
                    greenFullIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            } else {
                magSafeIndicator
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var redLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.red.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.gradient)
                .frame(width: 8, height: 14)
                .opacity(pulse ? 1 : 0.3)
                .offset(x: -15)

            RoundedRectangle(cornerRadius: 30)
                .stroke(Color.red.opacity(0.9), lineWidth: 1.5)
                .frame(width: pulse ? 8 : 30, height: pulse ? 14 : 32)
                .offset(x: -15)
                .opacity(pulse ? 0.3 : 1)
        }
    }

    /// Battery shape filled to the level it is being held at.
    private var heldIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.white.opacity(0.1))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.22))
                    .frame(width: 44, height: 24)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(NotchlyTheme.Palette.silver.gradient)
                            .frame(width: 34 * CGFloat(min(max(batteryLevel, 0), 100)) / 100, height: 14)
                            .padding(.leading, 5)
                            .opacity(pulse ? 1 : 0.6)
                    }

                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.22))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var yellowLowIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 40, height: 24)

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
            .padding(.trailing, 5)

            RoundedRectangle(cornerRadius: 8)
                .fill(.yellow.gradient)
                .frame(width: 8, height: 14)
                .offset(x: -15)
        }
    }

    private var greenFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.green.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.green.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var yellowFullIndicator: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30)
                .fill(.yellow.opacity(0.2))
                .frame(width: 70, height: 40)

            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 44, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.yellow.gradient)
                            .frame(width: 34, height: 14)
                            .opacity(pulse ? 1 : 0.4)
                    )

                RoundedRectangle(cornerRadius: 10)
                    .fill(.yellow.opacity(0.4))
                    .frame(width: 3, height: 8)
            }
        }
    }

    private var magSafeIndicator: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.gray.opacity(0.15))
                .frame(width: 30, height: 5)

            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.gray.opacity(0.2).gradient)
                    .frame(width: 30, height: 40)

                Circle()
                    .fill(changeBatteryIndicator ? .orange : .green)
                    .shadow(color: changeBatteryIndicator ? .orange : .green, radius: 5)
                    .frame(width: 5, height: 5)
            }

            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 3, height: 32)
        }
    }

    private func prepareAnimations() {
        pulse = false
        showBatteryIndicator = kind == .fullBattery && style == .standard && flavor != .chargeHeld
        changeBatteryIndicator = true

        guard style == .standard, !NotchlyTheme.Motion.reduceMotion else { return }

        switch kind {
        case .charging:
            break
        case .lowBattery:
            if !isLowPowerMode || flavor == .critical {
                withAnimation(.easeInOut(duration: flavor == .critical ? 0.5 : 1).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        case .fullBattery where flavor == .chargeHeld:
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        case .fullBattery:
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(duration: 0.4)) {
                    showBatteryIndicator = false
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation(.spring(duration: 0.2)) {
                    changeBatteryIndicator = false
                }
            }
        }
    }
}

#Preview {
    DynamicIslandBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
