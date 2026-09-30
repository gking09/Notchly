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

import SwiftUI
import AppKit
import AVFoundation
import Defaults

// MARK: - Inline HUD looping .mov icon

private final class LoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        self.player = AVQueuePlayer()
        self.player.isMuted = true
        self.player.actionAtItemEnd = .none
        self.looper = AVPlayerLooper(player: self.player, templateItem: item)
        self.player.play()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

private struct LoopingVideoIcon: NSViewRepresentable {
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

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op; the animation loops via AVPlayerLooper.
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var controller: LoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = LoopingPlayerController(url: url)
            layer.player = controller?.player
        }
    }
}

struct AirPodsListeningModeSymbol: View {
    let mode: AirPodsListeningMode
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: mode.sfSymbol)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .contentTransition(.symbolEffect)
            .frame(width: size + 2, height: size + 2)
    }
}

struct InlineHUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    
    @Default(.useColorCodedBatteryDisplay) var useColorCodedBatteryDisplay
    @Default(.useColorCodedVolumeDisplay) var useColorCodedVolumeDisplay
    @Default(.useSmoothColorGradient) var useSmoothColorGradient
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.showProgressPercentages) var showProgressPercentages
    @Default(.useCircularBluetoothBatteryIndicator) var useCircularBluetoothBatteryIndicator
    @Default(.showBluetoothBatteryPercentageText) var showBluetoothBatteryPercentageText
    @Default(.showBluetoothDeviceNameMarquee) var showBluetoothDeviceNameMarquee
    @Default(.useBluetoothHUD3DIcon) var useBluetoothHUD3DIcon
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @ObservedObject var bluetoothManager = BluetoothAudioManager.shared
    
    @State private var displayName: String = ""

    /// Widest either wing of the inline HUD ever asks for. Anything that has to
    /// reserve room for the HUD before it draws (the notch's outer frame) uses
    /// this so it can never be narrower than the wings.
    static let widestWingContent: CGFloat = 190

    /// Closed-notch width of the AirPods listening-mode HUD. The wings are
    /// symmetric -- the long mode label sets both -- so the gap stays on the notch.
    static func airPodsListeningModeWidth(
        closedNotchWidth: CGFloat,
        gestureProgress: CGFloat,
        minimalistic: Bool
    ) -> CGFloat {
        let leadingWidth: CGFloat = minimalistic ? 36 : 44
        let trailingWidth: CGFloat = minimalistic ? 136 : 180
        return NotchWingLayout.make(
            notchWidth: closedNotchWidth,
            leftContent: leadingWidth + gestureProgress / 2,
            rightContent: trailingWidth + gestureProgress / 2,
            innerClearance: NotchWingLayout.innerClearance
        ).totalWidth
    }

    /// Notch width reserved while any inline HUD is showing.
    static func reservedWidth(closedNotchWidth: CGFloat) -> CGFloat {
        NotchWingLayout.make(
            notchWidth: closedNotchWidth,
            leftContent: widestWingContent,
            rightContent: widestWingContent,
            innerClearance: NotchWingLayout.innerClearance
        ).totalWidth
    }
    
    var body: some View {
        let useCircularIndicator = useCircularBluetoothBatteryIndicator
        // A low-battery alert always spells the number out and tints it red.
        let lowAlert = type == .bluetoothAudio ? bluetoothManager.activeLowBatteryAlert : nil
        let showBluetoothPercent = showBluetoothBatteryPercentageText || lowAlert != nil
        let alertTint: Color? = lowAlert != nil ? .red : nil
        let listeningModeEvent = bluetoothManager.activeListeningModeEvent
        let listeningMode = listeningModeEvent?.mode ?? (type == .bluetoothAudio && value < 0 ? AirPodsListeningMode.fromHUDSymbol(icon) : nil)
        let isListeningModeEvent = type == .bluetoothAudio && listeningMode != nil
        let hasBatteryLevel = value > 0 && !isListeningModeEvent
        let capsLockAccentColor = capsLockTintMode.color

        // Widths stay constant whether hovered or not so HUD text/icons do
        // not slide toward the notch edges when the user moves over it.
        // Mini BT marquee widths are reduced to keep both wings inside the
        // minimalistic open notch (420pt) on wider hardware notches.
        let baseInfoWidth: CGFloat = {
            if type == .bluetoothAudio {
                if isListeningModeEvent {
                    return enableMinimalisticUI ? 36 : 44
                }
                if showBluetoothDeviceNameMarquee {
                    return enableMinimalisticUI ? 96 : 132
                }
                return enableMinimalisticUI ? 56 : 64
            }

            if type == .capsLock && !showCapsLockLabel {
                return enableMinimalisticUI ? 48 : 56
            }

            return 92
        }()

        let infoWidth: CGFloat = {
            let width = baseInfoWidth + gestureProgress / 2
            let minimum: CGFloat = {
                if type == .bluetoothAudio {
                    if isListeningModeEvent {
                        return enableMinimalisticUI ? 32 : 38
                    }
                    if showBluetoothDeviceNameMarquee {
                        return enableMinimalisticUI ? 84 : 112
                    }
                    return enableMinimalisticUI ? 48 : 60
                }

                if type == .capsLock && !showCapsLockLabel {
                    return enableMinimalisticUI ? 36 : 44
                }

                return 88
            }()
            return max(width, minimum)
        }()

        let baseTrailingWidth: CGFloat = {
            if type == .bluetoothAudio {
                if !hasBatteryLevel {
                    if isListeningModeEvent {
                        return enableMinimalisticUI ? 136 : 180
                    }
                    return showBluetoothDeviceNameMarquee ? (enableMinimalisticUI ? 88 : 110) : (enableMinimalisticUI ? 66 : 80)
                }

                if useCircularIndicator {
                    return showBluetoothPercent ? (enableMinimalisticUI ? 92 : 112) : (enableMinimalisticUI ? 64 : 76)
                }

                return showBluetoothPercent ? (enableMinimalisticUI ? 100 : 128) : (enableMinimalisticUI ? 84 : 100)
            }

            if type == .capsLock {
                if showCapsLockLabel {
                    return enableMinimalisticUI ? 76 : 88
                }
                return 0
            }

            return 92
        }()

        let trailingWidth: CGFloat = {
            let width = baseTrailingWidth + gestureProgress / 2
            let minimum: CGFloat = {
                if type == .bluetoothAudio {
                    if !hasBatteryLevel {
                        if isListeningModeEvent {
                            return enableMinimalisticUI ? 128 : 172
                        }
                        return showBluetoothDeviceNameMarquee ? (enableMinimalisticUI ? 80 : 102) : (enableMinimalisticUI ? 56 : 80)
                    }

                    if useCircularIndicator {
                        return showBluetoothPercent ? (enableMinimalisticUI ? 80 : 102) : (enableMinimalisticUI ? 48 : 64)
                    }

                    return showBluetoothPercent ? (enableMinimalisticUI ? 88 : 112) : (enableMinimalisticUI ? 64 : 82)
                }

                if type == .capsLock {
                    return showCapsLockLabel ? (enableMinimalisticUI ? 60 : 72) : 0
                }

                return 90
            }()
            return max(width, minimum)
        }()

        // The wings are always the same width and the gap between them is the
        // notch itself, so the cut-out is left empty and everything stays to
        // one side of it. `infoWidth` / `trailingWidth` are what each side wants;
        // the layout takes the wider and gives both wings that, limited to what
        // the screen (and the frontmost app's menus) leave.
        let layout = NotchWingLayout.make(
            notchWidth: vm.closedNotchSize.width,
            leftContent: infoWidth,
            rightContent: trailingWidth,
            innerClearance: NotchWingLayout.innerClearance,
            maximumTotalWidth: ClosedNotchMetrics.maximumContentWidth(screenName: vm.screen)
        )
        let wingHeight = vm.closedNotchSize.height + (hoverAnimation ? 8 : 0)

        return HUDBumpReader(type: type, value: value) { bumpToken, bumpEdge in
            NotchWings(layout: layout, height: wingHeight) {
                HStack(spacing: 5) {
                    Group {
                        switch (type) {
                            case .volume, .brightness, .backlight:
                                HUDGlyph(
                                    type: type,
                                    value: value,
                                    icon: icon,
                                    bumpToken: bumpToken,
                                    bluetoothConnected: bluetoothManager.isBluetoothAudioConnected
                                )
                            case .mic:
                                Image(systemName: "mic")
                                    .symbolRenderingMode(.hierarchical)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                            case .bluetoothAudio:
                                if let listeningMode {
                                    AirPodsListeningModeSymbol(mode: listeningMode)
                                        .contentTransition(.interpolate)
                                        .frame(width: 20, height: 15, alignment: .center)
                                } else if useBluetoothHUD3DIcon,
                                   lowAlert == nil,
                                   let deviceType = bluetoothManager.lastConnectedDevice?.deviceType,
                                   let url = deviceType.inlineHUDAnimationURL {
                                    LoopingVideoIcon(url: url, size: CGSize(width: 20, height: 20))
                                        .frame(width: 20, height: 20, alignment: .center)
                                } else {
                                    Image(systemName: icon.isEmpty ? "dot.radiowaves.left.and.right" : icon)
                                        .symbolRenderingMode(.hierarchical)
                                        .contentTransition(.interpolate)
                                        .frame(width: 20, height: 15, alignment: .center)
                                        .symbolEffect(.pulse, options: .repeating, isActive: lowAlert != nil && !NotchlyTheme.Motion.reduceMotion)
                                }
                            case .capsLock:
                                Image(systemName: "capslock.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                                    .foregroundStyle(capsLockAccentColor)
                            default:
                                EmptyView()
                        }
                    }
                    .foregroundStyle(.white)
                    .symbolVariant(.fill)
                
                    // Use marquee text for device names to handle long names
                    if type == .bluetoothAudio {
                        if isListeningModeEvent {
                            EmptyView()
                        } else if showBluetoothDeviceNameMarquee {
                            MarqueeText(
                                $displayName,
                                font: .system(size: 13, weight: .medium),
                                nsFont: .body,
                                textColor: .white,
                                minDuration: 0.2,
                                frameWidth: max(0, layout.contentWidth - 25)
                            )
                        } else if lowAlert != nil {
                            Text("Low")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    } else if type != .capsLock {
                        Text(Type2Name(type))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } right: {
                HStack {
                    if (type == .mic) {
                        Text(value.isZero ? "muted" : "unmuted")
                            .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .contentTransition(.interpolate)
                    } else if (type == .capsLock) {
                        if showCapsLockLabel {
                            Text("Caps Lock")
                                .foregroundStyle(capsLockAccentColor)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .contentTransition(.interpolate)
                        }
                    } else if (type == .bluetoothAudio) {
                        if let listeningMode {
                            let listeningModeTextWidth: CGFloat = enableMinimalisticUI ? 96 : 124

                            // Render every mode label with a trailing-aligned Text.
                            // The previous MarqueeText path is `.leading`-aligned
                            // internally, so the longer modes (Noise Cancellation /
                            // Adaptive Audio / Conversation Awareness) hugged the notch
                            // edge and were clipped behind it — only the short,
                            // trailing-aligned modes (Transparency / Off) stayed
                            // visible. A scaling Text keeps every mode on screen.
                            Text(listeningMode.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .truncationMode(.tail)
                                .allowsTightening(true)
                                .frame(
                                    width: min(max(trailingWidth - 44, 64), listeningModeTextWidth),
                                    alignment: .trailing
                                )
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else if hasBatteryLevel {
                            let indicatorSpacing: CGFloat = {
                                if useCircularIndicator {
                                    return showBluetoothPercent ? 8 : 2
                                }
                                return showBluetoothPercent ? 6 : 4
                            }()

                            HStack(spacing: indicatorSpacing) {
                                if useCircularIndicator {
                                    CircularBatteryIndicator(
                                        value: value,
                                        tint: alertTint,
                                        useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                        smoothGradient: useSmoothColorGradient
                                    )
                                    .allowsHitTesting(false)
                                } else {
                                    LinearBatteryIndicator(
                                        value: value,
                                        tint: alertTint,
                                        useColorCoding: useColorCodedBatteryDisplay && progressBarStyle != .segmented,
                                        smoothGradient: useSmoothColorGradient
                                    )
                                    .allowsHitTesting(false)
                                }

                                if showBluetoothPercent {
                                    Text("\(Int(value * 100))%")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(alertTint ?? .white)
                                        .lineLimit(1)
                                        .contentTransition(.numericText(value: Double(value)))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    } else {
                        // Volume and brightness displays
                        Group {
                            if type == .volume {
                                Group {
                                    if value.isZero {
                                        Text("muted")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                                            .lineLimit(1)
                                            .allowsTightening(true)
                                            .multilineTextAlignment(.trailing)
                                            .transition(.blurReplace)
                                    } else {
                                        HStack(spacing: 6) {
                                            DraggableProgressBar(value: $value, colorMode: .volume)
                                            PercentageLabel(value: value, isVisible: showProgressPercentages)
                                        }
                                        .hudBump(trigger: bumpToken, edge: bumpEdge)
                                        .transition(.blurReplace)
                                    }
                                }
                                .animation(NotchlyTheme.Motion.spring, value: value.isZero)
                            } else {
                                HStack(spacing: 6) {
                                    DraggableProgressBar(value: $value)
                                    PercentageLabel(value: value, isVisible: showProgressPercentages)
                                }
                                .hudBump(trigger: bumpToken, edge: bumpEdge)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear {
            displayName = resolvedDisplayName
        }
        .onChange(of: type) { _, _ in
            displayName = resolvedDisplayName
        }
        .onChange(of: bluetoothManager.lastConnectedDevice?.name) { _, _ in
            displayName = resolvedDisplayName
        }
        .onChange(of: bluetoothManager.activeLowBatteryAlert) { _, _ in
            displayName = resolvedDisplayName
        }
    }
    
    private struct CircularBatteryIndicator: View {
        let value: CGFloat
        var tint: Color? = nil
        let useColorCoding: Bool
        let smoothGradient: Bool

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var indicatorColor: Color {
            if let tint { return tint }
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(NotchlyTheme.Palette.track, lineWidth: 2)

                Circle()
                    .trim(from: 0, to: max(clampedValue, 0.015))
                    .rotation(.degrees(-90))
                    .stroke(indicatorColor, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .frame(width: 16, height: 16)
            .animation(NotchlyTheme.Motion.spring, value: clampedValue)
        }
    }

    private struct LinearBatteryIndicator: View {
        let value: CGFloat
        var tint: Color? = nil
        let useColorCoding: Bool
        let smoothGradient: Bool

        private let trackWidth: CGFloat = 54
        private let trackHeight: CGFloat = 6

        private var clampedValue: CGFloat {
            min(max(value, 0), 1)
        }

        private var fillColor: Color {
            if let tint { return tint }
            if useColorCoding {
                return ColorCodedProgressBar.paletteColor(for: clampedValue, mode: .battery, smoothGradient: smoothGradient)
            }
            return .white
        }

        var body: some View {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NotchlyTheme.Palette.track)
                    .frame(width: trackWidth, height: trackHeight)

                Capsule()
                    .fill(fillColor)
                    .frame(width: trackWidth * clampedValue, height: trackHeight)
            }
            .frame(width: trackWidth, height: trackHeight)
            .animation(NotchlyTheme.Motion.spring, value: clampedValue)
        }
    }

    /// The device a low-battery alert is about, otherwise the usual label.
    private var resolvedDisplayName: String {
        if type == .bluetoothAudio, let alert = bluetoothManager.activeLowBatteryAlert {
            return alert.deviceName
        }
        return Type2Name(type)
    }

    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return String(localized: "Volume")
            case .brightness:
                return String(localized: "Brightness")
            case .backlight:
                return String(localized: "Backlight")
            case .mic:
                return String(localized: "Mic")
            case .bluetoothAudio:
                return BluetoothAudioManager.shared.lastConnectedDevice?.name ?? "Bluetooth"
            case .capsLock:
                return String(localized: "Caps Lock")
            default:
                return ""
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(DynamicIslandViewModel())
}
