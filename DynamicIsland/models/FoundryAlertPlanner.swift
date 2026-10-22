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

import Foundation

// Decides when a change in Foundry's feed deserves a brief closed-notch alert.
// Pure: the previous feed, the new one and the history of alerts go in, and an
// optional alert comes out. Whether it can be shown right now (full screen,
// lock screen, Focus) is the view's business; whether it is shown at all is
// decided here, and the answer is "rarely".

/// One closed-notch alert.
struct FoundryAlert: Equatable {
    /// The warning it is about, normalised, for rate limiting and tests.
    var key: String
    var severity: FoundrySeverity
    var title: String
    var projectName: String?
    /// Open items in the feed's attention list.
    var count: Int

    /// The longest title shown beside the notch.
    static let maxTitleLength = 22

    /// What the right wing says: the warning when there is one, otherwise the count.
    var label: String {
        count > 1 ? String(localized: "\(count) to review") : Self.shortTitle(title)
    }

    static func shortTitle(_ title: String, limit: Int = maxTitleLength) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(1, limit - 1))).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}

/// When each warning last raised an alert.
struct FoundryAlertHistory: Equatable {
    /// How long a record is worth keeping; the longest cooldown, with room to spare.
    static let retention: TimeInterval = 3600

    private(set) var byWarning: [String: Date] = [:]
    private(set) var last: Date?

    init() {}

    func lastAlert(for cooldownKey: String) -> Date? { byWarning[cooldownKey] }

    mutating func record(_ alert: FoundryAlert, at now: Date) {
        byWarning[FoundryAlertPlanner.cooldownKey(for: alert)] = now
        last = now
        byWarning = byWarning.filter { now.timeIntervalSince($0.value) < Self.retention }
    }
}

enum FoundryAlertPlanner {
    /// The same warning (at the same severity) alerts at most once per this long.
    static let perWarningCooldown: TimeInterval = 600
    /// Two alerts of any kind are at least this far apart.
    static let globalCooldown: TimeInterval = 20
    /// How long an alert stays in the wings.
    static let displayDuration: TimeInterval = 3

    /// The warning at the top of the feed, if it is one worth a closed-notch alert.
    static func topWarning(in feed: FoundryFeed) -> FoundryAlert? {
        let severity = FoundrySeverity(raw: feed.attention.topSeverity)
        guard severity.isActionable, feed.attention.count > 0 else { return nil }
        guard let title = feed.attention.topTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        let project = feed.attention.topProjectName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoundryAlert(
            key: "\(project ?? "")|\(title)".lowercased(),
            severity: severity,
            title: title,
            projectName: project,
            count: feed.attention.count
        )
    }

    static func cooldownKey(for alert: FoundryAlert) -> String { "\(alert.key)|\(alert.severity.rawValue)" }

    /// - Parameter previous: the feed Notchly last saw. `nil` for the first feed
    ///   of a session, which only sets the baseline and never alerts, so launching
    ///   the app with an old warning open stays quiet.
    ///
    /// An alert needs news:
    /// - a warning where there was none,
    /// - the top warning getting more severe, or
    /// - a different warning on top because the number of open items grew.
    /// The same warning staying on top, a resolved one making way for the next,
    /// and a count that merely shrinks are not news.
    static func plan(
        previous: FoundryFeed?,
        new: FoundryFeed,
        history: FoundryAlertHistory,
        now: Date
    ) -> FoundryAlert? {
        guard let previous, let top = topWarning(in: new) else { return nil }

        let before = topWarning(in: previous)
        let isNews: Bool
        if let before {
            let escalated = top.severity > before.severity
            let newcomer = top.key != before.key && new.attention.count > previous.attention.count
            isNews = escalated || newcomer
        } else {
            isNews = true
        }
        guard isNews else { return nil }

        if let last = history.last, now.timeIntervalSince(last) >= 0, now.timeIntervalSince(last) < globalCooldown { return nil }
        if let seen = history.lastAlert(for: cooldownKey(for: top)), now.timeIntervalSince(seen) >= 0,
           now.timeIntervalSince(seen) < perWarningCooldown { return nil }
        return top
    }
}
