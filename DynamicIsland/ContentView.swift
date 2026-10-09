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

import AVFoundation
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @Default(.pinnedLyricContext) private var pinnedLyricContext
    @Default(.pinLyricsWhenClosed) private var pinLyricsWhenClosed
    @Default(.enableLyrics) private var enableLyrics
    @ObservedObject private var lyricsMode = LyricsModeController.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var stopwatchManager = StopwatchManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject private var networkConnectivityManager = NetworkConnectivityManager.shared
    @ObservedObject private var menuBarLayout = MenuBarLayout.shared
    /// Width of the closed-notch content, measured so its left edge can be
    /// compared against the frontmost app's menus. Only the *size* is read --
    /// the offset that follows does not change it, so there is no feedback.
    @State private var closedContentWidth: CGFloat = 0
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var stashManager = StashManager.shared
    /// The notch was opened by a drag arriving over it, so a drag leaving should close it again.
    @State private var stashOpenedByDrag = false
    @State private var stashDragExitTask: Task<Void, Never>?
    @State private var downloadManager = DownloadManager.shared
    
    @Default(.enableStash) var enableStash
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.showDoNotDisturbIndicator) var showDoNotDisturbIndicator
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.showRecordingIndicator) var showRecordingIndicator
    @Default(.recordingHoverStyle) var recordingHoverStyle
    @Default(.recordingControlMode) var recordingControlMode
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    
    // Battery settings reactivity
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) var showLowBatteryHUD
    @Default(.showFullBatteryHUD) var showFullBatteryHUD
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    
    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: isDynamicIslandMode) : openNotchSize

        if isConnectivityHUDVisible,
           let connectivitySize = NetworkConnectivityHUDMetrics.size(
               for: networkConnectivityManager.hudState,
               closedNotchSize: vm.closedNotchSize,
               effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
           ) {
            return connectivitySize
        }
        
        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let airPodsListeningModeSneakActive = vm.notchState == .closed
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let inlineSneakPeekActive = vm.notchState == .closed
            && (
                coordinator.expandingView.show
                    && coordinator.expandingView.type == .music
                    && Defaults[.sneakPeekStyles] == .inline
                || airPodsListeningModeSneakActive
            )
            && Defaults[.enableSneakPeek]
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat = airPodsListeningModeSneakActive
                ? InlineHUD.airPodsListeningModeWidth(
                    closedNotchWidth: vm.closedNotchSize.width,
                    gestureProgress: gestureProgress,
                    minimalistic: Defaults[.enableMinimalisticUI]
                ) + notchHorizontalPadding * 2
                : NotchWingLayout.make(
                    notchWidth: max(vm.closedNotchSize.width, 96) + (isHovering ? 8 : 0),
                    leftContent: MusicWingMetrics.maxTrackInfoWidth,
                    rightContent: MusicWingMetrics.maxTrackInfoWidth,
                    innerClearance: NotchWingLayout.innerClearance
                ).totalWidth + notchHorizontalPadding * 2
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }

        // Inline volume / brightness / backlight (and Bluetooth, mic) HUDs draw a
        // wing either side of the notch; keep the outer frame wide enough for
        // them even when the open notch is narrow (minimalistic, pill mode).
        if vm.notchState == .closed,
           isSneakPeekVisibleOnCurrentScreen,
           Defaults[.inlineHUD],
           ![.music, .battery].contains(coordinator.sneakPeek.type) {
            let hudWidth = InlineHUD.reservedWidth(closedNotchWidth: vm.closedNotchSize.width)
                + notchHorizontalPadding * 2
            return CGSize(width: max(baseSize.width, hudWidth), height: baseSize.height)
        }

        if let size = recordingHUDLayout.size(
            closedNotchSize: vm.closedNotchSize,
            effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
        ) {
            return size
        }
        
        // Handle battery HUD expansion sizing
        if vm.notchState == .closed && 
           coordinator.expandingView.show && 
           coordinator.expandingView.type == .battery &&
           isBatteryHUDVisibleOnCurrentScreen {
            
            if let kind = batteryModel.activeTemporaryHUDKind {
                let style: BatteryNotificationStyle = {
                    switch kind {
                    case .charging: return .compact
                    case .lowBattery: return Defaults[.lowBatteryHUDStyle]
                    case .fullBattery: return Defaults[.fullBatteryHUDStyle]
                    }
                }()
                
                var width = vm.closedNotchSize.width
                var height = vm.effectiveClosedNotchHeight
                
                switch (kind, style) {
                case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
                    width += 180
                case (.lowBattery, .standard):
                    width += 100
                    height += 75
                case (.fullBattery, .standard):
                    width += 80
                    height += 70
                }
                
                return CGSize(width: width, height: height)
            }
        }
        
        return inlineLyricsAdjustedNotchSize(
            from: baseSize,
            isHomeTabActive: coordinator.currentView == .home && vm.notchState == .open
        )
    }
    

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?
    @State private var isHoveringClosedMusicWaveformControl: Bool = false

    @State private var gestureProgress: CGFloat = .zero
    @State private var skipGestureActiveDirection: MusicManager.SkipDirection?
    @State private var isMusicControlWindowVisible = false
    @State private var pendingMusicControlTask: Task<Void, Never>?
    @State private var musicControlHideTask: Task<Void, Never>?
    @State private var musicControlVisibilityDeadline: Date?
    @State private var isMusicControlWindowSuppressed = false
    @State private var hasPendingMusicControlSync = false
    @State private var pendingMusicControlForceRefresh = false
    @State private var musicControlSuppressionTask: Task<Void, Never>?

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.musicControlWindowEnabled) var musicControlWindowEnabled
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    private static let musicControlLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func logMusicControlEvent(_ message: String) {
#if DEBUG
        let timestamp = Self.musicControlLogFormatter.string(from: Date())
        print("[MusicControl] \(timestamp): \(message)")
#endif
    }

    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private func requestMusicControlWindowSyncIfHidden(forceRefresh: Bool = false, delay: TimeInterval = 0) {
        guard !isMusicControlWindowVisible else { return }
        enqueueMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }
    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }
    
    private let zeroHeightHoverPadding: CGFloat = 10
    private let musicControlPauseGrace: TimeInterval = 5
    private let musicControlResumeDelay: TimeInterval = 0.24

    // MARK: - Tab switch direction for smooth transitions
    
    private var tabSwitchTransition: AnyTransition {
        .tabSlide(forward: coordinator.tabSwitchForward)
    }
    
    private var standardMediaControlsActive: Bool {
        showStandardMediaControls && !enableMinimalisticUI
    }

    private var closedMusicContentEnabled: Bool {
        enableMinimalisticUI || showStandardMediaControls
    }

    private var isMusicHUDDeferredAfterUnlock: Bool {
        lockScreenManager.shouldDelayPostUnlockMusicHUD
    }

    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isDynamicIslandMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            return activeCornerRadiusInsets.closed.bottom
        }
        if Defaults[.cornerRadiusScaling] {
            return activeCornerRadiusInsets.opened.top - 5
        }
        return activeCornerRadiusInsets.opened.bottom - 5
    }

    private var bodyHoverAreaPadding: CGFloat {
        if vm.notchState == .open && Defaults[.extendHoverArea] {
            return 0
        }
        return vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding + bodyHoverAreaPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }

    private func closedMusicPairingEligible(hasActiveMusicSnapshot: Bool) -> Bool {
        isClosedMusicPairingEligible(
            notchState: vm.notchState,
            hasActiveMusicSnapshot: hasActiveMusicSnapshot,
            musicLiveActivityEnabled: coordinator.musicLiveActivityEnabled,
            closedMusicContentEnabled: closedMusicContentEnabled,
            hideOnClosed: vm.hideOnClosed,
            isLocked: lockScreenManager.isLocked,
            isDeferredAfterUnlock: isMusicHUDDeferredAfterUnlock
        )
    }

    /// How every closed-notch live activity arrives and leaves. The wings grow
    /// out of the notch centre themselves (see `NotchWings`); this adds the
    /// squeeze-and-fade on the way in and out.
    private var closedLiveActivitySwapTransition: AnyTransition {
        .closedActivity
    }

    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        if enableMinimalisticUI {
            // Keep normal closed corner radius, use minimalistic when opened
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }
    
    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: enableMinimalisticUI)
    }

    private var currentNotchShape: NotchShape {
        let topRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Dynamic Island pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    private var shouldHideUntilHover: Bool {
        hideNonNotchUntilHover
            && isNonNotchScreen
            && vm.notchState == .closed
            && !isSneakPeekVisibleOnCurrentScreen
            && !isConnectivityHUDVisible
    }

    private var isConnectivityHUDVisible: Bool {
        NetworkConnectivityHUDMetrics.isPresented(
            state: networkConnectivityManager.hudState,
            notchState: vm.notchState,
            hideOnClosed: vm.hideOnClosed,
            isLocked: lockScreenManager.isLocked
        )
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        shouldHideUntilHover && !lockScreenManager.isLocked
    }
    
    /// Pill shape for Dynamic Island mode with animated corner radius transitions.
    private var currentPillShape: DynamicIslandPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return DynamicIslandPillShape(cornerRadius: radius)
    }

    private var isBatteryHUDVisibleOnCurrentScreen: Bool {
        guard coordinator.expandingView.show, coordinator.expandingView.type == .battery else { return false }
        guard showPowerStatusNotifications else { return false }
        guard batteryModel.activeTemporaryHUDKind != nil else { return false }
        if showOnAllDisplays { return true }
        guard let targetScreenName = batteryModel.activeTemporaryHUDTargetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    private var isCurrentScreenExpansionVisible: Bool {
        guard coordinator.expandingView.show else { return false }
        if coordinator.expandingView.type == .battery {
            return isBatteryHUDVisibleOnCurrentScreen
        }
        return true
    }

    private var currentScreenExpansionType: SneakContentType? {
        isCurrentScreenExpansionVisible ? coordinator.expandingView.type : nil
    }

    private var hasActiveMusicSnapshotForClosedPairing: Bool {
        if musicManager.isPlaying { return true }

        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !musicManager.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !musicManager.isPlayerIdle && hasMusicMetadata
    }

    private var recordingLiveActivityVisibleOnClosedNotch: Bool {
        recordingHUDLayout.isVisible
    }

    private var recordingHUDLayout: RecordingHUDLayout {
        makeRecordingHUDLayout(
            notchState: vm.notchState,
            screenRecordingDetectionEnabled: enableScreenRecordingDetection,
            showRecordingIndicator: showRecordingIndicator,
            hideOnClosed: vm.hideOnClosed,
            isRecording: recordingManager.isRecording,
            closedMusicPairingEligible: closedMusicPairingEligible(
                hasActiveMusicSnapshot: hasActiveMusicSnapshotForClosedPairing
            ),
            recordingControlMode: recordingControlMode,
            canStopFromHUD: recordingManager.shouldShowStopControlsInHUD,
            enableMinimalisticUI: enableMinimalisticUI,
            recordingHoverStyle: recordingHoverStyle,
            suppressHoverExpansion: recordingManager.isScreenSharingAppActive,
            expanded: isHovering
        )
    }

    private var recordingHUDDefaultExpandedOnHover: Bool {
        recordingHUDLayout.showsDefaultExpansion
    }

    private var recordingHUDInlineExpandedOnHover: Bool {
        recordingHUDLayout.showsInlineExpansion
    }

    private var recordingHUDExtraWidth: CGFloat {
        recordingHUDLayout.extraWidth
    }

    private var recordingHUDExtraHeight: CGFloat {
        recordingHUDLayout.extraHeight
    }

    private var displayedBatteryHUDLevel: Int {
        let resolvedLevel = batteryModel.activeTemporaryHUDLevelOverride
            ?? Int(batteryModel.levelBattery.rounded())
        return min(max(resolvedLevel, 0), 100)
    }

    private var displayedBatteryHUDUsesLowPowerMode: Bool {
        batteryModel.activeTemporaryHUDLowPowerModeOverride ?? batteryModel.isInLowPowerMode
    }


    private var activeClosedBatterySurfaceShape: AnyShape? {
        guard vm.notchState == .closed else { return nil }
        guard isBatteryHUDVisibleOnCurrentScreen else { return nil }
        guard let kind = batteryModel.activeTemporaryHUDKind else { return nil }

        if isDynamicIslandMode {
            let radius = dynamicIslandPillCornerRadiusInsets.opened
            return AnyShape(DynamicIslandPillShape(cornerRadius: radius))
        } else {
            let topRadius = activeCornerRadiusInsets.closed.top
            let bottomRadius: CGFloat = {
                switch resolvedBatteryNotificationStyle(for: kind) {
                case .compact:
                    return activeCornerRadiusInsets.closed.bottom
                case .standard:
                    return kind == .fullBattery ? 36 : 40
                }
            }()
            return AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        }
    }

    private var activeClosedRecordingSurfaceShape: AnyShape? {
        guard recordingHUDDefaultExpandedOnHover else { return nil }

        if isDynamicIslandMode {
            return AnyShape(DynamicIslandPillShape(cornerRadius: dynamicIslandPillCornerRadiusInsets.opened))
        }

        return AnyShape(
            NotchShape(
                topCornerRadius: activeCornerRadiusInsets.closed.top,
                bottomCornerRadius: 40
            )
        )
    }

    private func resolvedBatteryNotificationStyle(for kind: BatteryTemporaryHUDKind) -> BatteryNotificationStyle {
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }


    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when dynamic island mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if isConnectivityHUDVisible {
            if isDynamicIslandMode {
                let radius: CGFloat = networkConnectivityManager.hudState == .noConnection ? 40 : 24
                return AnyShape(DynamicIslandPillShape(cornerRadius: radius))
            }
            let bottomRadius: CGFloat = networkConnectivityManager.hudState == .noConnection ? 40 : 20
            return AnyShape(
                NotchShape(
                    topCornerRadius: activeCornerRadiusInsets.closed.top,
                    bottomCornerRadius: bottomRadius
                )
            )
        }
        if let activeClosedRecordingSurfaceShape {
            return activeClosedRecordingSurfaceShape
        }
        if let activeClosedBatterySurfaceShape {
            return activeClosedBatterySurfaceShape
        }
        if isDynamicIslandMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            .frame(alignment: .top)
            // Connectivity HUD metrics already describe the complete surface.
            // Applying the regular closed-notch inset here makes that surface
            // wider than both the root view and its NSWindow, clipping both sides.
            .padding(.horizontal, isConnectivityHUDVisible ? 0 : notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(.black)
            .clipShape(resolvedClipShape)
            // Keep the anti-gap fill outside the clipped notch. The window sits
            // this far above screen.maxY, so placing the spacer after clipShape
            // leaves the notch's top corners anchored to the visible screen edge.
            .padding(.top, isIslandMode ? 0 : notchTopScreenBleedAmount)
            .overlay(alignment: .top) {
                if !isIslandMode {
                    Rectangle()
                        .fill(.black)
                        .frame(height: notchTopScreenBleedAmount)
                }
            }
            .compositingGroup()
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                    ? .black.opacity(0.6)
                    : .clear,
                radius: Defaults[.cornerRadiusScaling] ? 10 : 5
            )
            // Extra horizontal inset for Dynamic Island mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.bottom, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.top, pillTopOffset)
            .accessibilityIdentifier("AtollNotch")
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .conditionalModifier(!useModernCloseAnimation) { view in
                let hoverAnimation = NotchlyTheme.Motion.hover
                let notchStateAnimation = NotchlyTheme.Motion.notchClose
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            }
            .conditionalModifier(useModernCloseAnimation) { view in
                let hoverAnimation = NotchlyTheme.Motion.hover
                let notchAnimation = vm.notchState == .open ? NotchlyTheme.Motion.notchOpen : NotchlyTheme.Motion.notchClose
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
            }
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        guard !isConnectivityHUDVisible else { return }
                        guard !recordingOpenGestureLocked else { return }
                        if handleClosedMusicWaveformTapIfNeeded() {
                            return
                        }
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .left) { translation, phase in
                                handleSkipGesture(direction: .forward, translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handleSkipGesture(direction: .backward, translation: translation, phase: phase)
                            }
                    }
            }
            .conditionalModifier((Defaults[.closeGestureEnabled] || Defaults[.reverseScrollGestures]) && Defaults[.enableGestures] && interactionsEnabled) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.
            .padding(.bottom, notchBottomPadding)
            .offset(y: shouldHideUntilHover && !isHovering
                ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                : 0
            )
            .onAppear(perform: {
                if coordinator.firstLaunch && !isConnectivityHUDVisible {
                    // Single open during first launch; closeHello() handles the timed close.
                    runAfter(1) {
                        openNotch()
                    }
                }
            })
            .onChange(of: vm.notchState) { _, newState in
                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
                if newState != .closed {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                runAfter(0.1) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
//                Button("Edit") { // Doesnt work....
//                    let dn = DynamicNotch(content: EditPanelView())
//                    dn.toggle()
//                }
//                #if DEBUG
//                .disabled(false)
//                #else
//                .disabled(true)
//                #endif
//                .keyboardShortcut("E", modifiers: .command)
            }
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
        }
        .frame(
            maxWidth: (dynamicNotchSize.width + (vm.notchState == .open ? 24 : 0) + (isDynamicIslandMode ? dynamicIslandShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height + (vm.notchState == .open ? 12 : 0) + (isIslandMode ? 0 : notchTopScreenBleedAmount) + (isDynamicIslandMode ? dynamicIslandTopOffset + dynamicIslandShadowInset * 2 : currentShadowPadding)).rounded(),
            alignment: .top
        )
        .animation(nil, value: vm.notchState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(privacyManager)
        .background(stashDropDetector)
        .environmentObject(vm)
        .environmentObject(webcamManager)
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        installSecondaryRootLifecycleHandlers(
            on: installPrimaryRootLifecycleHandlers(on: view)
        )
    }

    private func installPrimaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onAppear {
                isMusicControlWindowSuppressed = vm.notchState != .closed
                    || lockScreenManager.isLocked
                    || isMusicHUDDeferredAfterUnlock
                if musicManager.isPlaying || !musicManager.isPlayerIdle {
                    clearMusicControlVisibilityDeadline()
                }
                if let deadline = musicControlVisibilityDeadline, Date() > deadline {
                    clearMusicControlVisibilityDeadline()
                }
                enqueueMusicControlWindowSync(forceRefresh: true)
                startHiddenEdgeHoverPolling()
                // Deterministic teardown for borderless panels (`.onDisappear` is
                // unreliable); the window-cleanup path calls this before closing.
                vm.onViewTeardown = { performViewTeardown() }
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .open {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: musicControlWindowEnabled) { _, enabled in
                if enabled {
                    if musicManager.isPlaying || !musicManager.isPlayerIdle {
                        clearMusicControlVisibilityDeadline()
                    }
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: coordinator.musicLiveActivityEnabled) { _, enabled in
                if enabled {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: vm.hideOnClosed) { _, hidden in
                if hidden {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.isLocked) { _, locked in
                if locked {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.shouldDelayPostUnlockMusicHUD) { _, deferred in
                if deferred {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: 0)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
    }

    private func installSecondaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onChange(of: showStandardMediaControls) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: enableMinimalisticUI) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: gestureProgress) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: isHovering) { _, hovering in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: hovering ? 0.05 : 0.12)
                }
            }
            .onChange(of: recordingManager.isRecording) { _, isRecording in
                if isRecording {
                    stopHoverClickMonitor()
                } else if isHovering && Defaults[.openNotchOnHover] {
                    startHoverClickMonitor()
                }
            }
            .onChange(of: musicManager.isPlaying) { _, isPlaying in
                handleMusicControlPlaybackChange(isPlaying: isPlaying)
            }
            .onChange(of: musicManager.isPlayerIdle) { _, isIdle in
                handleMusicControlIdleChange(isIdle: isIdle)
            }
            .onChange(of: vm.closedNotchSize) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onChange(of: vm.effectiveClosedNotchHeight) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onAppear {
                if vm.notchState == .closed { menuBarLayout.startTracking() }
            }
            .onChange(of: vm.notchState) { _, state in
                // An open notch covers the menu bar wholesale and is the user's
                // own doing, so there is nothing to step around while it is up.
                if state == .closed {
                    menuBarLayout.startTracking()
                } else {
                    menuBarLayout.stopTracking()
                }
            }
            .onDisappear {
                performViewTeardown()
            }
    }

    /// How far right the closed-notch content has to move so it stops covering
    /// the frontmost app's menus.
    ///
    /// A live activity's left wing draws into the strip of menu bar beside the
    /// notch, which is where the app's own menus live. macOS lays those out
    /// against `NSScreen.auxiliaryTopLeftArea` and there is no way to tell it
    /// some of that strip is spoken for -- both auxiliary areas are read-only.
    /// So the content moves instead of the menus.
    ///
    /// Zero unless something is actually being covered: no live activity, an
    /// open notch, no accessibility permission, or menus that end before the
    /// content begins all leave the notch centred where it belongs.
    private var menuBarClearanceOffset: CGFloat {
        guard vm.notchState == .closed,
              !vm.hideOnClosed,
              closedContentWidth > 0,
              !closedActivityKeepsWingsCentred,
              let menusRightEdge = menuBarLayout.appMenusRightEdge,
              let screenFrame = getScreenFrame(currentScreenName)
        else { return 0 }

        return MenuBarLayout.clearanceOffset(
            contentWidth: closedContentWidth,
            screenFrame: screenFrame,
            menusRightEdge: menusRightEdge,
            gap: MenuBarLayout.clearanceGap
        )
    }

    /// True while the closed notch shows only activities built from `NotchWings`
    /// -- which is all of them except the tall panels.
    ///
    /// Wings keep the same width on both sides with the notch-sized gap dead
    /// centre, and stay clear of the frontmost app's menus by narrowing (see
    /// `ClosedNotchMetrics`). Sliding them sideways, as the offset does, would
    /// carry the gap off the hardware cut-out: the left wing would slide under
    /// the notch and the right wing would be clipped by the surface.
    ///
    /// The exceptions are the panels that hang *below* the menu bar -- the
    /// recording hover panel, the standard-style low/full battery alerts and
    /// the standard-style HUD line. They have no wings to narrow, so they still
    /// step aside instead.
    private var closedActivityKeepsWingsCentred: Bool {
        guard vm.notchState == .closed else { return false }
        if recordingHUDDefaultExpandedOnHover { return false }
        if currentScreenExpansionType == .battery,
           isBatteryHUDVisibleOnCurrentScreen,
           let kind = batteryModel.activeTemporaryHUDKind {
            return kind == .charging || resolvedBatteryNotificationStyle(for: kind) == .compact
        }
        return !standardSneakPeekPanelVisible
            || closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshotForClosedPairing)
    }

    /// A standard-style (non-inline) HUD or sneak peek is showing its line under
    /// the notch row.
    private var standardSneakPeekPanelVisible: Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let type = coordinator.sneakPeek.type
        if type == .capsLock || type == .battery { return false }
        let isAirPodsListeningModeSneak = type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        if type == .music {
            return resolvedSneakPeekStyle() == .standard
        }
        return !(Defaults[.inlineHUD] || isAirPodsListeningModeSneak)
    }

    /// Changes whenever a different closed-notch activity takes the floor, and
    /// only then. It keys the animation that lets the notch surface grow and
    /// shrink with the activity's wings, without a blanket animation on every
    /// layout change (a ticking timer must not spring the whole notch).
    private struct ClosedActivitySignature: Equatable {
        var sneakPeek: SneakContentType?
        var expansion: SneakContentType?
        var music: Bool
        var capsLock: Bool
        var timer: Bool
        var recording: Bool
        var download: Bool
        var focus: Bool
        var privacy: Bool
        var idleFace: Bool
        var stash: Bool
    }

    private var closedActivitySignature: ClosedActivitySignature {
        ClosedActivitySignature(
            sneakPeek: isSneakPeekVisibleOnCurrentScreen ? coordinator.sneakPeek.type : nil,
            expansion: currentScreenExpansionType,
            music: closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshotForClosedPairing),
            capsLock: capsLockManager.isCapsLockActive,
            timer: timerActivity != nil,
            recording: recordingManager.isRecording,
            download: downloadManager.isDownloading,
            focus: doNotDisturbManager.isDoNotDisturbActive || doNotDisturbManager.isFocusToastDismissing,
            privacy: privacyManager.hasAnyIndicator,
            idleFace: !musicManager.isPlaying && musicManager.isPlayerIdle,
            stash: stashClosedNoticeVisible
        )
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                  if isConnectivityHUDVisible {
                      NetworkConnectivityHUD(
                          state: networkConnectivityManager.hudState,
                          closedNotchSize: vm.closedNotchSize,
                          effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
                      )
                  } else if coordinator.firstLaunch {
                      Spacer()
                      HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                          vm.closeHello()
                      })
                      .padding(.top, 40)
                      Spacer()
                  } else {
                        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                            || !musicManager.artistName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                      let hasActiveMusicSnapshot: Bool = {
                          if musicManager.isPlaying { return true }
                          return !musicManager.isPlayerIdle && hasMusicMetadata
                      }()
                      let musicPairingEligible = closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshot)
                      let musicSecondary = resolveMusicSecondaryLiveActivity(isMusicPairingEligible: musicPairingEligible)
                      let activeSneakPeekStyle = resolvedSneakPeekStyle()
                      let expansionMatchesSecondary: Bool = {
                          guard let musicSecondary else { return false }
                          switch musicSecondary {
                          case .timer:
                              return false
                          case .recording:
                              return currentScreenExpansionType == .recording
                          case .focus:
                              return currentScreenExpansionType == .doNotDisturb
                          case .capsLock:
                              return false
                          }
                      }()
                      let canShowMusicDuringExpansion = !isCurrentScreenExpansionVisible
                          || currentScreenExpansionType == .music
                          || expansionMatchesSecondary
                      let isAirPodsListeningModeSneak = coordinator.sneakPeek.type == .bluetoothAudio
                          && coordinator.sneakPeek.value < 0
                          && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil

                      if currentScreenExpansionType == .battery
                            && isBatteryHUDVisibleOnCurrentScreen
                            && vm.notchState == .closed
                            && Defaults[.showPowerStatusNotifications]
                            && batteryModel.activeTemporaryHUDKind != nil {
                        BatteryTemporaryActivityView(
                            kind: batteryModel.activeTemporaryHUDKind ?? .charging,
                            batteryLevel: displayedBatteryHUDLevel,
                            isLowPowerMode: displayedBatteryHUDUsesLowPowerMode,
                            closedNotchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
                            baseHeight: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
                            isDynamicIslandMode: isDynamicIslandMode,
                            topCornerRadius: activeCornerRadiusInsets.closed.top,
                            styleOverride: batteryModel.activeTemporaryHUDKind.map { resolvedBatteryNotificationStyle(for: $0) },
                            extras: batteryModel.activeTemporaryHUDExtras
                        )
                        .id(batteryModel.activeTemporaryHUDToken)
                      } else if isSneakPeekVisibleOnCurrentScreen && (Defaults[.inlineHUD] || isAirPodsListeningModeSneak) && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(
                                  coordinator.sneakPeek.type == .capsLock
                                      ? closedLiveActivitySwapTransition
                                      : AnyTransition.hudReveal
                              )
                      } else if stashClosedNoticeVisible, let notice = stashManager.closedNotice {
                          StashClosedActivity(notice: notice)
                              .id(notice.id)
                              .transition(closedLiveActivitySwapTransition)
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock), value: .constant(1.0), icon: .constant(""), hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(closedLiveActivitySwapTransition)
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                              .id("closed-music-live-activity")
                              .transition(closedLiveActivitySwapTransition)
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && timerActivity != nil && coordinator.timerLiveActivityEnabled && !vm.hideOnClosed {
                          TimerActivityLiveActivity()
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .recording) && vm.notchState == .closed && recordingManager.isRecording && Defaults[.enableScreenRecordingDetection] && Defaults[.showRecordingIndicator] && !vm.hideOnClosed && !musicPairingEligible {
                          RecordingLiveActivity(hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .download) && vm.notchState == .closed && downloadManager.isDownloading && Defaults[.enableDownloadListener] && !vm.hideOnClosed {
                          DownloadLiveActivity()
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .doNotDisturb) && vm.notchState == .closed && Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && (doNotDisturbManager.isDoNotDisturbActive || doNotDisturbManager.isFocusToastDismissing) && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          DoNotDisturbLiveActivity()
                              .transition(closedLiveActivitySwapTransition)
                    } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .privacy) && vm.notchState == .closed && privacyManager.hasAnyIndicator && (Defaults[.enableCameraDetection] || Defaults[.enableMicrophoneDetection]) && !vm.hideOnClosed {
                        PrivacyLiveActivity()
                              .transition(closedLiveActivitySwapTransition)
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          DynamicIslandFaceAnimation()
                              .transition(closedLiveActivitySwapTransition)
                      } else if vm.notchState == .open {
                          DynamicIslandHeader()
                              .frame(height: (Defaults[.enableMinimalisticUI] && isDynamicIslandMode) ? nil : max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if isSneakPeekVisibleOnCurrentScreen {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .capsLock) && !Defaults[.inlineHUD] && !isAirPodsListeningModeSneak && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                              .transition(.hudReveal)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              // The surface follows the wings: animate it only when the activity changes.
              .animation(NotchlyTheme.Motion.spring, value: closedActivitySignature)
              .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                  view
                      .fixedSize()
              }
              .background {
                  GeometryReader { geo in
                      Color.clear
                          .onAppear { closedContentWidth = geo.size.width }
                          .onChange(of: geo.size.width) { _, width in closedContentWidth = width }
                  }
              }
              .pinnedLyrics(isVisible: pinnedLyricsVisible,
                  isContentHidden: isSneakPeekVisibleOnCurrentScreen || isConnectivityHUDVisible)
              // A connectivity HUD must remain centred on the physical notch:
              // its middle transparent lane is what keeps both wings visible.
              // Menu-bar clearance would shift that lane underneath the camera
              // housing and clip one of the two content areas.
              .offset(x: isConnectivityHUDVisible ? 0 : menuBarClearanceOffset)
              .animation(NotchlyTheme.Motion.spring, value: menuBarClearanceOffset)
              .zIndex(2)
              
              ZStack {
                  if vm.notchState == .open {
                      // The content arrives a beat after the shell has started to
                      // expand; switching tabs slides the page within it.
                      ZStack {
                          Group {
                              switch coordinator.currentView {
                                  case .home:
                                      NotchHomeView(albumArtNamespace: albumArtNamespace)
                                  case .stash:
                                      StashView()
                              }
                          }
                          .id(coordinator.currentView)
                          .transition(tabSwitchTransition)
                      }
                      .transition(.notchContentReveal)
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
              .animation(NotchlyTheme.Motion.spring, value: coordinator.currentView)
          }
      }

    /// The idle face: the animation sits beside the notch, in a wing the same
    /// width as its (empty) twin on the other side.
    @ViewBuilder
    func DynamicIslandFaceAnimation() -> some View {
        let sideSize = max(0, vm.effectiveClosedNotchHeight - 12)
        let layout = ClosedNotchMetrics.wingLayout(
            notchWidth: vm.closedNotchSize.width,
            screenName: currentScreenName,
            leftContent: sideSize,
            rightContent: sideSize,
            isHovering: isHovering
        )
        NotchWings(layout: layout, height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)) {
            Color.clear
                .frame(width: sideSize, height: sideSize)
        } right: {
            IdleAnimationView()
                .frame(width: sideSize, height: sideSize)
        }
    }

    /// Whether the closed music activity is showing the track's title and artist
    /// beside the notch (the inline sneak peek after a track change).
    private var closedMusicShowsTrackInfo: Bool {
        coordinator.expandingView.show
            && coordinator.expandingView.type == .music
            && Defaults[.enableSneakPeek]
            && Defaults[.sneakPeekStyles] == .inline
    }

    private var closedMusicTextColor: Color {
        Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray
    }

    private static let closedMusicTitleFont = NSFont.systemFont(ofSize: 12, weight: .medium)

    /// The line being sung, shown in the closed activity's title slot while
    /// lyrics mode is on and the music is playing. Timed lyrics only.
    private var closedLyricLine: String? {
        guard lyricsMode.isActive, musicManager.isPlaying, musicManager.hasTimedLyrics else { return nil }
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
    private static let closedMusicArtistFont = NSFont.systemFont(ofSize: 11, weight: .regular)

    /// Wing sizes for the closed music activity.
    ///
    /// The wings are symmetric and the gap between them is exactly the notch, so
    /// the artwork, title, artist and visualizer only ever sit beside the
    /// cut-out. The wider side (artwork + title, or artist + visualizer) sets
    /// both wings, which grow together on a spring.
    private func closedMusicWingLayout(secondary: MusicSecondaryLiveActivity?) -> NotchWingLayout {
        let closedHeight = vm.effectiveClosedNotchHeight
        let notchContentHeight = isHovering ? max(0, closedHeight) : max(0, closedHeight - 12)
        let wingBaseWidth = max(0, notchContentHeight + gestureProgress / 2)
        let artworkSize = max(0, closedHeight - 12)
        let showsInfo = closedMusicShowsTrackInfo
        let visualizerWidth = CGFloat(Defaults[.visualizerBarCount]) * 4

        let titleWidth: CGFloat = showsInfo
            ? NotchWingLayout.textWidth(musicManager.songTitle, font: Self.closedMusicTitleFont)
                + (musicManager.isCurrentTrackExplicit ? 22 : 0) + 2
            : 0
        // The right wing belongs to the pairing (timer, recording...) when there
        // is one, so the artist only shows alongside the plain visualizer.
        let artistWidth: CGFloat = (showsInfo && secondary == nil)
            ? NotchWingLayout.textWidth(musicManager.artistName, font: Self.closedMusicArtistFont) + 2
            : 0

        let leftContent = MusicWingMetrics.leftContent(
            artworkWidth: artworkSize + 3,
            titleWidth: titleWidth,
            showsTrackInfo: showsInfo
        )
        let pairedRight = resolvedRightWingWidth(
            for: secondary,
            baseWidth: wingBaseWidth,
            centerBaseWidth: max(vm.closedNotchSize.width, 96),
            notchHeight: notchContentHeight
        )
        let rightContent = secondary == nil
            ? max(pairedRight, MusicWingMetrics.rightContent(
                visualizerWidth: max(visualizerWidth, 0),
                artistWidth: artistWidth,
                showsTrackInfo: showsInfo
            ))
            : pairedRight

        return NotchWingLayout.make(
            notchWidth: max(vm.closedNotchSize.width, 96),
            leftContent: leftContent,
            rightContent: rightContent,
            minimumWing: wingBaseWidth,
            centerExtra: isHovering ? 8 : 0,
            innerClearance: showsInfo ? NotchWingLayout.innerClearance : 0,
            maximumTotalWidth: ClosedNotchMetrics.maximumContentWidth(screenName: currentScreenName)
        )
    }

    @ViewBuilder
    private func MusicLiveActivity(secondary preResolvedSecondary: MusicSecondaryLiveActivity? = nil) -> some View {
        let secondary = preResolvedSecondary ?? resolveMusicSecondaryLiveActivity()
        let closedHeight = vm.effectiveClosedNotchHeight
        let outerHeight = closedHeight + (isHovering ? 8 : 0)
        let notchContentHeight = isHovering ? max(0, closedHeight) : max(0, closedHeight - 12)
        let artworkSize = max(0, closedHeight - 12)
        let layout = closedMusicWingLayout(secondary: secondary)
        let showsInfo = closedMusicShowsTrackInfo
        let badgeBaseSize = max(13, artworkSize * 0.36)
        let badgeDisplaySize = badgeDisplaySize(for: secondary, baseSize: badgeBaseSize)
        let badgeOffset = badgeOverlayOffset(for: secondary, badgeSize: badgeDisplaySize)
        let artistFieldWidth = MusicWingMetrics.textFieldWidth(
            wingContentWidth: layout.contentWidth,
            reserved: CGFloat(Defaults[.visualizerBarCount]) * 4
        )
        let titleFieldWidth = MusicWingMetrics.textFieldWidth(
            wingContentWidth: layout.contentWidth,
            reserved: artworkSize + 3
        )
        let albumArt = musicManager.albumArt
        let artCornerRadius = albumArt.size.width / max(albumArt.size.height, 1) > 1.0
            ? MusicPlayerImageSizes.cornerRadiusInset.closed / 3.0
            : MusicPlayerImageSizes.cornerRadiusInset.closed

        ZStack {
            NotchWings(layout: layout, height: outerHeight) {
                HStack(spacing: MusicWingMetrics.spacing) {
                    ZStack(alignment: .bottomTrailing) {
                        // Keep the matched-geometry source bounded to the closed
                        // artwork square while the surrounding hover flap expands.
                        ZStack(alignment: .bottomTrailing) {
                            Color.clear
                                .frame(width: artworkSize, height: artworkSize)
                                .background(
                                    CrossfadeArtwork(image: albumArt, cornerRadius: artCornerRadius)
                                )
                                .clipped()
                                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                                .albumArtFlip(angle: musicManager.flipAngle)
                                .trackChangePop(trigger: musicManager.songTitle + "\u{1F}" + musicManager.artistName)
                                // Paused art settles back a little, playing art fills its square.
                                .scaleEffect(musicManager.isPlaying ? 1 : 0.94)
                                .opacity(musicManager.isPlaying ? 1 : 0.86)
                                .animation(NotchlyTheme.Motion.spring, value: musicManager.isPlaying)
                            albumArtBadge(for: secondary, badgeSize: badgeDisplaySize)
                                .offset(x: badgeOffset.width, y: badgeOffset.height)
                                .id(secondary?.id ?? "music-badge")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: artworkSize, height: artworkSize, alignment: .bottomTrailing)
                    }
                    .frame(width: artworkSize + 3, height: notchContentHeight, alignment: .center)

                    if showsInfo, titleFieldWidth > 8, !musicManager.songTitle.isEmpty {
                        // In lyrics mode the line being sung takes the title's
                        // place. The wing keeps the width the title asked for,
                        // so changing lines never resizes the activity.
                        if let lyric = closedLyricLine {
                            MarqueeText(
                                .constant(lyric),
                                font: .system(size: 12, weight: .medium),
                                nsFont: .callout,
                                textColor: closedMusicTextColor,
                                minDuration: 0.4,
                                frameWidth: titleFieldWidth
                            )
                            .id("closed-lyric-\(lyric)")
                            .transition(.lyricLine)
                        } else {
                            MusicTitleMarqueeView(
                                text: musicManager.songTitle,
                                isExplicit: musicManager.isCurrentTrackExplicit,
                                font: .system(size: 12, weight: .medium),
                                nsFont: .callout,
                                textColor: closedMusicTextColor,
                                minDuration: 0.4,
                                frameWidth: titleFieldWidth,
                                badgeHeight: 13
                            )
                            .id("closed-title-\(musicManager.songTitle)")
                            .transition(.wingSlide(from: .leading))
                        }
                    }
                }
                .animation(NotchlyTheme.Motion.spring, value: showsInfo)
                .animation(NotchlyTheme.Motion.spring, value: musicManager.songTitle)
                .animation(NotchlyTheme.Motion.spring, value: closedLyricLine)
            } right: {
                HStack(spacing: MusicWingMetrics.spacing) {
                    if showsInfo, secondary == nil, artistFieldWidth > 8, !musicManager.artistName.isEmpty {
                        MarqueeText(
                            .constant(musicManager.artistName),
                            font: .system(size: 11, weight: .regular),
                            nsFont: .caption1,
                            textColor: closedMusicTextColor,
                            minDuration: 0.4,
                            frameWidth: artistFieldWidth
                        )
                        .id("closed-artist-\(musicManager.artistName)")
                        .transition(.wingSlide(from: .trailing))
                    }

                    musicRightWing(for: secondary, notchHeight: notchContentHeight, trailingWidth: layout.rightWing)
                        .frame(
                            width: (showsInfo && secondary == nil)
                                ? CGFloat(Defaults[.visualizerBarCount]) * 4
                                : max(0, layout.contentWidth),
                            height: notchContentHeight,
                            alignment: .center
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary) else {
                                if isHoveringClosedMusicWaveformControl {
                                    isHoveringClosedMusicWaveformControl = false
                                }
                                return
                            }
                            withAnimation(.smooth(duration: 0.16)) {
                                isHoveringClosedMusicWaveformControl = hovering
                            }
                        }
                        .id(secondary?.id ?? "music-spectrum")
                        .contentTransition(.symbolEffect(.replace))
                }
                .animation(NotchlyTheme.Motion.spring, value: showsInfo)
                .animation(NotchlyTheme.Motion.spring, value: musicManager.artistName)
            }
            // On displays without a notch the "notch" is drawn, not cut, so its
            // middle is free to carry the song line.
            if Defaults[.showSongMetadataInClosedNotch] && isNonNotchScreen && !musicManager.songTitle.isEmpty
                && !(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                MarqueeText(
                    .constant("\(musicManager.songTitle) • \(musicManager.artistName)"),
                    textColor: closedMusicTextColor,
                    minDuration: 3,
                    frameWidth: max(0, layout.centerGap - 16)
                )
                .padding(.horizontal, 8)
                .frame(width: layout.centerGap, height: notchContentHeight)
                .clipped()
            }
        }
        .frame(height: outerHeight, alignment: .center)
        .animation(.smooth(duration: 0.25), value: secondary?.id)
    }

    private func resolveMusicSecondaryLiveActivity(isMusicPairingEligible: Bool = true) -> MusicSecondaryLiveActivity? {
        if coordinator.timerLiveActivityEnabled && timerActivity != nil {
            return .timer
        }

        if enableScreenRecordingDetection && showRecordingIndicator && recordingManager.isRecording {
            return .recording
        }

        if enableDoNotDisturbDetection && showDoNotDisturbIndicator && doNotDisturbManager.isDoNotDisturbActive {
            let mode = FocusModeType.resolve(identifier: doNotDisturbManager.currentFocusModeIdentifier, name: doNotDisturbManager.currentFocusModeName)
            return .focus(mode)
        }

        if enableCapsLockIndicator && capsLockManager.isCapsLockActive {
            return .capsLock(showLabel: showCapsLockLabel)
        }

        return nil
    }

    private func resolvedRightWingWidth(for secondary: MusicSecondaryLiveActivity?, baseWidth: CGFloat, centerBaseWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard let secondary else { return baseWidth }

        switch secondary {
        case .timer:
            guard let activity = timerActivity else { return baseWidth }
            return TimerActivityMetrics.pairedRightWingWidth(for: activity, notchHeight: notchHeight, baseWidth: baseWidth)
        case .capsLock(let showLabel):
            return showLabel ? scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.4, extra: 12) : baseWidth
        case .focus:
            return focusRightWingWidth(baseWidth: baseWidth)
        case .recording:
            return recordingRightWingWidth(baseWidth: baseWidth)
        }
    }

    private func focusRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Focus pairings now mirror the default music spectrum width to keep the notch compact.
        return baseWidth
    }

    private func recordingRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Keep recording pairings compact by reducing the width relative to the notch height.
        let absoluteMin: CGFloat = 38
        let preferredWidth = max(baseWidth * 0.6, 0)
        let maxWidth = min(baseWidth - 6, 52)
        let clampedPreferred = min(preferredWidth, maxWidth)
        return min(baseWidth, max(absoluteMin, clampedPreferred))
    }

    private func scaledWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat, factor: CGFloat, extra: CGFloat) -> CGFloat {
        max(baseWidth, max(centerBaseWidth * factor, baseWidth + extra))
    }

    @ViewBuilder
    private func albumArtBadge(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> some View {
        if let secondary, badgeSize > 0 {
            ZStack {
                Circle()
                    .fill(Color.black)

                switch secondary {
                case .timer:
                    Image(systemName: timerActivity?.symbolName ?? "timer")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(Color.white)
                case .focus(let mode):
                    mode.resolvedActiveIcon(usePrivateSymbol: true)
                        .renderingMode(.template)
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(mode.accentColor)
                case .recording:
                    Circle()
                        .fill(Color.red)
                        .frame(width: badgeSize * 0.45, height: badgeSize * 0.45)
                        .modifier(PulsingModifier())
                case .capsLock:
                    Image(systemName: "capslock.fill")
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(capsLockTintMode.color)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        } else {
            EmptyView()
        }
    }

    private func badgeDisplaySize(for secondary: MusicSecondaryLiveActivity?, baseSize: CGFloat) -> CGFloat {
        guard let secondary else { return baseSize }
        switch secondary {
        default:
            return baseSize
        }
    }

    private func badgeOverlayOffset(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> CGSize {
        guard let secondary else { return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25) }
        switch secondary {
        default:
            return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
        }
    }

    @ViewBuilder
    private func musicRightWing(for secondary: MusicSecondaryLiveActivity?, notchHeight: CGFloat, trailingWidth: CGFloat) -> some View {
        switch secondary {
        case .timer:
            if let activity = timerActivity {
                MusicTimerSupplementView(presentation: activity, notchHeight: notchHeight)
            }
        case .capsLock(let showLabel):
            if showLabel {
                MusicCapsLockLabelView(color: capsLockTintMode.color)
            } else {
                spectrumView(forceSpectrum: true)
            }
        case .focus:
            spectrumView(forceSpectrum: true)
        case .recording:
            spectrumView(forceSpectrum: true, trailingInset: 6)
        case .none:
            spectrumView(
                forceSpectrum: false,
                enableClosedPlayPauseOverlay: shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
            )
        }
    }

    @ViewBuilder
    private func SpectrumVisualizer(
        useMusicVisualizer: Bool,
        forceSpectrum: Bool
    ) -> some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        if useMusicVisualizer || forceSpectrum {
            Rectangle()
                .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
                .frame(width: 50, alignment: .center)
                .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                .mask {
                    AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                        .frame(width: width, height: 12)
                }
        }
    }

    @ViewBuilder
    private func spectrumView(
        forceSpectrum: Bool,
        trailingInset: CGFloat = 0,
        enableClosedPlayPauseOverlay: Bool = false
    ) -> some View {
        if useMusicVisualizer || forceSpectrum {
            SpectrumVisualizer(useMusicVisualizer: useMusicVisualizer, forceSpectrum: forceSpectrum)
                .blur(radius: (enableClosedPlayPauseOverlay && isHoveringClosedMusicWaveformControl) ? 2.4 : 0)
                .overlay {
                    if enableClosedPlayPauseOverlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(isHoveringClosedMusicWaveformControl ? 0.24 : 0.02))

                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(isHoveringClosedMusicWaveformControl ? 0.98 : 0.0))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, trailingInset)
                .animation(.smooth(duration: 0.16), value: isHoveringClosedMusicWaveformControl)
                .animation(.smooth(duration: 0.2), value: musicManager.isPlaying)
        } else {
            LottieAnimationView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// What the running timer / stopwatch looks like on the closed notch, if either is active.
    private var timerActivity: TimerActivityPresentation? {
        TimerActivityMetrics.resolve(timer: timerManager, stopwatch: stopwatchManager)
    }

    // MARK: - Private Methods
    private func openNotch() {
        vm.open()
    }

    private func shouldShowClosedMusicWaveformPlayPauseOverlay(for secondary: MusicSecondaryLiveActivity?) -> Bool {
        guard secondary == nil else { return false }
        return isClosedMusicGestureContext && !Defaults[.openNotchOnHover]
    }

    private var isClosedMusicGestureContext: Bool {
        vm.notchState == .closed
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
            && !isCurrentScreenExpansionVisible
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !coordinator.firstLaunch
    }

    private func handleClosedMusicWaveformTapIfNeeded() -> Bool {
        guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: nil),
              isHoveringClosedMusicWaveformControl else {
            return false
        }

        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        musicManager.playPause()
        return true
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        // Follows the rendered content: when a live activity has stepped aside
         // from the menus, activating at the old centre would arm the notch where
         // nothing is drawn and refuse the pointer where it is.
        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2 + menuBarClearanceOffset,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return activationRect.contains(location)
    }

    /// Cancels every long-lived task / event monitor this view owns. Called from
    /// `.onDisappear` and from `vm.onViewTeardown` on window close. Idempotent.
    private func performViewTeardown() {
        menuBarLayout.stopTracking()
        hoverTask?.cancel()
        stopHoverClickMonitor()
        stopHiddenEdgeHoverPolling()
        cancelMusicControlWindowSync()
        hideMusicControlWindow()
        cancelMusicControlVisibilityTimer()
        clearMusicControlVisibilityDeadline()
        musicControlSuppressionTask?.cancel()
        isHoveringClosedMusicWaveformControl = false
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                if self.shouldUseHiddenEdgeHoverPolling {
                    let hovering = self.hiddenHoverActivationContainsMouse()
                    if hovering != self.isHovering {
                        self.handleHover(hovering)
                    }
                } else if self.isHovering && self.interactionsEnabled {
                    let stillInside = self.vm.notchState == .open
                        ? self.isPointInsideNotchWindow()
                        : self.isMouseOverClosedNotchHitArea()
                    if !stillInside {
                        self.hoverTask?.cancel()
                        self.stopHoverClickMonitor()
                        self.finishHoverExit()
                    }
                }

                let intervalMs = self.hiddenEdgeHoverPollingIntervalMs()
                // Let the kernel coalesce these wakeups with other timers.
                try? await Task.sleep(
                    for: .milliseconds(intervalMs),
                    tolerance: .milliseconds(max(10, intervalMs / 5))
                )
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func hiddenEdgeHoverPollingIntervalMs() -> Int {
        let gate = ActivityMonitor.shared.gate
        // Nobody can be pointing at a dark display.
        if gate.isSuspended {
            return 2_000
        }
        if shouldUseHiddenEdgeHoverPolling {
            return gate.reducedActivity ? 100 : 50
        }
        if isHovering && interactionsEnabled {
            return 100
        }
        return gate.reducedActivity ? 2_000 : 1_000
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] else { return }
        guard !isConnectivityHUDVisible else { return }
        guard !recordingLiveActivityVisibleOnClosedNotch else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.isConnectivityHUDVisible else { return }
                guard !self.recordingOpenGestureLocked else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                guard self.isHovering else { return }
                guard !self.handleClosedMusicWaveformTapIfNeeded() else { return }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        // Ignore false hover-exit when the cursor is parked on the screen's top pixel.
        if !hovering, shouldRetainHoverAtScreenTopEdge() {
            return
        }

        hoverTask?.cancel()

        if hovering {
            if !recordingLiveActivityVisibleOnClosedNotch {
                startHoverClickMonitor()
            }
        } else {
            stopHoverClickMonitor()
            if isHoveringClosedMusicWaveformControl {
                withAnimation(.smooth(duration: 0.16)) {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
        }

        if hovering {
            withAnimation(.bouncy.speed(1.2)) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                !isConnectivityHUDVisible,
                !recordingLiveActivityVisibleOnClosedNotch,
                Defaults[.openNotchOnHover] else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.recordingManager.isRecording,
                          !self.recordingLiveActivityVisibleOnClosedNotch,
                          !self.isSneakPeekVisibleOnCurrentScreen,
                          !self.isConnectivityHUDVisible,
                          !self.coordinator.isHoverOpenSuppressed else { return }

                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.shouldRetainHoverAtScreenTopEdge() {
                        return
                    }
                    self.finishHoverExit()
                }
            }
        }
    }

    private func finishHoverExit() {
        withAnimation(.bouncy.speed(1.2)) {
            isHovering = false
        }

        if vm.notchState == .open && !shouldPreventAutoClose() {
            vm.close()
        }
    }

    private func shouldRetainHoverAtScreenTopEdge(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }
        guard isHovering || vm.notchState == .open else { return false }
        guard location.y >= screen.frame.maxY - 1.5 else { return false }

        if vm.notchState == .open {
            return isPointInsideNotchWindow(location)
        }
        return isMouseOverClosedNotchHitArea(location)
    }

    private func isMouseOverClosedNotchHitArea(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let closedHeight = vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
        let closedWidth = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        let recordingSize = recordingHUDLayout.size(
            closedNotchSize: vm.closedNotchSize,
            effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
        )
        let height = max(closedHeight, recordingSize?.height ?? 0) + 6
            + PinnedLyricsView.reservedHeight(isEligible: pinnedLyricsVisible,
                availability: musicManager.lyricsAvailability, context: pinnedLyricContext)
        let width = max(closedWidth, recordingSize?.width ?? 0) + 24
        // Same shift the content is drawn with, so the hit area stays under it.
        let minX = screen.frame.midX - width / 2 + menuBarClearanceOffset
        let minY = screen.frame.maxY - height

        return location.x >= minX && location.x <= minX + width
            && location.y >= minY && location.y <= screen.frame.maxY
    }

    private func isPointInsideNotchWindow(_ point: CGPoint = NSEvent.mouseLocation) -> Bool {
        if let appDelegate = AppDelegate.shared {
            if Defaults[.showOnAllDisplays] {
                return appDelegate.windows.values.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
            }
            if let window = appDelegate.window {
                return frameContainsPointIncludingTopEdge(window.frame, point)
            }
        }

        return NSApp.windows.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
    }

    /// `CGRect.contains` is half-open on max edges; the top pixel needs inclusive maxY.
    private func frameContainsPointIncludingTopEdge(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
    
    /// Track-level reservation. A sneak peek hides only the overlaid words.
    private var pinnedLyricsVisible: Bool {
        PinnedLyricsView.shouldReserve(
            lyricsEnabled: enableLyrics,
            pinEnabled: pinLyricsWhenClosed,
            surfaceEligible: vm.notchState == .closed && !vm.hideOnClosed
                && !lockScreenManager.isLocked && musicManager.isPlaying,
            availability: musicManager.lyricsAvailability
        )
    }

    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
     return vm.isBatteryPopoverActive || 
         vm.isMediaOutputPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        // Dragging a stash item out takes the cursor off the notch; closing it then
        // would tear down the view that is acting as the drag source.
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed || SharingStateManager.shared.preventNotchClose || stashManager.isDraggingOut
    }

    // MARK: - Stash drag and drop

    /// Whether the closed-notch "+1" confirmation is showing on this notch.
    private var stashClosedNoticeVisible: Bool {
        stashManager.closedNotice != nil
            && enableStash
            && vm.notchState == .closed
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
    }

    private var stashAcceptsDrops: Bool {
        enableStash && !enableMinimalisticUI && !lockScreenManager.isLocked && !coordinator.firstLaunch
    }

    /// A transparent layer over the whole notch window that takes drops of files,
    /// text, links and images. A drag over the closed notch opens it on the Stash
    /// tab; dropping adds the items.
    private var stashDropDetector: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: StashDropReader.acceptedTypes, delegate: StashDropDelegate(
                isEnabled: { stashAcceptsDrops },
                onTargetChange: { targeted in handleStashDropTarget(targeted) },
                onDrop: { providers in stashManager.ingest(providers: providers) }
            ))
            .onChange(of: stashManager.isDraggingOut) { _, dragging in
                guard !dragging else { return }
                // The drag has ended; if the pointer is not on the notch, let it close.
                runAfter(0.3) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() && !isPointInsideNotchWindow() {
                        vm.close()
                    }
                }
            }
    }

    private func handleStashDropTarget(_ targeted: Bool) {
        stashManager.isDropTargeted = targeted
        stashDragExitTask?.cancel()

        if targeted {
            if coordinator.currentView != .stash {
                withAnimation(NotchlyTheme.Motion.spring) { coordinator.currentView = .stash }
            }
            if vm.notchState == .closed {
                stashOpenedByDrag = true
                openNotch()
            }
            return
        }

        // Leaving can be the notch resizing under the pointer rather than the
        // drag actually leaving, so wait a beat and look again.
        stashDragExitTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                defer { stashOpenedByDrag = false }
                guard stashOpenedByDrag,
                      !stashManager.isDropTargeted,
                      vm.notchState == .open,
                      !isPointInsideNotchWindow(),
                      !shouldPreventAutoClose() else { return }
                vm.close()
            }
        }
    }
    
    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 { // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: true, translation: translation, phase: phase)
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: false, translation: translation, phase: phase)
    }

    private func handleScrollGesture(isDownward: Bool, translation: CGFloat, phase: NSEvent.Phase) {
        let reverse = Defaults[.reverseScrollGestures]
        let shouldOpen = isDownward ? !reverse : reverse

        if shouldOpen {
            handleOpenScrollGesture(translation: translation, phase: phase)
        } else {
            guard Defaults[.closeGestureEnabled] else { return }
            handleCloseScrollGesture(translation: translation, phase: phase)
        }
    }

    private func handleOpenScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }
        guard !recordingOpenGestureLocked else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
            openNotch()
        }
    }

    private var recordingOpenGestureLocked: Bool {
        recordingLiveActivityVisibleOnClosedNotch
    }

    private func handleCloseScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isScrollGestureActive else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(.smooth) {
                gestureProgress = .zero
                isHovering = false
            }
            vm.close()

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
        }
    }

    private func handleSkipGesture(direction: MusicManager.SkipDirection, translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended {
            skipGestureActiveDirection = nil
            return
        }

        guard canPerformSkipGesture() else {
            skipGestureActiveDirection = nil
            return
        }

        if skipGestureActiveDirection == nil && translation > Defaults[.gestureSensitivity] {
            let effectiveDirection: MusicManager.SkipDirection
            if Defaults[.reverseSwipeGestures] {
                effectiveDirection = direction == .forward ? .backward : .forward
            } else {
                effectiveDirection = direction
            }
            skipGestureActiveDirection = effectiveDirection

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            musicManager.handleSkipGesture(direction: effectiveDirection)
        }
    }

    private func canPerformSkipGesture() -> Bool {
        let canSkipInOpenHome = vm.notchState == .open && coordinator.currentView == .home
        let canSkipInClosedMusic = !Defaults[.openNotchOnHover] && isClosedMusicGestureContext

        return enableHorizontalMusicGestures
            && (canSkipInOpenHome || canSkipInClosedMusic)
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !lockScreenManager.isLocked
            && !hasAnyActivePopovers()
            && !vm.isScrollGestureActive
    }

    private func handleMusicControlPlaybackChange(isPlaying: Bool) {
        guard musicControlWindowEnabled else { return }

        if isPlaying {
            clearMusicControlVisibilityDeadline()
            requestMusicControlWindowSyncIfHidden()
        } else {
            extendMusicControlVisibilityAfterPause()
        }
    }

    private func handleMusicControlIdleChange(isIdle: Bool) {
        guard musicControlWindowEnabled else { return }

        if isIdle {
            if musicControlVisibilityDeadline == nil {
                extendMusicControlVisibilityAfterPause()
            }
        } else if musicManager.isPlaying {
            clearMusicControlVisibilityDeadline()
        }
    }

    private func handleStandardMediaControlsAvailabilityChange() {
        guard musicControlWindowEnabled else {
            hideMusicControlWindow()
            return
        }

        if standardMediaControlsActive {
            if musicManager.isPlaying || !musicManager.isPlayerIdle {
                clearMusicControlVisibilityDeadline()
            }
            enqueueMusicControlWindowSync(forceRefresh: true)
        } else {
            cancelMusicControlWindowSync()
            hideMusicControlWindow()
            clearMusicControlVisibilityDeadline()
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
        }
    }

    private func extendMusicControlVisibilityAfterPause() {
        let deadline = Date().addingTimeInterval(musicControlPauseGrace)
        musicControlVisibilityDeadline = deadline
        scheduleMusicControlVisibilityCheck(deadline: deadline)
        requestMusicControlWindowSyncIfHidden()
    }

    private func clearMusicControlVisibilityDeadline() {
        musicControlVisibilityDeadline = nil
        cancelMusicControlVisibilityTimer()
    }

    private func scheduleMusicControlVisibilityCheck(deadline: Date) {
        cancelMusicControlVisibilityTimer()

        let interval = max(0, deadline.timeIntervalSinceNow)

        musicControlHideTask = Task.detached(priority: .background) { [interval] in
            if interval > 0 {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let currentDeadline = musicControlVisibilityDeadline, currentDeadline <= Date() {
                    musicControlVisibilityDeadline = nil
                }

                enqueueMusicControlWindowSync(forceRefresh: false)

                musicControlHideTask = nil
            }
        }
    }

    private func cancelMusicControlVisibilityTimer() {
        musicControlHideTask?.cancel()
        musicControlHideTask = nil
    }

    private func musicControlVisibilityIsActive() -> Bool {
        if musicManager.isPlaying {
            return true
        }

        guard let deadline = musicControlVisibilityDeadline else { return false }
        return Date() <= deadline
    }

    private func suppressMusicControlWindowUpdates() {
        isMusicControlWindowSuppressed = true
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = nil
    }

    private func releaseMusicControlWindowUpdates(after delay: TimeInterval) {
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = Task { [delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if vm.notchState == .closed && !lockScreenManager.isLocked && !isMusicHUDDeferredAfterUnlock {
                    isMusicControlWindowSuppressed = false
                    triggerPendingMusicControlSyncIfNeeded()
                } else {
                    isMusicControlWindowSuppressed = true
                }
                musicControlSuppressionTask = nil
            }
        }
    }

    private func triggerPendingMusicControlSyncIfNeeded() {
        guard hasPendingMusicControlSync else { return }

        let shouldForce = pendingMusicControlForceRefresh
        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        logMusicControlEvent("Flushing pending floating window sync (force: \(shouldForce))")
        scheduleMusicControlWindowSync(forceRefresh: shouldForce, bypassSuppression: true)
    }

    private func shouldDeferMusicControlSync() -> Bool {
        vm.notchState != .closed
            || lockScreenManager.isLocked
            || isMusicHUDDeferredAfterUnlock
            || isMusicControlWindowSuppressed
    }

    private func enqueueMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0) {
        if shouldDeferMusicControlSync() {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            logMusicControlEvent("Queued floating window sync (force: \(forceRefresh)) while deferred")
            return
        }

        logMusicControlEvent("Scheduling floating window sync (force: \(forceRefresh), delay: \(delay))")
        scheduleMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }

    private func shouldShowMusicControlWindow() -> Bool {
        guard musicControlWindowEnabled,
              coordinator.musicLiveActivityEnabled,
              standardMediaControlsActive,
              vm.notchState == .closed,
              !vm.hideOnClosed,
              !lockScreenManager.isLocked,
              !isMusicHUDDeferredAfterUnlock,
              !isMusicControlWindowSuppressed else {
            return false
        }

        return musicControlVisibilityIsActive()
    }

    private func scheduleMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0, bypassSuppression: Bool = false) {
        #if os(macOS)
        cancelMusicControlWindowSync()

        guard shouldShowMusicControlWindow() else {
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
            hideMusicControlWindow()
            return
        }

        if !bypassSuppression && (isMusicControlWindowSuppressed || lockScreenManager.isLocked || isMusicHUDDeferredAfterUnlock) {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            return
        }

        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        let syncDelay = max(0, delay)

        pendingMusicControlTask = Task.detached(priority: .userInitiated) { [forceRefresh, syncDelay] in
            if syncDelay > 0 {
                let nanoseconds = UInt64(syncDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if shouldShowMusicControlWindow() {
                    logMusicControlEvent("Running floating window sync (force: \(forceRefresh))")
                    syncMusicControlWindow(forceRefresh: forceRefresh)
                } else {
                    logMusicControlEvent("Skipping floating window sync (conditions changed)")
                    hideMusicControlWindow()
                }

                pendingMusicControlTask = nil
            }
        }
        #endif
    }

    private func cancelMusicControlWindowSync() {
        pendingMusicControlTask?.cancel()
        pendingMusicControlTask = nil
    }

    #if os(macOS)
    private struct MusicControlWindowContentKey: Hashable {
        let isPlaying: Bool
        let isPlayerIdle: Bool
        let bundleIdentifier: String?
        let skipBehavior: String
        let skipGestureToken: Int?
    }

    private var musicControlWindowContentRevision: AnyHashable {
        AnyHashable(
            MusicControlWindowContentKey(
                isPlaying: musicManager.isPlaying,
                isPlayerIdle: musicManager.isPlayerIdle,
                bundleIdentifier: musicManager.bundleIdentifier,
                skipBehavior: Defaults[.musicSkipBehavior].rawValue,
                skipGestureToken: musicManager.skipGesturePulse?.token
            )
        )
    }

    private func currentMusicControlWindowMetrics() -> MusicControlWindowMetrics {
        MusicControlWindowMetrics(
            notchHeight: max(vm.closedNotchSize.height, vm.effectiveClosedNotchHeight),
            notchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
            rightWingWidth: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
            cornerRadius: activeCornerRadiusInsets.closed.bottom,
            spacing: 36,
            contentRevision: musicControlWindowContentRevision
        )
    }

    private func syncMusicControlWindow(forceRefresh: Bool = false) {
        let notchAvailable = vm.effectiveClosedNotchHeight > 0 && vm.closedNotchSize.width > 0
        let targetVisible = shouldShowMusicControlWindow() && notchAvailable

        if targetVisible {
            let metrics = currentMusicControlWindowMetrics()
            if !isMusicControlWindowVisible {
                let didPresent = MusicControlWindowManager.shared.present(using: vm, metrics: metrics)
                isMusicControlWindowVisible = didPresent
            } else if forceRefresh {
                let didRefresh = MusicControlWindowManager.shared.refresh(using: vm, metrics: metrics)
                if !didRefresh {
                    MusicControlWindowManager.shared.hide()
                    isMusicControlWindowVisible = false
                }
            }
        } else if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }

    private func hideMusicControlWindow() {
        if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }
    #else
    private func syncMusicControlWindow(forceRefresh: Bool = false) {}

    private func hideMusicControlWindow() {}
    #endif

    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let style = resolvedSneakPeekStyle()
        
        let isMusicSneak = coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isOtherSneak = coordinator.sneakPeek.type != .music && vm.notchState == .closed
        
        return isMusicSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {
        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

private enum MusicSecondaryLiveActivity: Equatable {
    case timer
    case recording
    case focus(FocusModeType)
    case capsLock(showLabel: Bool)

    var id: String {
        switch self {
        case .timer:
            return "timer"
        case .recording:
            return "recording"
        case .focus(let mode):
            return "focus-\(mode.rawValue)"
        case .capsLock(let showLabel):
            return showLabel ? "caps-lock-label" : "caps-lock-icon"
        }
    }
}

private struct MusicCapsLockLabelView: View {
    let color: Color

    var body: some View {
        Text("Caps Lock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.opacity)
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
