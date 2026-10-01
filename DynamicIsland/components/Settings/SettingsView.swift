//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case liveActivities
    case appearance
    case lockScreen
    case media
    case devices
    case quickActions
    case stash
    case hub
    case hudAndOSD
    case battery
    case downloads
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .liveActivities: return String(localized: "Live Activities")
        case .appearance: return String(localized: "Appearance")
        case .lockScreen: return String(localized: "Lock Screen")
        case .media: return String(localized: "Media")
        case .devices: return String(localized: "Devices")
        case .quickActions: return String(localized: "Quick Actions")
        case .stash: return String(localized: "Stash")
        case .hub: return String(localized: "Hub")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .downloads: return String(localized: "Downloads")
        case .shortcuts: return String(localized: "Shortcuts")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .liveActivities: return "waveform.path.ecg"
        case .appearance: return "paintpalette"
        case .lockScreen: return "lock.laptopcomputer"
        case .media: return "play.laptopcomputer"
        case .devices: return "headphones"
        case .quickActions: return "square.grid.2x2.fill"
        case .stash: return "tray.and.arrow.down.fill"
        case .hub: return "clock.fill"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .downloads: return "square.and.arrow.down"
        case .shortcuts: return "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .blue
        case .liveActivities: return .pink
        case .appearance: return .purple
        case .lockScreen: return .orange
        case .media: return .green
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .quickActions: return .red
        case .stash: return .teal
        case .hub: return .cyan
        case .hudAndOSD: return .indigo
        case .battery: return Color(red: 0.202, green: 0.783, blue: 0.348, opacity: 1.000)
        case .downloads: return .gray
        case .shortcuts: return .orange
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct LegacySettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    init(
        tab: SettingsTab,
        title: String,
        keywords: [String],
        highlightID: String?
    ) {
        self.tab = tab
        self.title = title
        self.keywords = keywords
        self.highlightID = highlightID
    }

    var id: String { "\(tab.rawValue)-\(title)" }
}

private enum LegacySettingsSearchCatalog {
    static let entries: [LegacySettingsSearchEntry] = [
        // General
        LegacySettingsSearchEntry(tab: .general, title: "Enable Minimalistic UI", keywords: ["minimalistic", "ui mode", "general"], highlightID: SettingsTab.general.highlightID(for: "Enable Minimalistic UI")),
        LegacySettingsSearchEntry(tab: .general, title: "Menubar icon", keywords: ["menu bar", "status bar", "icon"], highlightID: SettingsTab.general.highlightID(for: "Menubar icon")),
        LegacySettingsSearchEntry(tab: .general, title: "Launch at login", keywords: ["autostart", "startup"], highlightID: SettingsTab.general.highlightID(for: "Launch at login")),
        LegacySettingsSearchEntry(tab: .general, title: "Show on all displays", keywords: ["multi-display", "external monitor"], highlightID: SettingsTab.general.highlightID(for: "Show on all displays")),
        LegacySettingsSearchEntry(tab: .general, title: "Show on a specific display", keywords: ["preferred screen", "display picker"], highlightID: SettingsTab.general.highlightID(for: "Show on a specific display")),
        LegacySettingsSearchEntry(tab: .general, title: "Automatically switch displays", keywords: ["auto switch", "displays"], highlightID: SettingsTab.general.highlightID(for: "Automatically switch displays")),
        LegacySettingsSearchEntry(tab: .general, title: "Hide Notchly during screenshots & recordings", keywords: ["privacy", "screenshot", "recording"], highlightID: SettingsTab.general.highlightID(for: "Hide Notchly during screenshots & recordings")),
        LegacySettingsSearchEntry(tab: .general, title: "Enable gestures", keywords: ["gestures", "trackpad"], highlightID: SettingsTab.general.highlightID(for: "Enable gestures")),
        LegacySettingsSearchEntry(tab: .general, title: "Close gesture", keywords: ["pinch", "swipe"], highlightID: SettingsTab.general.highlightID(for: "Close gesture")),
        LegacySettingsSearchEntry(tab: .general, title: "Reverse swipe gestures", keywords: ["reverse", "swipe", "media"], highlightID: SettingsTab.general.highlightID(for: "Reverse swipe gestures")),
        LegacySettingsSearchEntry(tab: .general, title: "Reverse scroll gestures", keywords: ["reverse", "scroll", "open", "close"], highlightID: SettingsTab.general.highlightID(for: "Reverse scroll gestures")),
        LegacySettingsSearchEntry(tab: .general, title: "Extend hover area", keywords: ["hover", "cursor"], highlightID: SettingsTab.general.highlightID(for: "Extend hover area")),
        LegacySettingsSearchEntry(tab: .general, title: "Enable haptics", keywords: ["haptic", "feedback"], highlightID: SettingsTab.general.highlightID(for: "Enable haptics")),
        LegacySettingsSearchEntry(tab: .general, title: "Open notch on hover", keywords: ["hover to open", "auto open"], highlightID: SettingsTab.general.highlightID(for: "Open notch on hover")),
        LegacySettingsSearchEntry(tab: .general, title: "External display style", keywords: ["dynamic island", "pill", "external display", "non-notch", "floating", "capsule"], highlightID: SettingsTab.general.highlightID(for: "External display style")),
        LegacySettingsSearchEntry(tab: .general, title: "Hide until hovered", keywords: ["hide", "hover", "external", "non-notch", "auto hide", "slide"], highlightID: SettingsTab.general.highlightID(for: "Hide until hovered")),
        LegacySettingsSearchEntry(tab: .general, title: "Notch display height", keywords: ["display height", "menu bar size"], highlightID: SettingsTab.general.highlightID(for: "Notch display height")),

        // Live Activities
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Enable Screen Recording Detection", keywords: ["screen recording", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Screen Recording Detection")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Show Recording Indicator", keywords: ["recording indicator", "red dot"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Recording Indicator")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Recording Controls", keywords: ["screen recording", "stop button", "indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Recording Controls")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Recording Hover Style", keywords: ["screen recording", "hover", "inline", "stop"], highlightID: SettingsTab.liveActivities.highlightID(for: "Recording Hover Style")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Enable Focus Detection", keywords: ["focus", "do not disturb", "dnd"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Focus Detection")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Show Focus Indicator", keywords: ["focus icon", "moon"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Indicator")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Show Focus Label", keywords: ["focus label", "text"], highlightID: SettingsTab.liveActivities.highlightID(for: "Show Focus Label")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Enable Camera Detection", keywords: ["camera", "privacy indicator"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Camera Detection")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Enable Microphone Detection", keywords: ["microphone", "privacy"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable Microphone Detection")),
        LegacySettingsSearchEntry(tab: .liveActivities, title: "Enable music live activity", keywords: ["music", "now playing"], highlightID: SettingsTab.liveActivities.highlightID(for: "Enable music live activity")),

        // Battery (Charge)
        LegacySettingsSearchEntry(tab: .battery, title: "Show battery indicator", keywords: ["battery hud", "charge"], highlightID: SettingsTab.battery.highlightID(for: "Show battery indicator")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show battery percentage", keywords: ["battery percent"], highlightID: SettingsTab.battery.highlightID(for: "Show battery percentage")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show power status notifications", keywords: ["notifications", "power"], highlightID: SettingsTab.battery.highlightID(for: "Show power status notifications")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show power status icons", keywords: ["power icons", "charging icon"], highlightID: SettingsTab.battery.highlightID(for: "Show power status icons")),
        LegacySettingsSearchEntry(tab: .battery, title: "Play low battery alert sound", keywords: ["low battery", "alert", "sound"], highlightID: SettingsTab.battery.highlightID(for: "Play low battery alert sound")),
        LegacySettingsSearchEntry(tab: .battery, title: "Charging HUD", keywords: ["battery", "charging", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Charging HUD")),
        LegacySettingsSearchEntry(tab: .battery, title: "Low battery HUD", keywords: ["battery", "low", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Low battery HUD")),
        LegacySettingsSearchEntry(tab: .battery, title: "Fully charged HUD", keywords: ["battery", "full", "temporary activity"], highlightID: SettingsTab.battery.highlightID(for: "Fully charged HUD")),
        LegacySettingsSearchEntry(tab: .battery, title: "Charging duration", keywords: ["charging", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Charging duration")),
        LegacySettingsSearchEntry(tab: .battery, title: "Low battery duration", keywords: ["low battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Low battery duration")),
        LegacySettingsSearchEntry(tab: .battery, title: "Full battery duration", keywords: ["full battery", "duration", "seconds"], highlightID: SettingsTab.battery.highlightID(for: "Full battery duration")),
        LegacySettingsSearchEntry(tab: .battery, title: "Test charging HUD", keywords: ["battery", "test", "charging", "preview"], highlightID: nil),
        LegacySettingsSearchEntry(tab: .battery, title: "Test low battery HUD", keywords: ["battery", "test", "low", "preview"], highlightID: nil),
        LegacySettingsSearchEntry(tab: .battery, title: "Test full battery HUD", keywords: ["battery", "test", "full", "preview"], highlightID: nil),
        LegacySettingsSearchEntry(tab: .battery, title: "Low battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Low battery style")),
        LegacySettingsSearchEntry(tab: .battery, title: "Low battery threshold", keywords: ["battery", "threshold", "percent"], highlightID: SettingsTab.battery.highlightID(for: "Low battery threshold")),
        LegacySettingsSearchEntry(tab: .battery, title: "Full battery style", keywords: ["battery", "style", "compact", "standard"], highlightID: SettingsTab.battery.highlightID(for: "Full battery style")),
        LegacySettingsSearchEntry(tab: .battery, title: "Full charge threshold", keywords: ["battery", "threshold", "full"], highlightID: SettingsTab.battery.highlightID(for: "Full charge threshold")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show time remaining", keywords: ["battery","time remaining","time to full","eta"], highlightID: SettingsTab.battery.highlightID(for: "Show time remaining")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show charger wattage", keywords: ["battery","charger","watts","adapter"], highlightID: SettingsTab.battery.highlightID(for: "Show charger wattage")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show charging status", keywords: ["battery","fast charging","optimized","held"], highlightID: SettingsTab.battery.highlightID(for: "Show charging status")),
        LegacySettingsSearchEntry(tab: .battery, title: "Show battery health", keywords: ["battery","health","cycle count","capacity"], highlightID: SettingsTab.battery.highlightID(for: "Show battery health")),
        LegacySettingsSearchEntry(tab: .battery, title: "Critical battery HUD", keywords: ["battery","critical","alert"], highlightID: SettingsTab.battery.highlightID(for: "Critical battery HUD")),
        LegacySettingsSearchEntry(tab: .battery, title: "Charge limit reached HUD", keywords: ["battery","charge limit","optimized","held"], highlightID: SettingsTab.battery.highlightID(for: "Charge limit reached HUD")),
        LegacySettingsSearchEntry(tab: .battery, title: "Critical battery threshold", keywords: ["battery","critical","threshold","percent"], highlightID: SettingsTab.battery.highlightID(for: "Critical battery threshold")),
        LegacySettingsSearchEntry(tab: .battery, title: "Bluetooth low battery alert", keywords: ["bluetooth","airpods","mouse","keyboard","low battery"], highlightID: SettingsTab.battery.highlightID(for: "Bluetooth low battery alert")),
        LegacySettingsSearchEntry(tab: .battery, title: "Bluetooth low battery threshold", keywords: ["bluetooth","threshold","low battery","percent"], highlightID: SettingsTab.battery.highlightID(for: "Bluetooth low battery threshold")),
        LegacySettingsSearchEntry(tab: .battery, title: "Test critical battery HUD", keywords: ["battery", "test", "critical", "preview"], highlightID: nil),
        LegacySettingsSearchEntry(tab: .battery, title: "Test charge limit HUD", keywords: ["battery", "test", "charge limit", "preview"], highlightID: nil),

        // HUDs
        LegacySettingsSearchEntry(tab: .devices, title: "Show Bluetooth device connections", keywords: ["bluetooth", "hud"], highlightID: SettingsTab.devices.highlightID(for: "Show Bluetooth device connections")),
        LegacySettingsSearchEntry(tab: .devices, title: "Use circular battery indicator", keywords: ["battery", "circular"], highlightID: SettingsTab.devices.highlightID(for: "Use circular battery indicator")),
        LegacySettingsSearchEntry(tab: .devices, title: "Show battery percentage text in HUD", keywords: ["battery text"], highlightID: SettingsTab.devices.highlightID(for: "Show battery percentage text in HUD")),
        LegacySettingsSearchEntry(tab: .devices, title: "Scroll device name in HUD", keywords: ["marquee", "device name"], highlightID: SettingsTab.devices.highlightID(for: "Scroll device name in HUD")),
        LegacySettingsSearchEntry(tab: .devices, title: "Use 3D Bluetooth HUD icon", keywords: ["bluetooth", "3d", "animation", "mov"], highlightID: SettingsTab.devices.highlightID(for: "Use 3D Bluetooth HUD icon")),
        LegacySettingsSearchEntry(tab: .devices, title: "Color-coded battery display", keywords: ["color", "battery"], highlightID: SettingsTab.devices.highlightID(for: "Color-coded battery display")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Color-coded volume display", keywords: ["volume", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Color-coded volume display")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Smooth color transitions", keywords: ["gradient", "smooth"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Smooth color transitions")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Show percentages beside progress bars", keywords: ["percentages", "progress"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Show percentages beside progress bars")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "HUD style", keywords: ["inline", "compact"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "HUD style")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Progressbar style", keywords: ["progress", "style"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Progressbar style")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Enable glowing effect", keywords: ["glow", "indicator"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable glowing effect")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Use accent color", keywords: ["accent", "color"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Use accent color")),

        // Custom OSD
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Enable Custom OSD", keywords: ["osd", "on-screen display", "custom osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable Custom OSD")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Volume OSD", keywords: ["volume", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume OSD")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Brightness OSD", keywords: ["brightness", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness OSD")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Keyboard Backlight OSD", keywords: ["keyboard", "backlight", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Keyboard Backlight OSD")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Material", keywords: ["material", "frosted", "liquid", "glass", "solid", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Material")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Icon & Progress Color", keywords: ["color", "icon", "white", "black", "gray", "osd"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Icon & Progress Color")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Volume step", keywords: ["volume", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume step")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Volume fine step", keywords: ["volume", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Volume fine step")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Brightness step", keywords: ["brightness", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness step")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Brightness fine step", keywords: ["brightness", "fine", "step", "percent"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Brightness fine step")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC app integration", keywords: ["ddc", "third party", "external", "display", "betterdisplay", "lunar"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC app integration")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Third-party DDC provider", keywords: ["provider", "betterdisplay", "lunar", "integration", "refresh detection"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Third-party DDC provider")),
        LegacySettingsSearchEntry(tab: .hudAndOSD, title: "Enable external volume control listener", keywords: ["external volume", "ddc volume", "betterdisplay volume", "lunar volume", "disable native volume"], highlightID: SettingsTab.hudAndOSD.highlightID(for: "Enable external volume control listener")),

        // Media
        LegacySettingsSearchEntry(tab: .media, title: "Music Source", keywords: ["media source", "controller"], highlightID: SettingsTab.media.highlightID(for: "Music Source")),
        LegacySettingsSearchEntry(tab: .media, title: "Skip buttons", keywords: ["skip", "controls", "±10"], highlightID: SettingsTab.media.highlightID(for: "Skip buttons")),
        LegacySettingsSearchEntry(tab: .media, title: "Sneak Peek Style", keywords: ["sneak peek", "preview"], highlightID: SettingsTab.media.highlightID(for: "Sneak Peek Style")),
        LegacySettingsSearchEntry(tab: .media, title: "Pinned lyric context", keywords: ["pinned lyrics", "lyric context", "lyrics lines", "closed notch", "lyrics height"], highlightID: SettingsTab.media.highlightID(for: "Pinned lyric context")),
        LegacySettingsSearchEntry(tab: .media, title: "Keep lyrics under the closed notch", keywords: ["lyrics", "pin", "pinned", "closed notch", "always show"], highlightID: SettingsTab.media.highlightID(for: "Keep lyrics under the closed notch")),
        LegacySettingsSearchEntry(tab: .media, title: "Show lyrics", keywords: ["lyrics", "song text", "side panel", "hub", "inline"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        // Targets the lyrics toggle rather than the Highlight picker: the picker
        // only exists while lyrics are on, so a search result pointing at it
        // scrolls to nothing for anyone who has not turned them on yet -- which
        // is everyone, by default.
        LegacySettingsSearchEntry(tab: .media, title: "Lyric highlight", keywords: ["lyrics", "highlight", "sweep", "gradient", "solid", "karaoke", "animation"], highlightID: SettingsTab.media.highlightID(for: "Show lyrics")),
        LegacySettingsSearchEntry(tab: .media, title: "Side lyrics width", keywords: ["lyrics", "width", "panel"], highlightID: SettingsTab.media.highlightID(for: "Side lyrics width")),
        LegacySettingsSearchEntry(tab: .media, title: "Side lyrics horizontal offset", keywords: ["lyrics", "offset", "panel"], highlightID: SettingsTab.media.highlightID(for: "Side lyrics horizontal offset")),
        LegacySettingsSearchEntry(tab: .media, title: "Show live canvas in Notchly", keywords: ["canvas", "live canvas", "album art", "dynamic island", "spotify canvas"], highlightID: SettingsTab.media.highlightID(for: "Show live canvas in Notchly")),
        LegacySettingsSearchEntry(tab: .media, title: "Auto-hide inactive notch media player", keywords: ["auto hide", "inactive", "placeholder", "notch media"], highlightID: SettingsTab.media.highlightID(for: "Auto-hide inactive notch media player")),
        LegacySettingsSearchEntry(tab: .media, title: "Show Change Media Output control", keywords: ["airplay", "route picker", "media output"], highlightID: SettingsTab.media.highlightID(for: "Show Change Media Output control")),
        LegacySettingsSearchEntry(tab: .media, title: "Enable album art parallax effect", keywords: ["parallax", "parallax effect", "album art"], highlightID: SettingsTab.media.highlightID(for: "Enable album art parallax effect")),

        // Hub
        LegacySettingsSearchEntry(tab: .hub, title: "Show the Hub", keywords: ["hub", "clock", "centre", "center", "home"], highlightID: SettingsTab.hub.highlightID(for: "Show the Hub")),
        LegacySettingsSearchEntry(tab: .hub, title: "Show seconds", keywords: ["hub", "clock", "seconds"], highlightID: SettingsTab.hub.highlightID(for: "Show seconds")),
        LegacySettingsSearchEntry(tab: .hub, title: "Time format", keywords: ["hub", "clock", "12-hour", "24-hour", "am pm", "military"], highlightID: SettingsTab.hub.highlightID(for: "Time format")),
        LegacySettingsSearchEntry(tab: .hub, title: "Show the date", keywords: ["hub", "clock", "date", "day"], highlightID: SettingsTab.hub.highlightID(for: "Show the date")),
        LegacySettingsSearchEntry(tab: .hub, title: "Hub chips", keywords: ["hub", "chips", "timer", "battery", "stash", "focus", "paused music"], highlightID: SettingsTab.hub.highlightID(for: "Hub chips")),


        // Appearance
        LegacySettingsSearchEntry(tab: .appearance, title: "Main screen style", keywords: ["dynamic island", "pill", "non-notch", "display style", "notch style"], highlightID: SettingsTab.appearance.highlightID(for: "Main screen style")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Settings icon in notch", keywords: ["settings button", "toolbar"], highlightID: SettingsTab.appearance.highlightID(for: "Settings icon in notch")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Enable window shadow", keywords: ["shadow", "appearance"], highlightID: SettingsTab.appearance.highlightID(for: "Enable window shadow")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Corner radius scaling", keywords: ["corner radius", "shape"], highlightID: SettingsTab.appearance.highlightID(for: "Corner radius scaling")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Use simpler close animation", keywords: ["close animation", "notch"], highlightID: SettingsTab.appearance.highlightID(for: "Use simpler close animation")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Notch Width", keywords: ["expanded notch", "width", "resize"], highlightID: SettingsTab.appearance.highlightID(for: "Expanded notch width")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Enable colored spectrograms", keywords: ["spectrogram", "audio"], highlightID: SettingsTab.appearance.highlightID(for: "Enable colored spectrograms")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Enable blur effect behind album art", keywords: ["blur", "album art"], highlightID: SettingsTab.appearance.highlightID(for: "Enable blur effect behind album art")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Slider color", keywords: ["slider", "accent"], highlightID: SettingsTab.appearance.highlightID(for: "Slider color")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Enable Dynamic mirror", keywords: ["mirror", "reflection"], highlightID: SettingsTab.appearance.highlightID(for: "Enable Dynamic mirror")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Mirror shape", keywords: ["mirror shape", "circle", "rectangle"], highlightID: SettingsTab.appearance.highlightID(for: "Mirror shape")),
        LegacySettingsSearchEntry(tab: .appearance, title: "Idle Animation", keywords: ["face animation", "idle", "cool face"], highlightID: SettingsTab.appearance.highlightID(for: "Idle Animation")),
        LegacySettingsSearchEntry(tab: .appearance, title: "App icon", keywords: ["app icon", "custom icon"], highlightID: SettingsTab.appearance.highlightID(for: "App icon")),

        // Lock Screen
        LegacySettingsSearchEntry(tab: .lockScreen, title: "Enable lock screen live activity", keywords: ["lock screen", "live activity"], highlightID: SettingsTab.lockScreen.highlightID(for: "Enable lock screen live activity")),
        LegacySettingsSearchEntry(tab: .lockScreen, title: "Live activity icon", keywords: ["lock", "fingerprint", "touch id", "unlock", "biometric", "icon style"], highlightID: SettingsTab.lockScreen.highlightID(for: "Live activity icon")),
        LegacySettingsSearchEntry(tab: .lockScreen, title: "Play lock/unlock sounds", keywords: ["chime", "sound"], highlightID: SettingsTab.lockScreen.highlightID(for: "Play lock/unlock sounds")),

        // Shortcuts
        LegacySettingsSearchEntry(tab: .shortcuts, title: "Enable global keyboard shortcuts", keywords: ["keyboard", "shortcut"], highlightID: SettingsTab.shortcuts.highlightID(for: "Enable global keyboard shortcuts")),

        // Quick Actions
        // Stash
        LegacySettingsSearchEntry(tab: .stash, title: "Enable Stash", keywords: ["stash", "tray", "shelf", "clipboard", "drop", "files", "temporary"], highlightID: SettingsTab.stash.highlightID(for: "Enable Stash")),
        LegacySettingsSearchEntry(tab: .stash, title: "Keep items", keywords: ["stash", "retention", "expire", "hours", "days", "quit"], highlightID: SettingsTab.stash.highlightID(for: "Keep items")),
        LegacySettingsSearchEntry(tab: .stash, title: "Maximum items", keywords: ["stash", "cap", "limit", "oldest"], highlightID: SettingsTab.stash.highlightID(for: "Maximum items")),
        LegacySettingsSearchEntry(tab: .stash, title: "Link files larger than", keywords: ["stash", "size", "copy", "link", "megabytes", "big files"], highlightID: SettingsTab.stash.highlightID(for: "Link files larger than")),
        LegacySettingsSearchEntry(tab: .stash, title: "Clear when the Mac sleeps or locks", keywords: ["stash", "sleep", "lock", "privacy", "clear"], highlightID: SettingsTab.stash.highlightID(for: "Clear when the Mac sleeps or locks")),
        LegacySettingsSearchEntry(tab: .stash, title: "Hide previews until hover", keywords: ["stash", "privacy", "blur", "text", "preview"], highlightID: SettingsTab.stash.highlightID(for: "Hide previews until hover")),
        LegacySettingsSearchEntry(tab: .stash, title: "Stash clipboard shortcut", keywords: ["stash", "shortcut", "keyboard", "clipboard"], highlightID: SettingsTab.stash.highlightID(for: "Stash clipboard shortcut")),
        LegacySettingsSearchEntry(tab: .quickActions, title: "Show Quick Actions row", keywords: ["quick actions", "buttons", "row", "home"], highlightID: SettingsTab.quickActions.highlightID(for: "Show Quick Actions row")),
        LegacySettingsSearchEntry(tab: .quickActions, title: "Shortcut name", keywords: ["shortcuts", "focus", "do not disturb", "automation"], highlightID: SettingsTab.quickActions.highlightID(for: "Shortcut name")),
        LegacySettingsSearchEntry(tab: .quickActions, title: "Timer & stopwatch live activity", keywords: ["timer", "stopwatch", "live activity", "closed notch"], highlightID: SettingsTab.quickActions.highlightID(for: "Timer & stopwatch live activity")),
        LegacySettingsSearchEntry(tab: .quickActions, title: "Timer sound", keywords: ["timer", "sound", "alarm", "chime"], highlightID: SettingsTab.quickActions.highlightID(for: "Timer sound")),
    ]
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        let tab: SettingsTab
    }

    @Published var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    func focus(highlightID: String, tab: SettingsTab) {
        pendingScrollRequest = ScrollRequest(id: highlightID, tab: tab)
        activateHighlight(id: highlightID)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(
                Color.accentColor.opacity(isActive ? (animatePulse ? 0.95 : 0.4) : 0),
                lineWidth: 2
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.08 : 0))
            )
            .padding(-4)
            .shadow(color: Color.accentColor.opacity(isActive ? 0.25 : 0), radius: animatePulse ? 8 : 2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.tab == tab else { return nil }
                    return request
                }) { request in
                    withAnimation(.easeInOut(duration: 0.45)) {
                        proxy.scrollTo(request.id, anchor: .center)
                    }
                    highlightCoordinator.consumeScrollRequest(request)
                }
        }
    }
}

struct GeneralSettings: View {
    @State private var screens: [String] = NSScreen.screens.compactMap { $0.localizedName }
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.showEmojis) var showEmojis
    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showBatteryIndicator) var showBatteryIndicator
    @Default(.showMinimalisticBatteryIndicator) var showMinimalisticBatteryIndicator
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.musicGestureBehavior) var musicGestureBehavior
    @Default(.reverseSwipeGestures) var reverseSwipeGestures
    @Default(.reverseScrollGestures) var reverseScrollGestures
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover

    private func highlightID(_ title: String) -> String {
        SettingsTab.general.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableMinimalisticUI) {
                    Text("Enable Minimalistic UI")
                }
                .onChange(of: enableMinimalisticUI) { _, newValue in
                    if newValue {
                        // Auto-enable simpler animation mode
                        Defaults[.useModernCloseAnimation] = true
                    }
                }
                .settingsHighlight(id: highlightID("Enable Minimalistic UI"))

                Defaults.Toggle(key: .showMinimalisticBatteryIndicator) {
                    Text("Show battery indicator")
                }
                .disabled(!enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Show battery indicator in Minimalistic UI"))

                Defaults.Toggle(key: .showBatteryPercentInside) {
                    Text("Show battery percentage inside icon")
                }
                // Draws inside whichever battery the notch is showing, so it is
                // gated on there being one -- not on Minimalistic UI, which only
                // decides which of the two gets drawn.
                // Read through the observed properties, not Defaults directly:
                // a plain read is not a dependency, so switching the battery
                // indicator on left this row disabled until something else
                // redrew the view.
                .disabled(!showBatteryIndicator
                    || (enableMinimalisticUI && !showMinimalisticBatteryIndicator))
                .settingsHighlight(id: highlightID("Show battery percentage inside icon"))
            } header: {
                Text("UI Mode")
            } footer: {
                Text("Minimalistic mode focuses on media controls and system HUDs, hiding all extra features for a clean, focused experience. Automatically enables simpler animations.")
            }

            Section {
                Defaults.Toggle(key: .menubarIcon) {
                    Text("Menubar icon")
                }
                .settingsHighlight(id: highlightID("Menubar icon"))
                LaunchAtLogin.Toggle {
                    Text("Launch at login")
                }
                .settingsHighlight(id: highlightID("Launch at login"))
                Defaults.Toggle(key: .showOnAllDisplays) {
                    Text("Show on all displays")
                }
                .onChange(of: showOnAllDisplays) {
                    NotificationCenter.default.post(name: Notification.Name.showOnAllDisplaysChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Show on all displays"))
                Picker("Show on a specific display", selection: $coordinator.preferredScreen) {
                    ForEach(screens, id: \.self) { screen in
                        Text(screen)
                    }
                }
                .onChange(of: NSScreen.screens) {
                    screens =  NSScreen.screens.compactMap({$0.localizedName})
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Show on a specific display"))
                Defaults.Toggle(key: .automaticallySwitchDisplay) {
                    Text("Automatically switch displays")
                }
                .onChange(of: automaticallySwitchDisplay) {
                    NotificationCenter.default.post(name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
                }
                .disabled(showOnAllDisplays)
                .settingsHighlight(id: highlightID("Automatically switch displays"))
                Defaults.Toggle(key: .hideDynamicIslandFromScreenCapture) {
                    Text("Hide Notchly during screenshots & recordings")
                }
                .settingsHighlight(id: highlightID("Hide Notchly during screenshots & recordings"))
            } header: {
                Text("System features")
            }

            Section {
                Picker(selection: $notchHeightMode, label:
                        Text("Notch display height")) {
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                        .onChange(of: notchHeightMode) {
                            switch notchHeightMode {
                            case .matchRealNotchSize:
                                notchHeight = 38
                            case .matchMenuBar:
                                notchHeight = 44
                            case .custom:
                                notchHeight = 38
                            }
                            NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                        }
                        .settingsHighlight(id: highlightID("Notch display height"))
                if notchHeightMode == .custom {
                    Slider(value: $notchHeight, in: 15...45, step: 1) {
                        Text("Custom notch size - \(notchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: notchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
                Picker("Non-notch display height", selection: $nonNotchHeightMode) {
                    Text("Match menubar height")
                        .tag(WindowHeightMode.matchMenuBar)
                    Text("Match real notch size")
                        .tag(WindowHeightMode.matchRealNotchSize)
                    Text("Custom height")
                        .tag(WindowHeightMode.custom)
                }
                .onChange(of: nonNotchHeightMode) {
                    switch nonNotchHeightMode {
                    case .matchMenuBar:
                        nonNotchHeight = 24
                    case .matchRealNotchSize:
                        nonNotchHeight = 32
                    case .custom:
                        nonNotchHeight = 32
                    }
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                if nonNotchHeightMode == .custom {
                    Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                        Text("Custom notch size - \(nonNotchHeight, specifier: "%.0f")")
                    }
                    .onChange(of: nonNotchHeight) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            } header: {
                Text("Notch Height")
            }

            NotchBehaviour()

            gestureControls()
        }
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    @ViewBuilder
    func gestureControls() -> some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            .settingsHighlight(id: highlightID("Enable gestures"))
            if enableGestures {
                Defaults.Toggle(key: .enableHorizontalMusicGestures) {
                    Text("Media change with horizontal gestures")
                }
                .settingsHighlight(id: highlightID("Horizontal media gestures"))

                if enableHorizontalMusicGestures {
                    SettingsSegmentedPicker(
                        "Gesture skip behavior",
                        selection: $musicGestureBehavior,
                        items: Array(MusicSkipBehavior.allCases)
                    ) { $0.displayName }
                    .settingsHighlight(id: highlightID("Gesture skip behavior"))

                    Text(musicGestureBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Defaults.Toggle(key: .reverseSwipeGestures) {
                        Text("Reverse swipe gestures")
                    }
                    .settingsHighlight(id: highlightID("Reverse swipe gestures"))
                }

                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                .settingsHighlight(id: highlightID("Close gesture"))
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(Defaults[.gestureSensitivity] == 100 ? "High" : Defaults[.gestureSensitivity] == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .reverseScrollGestures) {
                    Text("Reverse open/close scroll gestures")
                }
                .settingsHighlight(id: highlightID("Reverse scroll gestures"))
            }
        } header: {
            HStack {
                Text("Gesture control")
                customBadge(text: "Beta")
            }
        } footer: {
            Text("Two-finger swipe up on notch to close, two-finger swipe down on notch to open when **Open notch on hover** option is disabled")
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    @ViewBuilder
    func NotchBehaviour() -> some View {
        Section {
            Defaults.Toggle(key: .extendHoverArea) {
                Text("Extend hover area")
            }
            .settingsHighlight(id: highlightID("Extend hover area"))
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable haptics")
            }
            .settingsHighlight(id: highlightID("Enable haptics"))
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            .settingsHighlight(id: highlightID("Open notch on hover"))
            Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Minimum hover duration")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("External display style", selection: $externalDisplayStyle) {
                ForEach(ExternalDisplayStyle.allCases) { style in
                    Text(style.localizedName)
                        .tag(style)
                }
            }
            .onChange(of: externalDisplayStyle) {
                NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
            }
            .settingsHighlight(id: highlightID("External display style"))
            Text(externalDisplayStyle.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Defaults.Toggle(key: .hideNonNotchUntilHover) {
                Text("Hide until hovered on non-notch displays")
            }
            .settingsHighlight(id: highlightID("Hide until hovered"))
            Text("When enabled, the notch slides up and hides on external (non-notch) displays until you hover over it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Notch behavior")
        }
    }
}

struct Charge: View {
    @ObservedObject private var batteryStatusViewModel = BatteryStatusViewModel.shared
    @Default(.showPowerStatusNotifications) private var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) private var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) private var showLowBatteryHUD
    @Default(.showFullBatteryHUD) private var showFullBatteryHUD
    @Default(.chargingBatteryHUDDuration) private var chargingBatteryHUDDuration
    @Default(.lowBatteryHUDDuration) private var lowBatteryHUDDuration
    @Default(.fullBatteryHUDDuration) private var fullBatteryHUDDuration
    @Default(.lowBatteryHUDThreshold) private var lowBatteryHUDThreshold
    @Default(.fullBatteryHUDThreshold) private var fullBatteryHUDThreshold
    @Default(.lowBatteryHUDStyle) private var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) private var fullBatteryHUDStyle
    @Default(.showCriticalBatteryHUD) private var showCriticalBatteryHUD
    @Default(.criticalBatteryHUDThreshold) private var criticalBatteryHUDThreshold
    @Default(.showChargeHeldHUD) private var showChargeHeldHUD
    @Default(.showBluetoothLowBatteryAlert) private var showBluetoothLowBatteryAlert
    @Default(.bluetoothLowBatteryThreshold) private var bluetoothLowBatteryThreshold

    private var criticalBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(criticalBatteryHUDThreshold) },
            set: { criticalBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var bluetoothLowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(bluetoothLowBatteryThreshold) },
            set: { bluetoothLowBatteryThreshold = Int($0.rounded()) }
        )
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.battery.highlightID(for: title)
    }

    private var chargingDurationBinding: Binding<Double> {
        Binding(
            get: { Double(chargingBatteryHUDDuration) },
            set: { chargingBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDDuration) },
            set: { lowBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var fullBatteryDurationBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDDuration) },
            set: { fullBatteryHUDDuration = Int($0.rounded()) }
        )
    }

    private var lowBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(lowBatteryHUDThreshold) },
            set: { lowBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private var fullBatteryThresholdBinding: Binding<Double> {
        Binding(
            get: { Double(fullBatteryHUDThreshold) },
            set: { fullBatteryHUDThreshold = Int($0.rounded()) }
        )
    }

    private func sectionOpacity(_ isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.5
    }

    var body: some View {
        Form {
            if BatteryActivityManager.shared.hasBattery() {
                Section {
                    Defaults.Toggle(key: .showBatteryIndicator) {
                        Text("Show battery indicator")
                    }
                    .settingsHighlight(id: highlightID("Show battery indicator"))
                    Defaults.Toggle(key: .showPowerStatusNotifications) {
                        Text("Show power status notifications")
                    }
                    .settingsHighlight(id: highlightID("Show power status notifications"))
                    Defaults.Toggle(key: .playLowBatteryAlertSound) {
                        Text("Play low battery alert sound")
                    }
                    .settingsHighlight(id: highlightID("Play low battery alert sound"))
                } header: {
                    Text("General")
                }
                Section {
                    Defaults.Toggle(key: .showBatteryPercentage) {
                        Text("Show battery percentage")
                    }
                    .settingsHighlight(id: highlightID("Show battery percentage"))
                    Defaults.Toggle(key: .showPowerStatusIcons) {
                        Text("Show power status icons")
                    }
                    .settingsHighlight(id: highlightID("Show power status icons"))
                } header: {
                    Text("Battery Information")
                }
                Section {
                    Defaults.Toggle(key: .showBatteryTimeRemaining) {
                        Text("Show time remaining / time to full")
                    }
                    .settingsHighlight(id: highlightID("Show time remaining"))
                    Defaults.Toggle(key: .showChargerWattage) {
                        Text("Show charger wattage")
                    }
                    .settingsHighlight(id: highlightID("Show charger wattage"))
                    Defaults.Toggle(key: .showChargingStatusText) {
                        Text("Show fast / held charging status")
                    }
                    .settingsHighlight(id: highlightID("Show charging status"))
                    Defaults.Toggle(key: .showBatteryHealthDetail) {
                        Text("Show battery health and cycle count")
                    }
                    .settingsHighlight(id: highlightID("Show battery health"))
                } header: {
                    Text("Charging Details")
                } footer: {
                    Text("Each line appears only when macOS reports the data. Click the battery in the open notch for health and cycle count.")
                }
                Section {
                    Defaults.Toggle(key: .showChargingBatteryHUD) {
                        Text("Charging HUD")
                    }
                    .settingsHighlight(id: highlightID("Charging HUD"))

                    Defaults.Toggle(key: .showLowBatteryHUD) {
                        Text("Low battery HUD")
                    }
                    .settingsHighlight(id: highlightID("Low battery HUD"))

                    Defaults.Toggle(key: .showFullBatteryHUD) {
                        Text("Fully charged HUD")
                    }
                    .settingsHighlight(id: highlightID("Fully charged HUD"))

                    Defaults.Toggle(key: .showCriticalBatteryHUD) {
                        Text("Critical battery HUD")
                    }
                    .settingsHighlight(id: highlightID("Critical battery HUD"))

                    Defaults.Toggle(key: .showChargeHeldHUD) {
                        Text("Charge limit reached HUD")
                    }
                    .settingsHighlight(id: highlightID("Charge limit reached HUD"))
                } header: {
                    Text("Battery HUDs")
                } footer: {
                    Text("These temporary HUDs recreate the charging, low-battery, and full-battery notch alerts.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Charging duration")
                            Spacer()
                            Text("\(chargingBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: chargingDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Charging duration"))
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showChargingBatteryHUD))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Low battery duration")
                            Spacer()
                            Text("\(lowBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: lowBatteryDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Low battery duration"))
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Full battery duration")
                            Spacer()
                            Text("\(fullBatteryHUDDuration)s")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: fullBatteryDurationBinding, in: 1...10, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Full battery duration"))
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                    .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
                } header: {
                    Text("HUD Duration")
                }
                Section {
                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .charging)
                    } label: {
                        Label("Test charging HUD", systemImage: "bolt.fill")
                    }
                    .disabled(!showPowerStatusNotifications || !showChargingBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .lowBattery)
                    } label: {
                        Label("Test low battery HUD", systemImage: "battery.25")
                    }
                    .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .lowBattery, flavor: .critical)
                    } label: {
                        Label("Test critical battery HUD", systemImage: "exclamationmark.triangle.fill")
                    }
                    .disabled(!showPowerStatusNotifications || !showCriticalBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .fullBattery)
                    } label: {
                        Label("Test full battery HUD", systemImage: "battery.100")
                    }
                    .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)

                    Button {
                        batteryStatusViewModel.triggerTestHUD(kind: .fullBattery, flavor: .chargeHeld)
                    } label: {
                        Label("Test charge limit HUD", systemImage: "pause.circle")
                    }
                    .disabled(!showPowerStatusNotifications || !showChargeHeldHUD)
                } header: {
                    Text("HUD Tests")
                } footer: {
                    Text("Runs the real notch animation on the current target display. If an external screen is using Dynamic Island mode, the battery HUD is sent there first.")
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSegmentedPicker(
                            "Low battery style",
                            selection: $lowBatteryHUDStyle,
                            items: Array(BatteryNotificationStyle.allCases)
                        ) { $0.title }
                        Text("Compact matches the charging HUD. Standard uses the expanded DynamicNotch-style card.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Low battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Low battery threshold")
                            Spacer()
                            Text("\(lowBatteryHUDThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: lowBatteryThresholdBinding, in: 5...30, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Low battery threshold"))
                } header: {
                    Text("Low Battery")
                }
                .disabled(!showPowerStatusNotifications || !showLowBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showLowBatteryHUD))

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Critical battery threshold")
                            Spacer()
                            Text("\(criticalBatteryHUDThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: criticalBatteryThresholdBinding, in: 3...15, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Critical battery threshold"))
                } header: {
                    Text("Critical Battery")
                } footer: {
                    Text("A second, stronger alert below the low-battery level. It is always kept below the low-battery threshold.")
                }
                .disabled(!showPowerStatusNotifications || !showCriticalBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showCriticalBatteryHUD))

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingsSegmentedPicker(
                            "Full battery style",
                            selection: $fullBatteryHUDStyle,
                            items: Array(BatteryNotificationStyle.allCases)
                        ) { $0.title }
                        Text("Compact keeps the alert inline. Standard uses the taller full-charge HUD with the charging animation.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .settingsHighlight(id: highlightID("Full battery style"))


                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Full charge threshold")
                            Spacer()
                            Text("\(fullBatteryHUDThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: fullBatteryThresholdBinding, in: 80...100, step: 1)
                    }
                    .settingsHighlight(id: highlightID("Full charge threshold"))
                } header: {
                    Text("Full Battery")
                } footer: {
                    Text("Set this to your charge limit. If macOS holds charging below 100% (Optimized Battery Charging or a charge limit), the charge limit HUD tells you once per plug-in.")
                }
                .disabled(!showPowerStatusNotifications || !showFullBatteryHUD)
                .opacity(sectionOpacity(showPowerStatusNotifications && showFullBatteryHUD))
                Section {
                    Defaults.Toggle(key: .showBluetoothLowBatteryAlert) {
                        Text("Low battery alert")
                    }
                    .settingsHighlight(id: highlightID("Bluetooth low battery alert"))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Alert at or below")
                            Spacer()
                            Text("\(bluetoothLowBatteryThreshold)%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: bluetoothLowBatteryThresholdBinding, in: 5...40, step: 5)
                    }
                    .settingsHighlight(id: highlightID("Bluetooth low battery threshold"))
                    .disabled(!showBluetoothLowBatteryAlert)
                    .opacity(sectionOpacity(showBluetoothLowBatteryAlert))
                } header: {
                    Text("Bluetooth Devices")
                } footer: {
                    Text("AirPods, headphones, mice, keyboards and trackpads that report a battery level. Each device alerts once per connection.")
                }
            } else {
                ContentUnavailableView {
                    VStack(spacing: 16) {
                        Image(systemName: "battery.100percent.slash")
                            .font(.title)
                        Text("Battery settings and informations are only available on MacBooks")
                            .font(.title3)
                    }
                }
            }
        }
        .animation(NotchlyTheme.Motion.snappy, value: showPowerStatusNotifications)
        .animation(NotchlyTheme.Motion.snappy, value: showChargingBatteryHUD)
        .animation(NotchlyTheme.Motion.snappy, value: showLowBatteryHUD)
        .animation(NotchlyTheme.Motion.snappy, value: showFullBatteryHUD)
        .animation(NotchlyTheme.Motion.snappy, value: showCriticalBatteryHUD)
    }
}

struct Downloads: View {
    @Default(.selectedDownloadIndicatorStyle) var selectedDownloadIndicatorStyle
    @Default(.selectedDownloadIconStyle) var selectedDownloadIconStyle
    @Default(.enableDownloadListener) var enableDownloadListener

    private func highlightID(_ title: String) -> String {
        SettingsTab.downloads.highlightID(for: title)
    }

    var body: some View {
        SwiftUI.Form {
            Section {
                Defaults.Toggle(key: .enableDownloadListener) {
                    Text("Enable download detection")
                }
                .settingsHighlight(id: highlightID("Enable download detection"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("Download indicator style")
                        .font(.system(size: 13, weight: .semibold))
                        // .white is invisible against a light Settings window;
                        // the label follows the appearance like every other one.
                        .foregroundStyle(enableDownloadListener ? Color.primary : Color.secondary)

                    HStack(spacing: 16) {
                        DownloadStyleButton(
                            style: .progress,
                            isSelected: selectedDownloadIndicatorStyle == .progress,
                            disabled: !enableDownloadListener
                        ) {
                            selectedDownloadIndicatorStyle = .progress
                        }

                        DownloadStyleButton(
                            style: .circle,
                            isSelected: selectedDownloadIndicatorStyle == .circle,
                            disabled: !enableDownloadListener
                        ) {
                            selectedDownloadIndicatorStyle = .circle
                        }
                    }

                    Text("A bar that fills as the download runs, or a ring around the notch's corner.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .settingsHighlight(id: highlightID("Download indicator style"))

                VStack(alignment: .leading, spacing: 6) {
                    Defaults.Toggle(key: .showDownloadSpeed) {
                        Text("Show download speed")
                    }
                    .disabled(!enableDownloadListener)

                    Text("Adds the current rate beside the indicator, measured from how fast the files in your Downloads folder are growing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .settingsHighlight(id: highlightID("Show download speed"))
            } header: {
                Text("Download Detection")
            } footer: {
                Text("Shows a live activity in the notch while a file is downloading. Works with Safari, Firefox, and Chrome and the browsers built on it — Edge, Brave, Arc, Vivaldi and Opera. Only your Downloads folder is watched, so a file saved anywhere else will not appear.")
            }
        }
    }

    struct DownloadStyleButton: View {
        let style: DownloadIndicatorStyle
        let isSelected: Bool
        let disabled: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    if style == .progress {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 40)
                    } else {
                        SpinningCircleDownloadView()
                    }
                }
                .frame(width: 80, height: 60)
                .onHover { hovering in
                    if !disabled {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isHovering = hovering
                        }
                    }
                }

                Text(style.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 100)
                    .foregroundStyle(disabled ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if !disabled {
                    action()
                }
            }
            .opacity(disabled ? 0.5 : 1.0)
        }

        private var backgroundColor: Color {
            if disabled { return Color(nsColor: .controlBackgroundColor) }
            if isSelected { return Color.accentColor.opacity(0.1) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

final class HUDPreviewViewModel: ObservableObject {
    @Published var level: Float = 0
    @Published var iconName: String = "speaker.wave.3.fill"

    private var cancellables = Set<AnyCancellable>()

    init() {
        setup()
    }

    private func setup() {
        // Ensure controllers are active
        SystemVolumeController.shared.start()
        SystemBrightnessController.shared.start()
        SystemKeyboardBacklightController.shared.start()

        // Initial state from volume
        let vol = SystemVolumeController.shared.currentVolume
        self.level = vol
        if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
        else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
        else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
        else { self.iconName = "speaker.wave.3.fill" }

        // Listeners
        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let vol = info["value"] as? Float {
                    self.level = vol
                    if vol <= 0.01 { self.iconName = "speaker.slash.fill" }
                    else if vol < 0.33 { self.iconName = "speaker.wave.1.fill" }
                    else if vol < 0.66 { self.iconName = "speaker.wave.2.fill" }
                    else { self.iconName = "speaker.wave.3.fill" }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemBrightnessDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = "sun.max.fill"
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .keyboardBacklightDidChange)
            .compactMap { $0.userInfo }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                guard let self else { return }
                if let val = info["value"] as? Float {
                    self.level = val
                    self.iconName = val > 0.5 ? "light.max" : "light.min"
                }
            }
            .store(in: &cancellables)
    }
}

/// Disables a control while the selected external display app is the one actually
/// handling those keys.
///
/// Ownership is not the integration toggle on its own. `resolvedControlFlags()`
/// hands the keys over only while integration is enabled *and* the provider is
/// running, so quitting the provider gives them back to Atoll -- and a control
/// gated on the toggle alone stays greyed out over a setting that has started
/// working again.
///
/// A modifier rather than a computed property per view: it carries the
/// observation of both providers with it, so a control re-enables the moment the
/// provider quits without every settings view having to observe them itself.
private struct ExternalKeyOwnershipModifier: ViewModifier {
    @Default(.enableThirdPartyDDCIntegration) private var integrationEnabled
    @Default(.thirdPartyDDCProvider) private var provider
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    let message: String

    private var providerRunning: Bool {
        switch provider {
        case .betterDisplay: return betterDisplayManager.isRunning
        case .lunar: return lunarManager.isRunning
        }
    }

    private var externalOwnsKeys: Bool {
        integrationEnabled && providerRunning
    }

    func body(content: Content) -> some View {
        content
            .disabled(externalOwnsKeys)
            .help(externalOwnsKeys ? message : "")
    }
}

extension View {
    /// Greys this control out while the running external display app owns the
    /// keys it configures.
    func disabledWhileExternalAppOwnsKeys(_ message: String) -> some View {
        modifier(ExternalKeyOwnershipModifier(message: message))
    }
}

struct HUDAndOSDSettingsView: View {
    @State private var selectedTab: Tab = {
        if Defaults[.enableSystemHUD] { return .hud }
        if Defaults[.enableCustomOSD] { return .osd }
        if Defaults[.enableVerticalHUD] { return .vertical }
        if Defaults[.enableCircularHUD] { return .circular }
        return .hud
    }()
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.enableVerticalHUD) var enableVerticalHUD
    @Default(.enableCircularHUD) var enableCircularHUD
    @Default(.verticalHUDPosition) var verticalHUDPosition
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.verticalHUDShowValue) var verticalHUDShowValue
    @Default(.verticalHUDInteractive) var verticalHUDInteractive
    @Default(.verticalHUDHeight) var verticalHUDHeight
    @Default(.verticalHUDWidth) var verticalHUDWidth
    @Default(.verticalHUDPadding) var verticalHUDPadding
    @Default(.verticalHUDUseAccentColor) var verticalHUDUseAccentColor
    @Default(.verticalHUDMaterial) var verticalHUDMaterial
    @Default(.verticalHUDLiquidGlassCustomizationMode) var verticalHUDLiquidGlassCustomizationMode
    @Default(.verticalHUDLiquidGlassVariant) var verticalHUDLiquidGlassVariant

    // Circular HUD Props
    @Default(.circularHUDShowValue) var circularHUDShowValue
    @Default(.circularHUDSize) var circularHUDSize
    @Default(.circularHUDStrokeWidth) var circularHUDStrokeWidth
    @Default(.circularHUDUseAccentColor) var circularHUDUseAccentColor
    @StateObject private var previewModel = HUDPreviewViewModel()
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private enum Tab: String, CaseIterable, Identifiable {
        case hud = "Dynamic Island HUD"
        case osd = "Custom OSD"
        case vertical = "Vertical Bar"
        case circular = "Circular"

        var id: String { rawValue }
    }

    private var paneBackgroundColor: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var availableVerticalMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var verticalLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(verticalHUDLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                verticalHUDLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    private var hudVariantCards: some View {
            HStack(spacing: 16) {
                HUDSelectionCard(
                    title: String(localized: "Dynamic Island"),
                    isSelected: selectedTab == .hud,
                    action: {
                        selectedTab = .hud
                        enableSystemHUD = true
                        enableCustomOSD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    VStack {
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
                    }
                }

                HUDSelectionCard(
                    title: String(localized: "Custom OSD"),
                    isSelected: selectedTab == .osd,
                    action: {
                        selectedTab = .osd
                        enableCustomOSD = true
                        enableSystemHUD = false
                        enableVerticalHUD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack(spacing: 6) {
                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))

                                GeometryReader { geo in
                                    Capsule()
                                        .fill(Color.secondary.opacity(0.2))
                                        .overlay(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary)
                                                .frame(width: geo.size.width * CGFloat(previewModel.level))
                                                .animation(.spring(response: 0.3), value: previewModel.level)
                                        }
                                }
                                .frame(width: 36, height: 4)
                            }
                        }
                        .frame(width: 44, height: 44)
                }

                HUDSelectionCard(
                    title: String(localized: "Vertical Bar"),
                    isSelected: selectedTab == .vertical,
                    action: {
                        selectedTab = .vertical
                        enableVerticalHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableCircularHUD = false
                    }
                ) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                        .overlay {
                            VStack {
                                GeometryReader { geo in
                                    VStack {
                                        Spacer()
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(Color.white)
                                            .frame(height: max(0, geo.size.height * CGFloat(previewModel.level)))
                                            .animation(.spring(response: 0.3), value: previewModel.level)
                                    }
                                }
                                .mask(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(.bottom, 2)

                                Image(systemName: previewModel.iconName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(previewModel.level > 0.15 ? .black : .secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(4)
                        }
                        .frame(width: 22, height: 54)
                }

                HUDSelectionCard(
                    title: String(localized: "Circular"),
                    isSelected: selectedTab == .circular,
                    action: {
                        selectedTab = .circular
                        enableCircularHUD = true
                        enableSystemHUD = false
                        enableCustomOSD = false
                        enableVerticalHUD = false
                    }
                ) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: CGFloat(previewModel.level))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.spring(response: 0.3), value: previewModel.level)
                        Image(systemName: previewModel.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: 44, height: 44)
                }
            }
    }

    var body: some View {
        Form {
            Section {
                // Four fixed-width cards ask for about 490pt. In a grouped
                // Form that is a hard minimum, so on a narrower window the
                // whole settings pane was pushed wider to satisfy it and the
                // content overflowed sideways. It scrolls instead when it
                // does not fit, and lays out as a row whenever it does.
                ViewThatFits(in: .horizontal) {
                    hudVariantCards
                    ScrollView(.horizontal, showsIndicators: false) {
                        hudVariantCards
                    }
                }
                .padding(.top, 8)
            }

            switch selectedTab {
            case .hud:
                HUD()
            case .osd:
                if #available(macOS 15.0, *) {
                    CustomOSDSettings()
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)

                        Text("macOS 15 or later required")
                            .font(.headline)

                        Text("Custom OSD feature requires macOS 15 or later.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            case .vertical:
                Group {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Vertical HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $verticalHUDShowValue)
                        Toggle("Use Accent Color", isOn: $verticalHUDUseAccentColor)
                        Toggle("Interactive (Drag to Change)", isOn: $verticalHUDInteractive)
                        Picker("Material", selection: $verticalHUDMaterial) {
                            ForEach(availableVerticalMaterials, id: \.self) { material in
                                Text(material.rawValue).tag(material)
                            }
                        }

                        if verticalHUDMaterial == .liquid {
                            if #available(macOS 26.0, *) {
                                SettingsSegmentedPicker(
                                    "Glass mode",
                                    selection: $verticalHUDLiquidGlassCustomizationMode,
                                    items: Array(LockScreenGlassCustomizationMode.allCases)
                                ) { $0.rawValue }

                                if verticalHUDLiquidGlassCustomizationMode == .customLiquid {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Custom liquid variant")
                                            Spacer()
                                            Text("v\(verticalHUDLiquidGlassVariant.rawValue)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: verticalLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                    }
                                }
                            } else {
                                Text("Custom Liquid is available on macOS 26 or later.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Behavior & Style")
                    }

                    Section {
                        Picker("HUD Position", selection: $verticalHUDPosition) {
                            Text("Left").tag("left")
                            Text("Right").tag("right")
                        }
                        .pickerStyle(.menu)

                        VStack(alignment: .leading) {
                            Text("Screen Padding: \(Int(verticalHUDPadding))px")
                            Slider(value: $verticalHUDPadding, in: 0...100, step: 4)
                        }
                    } header: {
                        Text("Position")
                    } footer: {
                        Text("Choose directly on which side of the screen the vertical bar appears.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Width: \(Int(verticalHUDWidth))px")
                            Slider(value: $verticalHUDWidth, in: 24...80, step: 2)
                        }
                        VStack(alignment: .leading) {
                            Text("Height: \(Int(verticalHUDHeight))px")
                            Slider(value: $verticalHUDHeight, in: 100...500, step: 10)
                        }
                        Button("Reset to Default") {
                            verticalHUDWidth = 36
                            verticalHUDHeight = 160
                            verticalHUDPadding = 24
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }

            case .circular:
                Group {
                    if !accessibilityPermission.isAuthorized && !enableThirdPartyDDCIntegration {
                        Section {
                            SettingsPermissionCallout(
                                message: "Accessibility permission is needed to intercept system controls for the Circular HUD.",
                                requestAction: {
                                    accessibilityPermission.requestAuthorizationPrompt()
                                },
                                openSettingsAction: {
                                    accessibilityPermission.openSystemSettings()
                                }
                            )
                        } header: {
                            Text("Accessibility")
                        }
                    }

                    if accessibilityPermission.isAuthorized || enableThirdPartyDDCIntegration {
                        Section {
                            Toggle("Volume HUD", isOn: $enableVolumeHUD)
                            Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                            Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                                .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                        } header: {
                            Text("Controls")
                        } footer: {
                            Text("Choose which system controls should display HUD notifications.")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Section {
                        Toggle("Show Percentage", isOn: $circularHUDShowValue)
                        Toggle("Use Accent Color", isOn: $circularHUDUseAccentColor)
                        Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                            Text("Color-coded Volume")
                        }
                        if Defaults[.useColorCodedVolumeDisplay] {
                            Defaults.Toggle(key: .useSmoothColorGradient) {
                                Text("Smooth color transitions")
                            }
                        }
                    } header: {
                        Text("Style")
                    }

                    Section {
                        VStack(alignment: .leading) {
                            Text("Size: \(Int(circularHUDSize))px")
                            Slider(value: $circularHUDSize, in: 40...200, step: 5)
                        }
                        VStack(alignment: .leading) {
                            Text("Line Width: \(Int(circularHUDStrokeWidth))px")
                            Slider(value: $circularHUDStrokeWidth, in: 2...16, step: 1)
                        }
                        Button("Reset to Default") {
                            circularHUDSize = 65
                            circularHUDStrokeWidth = 4
                        }
                    } header: {
                        Text("Dimensions")
                    }
                }
            }

            // Third-party display integrations (shared across all HUD variants)
            ExternalDisplayIntegrationsSection()
        }
        .onAppear {
            if #unavailable(macOS 26.0), verticalHUDMaterial == .liquid {
                verticalHUDMaterial = .frosted
                verticalHUDLiquidGlassCustomizationMode = .standard
            }
        }
    }
}

// MARK: - External Display Integrations Settings Section

private struct ExternalDisplayIntegrationsSection: View {
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.thirdPartyDDCProvider) var thirdPartyDDCProvider
    @Default(.enableExternalVolumeControlListener) var enableExternalVolumeControlListener
    @Default(.volumeStepPercent) var volumeStepPercent
    @Default(.volumeFineStepPercent) var volumeFineStepPercent
    @Default(.brightnessStepPercent) var brightnessStepPercent
    @Default(.brightnessFineStepPercent) var brightnessFineStepPercent
    @ObservedObject private var betterDisplayManager = BetterDisplayManager.shared
    @ObservedObject private var lunarManager = LunarManager.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    /// Whether the selected DDC provider is actually running.
    ///
    /// The one place that answers this. Ownership of the keys and everything the
    /// section says about the provider's state are read from here, so the
    /// controls and the status beside them cannot disagree about whether the
    /// provider is up.
    private var ddcProviderRunning: Bool {
        switch thirdPartyDDCProvider {
        case .betterDisplay: return betterDisplayManager.isRunning
        case .lunar: return lunarManager.isRunning
        }
    }

    /// Mirrors `SystemHUDManager.resolvedControlFlags()`: ownership only transfers
    /// while integration is enabled *and* the provider is running. When the
    /// provider is quit, Atoll handles the keys again and the saved step sizes
    /// apply, so the controls have to come back with it.
    private var externalOwnsBrightness: Bool {
        enableThirdPartyDDCIntegration && ddcProviderRunning
    }

    private var externalOwnsVolume: Bool {
        externalOwnsBrightness && enableExternalVolumeControlListener
    }

    private var providerStatusText: String {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            if ddcProviderRunning { return "Running" }
            if betterDisplayManager.isDetected { return "Not running" }
            return "Not detected"
        case .lunar:
            if lunarManager.isConnected { return "Connected" }
            if ddcProviderRunning { return "Running" }
            if lunarManager.isDetected { return "Not running" }
            return "Not detected"
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
            if ddcProviderRunning { return .orange }
            if lunarManager.isDetected { return .orange }
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
            return "BetterDisplay OSD events will be routed through Notchly's active HUD style. Brightness is always routed; volume is routed when external volume control listener is enabled below. Make sure BetterDisplay's OSD integration is enabled in Settings › Application › Integration."
        case .lunar:
            if !lunarManager.isDetected {
                return "Install [Lunar](https://lunar.fyi) to control external display brightness, contrast, and optional volume through Notchly's HUD via DDC."
            }
            if !ddcProviderRunning {
                return "Lunar is installed but not currently running. Launch Lunar to enable integration."
            }
            if lunarManager.isConnected {
                return "Connected to Lunar's DDC socket. Brightness and contrast adjustments are shown through Notchly's HUD; volume follows when external volume control listener is enabled below."
            }
            return "Lunar is running but the socket connection is not yet established. It will connect automatically."
        }
    }

    private func refreshDetectionStatus() {
        switch thirdPartyDDCProvider {
        case .betterDisplay:
            betterDisplayManager.refreshDetectionStatus()
        case .lunar:
            lunarManager.refreshDetectionStatus()
        }
    }

    var body: some View {
        Group {
            Section {
                Stepper(value: $volumeStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume step")
                        Spacer()
                        Text("\(volumeStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume step"))
                .disabled(externalOwnsVolume)
                .help(externalOwnsVolume ? "Disabled while \"Enable external volume control listener\" is on in External Display Integrations \u{2014} that app owns the volume keys." : "")

                Stepper(value: $volumeFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Volume fine step")
                        Spacer()
                        Text("\(volumeFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Volume fine step"))
                .disabled(externalOwnsVolume)
                .help(externalOwnsVolume ? "Disabled while \"Enable external volume control listener\" is on in External Display Integrations \u{2014} that app owns the volume keys." : "")

                if externalOwnsVolume {
                    Text("Disabled while external display volume integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Stepper(value: $brightnessStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness step")
                        Spacer()
                        Text("\(brightnessStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness step"))
                .disabled(externalOwnsBrightness)
                .help(externalOwnsBrightness ? "Disabled while external display integration is on \u{2014} that app owns the brightness keys." : "")

                Stepper(value: $brightnessFineStepPercent, in: 1...25) {
                    HStack {
                        Text("Brightness fine step")
                        Spacer()
                        Text("\(brightnessFineStepPercent)%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .settingsHighlight(id: highlightID("Brightness fine step"))
                .disabled(externalOwnsBrightness)
                .help(externalOwnsBrightness ? "Disabled while external display integration is on \u{2014} that app owns the brightness keys." : "")

                if externalOwnsBrightness {
                    Text("Disabled while external display brightness integration is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Step size")
            } footer: {
                Text("Percent change per key press. Fine step applies when holding Shift+Option.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Toggle("Enable third-party DDC app integration", isOn: $enableThirdPartyDDCIntegration)
                    .settingsHighlight(id: highlightID("Third-party DDC app integration"))

                if enableThirdPartyDDCIntegration {
                    Picker("Provider", selection: $thirdPartyDDCProvider) {
                        ForEach(ThirdPartyDDCProvider.allCases) { provider in
                            HStack {
                                AppIconImage(
                                    bundleIdentifiers: provider.bundleIdentifiers,
                                    symbolFallback: "display",
                                    symbolColor: .secondary
                                )
                                Text(provider.displayName)
                            }
                            .tag(provider)
                        }
                    }
                    .settingsHighlight(id: highlightID("Third-party DDC provider"))

                    Toggle("Enable external volume control listener", isOn: $enableExternalVolumeControlListener)
                        .settingsHighlight(id: highlightID("Enable external volume control listener"))

                    Text(
                        enableExternalVolumeControlListener
                        ? "Notchly's built-in volume key interception is disabled while external volume listening is on. Volume HUD/OSD will follow \(thirdPartyDDCProvider.displayName) payloads."
                        : "Notchly keeps native volume key interception. External provider volume payloads are ignored while this is off."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(providerStatusText)
                            .font(.caption)
                            .foregroundStyle(providerStatusColor)
                    }

                    Text(providerStatusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        refreshDetectionStatus()
                    } label: {
                        Label("Refresh detection", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                } else {
                    Text("Enable to route BetterDisplay or Lunar display adjustments through Notchly's active HUD style.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if enableThirdPartyDDCIntegration {
                    Text("Notchly always listens to selected-provider brightness events, and listens to provider volume events only when external volume listener is enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

private struct HUDSelectionCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    isSelected ? Color.accentColor : Color.clear,
                                    lineWidth: 2.5
                                )
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)

                    preview
                }
                .frame(width: 110, height: 80)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)

                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 4, height: 4)
                    } else {
                        Color.clear
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct DevicesSettingsView: View {
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.useBluetoothHUD3DIcon) private var useBluetoothHUD3DIcon

    private func highlightID(_ title: String) -> String {
        SettingsTab.devices.highlightID(for: title)
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showBluetoothDeviceConnections) {
                    Text("Show Bluetooth device connections")
                }
                .settingsHighlight(id: highlightID("Show Bluetooth device connections"))
                Defaults.Toggle(key: .useCircularBluetoothBatteryIndicator) {
                    Text("Use circular battery indicator")
                }
                .settingsHighlight(id: highlightID("Use circular battery indicator"))
                Defaults.Toggle(key: .showBluetoothBatteryPercentageText) {
                    Text("Show battery percentage text in HUD")
                }
                .settingsHighlight(id: highlightID("Show battery percentage text in HUD"))
                Defaults.Toggle(key: .showBluetoothDeviceNameMarquee) {
                    Text("Scroll device name in HUD")
                }
                .settingsHighlight(id: highlightID("Scroll device name in HUD"))
                Defaults.Toggle(key: .showAirPodsListeningModeChanges) {
                    Text("Show AirPods listening mode changes")
                }
                .settingsHighlight(id: highlightID("Show AirPods listening mode changes"))
                VStack(alignment: .leading, spacing: 12) {
                    Text("HUD icon style")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        BluetoothHUDIconStyleCard(
                            style: .symbol,
                            isSelected: !useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = false
                        }
                        BluetoothHUDIconStyleCard(
                            style: .threeD,
                            isSelected: useBluetoothHUD3DIcon
                        ) {
                            useBluetoothHUD3DIcon = true
                        }
                        Spacer(minLength: 0)
                    }
                }
                .settingsHighlight(id: highlightID("Use 3D Bluetooth HUD icon"))
            } header: {
                Text("Bluetooth Audio Devices")
            } footer: {
                Text("Displays a HUD notification when Bluetooth audio devices (headphones, AirPods, speakers) connect, showing device name and battery level.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedBatteryDisplay) {
                    Text("Color-coded battery display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded battery display"))
            } header: {
                Text("Battery Indicator Styling")
            } footer: {
                if progressBarStyle == .segmented {
                    Text("Color-coded fills are unavailable in Segmented mode. Switch to Hierarchical or Gradient inside Controls › Dynamic Island to adjust advanced options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill. Adjust gradient behavior from Controls › Dynamic Island.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
}

struct HUD: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Default(.inlineHUD) var inlineHUD
    @Default(.progressBarStyle) var progressBarStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @Default(.enableVolumeHUD) var enableVolumeHUD
    @Default(.enableBrightnessHUD) var enableBrightnessHUD
    @Default(.enableKeyboardBacklightHUD) var enableKeyboardBacklightHUD
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.systemHUDSensitivity) var systemHUDSensitivity
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var colorCodingDisabled: Bool {
        progressBarStyle == .segmented
    }

    var body: some View {
        Group {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission lets Notchly replace the native volume, brightness, and keyboard HUDs.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }



            if enableSystemHUD && !Defaults[.enableCustomOSD] && (hasAccessibilityPermission || enableThirdPartyDDCIntegration) {
                Section {
                    Toggle("Volume HUD", isOn: $enableVolumeHUD)
                    Toggle("Brightness HUD", isOn: $enableBrightnessHUD)
                    Toggle("Keyboard Backlight HUD", isOn: $enableKeyboardBacklightHUD)
                        .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display HUD notifications.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Defaults.Toggle(key: .playVolumeChangeFeedback) {
                    Text("Play feedback when volume is changed")
                }
                .settingsHighlight(id: highlightID("Play feedback when volume is changed"))
                .help("Plays the supplied feedback clip whenever you press the hardware volume keys.")
            } header: {
                Text("Audio feedback")
            } footer: {
                Text("Requires Accessibility permission so Notchly can intercept the hardware volume keys.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Defaults.Toggle(key: .useColorCodedVolumeDisplay) {
                    Text("Color-coded volume display")
                }
                .disabled(colorCodingDisabled)
                .settingsHighlight(id: highlightID("Color-coded volume display"))

                if !colorCodingDisabled && (Defaults[.useColorCodedBatteryDisplay] || Defaults[.useColorCodedVolumeDisplay]) {
                    Defaults.Toggle(key: .useSmoothColorGradient) {
                        Text("Smooth color transitions")
                    }
                    .settingsHighlight(id: highlightID("Smooth color transitions"))
                }

                Defaults.Toggle(key: .showProgressPercentages) {
                    Text("Show percentages beside progress bars")
                }
                .settingsHighlight(id: highlightID("Show percentages beside progress bars"))
            } header: {
                Text("Notchly Progress Bars")
            } footer: {
                if colorCodingDisabled {
                    Text("Color-coded fills and smooth gradients are unavailable in Segmented mode. Switch to Hierarchical or Gradient to adjust these options.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if Defaults[.useSmoothColorGradient] {
                    Text("Smooth transitions blend Green (0–60%), Yellow (60–85%), and Red (85–100%) through the entire fill.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("Discrete transitions snap between Green (0–60%), Yellow (60–85%), and Red (85–100%).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Picker("HUD style", selection: $inlineHUD) {
                    Text("Default")
                        .tag(false)
                    Text("Inline")
                        .tag(true)
                }
                .settingsHighlight(id: highlightID("HUD style"))
                .onChange(of: Defaults[.inlineHUD]) {
                    if Defaults[.inlineHUD] {
                        withAnimation {
                            Defaults[.systemEventIndicatorShadow] = false
                            Defaults[.progressBarStyle] = .hierarchical
                        }
                    }
                }
                Picker("Progressbar style", selection: $progressBarStyle) {
                    Text("Hierarchical")
                        .tag(ProgressBarStyle.hierarchical)
                    Text("Gradient")
                        .tag(ProgressBarStyle.gradient)
                    Text("Segmented")
                        .tag(ProgressBarStyle.segmented)
                }
                .settingsHighlight(id: highlightID("Progressbar style"))
                Defaults.Toggle(key: .systemEventIndicatorShadow) {
                    Text("Enable glowing effect")
                }
                .settingsHighlight(id: highlightID("Enable glowing effect"))
                Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                    Text("Use accent color")
                }
                .settingsHighlight(id: highlightID("Use accent color"))
            } header: {
                HStack {
                    Text("Appearance")
                }
            }
        }
        .onAppear {
            accessibilityPermission.refreshStatus()
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableSystemHUD = false
            }
        }
    }
}

private struct MusicSourceSelector: View {
    @Binding var selection: MediaControllerType
    let controllers: [MediaControllerType]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(controllers) { controller in
                        MusicSourceCard(
                            controller: controller,
                            isSelected: selection == controller
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = controller
                            }
                        }
                        .id(controller)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .onAppear {
                proxy.scrollTo(selection, anchor: .center)
            }
            .onChange(of: selection) { _, controller in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(controller, anchor: .center)
                }
            }
        }
        .frame(height: 112)
    }
}

private struct MusicSourceCard: View {
    let controller: MediaControllerType
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                // Every source shows the app's own icon, so the row does not
                // mix real icons for the apps we happen to ship a logo for
                // with flat brand marks for the rest. The bundled logo is the
                // fallback for when the app is not installed, which is better
                // than the generic symbol that used to stand in there.
                AppIconImage(
                    bundleIdentifiers: controller.applicationBundleIdentifiers,
                    assetFallback: controller.officialLogoAssetName,
                    symbolFallback: controller.fallbackSymbol,
                    symbolColor: controller.fallbackColor,
                    size: 42
                )
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 42, height: 42)

                Text(controller.localizedName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 112, height: 92)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 2.5 : 1)
            }
            .scaleEffect(isHovering && !isSelected ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(controller.localizedName)
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovering {
            return Color(nsColor: .controlBackgroundColor).opacity(0.92)
        }
        return Color(nsColor: .controlBackgroundColor).opacity(0.7)
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return Color(nsColor: .separatorColor).opacity(isHovering ? 0.8 : 0.45)
    }
}

private extension MediaControllerType {
    var officialLogoAssetName: String? {
        switch self {
        case .youtubeMusic: return "YouTubeMusicLogo"
        case .amazonMusic: return "AmazonMusicLogo"
        case .tidal: return "TidalLogo"
        case .cider: return "CiderLogo"
        default: return nil
        }
    }

    var applicationBundleIdentifiers: [String] {
        switch self {
        case .nowPlaying:
            return []
        case .appleMusic:
            return ["com.apple.Music"]
        case .spotify:
            return ["com.spotify.client"]
        case .youtubeMusic:
            return ["com.github.th-ch.youtube-music"]
        case .amazonMusic:
            return ["com.amazon.music"]
        case .tidal:
            return [TidalController.bundleIdentifier]
        case .cider:
            return ["sh.cider.genten.mac"]
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .nowPlaying: return "waveform"
        case .appleMusic: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        case .youtubeMusic: return "play.rectangle.fill"
        case .amazonMusic: return "music.note.list"
        case .tidal: return "waveform.path"
        case .cider: return "cup.and.saucer.fill"
        }
    }

    var fallbackColor: Color {
        switch self {
        case .nowPlaying: return .accentColor
        case .appleMusic: return .pink
        case .spotify: return .green
        case .youtubeMusic: return .red
        case .amazonMusic: return .cyan
        case .tidal: return .primary
        case .cider: return .orange
        }
    }
}

struct Media: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.showShuffleAndRepeat) private var showShuffleAndRepeat
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.musicControlWindowEnabled) private var musicControlWindowEnabled
    @Default(.showSneakPeekOnTrackChange) private var showSneakPeekOnTrackChange
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.enableHub) private var enableHub
    @Default(.enableLyrics) private var enableLyrics
    @Default(.pinLyricsWhenClosed) private var pinLyricsWhenClosed
    @Default(.pinnedLyricContext) private var pinnedLyricContext
    @Default(.lyricHighlightStyle) private var lyricHighlightStyle
    @Default(.lyricsPanelWidth) private var lyricsPanelWidth
    @Default(.lyricsPanelOffset) private var lyricsPanelOffset
    @Default(.visualizerBarCount) private var visualizerBarCount
    @Default(.enableWaveformScrubber) private var enableWaveformScrubber
    @Default(.colorExtractionMode) private var colorExtractionMode
    @Default(.parallaxEffectIntensity) private var parallaxEffectIntensity


    private func highlightID(_ title: String) -> String {
        SettingsTab.media.highlightID(for: title)
    }

    private var standardControlsSuppressed: Bool {
        !showStandardMediaControls && !enableMinimalisticUI
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("Music Source")
                            .font(.system(size: 13, weight: .semibold))
                        MediaSourceCapabilitiesButton(controllers: availableMediaControllers)
                        Spacer()
                        ScrollHintIndicator()
                    }

                    MusicSourceSelector(
                        selection: $mediaController,
                        controllers: availableMediaControllers
                    )
                }
                .onChange(of: mediaController) { _, _ in
                    NotificationCenter.default.post(
                        name: Notification.Name.mediaControllerChanged,
                        object: nil
                    )
                }
                .settingsHighlight(id: highlightID("Music Source"))
            } header: {
                Text("Media Source")
            } footer: {
                if MusicManager.shared.isNowPlayingDeprecated {
                    HStack {
                        Text("YouTube Music requires this third-party app to be installed: ")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Link("https://github.com/th-ch/youtube-music", destination: URL(string: "https://github.com/th-ch/youtube-music")!)
                            .font(.caption)
                            .foregroundColor(.blue) // Ensures it's visibly a link
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "'Now Playing' was the only option on previous versions and works with all media apps."))
                        if mediaController == .amazonMusic || mediaController == .tidal || mediaController == .cider {
                            Text(mediaController.description)
                        }
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            if mediaController == .spotify {
                SpotifyAuthSettingsSection()
                SpotifyLikeButtonSettingsSection()
            }

            if mediaController == .cider {
                CiderFavoritingSettingsSection()
            }

            Section {
                Defaults.Toggle(key: .showStandardMediaControls) {
                    Text("Show media controls in Notchly")
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Show media controls in Notchly"))

                Defaults.Toggle(key: .autoHideInactiveNotchMediaPlayer) {
                    Text("Auto-hide inactive notch media player")
                }
                .disabled(enableMinimalisticUI || !showStandardMediaControls)
                .settingsHighlight(id: highlightID("Auto-hide inactive notch media player"))

                if enableMinimalisticUI {
                    Text("Disable Minimalistic UI to configure the standard notch media controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if standardControlsSuppressed {
                    Text("Standard notch media controls are hidden. Re-enable the toggle above to restore them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !autoHideInactiveNotchMediaPlayer {
                    Text("When disabled, the notch music player stays visible with placeholder metadata even when playback is inactive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Notchly Visibility")
            }
            Section {
                Defaults.Toggle(key: .showShuffleAndRepeat) {
                    HStack {
                        Text("Enable customizable controls")
                        customBadge(text: "Beta")
                    }
                }
                if showShuffleAndRepeat {
                    Defaults.Toggle(key: .showMediaOutputControl) {
                        Text("Show \"Change Media Output\" control")
                    }
                    .settingsHighlight(id: highlightID("Show Change Media Output control"))
                    .help("Adds the AirPlay/route picker button back to the customizable controls palette.")
                    MusicSlotConfigurationView()
                } else {
                    Text("Turn on customizable controls to rearrange media buttons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            } header: {
                Text("Media controls")
            }

            Section {
                SettingsSegmentedPicker(
                    "Skip buttons",
                    selection: $musicSkipBehavior,
                    items: Array(MusicSkipBehavior.allCases)
                ) { $0.displayName }
                .settingsHighlight(id: highlightID("Skip buttons"))

                Text(musicSkipBehavior.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Skip button behaviour")
            } footer: {
                Text("Applies everywhere the transport controls appear: the notch player and the floating window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .disabled(standardControlsSuppressed)
                .help(standardControlsSuppressed ? "Standard notch media controls are hidden while this toggle is off." : "")
                Defaults.Toggle(key: .musicControlWindowEnabled) {
                    Text("Show floating media controls")
                }
                .disabled(!coordinator.musicLiveActivityEnabled || standardControlsSuppressed)
                .help("Displays play/pause and skip buttons beside the notch while music is active. Disabled by default.")
                Toggle("Enable sneak peek", isOn: $enableSneakPeek)
                Toggle("Show sneak peek on playback changes", isOn: $showSneakPeekOnTrackChange)
                    .disabled(!enableSneakPeek)
                Defaults.Toggle(key: .enableLyrics) {
                    Text("Show lyrics")
                }
                .disabled(enableMinimalisticUI || !showStandardMediaControls)
                .opacity(enableMinimalisticUI || !showStandardMediaControls ? 0.5 : 1)
                .help(
                    enableMinimalisticUI
                        ? "Disable Minimalistic UI to show lyrics."
                        : !showStandardMediaControls
                            ? "Enable Notchly media controls to show lyrics."
                            : ""
                )
                .settingsHighlight(id: highlightID("Show lyrics"))

                if enableLyrics && !enableMinimalisticUI && showStandardMediaControls {
                    // Caption inside the row rather than after it: a Form gives
                    // every top-level view its own row and a divider, so the
                    // explanation was being ruled off from the control it
                    // explains and read as belonging to nothing.
                    VStack(alignment: .leading, spacing: 6) {
                        SettingsSegmentedPicker(
                            "Highlight",
                            selection: $lyricHighlightStyle,
                            items: Array(LyricHighlightStyle.allCases)
                        ) { $0.localizedName }

                        Text(lyricHighlightStyle.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .settingsHighlight(id: highlightID("Lyric highlight"))
                }

                if enableLyrics && !enableMinimalisticUI && showStandardMediaControls {
                    Defaults.Toggle(key: .pinLyricsWhenClosed) {
                        Text("Keep lyrics under the closed notch")
                    }
                    .settingsHighlight(id: highlightID("Keep lyrics under the closed notch"))

                    SettingsSegmentedPicker(
                        "Pinned lyric context",
                        selection: $pinnedLyricContext,
                        items: Array(PinnedLyricContext.allCases)
                    ) { $0.localizedName }
                    .disabled(!pinLyricsWhenClosed)
                    .settingsHighlight(id: highlightID("Pinned lyric context"))


                    Text("Shows timed lyrics below the closed notch with the selected context. Keeps the space during instrumental breaks; hides the words while a HUD is on screen. Can also be toggled from the pin on the lyrics panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(
                    enableHub
                        ? "Lyrics sit on one line under the artist name, since the Hub is using the rest of the notch. Turn the Hub off to give them a full panel beside the player."
                        : "Lyrics get their own panel beside the player. Turn the Hub on to move them under the artist name instead."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if enableMinimalisticUI {
                    Text("Disable Minimalistic UI to use lyrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !showStandardMediaControls {
                    Text("Enable Notchly media controls to use lyrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if enableLyrics && !enableMinimalisticUI && !enableHub && showStandardMediaControls {
                    Slider(value: $lyricsPanelWidth, in: 180...420, step: 10) {
                        HStack {
                            Text("Side lyrics width")
                            Spacer()
                            Text("\(Int(lyricsPanelWidth)) px")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Side lyrics width"))

                    Slider(value: $lyricsPanelOffset, in: -100...100, step: 1) {
                        HStack {
                            Text("Side lyrics horizontal offset")
                            Spacer()
                            Text("\(lyricsPanelOffset >= 0 ? "+" : "")\(Int(lyricsPanelOffset)) px")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(id: highlightID("Side lyrics horizontal offset"))

                    Text("These controls apply when the Hub is turned off.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Defaults.Toggle(key: .showLiveCanvasInDynamicIsland) {
                    Text("Show live canvas in Notchly")
                }
                .settingsHighlight(id: highlightID("Show live canvas in Notchly"))
                .help("Replaces the artwork tile with the live canvas when the current app provides one, and reuses that moving canvas for the surrounding lighting effect.")
                
                //Parallax Effect Intensity to control how much parallax is wanted
                Slider(value: $parallaxEffectIntensity, in: 0...12, step: 1.0) {
                    HStack {
                        Text("Parallax Effect Intensity")
                        Spacer()
                        Text("\(parallaxEffectIntensity, specifier: "%0.1f")")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Enable album art parallax effect"))
                
                Picker("Sneak Peek Style", selection: $sneakPeekStyles){
                    ForEach(SneakPeekStyle.allCases) { style in
                        Text(style.localizedName).tag(style)
                    }
                }
                .disabled(!enableSneakPeek)
                .settingsHighlight(id: highlightID("Sneak Peek Style"))

                HStack {
                    Stepper(value: $waitInterval, in: 0...10, step: 1) {
                        HStack {
                            Text("Media inactivity timeout")
                            Spacer()
                            Text("\(Defaults[.waitInterval], specifier: "%.0f") seconds")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Defaults.Toggle(key: .showSongMetadataInClosedNotch) {
                    Text("Show song title and artist on non-notch displays")
                }
                .settingsHighlight(id: highlightID("Show song title and artist in closed notch"))
            } header: {
                Text("Media playback live activity")
            }

            Section {
                Defaults.Toggle(key: .enableRealTimeWaveform) {
                    HStack {
                        Text("Enable real-time waveform")
                        customBadge(text: "Beta")
                    }
                }
                .settingsHighlight(id: highlightID("Enable real-time waveform"))
                
                Picker("Visualizer candles", selection: $visualizerBarCount) {
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                
                Picker("Color extraction", selection: $colorExtractionMode) {
                    Text("Legacy").tag(ColorExtractionMode.legacy)
                    Text("Vibrant").tag(ColorExtractionMode.vibrant)
                }
                
                Toggle("Scrubbable real-time waveform", isOn: $enableWaveformScrubber)
            } header: {
                Text("Music Visualizer")
            } footer: {
                Text("When enabled, the music visualizer displays real-time audio spectrum data synced to your music. Requires macOS 14.2+ and uses minimal CPU/GPU resources via the Accelerate framework.")
            }

            Picker(selection: $hideNotchOption, label:
                    HStack {
                Text("Hide Notchly Options")
                customBadge(text: "Beta")
            }) {
                Text("Always hide in fullscreen").tag(HideNotchOption.always)
                Text("Hide only when NowPlaying app is in fullscreen").tag(HideNotchOption.nowPlayingOnly)
                Text("Never hide").tag(HideNotchOption.never)
            }
            .onChange(of: hideNotchOption) {
                Defaults[.enableFullscreenMediaDetection] = hideNotchOption != .never
            }
        }
    }

    // Only show controller options that are available on this macOS version
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}

struct HubSettings: View {
    @Default(.enableHub) private var enableHub
    @Default(.hubShowSeconds) private var showSeconds
    @Default(.hubTimeFormat) private var timeFormat
    @Default(.hubShowDate) private var showDate
    @Default(.hubHiddenChips) private var hiddenChips

    private func highlightID(_ title: String) -> String {
        SettingsTab.hub.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableHub) {
                    Text("Show the Hub")
                }
                .settingsHighlight(id: highlightID("Show the Hub"))
            } header: {
                Text("Hub")
            } footer: {
                Text("A large clock in the middle of the Home tab, with chips for whatever is relevant right now. It is not shown in Minimalistic UI.")
            }

            if enableHub {
                Section {
                    Defaults.Toggle(key: .hubShowSeconds) {
                        Text("Show seconds")
                    }
                    .settingsHighlight(id: highlightID("Show seconds"))

                    SettingsSegmentedPicker(
                        "Time format",
                        selection: $timeFormat,
                        items: Array(HubTimeFormat.allCases)
                    ) { $0.title }
                    .settingsHighlight(id: highlightID("Time format"))

                    Defaults.Toggle(key: .hubShowDate) {
                        Text("Show the date")
                    }
                    .settingsHighlight(id: highlightID("Show the date"))
                } header: {
                    Text("Clock")
                } footer: {
                    Text("Follow system uses the 12 or 24-hour setting of your Mac.")
                }

                Section {
                    ForEach(HubChip.priority) { chip in
                        Toggle(isOn: visibilityBinding(for: chip)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chip.title)
                                Text(chip.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Chips")
                } footer: {
                    Text("Chips only appear while they have something to show, and the clock stands alone when none do. Up to three are shown at once, most important first.")
                }
                .settingsHighlight(id: highlightID("Hub chips"))
            }
        }
        .animation(NotchlyTheme.Motion.snappy, value: enableHub)
    }

    private func visibilityBinding(for chip: HubChip) -> Binding<Bool> {
        Binding(
            get: { !hiddenChips.contains(chip) },
            set: { isOn in
                var updated = hiddenChips.filter { $0 != chip }
                if !isOn { updated.append(chip) }
                hiddenChips = updated
            }
        )
    }
}

private extension DevicesSettingsView {
    enum BluetoothHUDIconStyle: String {
        case symbol
        case threeD

        var title: String {
            switch self {
            case .symbol:
                return String(localized: "Symbol")
            case .threeD:
                return String(localized: "3D")
            }
        }
    }

    struct BluetoothHUDIconStyleCard: View {
        let style: BluetoothHUDIconStyle
        let isSelected: Bool
        let action: () -> Void

        @State private var isHovering = false

        var body: some View {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        )

                    preview
                }
                .frame(width: 90, height: 64)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isHovering = hovering
                    }
                }

                Text(style.title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
            .onTapGesture { action() }
        }

        private var preview: some View {
            Group {
                switch style {
                case .symbol:
                    Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                case .threeD:
                    if let url = BluetoothAudioDeviceType.airpods.inlineHUDAnimationURL {
                        SettingsLoopingVideoIcon(url: url, size: CGSize(width: 28, height: 28))
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: BluetoothAudioDeviceType.airpods.sfSymbol)
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }

        private var backgroundColor: Color {
            if isSelected { return Color.accentColor.opacity(0.12) }
            if isHovering { return Color.primary.opacity(0.05) }
            return Color(nsColor: .controlBackgroundColor)
        }

        private var borderColor: Color {
            if isSelected { return Color.accentColor }
            if isHovering { return Color.primary.opacity(0.1) }
            return Color.clear
        }
    }
}

private struct SettingsLoopingVideoIcon: NSViewRepresentable {
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
        private var controller: SettingsLoopingPlayerController?

        func attach(layer: AVPlayerLayer, url: URL) {
            controller = SettingsLoopingPlayerController(url: url, autoPlay: true)
            layer.player = controller?.player
        }
    }
}

private final class SettingsLoopingPlayerController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?

    init(url: URL, autoPlay: Bool = true) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)
        if autoPlay {
            player.play()
        }
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    deinit {
        player.pause()
        looper = nil
    }
}

struct LiveActivitiesSettings: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject private var fullDiskAccessPermission = FullDiskAccessPermissionStore.shared

    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.showRecordingIndicator) var showRecordingIndicator
    @Default(.recordingHoverStyle) var recordingHoverStyle
    @Default(.recordingControlMode) var recordingControlMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.focusIndicatorNonPersistent) var focusIndicatorNonPersistent
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.liveActivities.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableScreenRecordingDetection) {
                    Text("Enable Screen Recording Detection")
                }
                .settingsHighlight(id: highlightID("Enable Screen Recording Detection"))

                Defaults.Toggle(key: .showRecordingIndicator) {
                    Text("Show Recording Indicator")
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Show Recording Indicator"))

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSegmentedPicker(
                        "Recording controls",
                        selection: $recordingControlMode,
                        items: Array(RecordingControlMode.allCases)
                    ) { $0.title }

                    Text("Indicator only keeps the recording live activity passive. With stop button enables native recording controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableScreenRecordingDetection)
                .settingsHighlight(id: highlightID("Recording Controls"))

                VStack(alignment: .leading, spacing: 8) {
                    SettingsSegmentedPicker(
                        "Recording hover style",
                        selection: $recordingHoverStyle,
                        items: Array(RecordingHoverStyle.allCases)
                    ) { $0.title }

                    Text("Default uses the expanded recording HUD. Inline keeps the stop control inside the notch height.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(!enableScreenRecordingDetection || !showRecordingIndicator || recordingControlMode != .withStopButton)
                .settingsHighlight(id: highlightID("Recording Hover Style"))

                if recordingManager.isMonitoring {
                    HStack {
                        Text("Detection Status")
                        Spacer()
                        if recordingManager.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Recording Detected")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("Active - No Recording")
                                .foregroundColor(.green)
                        }
                    }
                }
            } header: {
                Text("Screen Recording")
            } footer: {
                Text("Uses event-driven private API for real-time screen recording detection")
            }

            Section {
                if !fullDiskAccessPermission.isAuthorized {
                    SettingsPermissionCallout(
                        title: String(localized: "Custom Focus metadata"),
                        message: String(localized: "Full Disk Access unlocks custom Focus icons, colors, and labels. Standard Focus detection still works without it—grant access only if you need personalized indicators."),
                        icon: "externaldrive.fill",
                        iconColor: .purple,
                        requestButtonTitle: String(localized: "Request Full Disk Access"),
                        openSettingsButtonTitle: String(localized: "Open Privacy & Security"),
                        requestAction: { fullDiskAccessPermission.requestAccessPrompt() },
                        openSettingsAction: { fullDiskAccessPermission.openSystemSettings() }
                    )
                }

                Defaults.Toggle(key: .enableDoNotDisturbDetection) {
                    Text("Enable Focus Detection")
                }
                .settingsHighlight(id: highlightID("Enable Focus Detection"))

                Defaults.Toggle(key: .showDoNotDisturbIndicator) {
                    Text("Show Focus Indicator")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus Indicator"))

                Defaults.Toggle(key: .showDoNotDisturbLabel) {
                    Text("Show Focus Label")
                }
                .disabled(!enableDoNotDisturbDetection || focusIndicatorNonPersistent)
                .help(focusIndicatorNonPersistent ? "Labels are forced to compact on/off text while brief toast mode is enabled." : "Show the active Focus name inside the indicator.")
                .settingsHighlight(id: highlightID("Show Focus Label"))

                Defaults.Toggle(key: .focusIndicatorNonPersistent) {
                    Text("Show Focus as brief toast")
                }
                .disabled(!enableDoNotDisturbDetection)
                .settingsHighlight(id: highlightID("Show Focus as brief toast"))
                .help("When enabled, Focus appears briefly (on/off) and then collapses instead of staying visible.")

                if doNotDisturbManager.isMonitoring {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        if doNotDisturbManager.isDoNotDisturbActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                Text(doNotDisturbManager.currentFocusModeName.isEmpty ? "Focus Enabled" : doNotDisturbManager.currentFocusModeName)
                                    .foregroundColor(.purple)
                            }
                        } else {
                            Text("Active - No Focus")
                                .foregroundColor(.green)
                        }
                    }
                } else {
                    HStack {
                        Text("Focus Status")
                        Spacer()
                        Text("Disabled")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Do Not Disturb")
            } footer: {
                Text("Listens for Focus session changes via distributed notifications")
            }

            Section {
                Defaults.Toggle(key: .enableCapsLockIndicator) {
                    Text("Show Caps Lock Indicator")
                }
                .settingsHighlight(id: highlightID("Show Caps Lock Indicator"))

                Defaults.Toggle(key: .showCapsLockLabel) {
                    Text("Show Caps Lock label")
                }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Show Caps Lock label"))

                SettingsSegmentedPicker(
                    "Caps Lock color",
                    selection: $capsLockTintMode,
                    items: Array(CapsLockIndicatorTintMode.allCases)
                ) { $0.displayName }
                .disabled(!Defaults[.enableCapsLockIndicator])
                .settingsHighlight(id: highlightID("Caps Lock color"))
            } header: {
                Text("Caps Lock Indicator")
            } footer: {
                Text("Adds a notch HUD when Caps Lock is enabled, with optional label and tint controls.")
            }

            Section {
                Defaults.Toggle(key: .enableCameraDetection) {
                    Text("Enable Camera Detection")
                }
                .settingsHighlight(id: highlightID("Enable Camera Detection"))
                Defaults.Toggle(key: .enableMicrophoneDetection) {
                    Text("Enable Microphone Detection")
                }
                .settingsHighlight(id: highlightID("Enable Microphone Detection"))

                if privacyManager.isMonitoring {
                    HStack {
                        Text("Camera Status")
                        Spacer()
                        if privacyManager.cameraActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Camera Active")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Microphone Status")
                        Spacer()
                        if privacyManager.microphoneActive {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 8, height: 8)
                                Text("Microphone Active")
                                    .foregroundColor(.yellow)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } header: {
                Text("Privacy Indicators")
            } footer: {
                Text("Shows green camera icon and yellow microphone icon when in use. Uses event-driven CoreAudio and CoreMediaIO APIs.")
            }

            Section {
                Toggle(
                    "Enable music live activity",
                    isOn: $coordinator.musicLiveActivityEnabled.animation()
                )
                .settingsHighlight(id: highlightID("Enable music live activity"))
            } header: {
                Text("Media Live Activity")
            } footer: {
                Text("Use the Media tab to configure sneak peek, lyrics, and floating media controls.")
            }
        }
        // Options that depend on a toggle dim and reveal smoothly rather than snapping.
        .animation(NotchlyTheme.Motion.snappy, value: enableScreenRecordingDetection)
        .animation(NotchlyTheme.Motion.snappy, value: showRecordingIndicator)
        .animation(NotchlyTheme.Motion.snappy, value: recordingControlMode)
        .animation(NotchlyTheme.Motion.snappy, value: enableDoNotDisturbDetection)
        .animation(NotchlyTheme.Motion.snappy, value: focusIndicatorNonPersistent)
        .onAppear {
            fullDiskAccessPermission.refreshStatus()
        }
    }
}

struct Appearance: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var webcamManager = WebcamManager.shared
    @Default(.mirrorShape) var mirrorShape
    @Default(.selectedCameraID) var selectedCameraID
    @Default(.sliderColor) var sliderColor
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.customVisualizers) var customVisualizers
    @Default(.selectedVisualizer) var selectedVisualizer
    @Default(.customAppIcons) private var customAppIcons
    @Default(.selectedAppIconID) private var selectedAppIconID
    @Default(.openNotchWidth) var openNotchWidth
    @Default(.closedNotchWidth) var closedNotchWidth
    @Default(.customizePhysicalNotchWidth) var customizePhysicalNotchWidth
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    @Default(.externalDisplayStyle) private var externalDisplayStyle
    @State private var selectedListVisualizer: CustomVisualizer? = nil

    @State private var isIconImporterPresented = false
    @State private var isIconDropTarget = false
    @State private var iconImportError: String?

    @State private var isPresented: Bool = false
    @State private var name: String = ""
    @State private var url: String = ""
    @State private var speed: CGFloat = 1.0

    /// Whether the main screen has a physical notch.
    private var mainScreenHasPhysicalNotch: Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    private var notchWidthRange: ClosedRange<Double> {
        let minW = Double(currentRecommendedMinimumNotchWidth())
        let maxW = min(900, Double(maxAllowedNotchWidth()))
        return minW...max(minW, maxW)
    }
    private var defaultOpenNotchWidth: CGFloat {
        currentRecommendedMinimumNotchWidth()
    }

    private func highlightID(_ title: String) -> String {
        SettingsTab.appearance.highlightID(for: title)
    }


    var body: some View {
        Form {
            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Defaults.Toggle(key: .settingsIconInNotch) {
                    Text("Settings icon in notch")
                }
                .settingsHighlight(id: highlightID("Settings icon in notch"))
                Defaults.Toggle(key: .enableShadow) {
                    Text("Enable window shadow")
                }
                .settingsHighlight(id: highlightID("Enable window shadow"))
                Defaults.Toggle(key: .cornerRadiusScaling) {
                    Text("Corner radius scaling")
                }
                .settingsHighlight(id: highlightID("Corner radius scaling"))
                Defaults.Toggle(key: .useModernCloseAnimation) {
                    Text("Use simpler close animation")
                }
                .settingsHighlight(id: highlightID("Use simpler close animation"))
            } header: {
                Text("General")
            }

            // Show display style picker only on non-notch Macs (main screen has no physical notch)
            if !mainScreenHasPhysicalNotch {
                Section {
                    Picker("Main screen style", selection: $externalDisplayStyle) {
                        ForEach(ExternalDisplayStyle.allCases) { style in
                            Text(style.localizedName)
                                .tag(style)
                        }
                    }
                    .onChange(of: externalDisplayStyle) {
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                    .settingsHighlight(id: highlightID("Main screen style"))
                    Text(externalDisplayStyle.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Display Style")
                }
            }

            notchWidthControls()

            Section {
                Defaults.Toggle(key: .coloredSpectrogram) {
                    Text("Enable colored spectrograms")
                }
                .settingsHighlight(id: highlightID("Enable colored spectrograms"))
                Defaults.Toggle(key: .playerColorTinting) {
                    Text("Enable colored spectograms")
                }
                Defaults.Toggle(key: .lightingEffect) {
                    Text("Enable blur effect behind album art")
                }
                .settingsHighlight(id: highlightID("Enable blur effect behind album art"))
                Picker("Slider color", selection: $sliderColor) {
                    ForEach(SliderColorEnum.allCases, id: \.self) { option in
                        Text(option.localizedName)
                    }
                }
                .settingsHighlight(id: highlightID("Slider color"))
            } header: {
                Text("Media")
            }

            Section {
                Toggle(
                    "Use music visualizer spectrogram",
                    isOn: $useMusicVisualizer.animation()
                )
                .disabled(true)
                if !useMusicVisualizer {
                    if customVisualizers.count > 0 {
                        Picker(
                            "Selected animation",
                            selection: $selectedVisualizer
                        ) {
                            ForEach(
                                customVisualizers,
                                id: \.self
                            ) { visualizer in
                                Text(visualizer.name)
                                    .tag(visualizer)
                            }
                        }
                    } else {
                        HStack {
                            Text("Selected animation")
                            Spacer()
                            Text("No custom animation available")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Custom music live activity animation")
                    customBadge(text: "Coming soon")
                }
            }

            Section {
                List {
                    ForEach(customVisualizers, id: \.self) { visualizer in
                        HStack {
                            LottieView(state: LUStateData(type: .loadedFrom(visualizer.url), speed: visualizer.speed, loopMode: .loop))
                                .frame(width: 30, height: 30, alignment: .center)
                            Text(visualizer.name)
                            Spacer(minLength: 0)
                            if selectedVisualizer == visualizer {
                                Text("selected")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 8)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 2)
                        .background(
                            selectedListVisualizer != nil ? selectedListVisualizer == visualizer ? Color.accentColor : Color.clear : Color.clear,
                            in: RoundedRectangle(cornerRadius: 5)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedListVisualizer == visualizer {
                                selectedListVisualizer = nil
                                return
                            }
                            selectedListVisualizer = visualizer
                        }
                    }
                }
                .safeAreaPadding(
                    EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0)
                )
                .frame(minHeight: 120)
                .actionBar {
                    HStack(spacing: 5) {
                        Button {
                            name = ""
                            url = ""
                            speed = 1.0
                            isPresented.toggle()
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        Divider()
                        Button {
                            if selectedListVisualizer != nil {
                                let visualizer = selectedListVisualizer!
                                selectedListVisualizer = nil
                                customVisualizers.remove(at: customVisualizers.firstIndex(of: visualizer)!)
                                if visualizer == selectedVisualizer && customVisualizers.count > 0 {
                                    selectedVisualizer = customVisualizers[0]
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                    }
                }
                .controlSize(.small)
                .buttonStyle(PlainButtonStyle())
                .overlay {
                    if customVisualizers.isEmpty {
                        Text("No custom visualizer")
                            .foregroundStyle(Color(.secondaryLabelColor))
                            .padding(.bottom, 22)
                    }
                }
                .sheet(isPresented: $isPresented) {
                    VStack(alignment: .leading) {
                        Text("Add new visualizer")
                            .font(.largeTitle.bold())
                            .padding(.vertical)
                        TextField("Name", text: $name)
                        TextField("Lottie JSON URL", text: $url)
                        HStack {
                            Text("Speed")
                            Spacer(minLength: 80)
                            Text("\(speed, specifier: "%.1f")s")
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.secondary)
                            Slider(value: $speed, in: 0...2, step: 0.1)
                        }
                        .padding(.vertical)
                        HStack {
                            Button {
                                isPresented.toggle()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }

                            Button {
                                let visualizer: CustomVisualizer = .init(
                                    UUID: UUID(),
                                    name: name,
                                    url: URL(string: url)!,
                                    speed: speed
                                )

                                if !customVisualizers.contains(visualizer) {
                                    customVisualizers.append(visualizer)
                                }

                                isPresented.toggle()
                            } label: {
                                Text("Add")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .controlSize(.extraLarge)
                    .padding()
                }
            } header: {
                HStack(spacing: 0) {
                    Text("Custom vizualizers (Lottie)")
                    if !Defaults[.customVisualizers].isEmpty {
                        Text(" – \(Defaults[.customVisualizers].count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Defaults.Toggle(key: .showMirror) {
                    Text("Enable Dynamic mirror")
                }
                .disabled(!checkVideoInput())
                .settingsHighlight(id: highlightID("Enable Dynamic mirror"))
                Picker("Mirror shape", selection: $mirrorShape) {
                    Text("Circle")
                        .tag(MirrorShapeEnum.circle)
                    Text("Square")
                        .tag(MirrorShapeEnum.rectangle)
                }
                .settingsHighlight(id: highlightID("Mirror shape"))
                
                if webcamManager.cameraAvailable {
                    Picker("Mirror Camera", selection: $selectedCameraID) {
                        ForEach(webcamManager.availableCameras, id: \.uniqueID) { device in
                            Text(device.localizedName)
                                .tag(device.uniqueID)
                        }
                    }
                    .onChange(of: selectedCameraID) { _, _ in
                        if Defaults[.showMirror] {
                            webcamManager.stopSession()
                            webcamManager.startSession()
                        }
                    }
                    .settingsHighlight(id: highlightID("Mirror Camera"))
                }
                Defaults.Toggle(key: .showNotHumanFace) {
                    Text("Idle Animation")
                }
                .settingsHighlight(id: highlightID("Idle Animation"))
            } header: {
                HStack {
                    Text("Additional features")
                }
            }

            // MARK: - Custom Idle Animations Section
            IdleAnimationsSettingsSection()

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        appIconCard(
                            title: "Default",
                            image: defaultAppIconImage(),
                            isSelected: selectedAppIconID == nil
                        ) {
                            selectedAppIconID = nil
                            applySelectedAppIcon()
                        }

                        ForEach(customAppIcons) { icon in
                            appIconCard(
                                title: icon.name,
                                image: customIconImage(for: icon),
                                isSelected: selectedAppIconID == icon.id.uuidString
                            ) {
                                selectedAppIconID = icon.id.uuidString
                                applySelectedAppIcon()
                            }
                            .contextMenu {
                                Button("Remove") {
                                    removeCustomIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(isIconDropTarget ? 0.18 : 0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(isIconDropTarget ? 0.8 : 0), lineWidth: 2)
                    )
                    .onDrop(of: [UTType.fileURL], isTargeted: $isIconDropTarget) { providers in
                        handleIconDrop(providers)
                    }

                    HStack(spacing: 8) {
                        Button("Add icon") {
                            iconImportError = nil
                            isIconImporterPresented = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove selected") {
                            if let id = selectedAppIconID,
                               let icon = customAppIcons.first(where: { $0.id.uuidString == id }) {
                                removeCustomIcon(icon)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedAppIconID == nil)
                    }

                    if let iconImportError {
                        Text(iconImportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Drop a PNG, JPEG, TIFF, or ICNS file to add it to your icon library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("App icon"))
            } header: {
                HStack {
                    Text("App icon")
                }
            }
        }
        .fileImporter(
            isPresented: $isIconImporterPresented,
            allowedContentTypes: [.png, .jpeg, .tiff, .icns, .image]
        ) { result in
            switch result {
            case .success(let url):
                importCustomIcon(from: url)
            case .failure:
                iconImportError = "Icon import was canceled or failed."
            }
        }
    }

    private func defaultAppIconImage() -> NSImage? {
        let fallbackName = Bundle.main.iconFileName ?? "AppIcon"
        return NSImage(named: fallbackName)
    }

    private func customIconImage(for icon: CustomAppIcon) -> NSImage? {
        NSImage(contentsOf: icon.fileURL)
    }

    private func appIconCard(title: String, image: NSImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                )

                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor : .clear)
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func handleIconDrop(_ providers: [NSItemProvider]) -> Bool {
        let matching = providers.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider = matching else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let directURL = item as? URL {
                url = directURL
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

    func checkVideoInput() -> Bool {
        if let _ = AVCaptureDevice.default(for: .video) {
            return true
        }

        return false
    }

    @ViewBuilder
    private func notchWidthControls() -> some View {
        Section {
            let recommendedMin = currentRecommendedMinimumNotchWidth()
            let tabCount = enabledStandardTabCount()
            let dynamicRange = Double(recommendedMin)...900
            
            let closedRange = Double(80)...400
            let minimalisticRange = Double(250)...600

            let widthBinding = Binding<Double>(
                get: { Double(openNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, dynamicRange.lowerBound), dynamicRange.upperBound)
                    let value = CGFloat(clamped)
                    if openNotchWidth != value {
                        openNotchWidth = value
                    }
                }
            )
            
            let closedWidthBinding = Binding<Double>(
                get: { Double(closedNotchWidth) },
                set: { newValue in
                    let clamped = min(max(newValue, closedRange.lowerBound), closedRange.upperBound)
                    let value = CGFloat(clamped)
                    if closedNotchWidth != value {
                        closedNotchWidth = value
                        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                    }
                }
            )

            VStack(alignment: .leading, spacing: 10) {
                Defaults.Toggle(key: .customizePhysicalNotchWidth) {
                    Text("Customize physical notch width")
                }
                .onChange(of: customizePhysicalNotchWidth) {
                    NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
                }
                .settingsHighlight(id: highlightID("Customize physical notch width"))
                
                Slider(
                    value: closedWidthBinding,
                    in: closedRange,
                    step: 5
                ) {
                    HStack {
                        Text("Closed notch / pill width")
                        Spacer()
                        Text("\(Int(closedNotchWidth)) px")
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsHighlight(id: highlightID("Closed notch / pill width"))

                Divider().padding(.vertical, 4)

                Slider(
                    value: widthBinding,
                    in: dynamicRange,
                    step: 10
                ) {
                    HStack {
                        Text("Expanded notch width")
                        Spacer()
                        Text("\(Int(openNotchWidth)) px")
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(enableMinimalisticUI)
                .settingsHighlight(id: highlightID("Expanded notch width"))

                HStack {
                    Text("\(tabCount) tab\(tabCount == 1 ? "" : "s") enabled · min \(Int(recommendedMin)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Width") {
                        openNotchWidth = recommendedMin
                    }
                    .disabled(abs(openNotchWidth - recommendedMin) < 0.5)
                    .buttonStyle(.bordered)
                }

                let description = enableMinimalisticUI
                ? String(localized: "Expanded width adjustments apply only to the standard notch layout. Disable Minimalistic UI to edit this value.")
                : String(localized: "Recommended minimum width adjusts automatically based on the number of enabled tabs.")

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onAppear {
                enforceMinimumNotchWidth()
            }
        } header: {
            HStack {
                Text("Notch Width")
                customBadge(text: "Beta")
            }
        }
    }
}


/// A segmented control with a sliding selection shape.
///
/// `Picker`'s segmented style paints the selection as a flat accent-coloured
/// rectangle that snaps between segments with no transition, which looks
/// nothing like the rest of the app. This is a soft track with one rounded
/// selection shape that slides between segments.
struct SettingsSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    /// Segments share the width equally instead of sizing to their text. Used
    /// where the control is a tab bar rather than a row's right-hand control.
    var fillsWidth: Bool = false

    @Namespace private var selectionNamespace
    @State private var hovered: Item?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        // Driven from the value, not only from `withAnimation` at the tap: a
        // selection changed from anywhere else -- settings search switching
        // segments, a Defaults write from another window -- should slide too,
        // and inside a Form row the tap's transaction does not always reach
        // the row's own content.
        .animation(selectionAnimation, value: selection)
    }

    private var selectionAnimation: Animation { .spring(response: 0.32, dampingFraction: 0.82) }

    @ViewBuilder
    private func segment(for item: Item) -> some View {
        let isSelected = selection == item
        let isHovered = hovered == item

        Button {
            guard selection != item else { return }
            withAnimation(selectionAnimation) { selection = item }
        } label: {
            Text(label(item))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: 24)
                .background {
                    if isSelected {
                        // The system accent colour, so the control follows
                        // System Settings > Appearance the way the stock
                        // segmented picker did.
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside {
                    hovered = item
                } else if hovered == item {
                    hovered = nil
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A settings row whose control is a ``SettingsSegmentedControl``.
///
/// Drop-in for `Picker(title, selection:).pickerStyle(.segmented)`: label on
/// the left, control on the right, same as every other row in the form.
struct SettingsSegmentedPicker<Item: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Item
    let items: [Item]
    let label: (Item) -> String

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Item>,
        items: [Item],
        label: @escaping (Item) -> String
    ) {
        self.title = title
        self._selection = selection
        self.items = items
        self.label = label
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            SettingsSegmentedControl(items: items, selection: $selection, label: label)
        }
    }
}

struct LockScreenSettings: View {
    @Default(.lockScreenLiveActivityIconStyle) private var lockScreenLiveActivityIconStyle
    @Default(.siriResponsivenessMode) private var siriResponsivenessMode

    private func highlightID(_ title: String) -> String {
        SettingsTab.lockScreen.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableLockScreenLiveActivity) {
                    Text("Enable lock screen live activity")
                }
                .settingsHighlight(id: highlightID("Enable lock screen live activity"))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Live activity icon")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        LockScreenIconStyleCard(
                            title: "Lock",
                            systemImage: "lock.fill",
                            isSelected: lockScreenLiveActivityIconStyle.showsLock
                        ) {
                            if lockScreenLiveActivityIconStyle.showsLock {
                                if lockScreenLiveActivityIconStyle.showsFingerprint {
                                    lockScreenLiveActivityIconStyle = .fingerprint
                                }
                            } else {
                                lockScreenLiveActivityIconStyle = .both
                            }
                        }
                        LockScreenIconStyleCard(
                            title: "Fingerprint",
                            systemImage: "touchid",
                            isSelected: lockScreenLiveActivityIconStyle.showsFingerprint
                        ) {
                            if lockScreenLiveActivityIconStyle.showsFingerprint {
                                if lockScreenLiveActivityIconStyle.showsLock {
                                    lockScreenLiveActivityIconStyle = .lock
                                }
                            } else {
                                lockScreenLiveActivityIconStyle = .both
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .settingsHighlight(id: highlightID("Live activity icon"))

                Defaults.Toggle(key: .enableLockSounds) {
                    Text("Play lock/unlock sounds")
                }
                .settingsHighlight(id: highlightID("Play lock/unlock sounds"))
            } header: {
                Text("Live Activity & Feedback")
            } footer: {
                Text("Select the lock, the fingerprint, or both icons. When the fingerprint is selected, the live activity stays open long enough to complete its unlock animation.")
            }

            Section {
                Picker("Siri detection speed", selection: $siriResponsivenessMode) {
                    ForEach(SiriResponsivenessMode.allCases) { mode in
                        VStack(alignment: .leading) {
                            Text(mode.displayName)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }.tag(mode)
                    }
                }
                .settingsHighlight(id: highlightID("Siri detection speed"))
            } header: {
                Text("Siri Detection")
            } footer: {
                Text("Higher speeds allow the lock screen and HUD overlays to hide almost instantly when Siri is invoked, but may impact battery life when on battery power.")
            }

            Section {
                Button("Copy Latest Crash Report") {
                    copyLatestCrashReport()
                }
            } header: {
                Text("Diagnostics")
            } footer: {
                Text("Collect the latest crash report to share with the developer when reporting lock screen or overlay issues.")
            }
        }
    }
}

private struct LockScreenIconStyleCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
                        }

                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .frame(width: 72, height: 50)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.12) }
        if isHovering { return Color.primary.opacity(0.05) }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor }
        if isHovering { return Color.primary.opacity(0.1) }
        return Color.clear
    }
}

private func copyLatestCrashReport() {
    let crashReportsPath = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
    let fileManager = FileManager.default

    do {
        let files = try fileManager.contentsOfDirectory(atPath: crashReportsPath)
        let crashFiles = files.filter { $0.contains("DynamicIsland") && $0.hasSuffix(".crash") }

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

struct Shortcuts: View {
    @Default(.enableShortcuts) var enableShortcuts

    private func highlightID(_ title: String) -> String {
        SettingsTab.shortcuts.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableShortcuts) {
                    Text("Enable global keyboard shortcuts")
                }
                .settingsHighlight(id: highlightID("Enable global keyboard shortcuts"))
            } header: {
                Text("General")
            } footer: {
                Text("When disabled, all keyboard shortcuts will be inactive. You can still use the UI controls.")
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if enableShortcuts {
                Section {
                    KeyboardShortcuts.Recorder("Toggle Sneak Peek:", name: .toggleSneakPeek)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Media")
                } footer: {
                    Text("Sneak Peek shows the media title and artist under the notch for a few seconds.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    KeyboardShortcuts.Recorder("Stash clipboard:", name: .stashClipboard)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Stash")
                } footer: {
                    Text("Adds whatever is on the clipboard to the Stash. No shortcut is set by default.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    KeyboardShortcuts.Recorder("Toggle Notch Open:", name: .toggleNotchOpen)
                        .disabled(!enableShortcuts)
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Toggle the notch open or closed from anywhere.")
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard shortcuts are disabled")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Enable global keyboard shortcuts above to customize your shortcuts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(LocalizedStringKey(text))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct QuickActionsSettings: View {
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableQuickActions) private var enableQuickActions
    @Default(.quickActionsOrder) private var order
    @Default(.quickActionsHidden) private var hidden
    @Default(.quickActionsShortcutName) private var shortcutName
    @State private var soundRefresh = 0

    private func highlightID(_ title: String) -> String {
        SettingsTab.quickActions.highlightID(for: title)
    }

    private var orderedActions: [QuickAction] {
        QuickActionsLayout.normalizedOrder(order)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableQuickActions) {
                    Text("Show Quick Actions row")
                }
                .settingsHighlight(id: highlightID("Show Quick Actions row"))
            } header: {
                Text("Quick Actions")
            } footer: {
                Text("A row of small glass buttons at the top of the Home tab. It is not shown in Minimalistic UI.")
            }

            if enableQuickActions {
                actionsSection
                shortcutSection
                liveActivitySection
                soundSection
            }
        }
    }

    // MARK: Actions

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            ForEach(orderedActions) { action in
                HStack(spacing: 10) {
                    Toggle(isOn: visibilityBinding(for: action)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(action.title, systemImage: action.symbolName)
                            Text(action.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        move(action, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(orderedActions.first == action)
                    .help("Move earlier")

                    Button {
                        move(action, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(orderedActions.last == action)
                    .help("Move later")
                }
            }
        } header: {
            Text("Buttons")
        } footer: {
            Text("Choose which buttons appear and in what order, left to right.")
        }
    }

    private func visibilityBinding(for action: QuickAction) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(action) },
            set: { isOn in
                var updated = hidden.filter { $0 != action }
                if !isOn { updated.append(action) }
                hidden = updated
            }
        )
    }

    private func move(_ action: QuickAction, by offset: Int) {
        withAnimation(.smooth) {
            order = QuickActionsLayout.moved(order, action: action, by: offset)
        }
    }

    // MARK: Shortcut

    @ViewBuilder
    private var shortcutSection: some View {
        Section {
            TextField("Shortcut name", text: $shortcutName)
                .settingsHighlight(id: highlightID("Shortcut name"))
        } header: {
            Text("Run Shortcut")
        } footer: {
            Text("macOS has no public switch for Do Not Disturb. Create a Shortcut that sets a Focus, or does anything else, and enter its exact name here. The button stays hidden until a name is set.")
        }
    }

    // MARK: Timer & stopwatch

    @ViewBuilder
    private var liveActivitySection: some View {
        Section {
            Toggle("Timer & stopwatch live activity", isOn: $coordinator.timerLiveActivityEnabled)
                .settingsHighlight(id: highlightID("Timer & stopwatch live activity"))
        } header: {
            Text("Timer & Stopwatch")
        } footer: {
            Text("While a timer or stopwatch runs, the closed notch shows it: a progress ring and the remaining time for a timer, a pulsing dot and the elapsed time for a stopwatch.")
        }
    }

    @ViewBuilder
    private var soundSection: some View {
        let customPath = UserDefaults.standard.string(forKey: "customTimerSoundPath")
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Timer sound")
                        .font(.system(size: 16, weight: .medium))
                    Spacer()
                    Button("Choose File", action: selectCustomTimerSound)
                        .buttonStyle(.bordered)
                }

                if let customPath {
                    Text("Custom: \(URL(fileURLWithPath: customPath).lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Default: timer.mp3")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Reset to Default") {
                    UserDefaults.standard.removeObject(forKey: "customTimerSoundPath")
                    soundRefresh += 1
                }
                .buttonStyle(.bordered)
                .disabled(customPath == nil)
            }
            .settingsHighlight(id: highlightID("Timer sound"))
        } header: {
            Text("Timer Sound")
        } footer: {
            Text("Plays once when a timer ends. Supported formats include MP3, M4A, WAV, and AIFF.")
        }
        .id(soundRefresh)
    }

    private func selectCustomTimerSound() {
        let panel = NSOpenPanel()
        panel.title = "Select Timer Sound"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "customTimerSoundPath")
            soundRefresh += 1
        }
    }
}

struct CustomOSDSettings: View {
    @Default(.enableCustomOSD) var enableCustomOSD
    @Default(.hasSeenOSDAlphaWarning) var hasSeenOSDAlphaWarning
    @Default(.enableOSDVolume) var enableOSDVolume
    @Default(.enableOSDBrightness) var enableOSDBrightness
    @Default(.enableOSDKeyboardBacklight) var enableOSDKeyboardBacklight
    @Default(.enableThirdPartyDDCIntegration) var enableThirdPartyDDCIntegration
    @Default(.osdMaterial) var osdMaterial
    @Default(.osdLiquidGlassCustomizationMode) var osdLiquidGlassCustomizationMode
    @Default(.osdLiquidGlassVariant) var osdLiquidGlassVariant
    @Default(.osdIconColorStyle) var osdIconColorStyle
    @Default(.enableSystemHUD) var enableSystemHUD
    @ObservedObject private var accessibilityPermission = AccessibilityPermissionStore.shared

    @State private var showAlphaWarning = false
    @State private var previewValue: CGFloat = 0.65
    @State private var previewType: SneakContentType = .volume

    private func highlightID(_ title: String) -> String {
        SettingsTab.hudAndOSD.highlightID(for: title)
    }

    private var hasAccessibilityPermission: Bool {
        accessibilityPermission.isAuthorized
    }

    private var availableOSDMaterials: [OSDMaterial] {
        if #available(macOS 26.0, *) {
            return OSDMaterial.allCases
        }
        return OSDMaterial.allCases.filter { $0 != .liquid }
    }

    private var liquidVariantRange: ClosedRange<Double> {
        Double(LiquidGlassVariant.supportedRange.lowerBound)...Double(LiquidGlassVariant.supportedRange.upperBound)
    }

    private var osdLiquidVariantBinding: Binding<Double> {
        Binding(
            get: { Double(osdLiquidGlassVariant.rawValue) },
            set: { newValue in
                let raw = Int(newValue.rounded())
                osdLiquidGlassVariant = LiquidGlassVariant.clamped(raw)
            }
        )
    }

    var body: some View {
        Group {
            if !hasAccessibilityPermission && !enableThirdPartyDDCIntegration {
                Section {
                    SettingsPermissionCallout(
                        message: "Accessibility permission is needed to intercept system controls for the Custom OSD.",
                        requestAction: { accessibilityPermission.requestAuthorizationPrompt() },
                        openSettingsAction: { accessibilityPermission.openSystemSettings() }
                    )
                } header: {
                    Text("Accessibility")
                }
            }

            if hasAccessibilityPermission || enableThirdPartyDDCIntegration {
                Section {
                    Toggle("Volume OSD", isOn: $enableOSDVolume)
                        .settingsHighlight(id: highlightID("Volume OSD"))
                    Toggle("Brightness OSD", isOn: $enableOSDBrightness)
                        .settingsHighlight(id: highlightID("Brightness OSD"))
                    Toggle("Keyboard Backlight OSD", isOn: $enableOSDKeyboardBacklight)
                        .settingsHighlight(id: highlightID("Keyboard Backlight OSD"))
                        .disabledWhileExternalAppOwnsKeys("Disabled while the external display app is running \u{2014} that app owns the keyboard backlight keys.")
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Choose which system controls should display custom OSD windows.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    Picker("Material", selection: $osdMaterial) {
                        ForEach(availableOSDMaterials, id: \.self) { material in
                            Text(material.rawValue).tag(material)
                        }
                    }
                    .settingsHighlight(id: highlightID("Material"))
                    .onChange(of: osdMaterial) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }

                    if osdMaterial == .liquid {
                        if #available(macOS 26.0, *) {
                            SettingsSegmentedPicker(
                                "Glass mode",
                                selection: $osdLiquidGlassCustomizationMode,
                                items: Array(LockScreenGlassCustomizationMode.allCases)
                            ) { $0.rawValue }

                            if osdLiquidGlassCustomizationMode == .customLiquid {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Custom liquid variant")
                                        Spacer()
                                        Text("v\(osdLiquidGlassVariant.rawValue)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Slider(value: osdLiquidVariantBinding, in: liquidVariantRange, step: 1)
                                }
                            }
                        } else {
                            Text("Custom Liquid is available on macOS 26 or later.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Icon & Progress Color", selection: $osdIconColorStyle) {
                        ForEach(OSDIconColorStyle.allCases, id: \.self) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .settingsHighlight(id: highlightID("Icon & Progress Color"))
                    .onChange(of: osdIconColorStyle) { _, _ in
                        previewValue = previewValue == 0.65 ? 0.651 : 0.65
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Material Options:")
                        Text("• Frosted Glass: Translucent blur effect")
                        Text("• Liquid Glass: Modern glass effect (macOS 26+)")
                        Text("• Solid Dark/Light/Auto: Opaque backgrounds")
                        Text("")
                        Text("Color options control the icon and progress bar appearance. Auto adapts to system theme.")
                    }
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }

                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 16) {
                            Text("Live Preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            CustomOSDView(
                                type: .constant(previewType),
                                value: .constant(previewValue),
                                icon: .constant("")
                            )
                            .frame(width: 200, height: 200)

                            HStack(spacing: 8) {
                                Button("Volume") {
                                    previewType = .volume
                                }
                                .buttonStyle(.bordered)

                                Button("Brightness") {
                                    previewType = .brightness
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Backlight") {
                                    previewType = .backlight
                                }
                                .buttonStyle(.bordered)
                            }
                            .controlSize(.small)
                            
                            Slider(value: $previewValue, in: 0...1)
                                .frame(width: 160)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Adjust settings above to see changes in real-time. The actual OSD appears at the bottom center of your screen.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .onAppear {
            accessibilityPermission.refreshStatus()
            if #unavailable(macOS 26.0), osdMaterial == .liquid {
                osdMaterial = .frosted
                osdLiquidGlassCustomizationMode = .standard
            }
        }
        .onChange(of: accessibilityPermission.isAuthorized) { _, granted in
            if !granted {
                enableCustomOSD = false
            }
        }
    }
}

struct SettingsPermissionCallout: View {
    let title: String
    let message: String
    let icon: String
    let iconColor: Color
    let requestButtonTitle: String
    let openSettingsButtonTitle: String
    let requestAction: () -> Void
    let openSettingsAction: () -> Void

    init(
        title: String = "Accessibility permission required",
        message: String,
        icon: String = "exclamationmark.triangle.fill",
        iconColor: Color = .orange,
        requestButtonTitle: String = "Request Access",
        openSettingsButtonTitle: String = "Open Settings",
        requestAction: @escaping () -> Void,
        openSettingsAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconColor = iconColor
        self.requestButtonTitle = requestButtonTitle
        self.openSettingsButtonTitle = openSettingsButtonTitle
        self.requestAction = requestAction
        self.openSettingsAction = openSettingsAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)

            Text(LocalizedStringKey(message))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(LocalizedStringKey(requestButtonTitle)) {
                    requestAction()
                }
                .buttonStyle(.borderedProminent)

                Button(LocalizedStringKey(openSettingsButtonTitle)) {
                    openSettingsAction()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    HUD()
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // redraw it small to keep memory low. At twice the size it is
                // asked for, so it stays sharp on a Retina display -- the old
                // flat 32 was being scaled *up* wherever this is drawn larger
                // than that, which is why the bigger icons looked soft.
                let side = max(32, size * 2)
                let thumb = NSImage(size: NSSize(width: side, height: side))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

// MARK: - Stash

struct StashSettings: View {
    @Default(.enableStash) private var enableStash
    @Default(.stashRetention) private var retention
    @Default(.stashMaxItems) private var maxItems
    @Default(.stashLinkThresholdMB) private var linkThresholdMB
    @Default(.enableShortcuts) private var enableShortcuts

    private func highlightID(_ title: String) -> String {
        SettingsTab.stash.highlightID(for: title)
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .enableStash) {
                    Text("Enable Stash")
                }
                .settingsHighlight(id: highlightID("Enable Stash"))
            } header: {
                Text("Stash")
            } footer: {
                Text("A temporary tray for text, links, images and files. Drop them on the notch, or add what is on the clipboard. It is not shown in Minimalistic UI.")
            }

            if enableStash {
                Section {
                    Picker("Keep items", selection: $retention) {
                        ForEach(StashRetention.allCases) { option in
                            Text(option.localizedName).tag(option)
                        }
                    }
                    .settingsHighlight(id: highlightID("Keep items"))

                    Stepper(value: $maxItems, in: StashLimits.maxItemsRange, step: 5) {
                        HStack {
                            Text("Maximum items")
                            Spacer()
                            Text("\(maxItems)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .settingsHighlight(id: highlightID("Maximum items"))

                    Stepper(value: $linkThresholdMB, in: 10...5000, step: 50) {
                        HStack {
                            Text("Link files larger than")
                            Spacer()
                            Text("\(linkThresholdMB) MB")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .settingsHighlight(id: highlightID("Link files larger than"))
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Files are copied into Notchly's own folder so they survive the original being moved or deleted. Bigger files are only linked, and show a Linked badge. When the cap is reached the oldest item is removed. Text is kept in a file on this Mac until it expires.")
                }

                Section {
                    Defaults.Toggle(key: .stashClearOnSleepOrLock) {
                        Text("Clear when the Mac sleeps or locks")
                    }
                    .settingsHighlight(id: highlightID("Clear when the Mac sleeps or locks"))

                    Defaults.Toggle(key: .stashHidePreviewsUntilHover) {
                        Text("Hide previews until hover")
                    }
                    .settingsHighlight(id: highlightID("Hide previews until hover"))
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Nothing is uploaded, and the clipboard is only read when you press Add from clipboard or use the shortcut. Items that password managers mark as private are never taken.")
                }

                Section {
                    KeyboardShortcuts.Recorder("Stash clipboard:", name: .stashClipboard)
                        .disabled(!enableShortcuts)
                        .settingsHighlight(id: highlightID("Stash clipboard shortcut"))
                } header: {
                    Text("Shortcut")
                } footer: {
                    Text(enableShortcuts
                         ? "Adds whatever is on the clipboard to the Stash. No shortcut is set by default."
                         : "Global keyboard shortcuts are turned off in the Shortcuts section.")
                }
            }
        }
    }
}


// MARK: - Bridge to the Notchly settings shell
//
// The pages themselves are still the legacy section views (stages 2-3 migrate
// them row by row); the shell reaches them, their search entries and their
// highlight anchors through the declarations below.

extension SettingsTab {
    /// The Notchly page this legacy tab now lives on.
    var page: NotchlySettingsPage {
        switch self {
        case .general: return .general
        case .appearance: return .appearance
        case .hub, .quickActions: return .homeHub
        case .media: return .music
        case .liveActivities, .lockScreen, .devices, .battery, .hudAndOSD, .downloads: return .liveActivities
        case .stash: return .stash
        case .shortcuts: return .shortcuts
        }
    }

    /// Label used by the sub-section picker on pages that hold several legacy tabs.
    var sectionTitle: String {
        switch self {
        case .liveActivities: return String(localized: "Activities")
        case .hudAndOSD: return String(localized: "Volume & Brightness")
        case .hub: return String(localized: "Hub")
        default: return title
        }
    }

    /// The legacy page content, hosted by the Notchly shell.
    @ViewBuilder
    var legacyContent: some View {
        switch self {
        case .general: SettingsForm(tab: .general) { GeneralSettings() }
        case .liveActivities: SettingsForm(tab: .liveActivities) { LiveActivitiesSettings() }
        case .appearance: SettingsForm(tab: .appearance) { Appearance() }
        case .lockScreen: SettingsForm(tab: .lockScreen) { LockScreenSettings() }
        case .media: SettingsForm(tab: .media) { Media() }
        case .devices: SettingsForm(tab: .devices) { DevicesSettingsView() }
        case .quickActions: SettingsForm(tab: .quickActions) { QuickActionsSettings() }
        case .stash: SettingsForm(tab: .stash) { StashSettings() }
        case .hub: SettingsForm(tab: .hub) { HubSettings() }
        case .hudAndOSD: SettingsForm(tab: .hudAndOSD) { HUDAndOSDSettingsView() }
        case .battery: SettingsForm(tab: .battery) { Charge() }
        case .downloads: SettingsForm(tab: .downloads) { Downloads() }
        case .shortcuts: SettingsForm(tab: .shortcuts) { Shortcuts() }
        }
    }
}

extension NotchlySettingsPage {
    /// Legacy tabs hosted on this page, in display order.
    var legacySections: [SettingsTab] {
        switch self {
        case .general: return [.general]
        case .appearance: return [.appearance]
        case .homeHub: return [.hub, .quickActions]
        case .music: return [.media]
        case .liveActivities: return [.liveActivities, .battery, .hudAndOSD, .devices, .lockScreen, .downloads]
        case .stash: return [.stash]
        case .shortcuts: return [.shortcuts]
        case .about: return []
        }
    }
}

extension SettingsSearchIndex {
    /// Every page, plus every legacy row (mapped onto its page and section).
    static let shared: SettingsSearchIndex = {
        let pages = NotchlySettingsPage.allCases.map(SettingsSearchEntry.entry(for:))
        let rows = LegacySettingsSearchCatalog.entries.map { entry in
            SettingsSearchEntry(
                title: entry.title,
                keywords: entry.keywords,
                page: entry.tab.page,
                sectionID: entry.tab.rawValue,
                highlightID: entry.highlightID
            )
        }
        return SettingsSearchIndex(entries: pages + rows)
    }()
}
