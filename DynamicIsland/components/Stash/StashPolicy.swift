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

import Defaults
import Foundation

// MARK: - Retention

/// How long the Stash keeps things.
enum StashRetention: String, CaseIterable, Identifiable, Defaults.Serializable {
    case untilQuit = "Until I quit"
    case oneHour = "1 hour"
    case day = "24 hours"
    case week = "7 days"
    case untilCleared = "Until I clear"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .untilQuit: return String(localized: "Until I quit")
        case .oneHour: return String(localized: "1 hour")
        case .day: return String(localized: "24 hours")
        case .week: return String(localized: "7 days")
        case .untilCleared: return String(localized: "Until I clear")
        }
    }

    /// Seconds an item lives, or `nil` when time never expires it.
    var lifetime: TimeInterval? {
        switch self {
        case .untilQuit, .untilCleared: return nil
        case .oneHour: return 3_600
        case .day: return 86_400
        case .week: return 604_800
        }
    }

    /// `true` when everything is dropped on launch and on quit.
    var clearsOnLaunch: Bool { self == .untilQuit }

    func isExpired(createdAt: Date, now: Date) -> Bool {
        guard let lifetime else { return false }
        return now.timeIntervalSince(createdAt) >= lifetime
    }

    /// When an item added at `createdAt` expires, if it ever does.
    func expiryDate(createdAt: Date) -> Date? {
        lifetime.map { createdAt.addingTimeInterval($0) }
    }
}

// MARK: - Size policy

/// Decides whether a file is copied into the stash or only linked.
struct StashSizePolicy: Equatable {
    enum Decision: Equatable {
        case copy
        case link
    }

    static let defaultThresholdMegabytes = 200

    /// Files strictly larger than this are linked, not copied.
    var linkThresholdBytes: Int64

    init(linkThresholdBytes: Int64) {
        self.linkThresholdBytes = max(0, linkThresholdBytes)
    }

    init(megabytes: Int) {
        self.init(linkThresholdBytes: Self.bytes(megabytes: megabytes))
    }

    func decision(forByteSize size: Int64) -> Decision {
        size > linkThresholdBytes ? .link : .copy
    }

    static func bytes(megabytes: Int) -> Int64 {
        Int64(max(0, megabytes)) * 1_000_000
    }
}

// MARK: - Limits

enum StashLimits {
    static let defaultMaxItems = 50
    static let maxItemsRange = 5...200
    /// Text longer than this (UTF-8 bytes) is refused rather than stored in the JSON.
    static let maximumTextBytes = 2_000_000

    static func clampedMaxItems(_ value: Int) -> Int {
        min(max(value, maxItemsRange.lowerBound), maxItemsRange.upperBound)
    }
}

// MARK: - Configuration

/// Everything the store needs from settings, as plain values.
struct StashConfiguration: Equatable {
    var retention: StashRetention = .day
    var maxItems: Int = StashLimits.defaultMaxItems
    var sizePolicy = StashSizePolicy(megabytes: StashSizePolicy.defaultThresholdMegabytes)
}

// MARK: - Defaults

extension Defaults.Keys {
    static let enableStash = Key<Bool>("enableStash", default: true)
    static let stashRetention = Key<StashRetention>("stashRetention", default: .day)
    static let stashMaxItems = Key<Int>("stashMaxItems", default: StashLimits.defaultMaxItems)
    static let stashLinkThresholdMB = Key<Int>("stashLinkThresholdMB", default: StashSizePolicy.defaultThresholdMegabytes)
    static let stashClearOnSleepOrLock = Key<Bool>("stashClearOnSleepOrLock", default: false)
    static let stashHidePreviewsUntilHover = Key<Bool>("stashHidePreviewsUntilHover", default: false)
}
