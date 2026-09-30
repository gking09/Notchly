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

import Defaults
import SwiftUI

struct DynamicIslandHeader: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @State private var showTimerPopover = false
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showBatteryPercentInside) var showBatteryPercentInside
    @Default(.showMinimalisticBatteryIndicator) var showMinimalisticBatteryIndicator
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    
    /// Point size per symbol, so the row reads as one size.
    ///
    /// Equal point size is equal *cap height*, which is not equal optical size.
    /// Measured at 15pt medium: `gearshape` covers 289pt² of ink against
    /// `web.camera`'s 208 — 39% more — and some glyphs stand taller than
    /// `timer`'s 16pt. These sizes were solved so every glyph lands on
    /// 16pt of ink height, which is what actually makes a mixed row look even.
    private static let headerGlyphSizes: [String: CGFloat] = [
        "web.camera": 14.5,
        "timer": 14.4,
        "gearshape": 14.2,
        // Not solved against measured ink the way the others were: the three
        // sliders stand slightly taller than `timer`, so this trims to match.
        "slider.vertical.3": 13.8,
        // Unlike the sizes above, these two were not solved against measured
        // ink height -- they are the row default, nudged down because the cup
        // glyph carries a saucer and so reads a shade wider than `timer`.
        "cup.and.saucer": 14.0,
        "cup.and.saucer.fill": 14.0
    ]

    /// One glyph in the header row, on a common centre.
    ///
    /// The 20pt box clears the largest frame any of these symbols asks for
    /// (19pt), so none of them is clipped — a smaller box
    /// silently cuts the tall ones.
    private func headerGlyph(_ name: String, color: Color = NotchlyTheme.Palette.textPrimary.opacity(0.9)) -> some View {
        Image(systemName: name)
            .foregroundColor(color)
            .font(.system(size: Self.headerGlyphSizes[name] ?? 14.4, weight: .medium))
            .frame(width: 20, height: 20)
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack {
                if !enableMinimalisticUI {
                    let shouldShowTabs = coordinator.alwaysShowTabs || vm.notchState == .open
                    if shouldShowTabs {
                        TabSelectionView()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(NotchlyTheme.Motion.spring.delay(0.1), value: vm.notchState)
            .zIndex(2)
            .padding(8)

            if vm.notchState == .open {
                let spacerWidth = min(vm.closedNotchSize.width, 300)
                Rectangle()
                    .fill(enableMinimalisticUI ? .clear : (NSScreen.screens
                        .first(where: { $0.localizedName == coordinator.selectedScreen })?.safeAreaInsets.top ?? 0 > 0 ? .black : .clear))
                    .frame(width: spacerWidth)
                    .mask {
                        NotchShape()
                    }
            }

            // 30pt targets sitting 4pt apart read as one run of buttons rather
            // than as separate ones; 8 is the gap Apple leaves between controls
            // of this size.
            HStack(spacing: 8) {
                if vm.notchState == .open && !enableMinimalisticUI {
                    if Defaults[.showMirror] {
                        Button(action: {
                            vm.toggleCameraPreview()
                        }) {
                            headerGlyph("web.camera")
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.notchlyGlassCircle)
                    }
                    
                    if Defaults[.enableTimerFeature] && timerDisplayMode == .popover {
                        Button(action: {
                            withAnimation(NotchlyTheme.Motion.spring) {
                                showTimerPopover.toggle()
                            }
                        }) {
                            headerGlyph("timer")
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.notchlyGlassCircle)
                        .popover(isPresented: $showTimerPopover, arrowEdge: .bottom) {
                            TimerPopover()
                        }
                        .onChange(of: showTimerPopover) { isActive in
                            vm.isTimerPopoverActive = isActive
                            if !isActive {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    vm.shouldRecheckHover.toggle()
                                }
                            }
                        }
                    }
                    
                    if Defaults[.settingsIconInNotch] {
                        Button(action: {
                            SettingsWindowController.shared.showWindow()
                        }) {
                            headerGlyph("gearshape")
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                        }
                        .buttonStyle(.notchlyGlassCircle)
                    }
                    
                    // Screen Recording Indicator
                    if Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !shouldSuppressStatusIndicators {
                        RecordingIndicator()
                            .frame(width: 30, height: 30) // Same size as other header elements
                    }

                    if Defaults[.enableDoNotDisturbDetection]
                        && Defaults[.showDoNotDisturbIndicator]
                        && doNotDisturbManager.isDoNotDisturbActive
                        && !shouldSuppressStatusIndicators {
                        FocusIndicator()
                            .frame(width: 30, height: 30)
                            .transition(.opacity)
                    }
                }

                if vm.notchState == .open && showBatteryIndicator {
                    if enableMinimalisticUI {
                        // In minimalistic notch mode, show the battery pill only when
                        // showMinimalisticBatteryIndicator is enabled (and not DI mode).
                        if !shouldUseDynamicIslandMode(for: vm.screen) && showMinimalisticBatteryIndicator {
                            MinimalisticBatteryView(
                                levelBattery: batteryModel.levelBattery,
                                isPluggedIn: batteryModel.isPluggedIn,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                bodyWidth: 28,
                                bodyHeight: 14,
                                isForNotification: false,
                                showPercentInside: showBatteryPercentInside
                            )
                            .padding(.trailing, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    } else {
                        DynamicIslandBatteryView(
                            batteryWidth: 30,
                            isCharging: batteryModel.isCharging,
                            isInLowPowerMode: batteryModel.isInLowPowerMode,
                            isPluggedIn: batteryModel.isPluggedIn,
                            levelBattery: batteryModel.levelBattery,
                            maxCapacity: batteryModel.maxCapacity,
                            timeToFullCharge: batteryModel.timeToFullCharge,
                            isForNotification: false
                        )
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .animation(NotchlyTheme.Motion.spring.delay(0.1), value: vm.notchState)
            .zIndex(2)
        }
        .foregroundColor(NotchlyTheme.Palette.textSecondary)
        .environmentObject(vm)
        .onChange(of: enableTimerFeature) { _, newValue in
            if !newValue {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
        .onChange(of: timerDisplayMode) { _, mode in
            if mode == .tab {
                showTimerPopover = false
                vm.isTimerPopoverActive = false
            }
        }
    }
}

private extension DynamicIslandHeader {
    var shouldSuppressStatusIndicators: Bool {
        Defaults[.settingsIconInNotch]
            && Defaults[.enableTimerFeature]
    }
}

#Preview {
    DynamicIslandHeader()
        .environmentObject(DynamicIslandViewModel())
        .environmentObject(WebcamManager.shared)
}
