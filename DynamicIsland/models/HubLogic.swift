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

import CoreGraphics
import Defaults
import Foundation

// Pure logic behind the Home tab's Hub: how the clock is written out, which
// chips are relevant right now and in what order, how the card tilts under the
// pointer, and how wide the Home tab needs the notch to be. Nothing here touches
// SwiftUI, the managers or the stored preferences, so all of it can be tested.

// MARK: - Clock

/// 12 / 24 hour preference. `system` follows the Mac's own setting.
enum HubTimeFormat: String, CaseIterable, Identifiable, Defaults.Serializable {
    case system
    case twelveHour
    case twentyFourHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "Follow system")
        case .twelveHour: return String(localized: "12-hour")
        case .twentyFourHour: return String(localized: "24-hour")
        }
    }
}

/// The clock broken into the pieces the Hub animates separately, so a digit
/// that changes can roll on its own without the rest of the time moving.
struct HubClockParts: Equatable {
    var hours: String
    var minutes: String
    /// `nil` when seconds are switched off.
    var seconds: String?
    /// "AM" / "PM", only in 12-hour mode.
    var period: String?

    /// "9:41", "21:41:07" or "9:41:07 PM": what a screen reader should say.
    var spokenText: String {
        var text = "\(hours):\(minutes)"
        if let seconds { text += ":\(seconds)" }
        if let period { text += " \(period)" }
        return text
    }
}

enum HubClockFormatter {
    /// Seconds between clock redraws: every second while seconds are shown (or
    /// the colon is blinking), once a minute when seconds are hidden and
    /// background activity is reduced.
    static func tickInterval(showSeconds: Bool, reducedActivity: Bool) -> TimeInterval {
        (!showSeconds && reducedActivity) ? 60 : 1
    }

    /// Whether the clock should be drawn on a 24-hour face.
    static func uses24Hour(format: HubTimeFormat, locale: Locale = .current) -> Bool {
        switch format {
        case .twelveHour: return false
        case .twentyFourHour: return true
        case .system:
            // The "j" template resolves to the locale's preferred hour cycle;
            // a 12-hour locale's pattern carries an "a" (AM/PM marker).
            let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "HH"
            return !pattern.contains("a")
        }
    }

    static func parts(
        for date: Date,
        format: HubTimeFormat,
        showSeconds: Bool,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HubClockParts {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let second = components.second ?? 0

        let twentyFour = uses24Hour(format: format, locale: locale)
        let hours: String
        var period: String?
        if twentyFour {
            hours = String(format: "%02d", hour)
        } else {
            let twelve = hour % 12 == 0 ? 12 : hour % 12
            hours = String(twelve)
            // Some locales give "am" / "pm"; the Hub always draws it in capitals.
            period = (hour < 12 ? calendar.amSymbol : calendar.pmSymbol).uppercased()
        }

        return HubClockParts(
            hours: hours,
            minutes: String(format: "%02d", minute),
            seconds: showSeconds ? String(format: "%02d", second) : nil,
            period: period
        )
    }

    /// "Thursday 1 Oct" in the user's locale ("Thursday, Oct 1" in en_US).
    static func dateLine(
        for date: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return formatter.string(from: date)
    }
}

// MARK: - Chips

/// One kind of glanceable chip under the Hub's clock.
enum HubChip: String, CaseIterable, Identifiable, Defaults.Serializable {
    case timer
    case stopwatch
    case focus
    case battery
    case music
    case stash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .timer: return String(localized: "Timer")
        case .stopwatch: return String(localized: "Stopwatch")
        case .focus: return String(localized: "Focus")
        case .battery: return String(localized: "Battery")
        case .music: return String(localized: "Paused music")
        case .stash: return String(localized: "Stash")
        }
    }

    var detail: String {
        switch self {
        case .timer: return String(localized: "Time left on a running timer. Click to open it.")
        case .stopwatch: return String(localized: "Elapsed time on a running stopwatch. Click to open it.")
        case .focus: return String(localized: "The Focus mode that is switched on.")
        case .battery: return String(localized: "While charging or when the battery is low.")
        case .music: return String(localized: "The track you paused. Click to resume.")
        case .stash: return String(localized: "How many items are waiting in the Stash. Click to open it.")
        }
    }

    /// Most important first. When there is not room for every relevant chip,
    /// the ones at the end are the ones that wait.
    static let priority: [HubChip] = [.timer, .stopwatch, .focus, .battery, .music, .stash]
}

/// What the Hub knows about the Mac right now, as plain values.
struct HubContext: Equatable {
    /// `nil` on a Mac with no battery.
    var batteryLevel: Int?
    var isPluggedIn = false
    var isCharging = false
    var isLowPowerMode = false
    /// "1h 12m": already formatted, `nil` while macOS is still estimating.
    var batteryTimeText: String?

    var timerPhase: ClockPhase = .idle
    var timerRemainingSeconds = 0
    var stopwatchPhase: ClockPhase = .idle
    var stopwatchElapsedSeconds = 0

    var stashEnabled = false
    var stashCount = 0

    var focusActive = false
    var focusName = ""

    /// A track is loaded but not playing.
    var musicIsPaused = false
    var musicTitle = ""
}

/// How a chip should read at a glance. Colour is reserved for meaning, in
/// keeping with the rest of the theme.
enum HubChipTone: Equatable {
    case neutral
    case positive
    case warning
    case critical
}

struct HubChipModel: Identifiable, Equatable {
    var kind: HubChip
    var symbol: String
    var text: String
    var tone: HubChipTone = .neutral
    /// Draws the chip filled, for something actively counting.
    var isLive = false

    var id: HubChip { kind }
}

enum HubChipPlanner {
    /// The battery chip appears on its own once the charge falls to this.
    static let lowBatteryThreshold = 30
    static let criticalBatteryThreshold = 15
    /// What fits in one row of the card.
    static let maxVisibleChips = 3

    /// The chips to show, most important first.
    ///
    /// - Parameters:
    ///   - hidden: chips the user has switched off in Settings.
    ///   - limit: how many fit; the rest wait until room frees up.
    static func chips(
        for context: HubContext,
        hidden: Set<HubChip> = [],
        limit: Int = maxVisibleChips
    ) -> [HubChipModel] {
        guard limit > 0 else { return [] }
        var result: [HubChipModel] = []
        for kind in HubChip.priority where !hidden.contains(kind) {
            guard let model = model(for: kind, context: context) else { continue }
            result.append(model)
            if result.count == limit { break }
        }
        return result
    }

    /// The chip for `kind`, or `nil` when it has nothing to say right now.
    static func model(for kind: HubChip, context: HubContext) -> HubChipModel? {
        switch kind {
        case .timer:
            guard context.timerPhase != .idle else { return nil }
            if context.timerPhase == .finished {
                return HubChipModel(kind: kind, symbol: "bell.fill", text: String(localized: "Done"), tone: .warning, isLive: true)
            }
            return HubChipModel(
                kind: kind,
                symbol: context.timerPhase == .paused ? "pause.fill" : "timer",
                text: ClockFormat.digital(seconds: context.timerRemainingSeconds),
                isLive: context.timerPhase == .running
            )

        case .stopwatch:
            guard context.stopwatchPhase != .idle else { return nil }
            return HubChipModel(
                kind: kind,
                symbol: context.stopwatchPhase == .paused ? "pause.fill" : "stopwatch",
                text: ClockFormat.digital(seconds: context.stopwatchElapsedSeconds),
                isLive: context.stopwatchPhase == .running
            )

        case .focus:
            guard context.focusActive else { return nil }
            let name = context.focusName.trimmingCharacters(in: .whitespacesAndNewlines)
            return HubChipModel(
                kind: kind,
                symbol: "moon.fill",
                text: name.isEmpty ? String(localized: "Focus") : name
            )

        case .battery:
            guard let level = context.batteryLevel else { return nil }
            let charging = context.isCharging
            let plugged = context.isPluggedIn
            let low = level <= lowBatteryThreshold
            guard charging || plugged || low else { return nil }

            var text = "\(level)%"
            if let time = context.batteryTimeText, !time.isEmpty, !(plugged && !charging) {
                text += " · \(time)"
            }
            let tone: HubChipTone
            if charging {
                tone = .positive
            } else if level <= criticalBatteryThreshold {
                tone = .critical
            } else if low {
                tone = .warning
            } else {
                tone = .neutral
            }
            return HubChipModel(
                kind: kind,
                symbol: charging ? "bolt.fill" : batterySymbol(forLevel: level),
                text: text,
                tone: tone
            )

        case .music:
            let title = context.musicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard context.musicIsPaused, !title.isEmpty else { return nil }
            return HubChipModel(kind: kind, symbol: "play.fill", text: title)

        case .stash:
            guard context.stashEnabled, context.stashCount > 0 else { return nil }
            let count = context.stashCount
            return HubChipModel(
                kind: kind,
                symbol: "tray.full.fill",
                text: count == 1 ? String(localized: "1 item") : String(localized: "\(count) items")
            )
        }
    }

    static func batterySymbol(forLevel level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - Parallax

/// How the Hub card leans toward the pointer.
enum HubParallax {
    static let maximumTilt: Double = 5

    /// Where `location` sits in a `size` card, as -1...1 on each axis (0 centre).
    static func normalizedOffset(location: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return .zero }
        let x = (location.x / size.width - 0.5) * 2
        let y = (location.y / size.height - 0.5) * 2
        return CGPoint(x: min(max(x, -1), 1), y: min(max(y, -1), 1))
    }

    /// Rotation, in degrees, about each axis for a normalised pointer offset.
    /// The card dips toward the pointer: pointer right -> right edge goes away
    /// (positive Y rotation), pointer low -> bottom edge goes away (negative X).
    static func tilt(for offset: CGPoint, maximum: Double = maximumTilt) -> (x: Double, y: Double) {
        (x: Double(-offset.y) * maximum, y: Double(offset.x) * maximum)
    }
}

// MARK: - Home layout

/// Width budgets for the Home tab's columns, shared by the view and the notch
/// sizing so they cannot disagree.
enum HomeLayoutBudget {
    /// Fixed width of the Hub card.
    static let hubWidth: CGFloat = 260
    /// Height of the Hub card. The Home content below the header is about 150pt
    /// tall; the card leaves a little air.
    static let hubHeight: CGFloat = 128
    /// Room the player needs for its artwork and five-button control row.
    static let minimumPlayerWidth: CGFloat = 320
    /// Room the webcam mirror needs to stay usable next to the Hub.
    static let minimumMirrorWidth: CGFloat = 180
    /// Gap between columns.
    static let columnSpacing: CGFloat = 20
    /// Home-view and notch content insets around the columns.
    static let combinedInset: CGFloat = 40

    /// Notch width the visible columns need, or 0 when the Hub is not one of them
    /// (the existing minimums already cover the player on its own).
    static func requiredNotchWidth(
        hubVisible: Bool,
        playerVisible: Bool,
        mirrorVisible: Bool
    ) -> CGFloat {
        guard hubVisible else { return 0 }
        var columns: [CGFloat] = [hubWidth]
        if playerVisible { columns.append(minimumPlayerWidth) }
        if mirrorVisible { columns.append(minimumMirrorWidth) }
        let spacing = CGFloat(max(columns.count - 1, 0)) * columnSpacing
        return columns.reduce(0, +) + spacing + combinedInset
    }
}
