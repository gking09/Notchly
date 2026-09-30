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
import Defaults
import KeyboardShortcuts
import Lottie
import Foundation

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

struct CustomAppIcon: Codable, Hashable, Equatable, Defaults.Serializable, Identifiable {
    let id: UUID
    var name: String
    var fileName: String
    var addedAt: Date

    init(id: UUID = UUID(), name: String, fileName: String, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.addedAt = addedAt
    }

    static let iconDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AppIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var fileURL: URL {
        Self.iconDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - Custom Idle Animation Models
struct CustomIdleAnimation: Codable, Hashable, Equatable, Defaults.Serializable, Identifiable {
    let id: UUID
    var name: String
    var source: AnimationSource
    var speed: CGFloat = 1.0
    var isBuiltIn: Bool = false  // Track if it's bundled vs user-added
    
    init(id: UUID = UUID(), name: String, source: AnimationSource, speed: CGFloat = 1.0, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.source = source
        self.speed = speed
        self.isBuiltIn = isBuiltIn
    }
    
    /// Get the effective transform config (override or default)
    func getTransformConfig() -> AnimationTransformConfig {
        let override = Defaults[.animationTransformOverrides][id.uuidString]
        if let override = override {
            print("📋 [CustomIdleAnimation] Found override for '\(name)': \(override)")
        } else {
            print("📋 [CustomIdleAnimation] No override for '\(name)', using default")
        }
        return override ?? .default
    }
}

struct AnimationTransformConfig: Codable, Hashable, Equatable, Defaults.Serializable {
    var scale: CGFloat = 1.0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var cropWidth: CGFloat = 30
    var cropHeight: CGFloat = 20
    var rotation: CGFloat = 0
    var opacity: CGFloat = 1.0
    var paddingBottom: CGFloat = 0  // Allow adjustment to fill notch from bottom
    var expandWithAnimation: Bool = false  // Whether notch should expand horizontally with animation
    var loopMode: AnimationLoopMode = .loop  // Loop mode for animation
    
    static let `default` = AnimationTransformConfig()
}

enum AnimationLoopMode: String, Codable, CaseIterable {
    case loop = "Loop"
    case playOnce = "Play Once"
    case autoReverse = "Auto Reverse"
    
    var lottieLoopMode: LottieLoopMode {
        switch self {
        case .loop: return .loop
        case .playOnce: return .playOnce
        case .autoReverse: return .autoReverse
        }
    }
}

enum AnimationSource: Codable, Hashable, Equatable {
    case lottieFile(URL)        // Local file (in app support or bundle)
    case lottieURL(URL)         // Remote URL
    
    var displayType: String {
        switch self {
        case .lottieFile: return "Local"
        case .lottieURL: return "Remote"
        }
    }
}

// MARK: - Extension Authorization Models

enum ExtensionPermissionScope: String, CaseIterable, Codable, Defaults.Serializable {
    case liveActivities
    case lockScreenWidgets
    case notchExperiences
    case fileSharing

    var displayName: String {
        switch self {
        case .liveActivities: return String(localized: "Live Activities")
        case .lockScreenWidgets: return String(localized: "Lock Screen Widgets")
        case .notchExperiences: return String(localized: "Notch Experiences")
        case .fileSharing: return String(localized: "File Sharing")
        }
    }
}

enum ExtensionAuthorizationStatus: String, CaseIterable, Codable, Defaults.Serializable {
    case pending
    case authorized
    case denied
    case revoked

    var isActive: Bool {
        switch self {
        case .authorized: return true
        case .pending, .denied, .revoked: return false
        }
    }
}

struct ExtensionAuthorizationEntry: Codable, Defaults.Serializable, Identifiable, Hashable {
    let bundleIdentifier: String
    var appName: String
    var status: ExtensionAuthorizationStatus
    var allowedScopes: Set<ExtensionPermissionScope>
    var requestedAt: Date
    var grantedAt: Date?
    var lastActivityAt: Date?
    var lastDeniedReason: String?
    var notes: String?

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        appName: String,
        status: ExtensionAuthorizationStatus,
        allowedScopes: Set<ExtensionPermissionScope> = Set(ExtensionPermissionScope.allCases),
        requestedAt: Date = .now,
        grantedAt: Date? = nil,
        lastActivityAt: Date? = nil,
        lastDeniedReason: String? = nil,
        notes: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.status = status
        self.allowedScopes = allowedScopes
        self.requestedAt = requestedAt
        self.grantedAt = grantedAt
        self.lastActivityAt = lastActivityAt
        self.lastDeniedReason = lastDeniedReason
        self.notes = notes
    }

    var isAuthorized: Bool { status.isActive }
}

struct ExtensionRateLimitRecord: Codable, Defaults.Serializable, Hashable, Identifiable {
    let bundleIdentifier: String
    var activityTimestamps: [Date]
    var widgetTimestamps: [Date]
    var notchExperienceTimestamps: [Date]

    var id: String { bundleIdentifier }

    init(
        bundleIdentifier: String,
        activityTimestamps: [Date] = [],
        widgetTimestamps: [Date] = [],
        notchExperienceTimestamps: [Date] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.activityTimestamps = activityTimestamps
        self.widgetTimestamps = widgetTimestamps
        self.notchExperienceTimestamps = notchExperienceTimestamps
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case activityTimestamps
        case widgetTimestamps
        case notchExperienceTimestamps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        activityTimestamps = try container.decodeIfPresent([Date].self, forKey: .activityTimestamps) ?? []
        widgetTimestamps = try container.decodeIfPresent([Date].self, forKey: .widgetTimestamps) ?? []
        notchExperienceTimestamps = try container.decodeIfPresent([Date].self, forKey: .notchExperienceTimestamps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(activityTimestamps, forKey: .activityTimestamps)
        try container.encode(widgetTimestamps, forKey: .widgetTimestamps)
        try container.encode(notchExperienceTimestamps, forKey: .notchExperienceTimestamps)
    }
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum FantasticalViewStyle: String, CaseIterable, Codable, Defaults.Serializable {
    case mini = "mini"
    case calendar = "calendar"
    
    var displayName: String {
        switch self {
        case .mini: return String(localized: "Mini View")
        case .calendar: return String(localized: "Full Calendar")
        }
    }
}

enum ThirdPartyCalendarApp: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case fantastical = "fantastical"
    case notionCalendar = "notionCalendar"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .fantastical: return "Fantastical"
        case .notionCalendar: return "Notion Calendar"
        }
    }
    
    /// Bundle identifiers to try when looking up the app icon (first match wins).
    var bundleIdentifiers: [String] {
        switch self {
        case .fantastical: return ["com.flexibits.fantastical2.mac", "com.flexibits.fantastical"]
        case .notionCalendar: return ["com.cron.electron"]
        }
    }
    
    var fallbackIconName: String {
        switch self {
        case .fantastical: return "calendar.badge.clock"
        case .notionCalendar: return "calendar.badge.plus"
        }
    }
    
    var fallbackIconColor: Color {
        switch self {
        case .fantastical: return .red
        case .notionCalendar: return .blue
        }
    }
}

enum ThirdPartyDDCProvider: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case betterDisplay
    case lunar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .betterDisplay:
            return "BetterDisplay"
        case .lunar:
            return "Lunar"
        }
    }
    
    /// Bundle identifiers to try when looking up the app icon.
    var bundleIdentifiers: [String] {
        switch self {
        case .betterDisplay: return ["pro.betterdisplay.BetterDisplay"]
        case .lunar: return ["fyi.lunar.Lunar"]
        }
    }
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
/// How the line being sung is picked out from the rest.
enum PinnedLyricContext: Int, CaseIterable, Identifiable, Defaults.Serializable {
    case current = 1
    case three = 3
    case five = 5

    var id: Int { rawValue }
    var localizedName: String {
        switch self {
        case .current: return String(localized: "Current")
        case .three: return String(localized: "3 lines")
        case .five: return String(localized: "5 lines")
        }
    }
}

enum LyricHighlightStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case sweep = "Sweep"
    case gradient = "Gradient"
    case solid = "Solid"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .sweep: return String(localized: "Sweep")
        case .gradient: return String(localized: "Gradient")
        case .solid: return String(localized: "Solid")
        }
    }

    var explanation: String {
        switch self {
        case .sweep:
            return String(localized: "The highlight travels across the line word by word, in reading order.")
        case .gradient:
            return String(localized: "The current line is lit by one fixed gradient that does not move, the way lyrics were marked before the sweep.")
        case .solid:
            return String(localized: "The current line is lit in one flat colour, with nothing crossing it.")
        }
    }
}

enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "Youtube Music"
    case amazonMusic = "Amazon Music"
    case tidal = "TIDAL"
    case cider = "Cider"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .nowPlaying: return String(localized: "Now Playing")
        case .appleMusic: return String(localized: "Apple Music")
        case .spotify: return String(localized: "Spotify")
        case .youtubeMusic: return String(localized: "Youtube Music")
        case .amazonMusic: return String(localized: "Amazon Music")
        case .tidal: return String(localized: "TIDAL")
        case .cider: return String(localized: "Cider")
        }
    }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
    
    var localizedName: String {
        switch self {
        case .standard: return String(localized: "Default")
        case .inline: return String(localized: "Inline")
        }
    }
}

enum LogLevel: Int, CaseIterable, Identifiable, Defaults.Serializable {
    case none = 0
    case error = 1
    case warning = 2
    case info = 3
    case debug = 4
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .none: return "No Logging"
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }
}

enum CapsLockIndicatorTintMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case green
    case accent
    case white

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .green:
            return String(localized: "Green")
        case .accent:
            return String(localized: "Accent")
        case .white:
            return String(localized: "White")
        }
    }

    var color: Color {
        switch self {
        case .green:
            return .green
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }
}

enum ProgressBarStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case hierarchical = "Hierarchical"
    case gradient = "Gradient"
    case segmented = "Segmented"
    
    var id: String { self.rawValue }
}

enum BatteryNotificationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard
    case compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return String(localized: "Standard")
        case .compact:
            return String(localized: "Compact")
        }
    }
}

enum RecordingHoverStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case `default`
    case inline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return String(localized: "Default")
        case .inline:
            return String(localized: "Inline")
        }
    }
}

enum RecordingControlMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case indicatorOnly
    case withStopButton

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indicatorOnly:
            return String(localized: "Indicator only")
        case .withStopButton:
            return String(localized: "With stop button")
        }
    }
}

enum MusicAuxiliaryControl: String, CaseIterable, Identifiable, Defaults.Serializable {
    case shuffle
    case repeatMode
    case mediaOutput
    case lyrics

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shuffle:
            return String(localized: "Shuffle")
        case .repeatMode:
            return String(localized: "Repeat")
        case .mediaOutput:
            return String(localized: "Media Output")
        case .lyrics:
            return String(localized: "Lyrics")
        }
    }

    var symbolName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .repeatMode:
            return "repeat"
        case .mediaOutput:
            return "laptopcomputer"
        case .lyrics:
            return "quote.bubble"
        }
    }

    static func alternative(
        excluding control: MusicAuxiliaryControl,
        preferring candidate: MusicAuxiliaryControl? = nil
    ) -> MusicAuxiliaryControl {
        if let candidate, candidate != control {
            return candidate
        }

        return allCases.first { $0 != control } ?? .shuffle
    }
}

enum MusicSkipBehavior: String, CaseIterable, Identifiable, Defaults.Serializable {
    case track
    case tenSecond

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .track:
            return String(localized: "Track Skip")
        case .tenSecond:
            return String(localized: "±10 Seconds")
        }
    }

    var description: String {
        switch self {
        case .track:
            return String(localized: "Standard previous/next track controls")
        case .tenSecond:
            return String(localized: "Skip forward or backward by ten seconds")
        }
    }
}

enum TimerIconColorMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case adaptive = "Adaptive"
    case solid = "Solid"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .adaptive: return String(localized:"Adaptive gradient")
        case .solid: return String(localized:"Solid colour")
        }
    }
}

enum TimerProgressStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case bar = "Bar"
    case ring = "Ring"
    
    var id: String { rawValue }
    
    var localizedName: String {
        switch self {
        case .bar: return String(localized:"Bar")
        case .ring: return String(localized:"Ring")
        }
    }
}

enum FocusMonitoringMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case withoutDevTools = "withoutDevTools"
    case useDevTools = "useDevTools"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .withoutDevTools:
            return "Use without DevTools"
        case .useDevTools:
            return "Use DevTools"
        }
    }
}

enum SiriResponsivenessMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automatic
    case highPerformance
    case balanced
    case powerSaver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .highPerformance: return String(localized: "High Performance")
        case .balanced: return String(localized: "Balanced")
        case .powerSaver: return String(localized: "Power Saver")
        }
    }

    var description: String {
        switch self {
        case .automatic: return String(localized: "Adapts based on power source and battery level.")
        case .highPerformance: return String(localized: "Ultra-fast detection (30Hz) for near-instant hiding.")
        case .balanced: return String(localized: "Standard detection (16Hz) for smooth responsiveness.")
        case .powerSaver: return String(localized: "Slower detection (4Hz) to maximize battery life.")
        }
    }
}

enum ReminderPresentationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case ringCountdown = "Ring"
    case digital = "Digital"
    case minutes = "Minutes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
            case .ringCountdown:
                return String(localized: "Ring")
            case .digital:
                return String(localized: "Digital")
            case .minutes:
                return String(localized: "Minutes")
        }
    }
}

enum ColorExtractionMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case legacy, vibrant
    var id: Self { self }
}

enum LockScreenLiveActivityIconStyle: String, Defaults.Serializable {
    case lock
    case fingerprint
    case both

    var showsLock: Bool { self == .lock || self == .both }
    var showsFingerprint: Bool { self == .fingerprint || self == .both }
}

extension Defaults.Keys {
        // MARK: General
    static let updateChannel = Key<UpdateChannel>("updateChannel", default: .stable)
    static let logLevel = Key<LogLevel>("logLevel", default: .none)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "Kaafu")
    static let hideDynamicIslandFromScreenCapture = Key<Bool>("hideDynamicIslandFromScreenCapture", default: false)
    
        // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
	static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)
    static let externalDisplayStyle = Key<ExternalDisplayStyle>(
        "externalDisplayStyle",
        default: .notch
    )
    static let hideNonNotchUntilHover = Key<Bool>("hideNonNotchUntilHover", default: false)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let openNotchWidth = Key<CGFloat>("openNotchWidth", default: 640)
    static let closedNotchWidth = Key<CGFloat>("closedNotchWidth", default: 150)
    static let customizePhysicalNotchWidth = Key<Bool>("customizePhysicalNotchWidth", default: false)
        //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    
        // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
        //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let selectedCameraID = Key<String>("selectedCameraID", default: "")
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let accentColor = Key<Color>("accentColor", default: Color.blue)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let useModernCloseAnimation = Key<Bool>("useModernCloseAnimation", default: true)
    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let customIdleAnimations = Key<[CustomIdleAnimation]>("customIdleAnimations", default: [])
    static let selectedIdleAnimation = Key<CustomIdleAnimation?>("selectedIdleAnimation", default: nil)
    static let animationTransformOverrides = Key<[String: AnimationTransformConfig]>("animationTransformOverrides", default: [:])
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: true)
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let visualizerBarCount = Key<Int>("visualizerBarCount", default: 4)
    static let enableWaveformScrubber = Key<Bool>("enableWaveformScrubber", default: true)
    static let colorExtractionMode = Key<ColorExtractionMode>("colorExtractionMode", default: .vibrant)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    static let customAppIcons = Key<[CustomAppIcon]>("customAppIcons", default: [])
    static let selectedAppIconID = Key<String?>("selectedAppIconID", default: nil)
    
        // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    static let enableHorizontalMusicGestures = Key<Bool>("enableHorizontalMusicGestures", default: true)
    static let musicGestureBehavior = Key<MusicSkipBehavior>("musicGestureBehavior", default: .track)
    static let reverseSwipeGestures = Key<Bool>("reverseSwipeGestures", default: false)
    static let reverseScrollGestures = Key<Bool>("reverseScrollGestures", default: false)
    
        // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableRealTimeWaveform = Key<Bool>("enableRealTimeWaveform", default: false)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let showSneakPeekOnTrackChange = Key<Bool>("showSneakPeekOnTrackChange", default: true)
    static let enableFullscreenMediaDetection = Key<Bool>("enableFullscreenMediaDetection", default: true)
    static let parallaxEffectIntensity = Key<Double>("parallaxEffectIntensity", default: 6.0)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: true)
    static let showMediaOutputControl = Key<Bool>("showMediaOutputControl", default: true)
    static let musicAuxLeftControl = Key<MusicAuxiliaryControl>("musicAuxLeftControl", default: .shuffle)
    static let musicAuxRightControl = Key<MusicAuxiliaryControl>("musicAuxRightControl", default: .repeatMode)
    static let didMigrateMusicAuxControls = Key<Bool>("didMigrateMusicAuxControls", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>("musicControlSlots", default: MusicControlButton.defaultLayout)
    static let didMigrateMusicControlSlots = Key<Bool>("didMigrateMusicControlSlots", default: false)
    static let musicSkipBehavior = Key<MusicSkipBehavior>("musicSkipBehavior", default: .track)
    static let musicControlWindowEnabled = Key<Bool>("musicControlWindowEnabled", default: false)
    static let showStandardMediaControls = Key<Bool>("showStandardMediaControls", default: true)
    static let autoHideInactiveNotchMediaPlayer = Key<Bool>("autoHideInactiveNotchMediaPlayer", default: true)
    static let cachedMusicLiveActivityPreference = Key<Bool?>("cachedMusicLiveActivityPreference", default: nil)
    static let cachedMusicControlWindowPreference = Key<Bool?>("cachedMusicControlWindowPreference", default: nil)
    static let siriResponsivenessMode = Key<SiriResponsivenessMode>("siriResponsivenessMode", default: .automatic)
    
    // MARK: Third-party Calendar Integration
    static let enableThirdPartyCalendarApp = Key<Bool>("enableThirdPartyCalendarApp", default: false)
    static let selectedCalendarApp = Key<ThirdPartyCalendarApp>("selectedCalendarApp", default: .fantastical)
    static let fantasticalDefaultView = Key<FantasticalViewStyle>("fantasticalDefaultView", default: .mini)
    
        // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: BatteryActivityManager.shared.hasBattery())
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showBatteryPercentInside = Key<Bool>("showBatteryPercentInside", default: true)
    static let showMinimalisticBatteryIndicator = Key<Bool>("showMinimalisticBatteryIndicator", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    static let playLowBatteryAlertSound = Key<Bool>("playLowBatteryAlertSound", default: true)
    static let showChargingBatteryHUD = Key<Bool>("showChargingBatteryHUD", default: true)
    static let showLowBatteryHUD = Key<Bool>("showLowBatteryHUD", default: true)
    static let showFullBatteryHUD = Key<Bool>("showFullBatteryHUD", default: true)
    static let chargingBatteryHUDDuration = Key<Int>("chargingBatteryHUDDuration", default: 3)
    static let lowBatteryHUDDuration = Key<Int>("lowBatteryHUDDuration", default: 3)
    static let fullBatteryHUDDuration = Key<Int>("fullBatteryHUDDuration", default: 3)
    static let lowBatteryHUDThreshold = Key<Int>("lowBatteryHUDThreshold", default: 20)
    static let fullBatteryHUDThreshold = Key<Int>("fullBatteryHUDThreshold", default: 100)
    static let lowBatteryHUDStyle = Key<BatteryNotificationStyle>("lowBatteryHUDStyle", default: .standard)
    static let fullBatteryHUDStyle = Key<BatteryNotificationStyle>("fullBatteryHUDStyle", default: .standard)

    
        // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let showDownloadSpeed = Key<Bool>("showDownloadSpeed", default: false)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
        // MARK: HUD
    static let inlineHUD = Key<Bool>("inlineHUD", default: true)
    static let progressBarStyle = Key<ProgressBarStyle>("progressBarStyle", default: .hierarchical)
    // Legacy support - keeping for backward compatibility
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showProgressPercentages = Key<Bool>("showProgressPercentages", default: true)
    
    
        // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
        static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
        static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
        // MARK: Fullscreen Media Detection
    static let alwaysHideInFullscreen = Key<Bool>("alwaysHideInFullscreen", default: false)
    
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Wobble Animation
    static let enableWobbleAnimation = Key<Bool>("enableWobbleAnimation", default: false)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    static let spotifySPDCCookie = Key<String>("spotifySPDCCookie", default: "")
    static let spotifyAuthAccessToken = Key<String>("spotifyAuthAccessToken", default: "")
    static let spotifyAuthAccessTokenExpiration = Key<Double>("spotifyAuthAccessTokenExpiration", default: 0)
    static let spotifyAuthLastValidatedAt = Key<Double>("spotifyAuthLastValidatedAt", default: 0)
    static let spotifyLibraryClientID = Key<String>("spotifyLibraryClientID", default: "")

    /// Token for Cider's external-application API, from
    /// Settings > Connectivity > Manage External Application Access in Cider.
    /// Empty is a valid setting: Cider can also run that API with
    /// authentication switched off, and then no header is wanted at all.
    /// Superseded by `CiderTokenStore`, which keeps the token in the Keychain.
    /// Kept only so an existing value can be migrated out of the preferences
    /// plist on first launch; nothing reads it to make a request.
    /// Named `legacy…` so nothing new reaches for it by the old name; the
    /// stored key string is unchanged so existing values still migrate.
    /// A `@available(*, deprecated)` attribute would have been the obvious
    /// alternative, but it fires on `CiderTokenStore` -- the one place that is
    /// supposed to read this -- and a warning at the sanctioned use site is
    /// worse than none.
    static let legacyCiderAPIToken = Key<String>("ciderAPIToken", default: "")
    // The OAuth token pair lives in the Keychain (see KeychainSpotifyTokenStore);
    // these two keys remain only for the one-time migration of early builds.
    static let spotifyLibraryAccessToken = Key<String>("spotifyLibraryAccessToken", default: "")
    static let spotifyLibraryRefreshToken = Key<String>("spotifyLibraryRefreshToken", default: "")
    static let spotifyLibraryTokenExpiration = Key<Double>("spotifyLibraryTokenExpiration", default: 0)
    
    // MARK: Bluetooth Audio Devices
    static let showBluetoothDeviceConnections = Key<Bool>("showBluetoothDeviceConnections", default: true)
    static let useColorCodedBatteryDisplay = Key<Bool>("useColorCodedBatteryDisplay", default: true)
    static let useColorCodedVolumeDisplay = Key<Bool>("useColorCodedVolumeDisplay", default: true)
    static let useSmoothColorGradient = Key<Bool>("useSmoothColorGradient", default: true)
    static let useCircularBluetoothBatteryIndicator = Key<Bool>("useCircularBluetoothBatteryIndicator", default: true)
    static let showBluetoothBatteryPercentageText = Key<Bool>("showBluetoothBatteryPercentageText", default: false)
    static let showBluetoothDeviceNameMarquee = Key<Bool>("showBluetoothDeviceNameMarquee", default: false)
    static let useBluetoothHUD3DIcon = Key<Bool>("useBluetoothHUD3DIcon", default: true)
    static let showAirPodsListeningModeChanges = Key<Bool>("showAirPodsListeningModeChanges", default: true)
    
    // MARK: Timer Feature
    static let enableTimerFeature = Key<Bool>("enableTimerFeature", default: true)
    static let timerDisplayMode = Key<TimerDisplayMode>("timerDisplayMode", default: .tab)
    static let timerPresets = Key<[TimerPreset]>("timerPresets", default: TimerPreset.defaultPresets)
    static let showTimerPresetsInNotchTab = Key<Bool>("showTimerPresetsInNotchTab", default: true)
    static let timerIconColorMode = Key<TimerIconColorMode>("timerIconColorMode", default: .adaptive)
    static let timerSolidColor = Key<Color>("timerSolidColor", default: .blue)
    static let timerShowsCountdown = Key<Bool>("timerShowsCountdown", default: true)
    static let timerShowsLabel = Key<Bool>("timerShowsLabel", default: false)
    static let timerShowsProgress = Key<Bool>("timerShowsProgress", default: true)
    static let timerProgressStyle = Key<TimerProgressStyle>("timerProgressStyle", default: .bar)
    static let mirrorSystemTimer = Key<Bool>("mirrorSystemTimer", default: true)
    static let timerInputStyle = Key<TimerInputStyle>("timerInputStyle", default: .manual)
    
    
    // MARK: Reminder Live Activity
    static let enableReminderLiveActivity = Key<Bool>("enableReminderLiveActivity", default: true)
    static let reminderPresentationStyle = Key<ReminderPresentationStyle>("reminderPresentationStyle", default: .ringCountdown)
    static let reminderLeadTime = Key<Int>("reminderLeadTime", default: 5)
    static let reminderSneakPeekDuration = Key<Double>("reminderSneakPeekDuration", default: 5)
    // Legacy key name: the separate control window is gone, this now shows inline notch controls.
    static let timerControlWindowEnabled = Key<Bool>("timerControlWindowEnabled", default: true)
    
    // MARK: Third-Party Extensions
    static let enableThirdPartyExtensions = Key<Bool>("enableThirdPartyExtensions", default: true)
    static let enableExtensionLiveActivities = Key<Bool>("enableExtensionLiveActivities", default: true)
    static let enableExtensionNotchExperiences = Key<Bool>("enableExtensionNotchExperiences", default: true)
    static let enableExtensionNotchTabs = Key<Bool>("enableExtensionNotchTabs", default: true)
    static let enableExtensionNotchMinimalisticOverrides = Key<Bool>("enableExtensionNotchMinimalisticOverrides", default: true)
    static let enableExtensionNotchInteractiveWebViews = Key<Bool>("enableExtensionNotchInteractiveWebViews", default: true)
    static let extensionAuthorizationEntries = Key<[ExtensionAuthorizationEntry]>("extensionAuthorizationEntries", default: [])
    static let extensionRateLimitRecords = Key<[ExtensionRateLimitRecord]>("extensionRateLimitRecords", default: [])
    static let extensionDiagnosticsLoggingEnabled = Key<Bool>("extensionDiagnosticsLoggingEnabled", default: true)
    static let extensionLiveActivityCapacity = Key<Int>("extensionLiveActivityCapacity", default: 4)
    static let extensionNotchExperienceCapacity = Key<Int>("extensionNotchExperienceCapacity", default: 2)
    static let enableExtensionFileSharing = Key<Bool>("enableExtensionFileSharing", default: true)
    
    // MARK: Keyboard Shortcuts
    static let enableShortcuts = Key<Bool>("enableShortcuts", default: true)
    
    // MARK: System HUD Feature
    static let enableSystemHUD = Key<Bool>("enableSystemHUD", default: true)
    static let enableVolumeHUD = Key<Bool>("enableVolumeHUD", default: true)
    static let enableBrightnessHUD = Key<Bool>("enableBrightnessHUD", default: true)
    static let enableKeyboardBacklightHUD = Key<Bool>("enableKeyboardBacklightHUD", default: true)
    static let systemHUDSensitivity = Key<Int>("systemHUDSensitivity", default: 5)
    static let playVolumeChangeFeedback = Key<Bool>("playVolumeChangeFeedback", default: false)

    // Step sizes for hardware media keys (percent of full range, 1-25)
    static let volumeStepPercent = Key<Int>("volumeStepPercent", default: 6)
    static let volumeFineStepPercent = Key<Int>("volumeFineStepPercent", default: 2)
    static let brightnessStepPercent = Key<Int>("brightnessStepPercent", default: 6)
    static let brightnessFineStepPercent = Key<Int>("brightnessFineStepPercent", default: 2)
    
    // MARK: Custom OSD Window Feature
    static let enableCustomOSD = Key<Bool>("enableCustomOSD", default: false)
    static let enableVerticalHUD = Key<Bool>("enableVerticalHUD", default: false)
    static let enableCircularHUD = Key<Bool>("enableCircularHUD", default: false)
    static let verticalHUDPosition = Key<String>("verticalHUDPosition", default: "right") // "left" or "right"
    
    // Vertical HUD Customization
    static let verticalHUDShowValue = Key<Bool>("verticalHUDShowValue", default: true)
    static let verticalHUDInteractive = Key<Bool>("verticalHUDInteractive", default: true)
    static let verticalHUDHeight = Key<CGFloat>("verticalHUDHeight", default: 160)
    static let verticalHUDWidth = Key<CGFloat>("verticalHUDWidth", default: 36)
    static let verticalHUDPadding = Key<CGFloat>("verticalHUDPadding", default: 24)
    static let verticalHUDUseAccentColor = Key<Bool>("verticalHUDUseAccentColor", default: false)
    static let verticalHUDMaterial = Key<OSDMaterial>("verticalHUDMaterial", default: .frosted)
    static let verticalHUDLiquidGlassCustomizationMode = Key<LockScreenGlassCustomizationMode>(
        "verticalHUDLiquidGlassCustomizationMode",
        default: .standard
    )
    static let verticalHUDLiquidGlassVariant = Key<LiquidGlassVariant>(
        "verticalHUDLiquidGlassVariant",
        default: .defaultVariant
    )
    
    // Circular HUD Customization
    static let circularHUDShowValue = Key<Bool>("circularHUDShowValue", default: true)
    static let circularHUDSize = Key<CGFloat>("circularHUDSize", default: 65)
    static let circularHUDStrokeWidth = Key<CGFloat>("circularHUDStrokeWidth", default: 4)
    static let circularHUDUseAccentColor = Key<Bool>("circularHUDUseAccentColor", default: true)

    // MARK: Third-Party DDC Integration
    static let enableThirdPartyDDCIntegration = Key<Bool>("enableThirdPartyDDCIntegration", default: false)
    static let thirdPartyDDCProvider = Key<ThirdPartyDDCProvider>("thirdPartyDDCProvider", default: .betterDisplay)
    static let enableExternalVolumeControlListener = Key<Bool>("enableExternalVolumeControlListener", default: false)
    static let didMigrateThirdPartyDDCIntegration = Key<Bool>("didMigrateThirdPartyDDCIntegration", default: false)

    // Legacy keys retained for migration/backward compatibility
    static let enableBetterDisplayIntegration = Key<Bool>("enableBetterDisplayIntegration", default: false)
    static let enableLunarIntegration = Key<Bool>("enableLunarIntegration", default: false)
    
    static let hasSeenOSDAlphaWarning = Key<Bool>("hasSeenOSDAlphaWarning", default: false)
    static let enableOSDVolume = Key<Bool>("enableOSDVolume", default: true)
    static let enableOSDBrightness = Key<Bool>("enableOSDBrightness", default: true)
    static let enableOSDKeyboardBacklight = Key<Bool>("enableOSDKeyboardBacklight", default: true)
    static let osdMaterial = Key<OSDMaterial>("osdMaterial", default: .frosted)
    static let osdLiquidGlassCustomizationMode = Key<LockScreenGlassCustomizationMode>(
        "osdLiquidGlassCustomizationMode",
        default: .standard
    )
    static let osdLiquidGlassVariant = Key<LiquidGlassVariant>(
        "osdLiquidGlassVariant",
        default: .defaultVariant
    )
    static let osdIconColorStyle = Key<OSDIconColorStyle>("osdIconColorStyle", default: .white)
    
    // MARK: Screen Recording Detection Feature
    static let enableScreenRecordingDetection = Key<Bool>("enableScreenRecordingDetection", default: true)
    static let showRecordingIndicator = Key<Bool>("showRecordingIndicator", default: true)
    static let recordingHoverStyle = Key<RecordingHoverStyle>("recordingHoverStyle", default: .default)
    static let recordingControlMode = Key<RecordingControlMode>("recordingControlMode", default: .withStopButton)
    // Polling removed - now uses event-driven private API detection (CGSIsScreenWatcherPresent)
    // static let enableScreenRecordingPolling = Key<Bool>("enableScreenRecordingPolling", default: false)

    // MARK: Focus / Do Not Disturb Detection
    static let enableDoNotDisturbDetection = Key<Bool>("enableDoNotDisturbDetection", default: true)
    static let focusMonitoringMode = Key<FocusMonitoringMode>("focusMonitoringMode", default: .withoutDevTools)
    static let showDoNotDisturbIndicator = Key<Bool>("showDoNotDisturbIndicator", default: true)
    static let showDoNotDisturbLabel = Key<Bool>("showDoNotDisturbLabel", default: true)
    static let focusIndicatorNonPersistent = Key<Bool>("focusIndicatorNonPersistent", default: false)
    
    // MARK: Privacy Indicators (Camera & Microphone Detection)
    static let enableCameraDetection = Key<Bool>("enableCameraDetection", default: true)
    static let enableMicrophoneDetection = Key<Bool>("enableMicrophoneDetection", default: true)
    
    // MARK: Lock Screen Features
    static let enableLockScreenLiveActivity = Key<Bool>("enableLockScreenLiveActivity", default: true)
    static let lockScreenLiveActivityIconStyle = Key<LockScreenLiveActivityIconStyle>("lockScreenLiveActivityIconStyle", default: .lock)
    static let enableLockSounds = Key<Bool>("enableLockSounds", default: true)
    
    // MARK: Caps Lock Indicator
    static let enableCapsLockIndicator = Key<Bool>("enableCapsLockIndicator", default: true)
    static let capsLockIndicatorUseGreenColor = Key<Bool>("capsLockIndicatorUseGreenColor", default: false) // Legacy toggle
    static let capsLockIndicatorTintMode = Key<CapsLockIndicatorTintMode>("capsLockIndicatorTintMode", default: .white)
    static let didMigrateCapsLockTintMode = Key<Bool>("didMigrateCapsLockTintMode", default: false)
    static let showCapsLockLabel = Key<Bool>("showCapsLockLabel", default: false)
    
    // MARK: ImageService
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCacheV1", default: false)
    
    // MARK: Minimalistic UI Mode
    static let enableMinimalisticUI = Key<Bool>("enableMinimalisticUI", default: false)
    
    // MARK: Lyrics Feature
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)

    /// Whether the sung line is swept or simply lit.
    static let lyricHighlightStyle = Key<LyricHighlightStyle>("lyricHighlightStyle", default: .sweep)
    /// Keeps the current line under the closed notch after the panel is gone.
    static let pinnedLyricContext = Key<PinnedLyricContext>("pinnedLyricContext", default: .current)
    static let pinLyricsWhenClosed = Key<Bool>("pinLyricsWhenClosed", default: false)
    static let lyricsPanelWidth = Key<CGFloat>("lyricsPanelWidth", default: 280)
    static let lyricsPanelOffset = Key<CGFloat>("lyricsPanelOffset", default: 0)
    static let showLiveCanvasInDynamicIsland = Key<Bool>("showLiveCanvasInDynamicIsland", default: false)
    
    // Helper to determine the default media controller based on macOS version
    static var defaultMediaController: MediaControllerType {
        if #available(macOS 15.4, *) {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }
    
    // Migration helper to convert from legacy enableGradient Boolean to new ProgressBarStyle enum
    static func migrateProgressBarStyle() {
        // Check if migration is needed by seeing if the old Boolean was set to gradient
        let wasGradientEnabled = Defaults[.enableGradient]
        
        // Only migrate if we're still using the default hierarchical value but gradient was enabled
        if wasGradientEnabled && Defaults[.progressBarStyle] == .hierarchical {
            Defaults[.progressBarStyle] = .gradient
        }
    }

    static func migrateMusicAuxControls() {
        if Defaults[.didMigrateMusicAuxControls] == false {
            if Defaults[.showMediaOutputControl] {
                Defaults[.musicAuxRightControl] = .mediaOutput
            }

            Defaults[.didMigrateMusicAuxControls] = true
        }

        normalizeMusicAuxControls()
    }

    static func migrateCapsLockTintMode() {
        guard Defaults[.didMigrateCapsLockTintMode] == false else { return }

        let legacyGreen = Defaults[.capsLockIndicatorUseGreenColor]
        Defaults[.capsLockIndicatorTintMode] = legacyGreen ? .green : .white
        Defaults[.didMigrateCapsLockTintMode] = true
    }

    static func migrateMusicControlSlots() {
        guard Defaults[.didMigrateMusicControlSlots] == false else { return }

        let allowMediaOutput = Defaults[.showMediaOutputControl]
        let baseLayout: [MusicControlButton]

        if Defaults[.showShuffleAndRepeat] {
            var slots = MusicControlButton.defaultLayout
            let left = MusicControlButton(auxiliaryControl: Defaults[.musicAuxLeftControl])
            let right = MusicControlButton(auxiliaryControl: Defaults[.musicAuxRightControl])
            slots[0] = left
            slots[4] = right
            baseLayout = slots
        } else {
            baseLayout = MusicControlButton.minimalLayout
        }

        Defaults[.musicControlSlots] = baseLayout.normalized(allowingMediaOutput: allowMediaOutput)
        Defaults[.didMigrateMusicControlSlots] = true
    }

    static func migrateThirdPartyDDCIntegration() {
        if Defaults[.didMigrateThirdPartyDDCIntegration] == false {
            let legacyBetterDisplayEnabled = Defaults[.enableBetterDisplayIntegration]
            let legacyLunarEnabled = Defaults[.enableLunarIntegration]

            if legacyBetterDisplayEnabled || legacyLunarEnabled {
                Defaults[.enableThirdPartyDDCIntegration] = true
                Defaults[.thirdPartyDDCProvider] = (legacyLunarEnabled && !legacyBetterDisplayEnabled) ? .lunar : .betterDisplay
            }

            Defaults[.didMigrateThirdPartyDDCIntegration] = true
        }

        syncLegacyThirdPartyDDCKeys()
    }

    static func syncLegacyThirdPartyDDCKeys() {
        let isIntegrationEnabled = Defaults[.enableThirdPartyDDCIntegration]
        let selectedProvider = Defaults[.thirdPartyDDCProvider]
        Defaults[.enableBetterDisplayIntegration] = isIntegrationEnabled && selectedProvider == .betterDisplay
        Defaults[.enableLunarIntegration] = isIntegrationEnabled && selectedProvider == .lunar
    }

    private static func normalizeMusicAuxControls() {
        guard Defaults[.musicAuxLeftControl] == Defaults[.musicAuxRightControl] else { return }

        let current = Defaults[.musicAuxLeftControl]
        let fallback = MusicAuxiliaryControl.alternative(excluding: current)
        Defaults[.musicAuxRightControl] = fallback
    }
    static let showSongMetadataInClosedNotch = Key<Bool>("showSongMetadataInClosedNotch", default: false)
}
