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

// Pure presentation logic for the Foundry tab, the settings status rows and the
// menu: what the feed says, in the words and shapes the views draw. Nothing here
// touches AppKit, Defaults or the file system.

// MARK: - Feed state

/// Where the feed stands, as the store reports it.
enum FoundryFeedState: Equatable {
    /// The integration is switched off. Nothing has been read.
    case off
    case notFound
    case rejected(FoundryFeedFilePolicy.Problem)
    case unsupported(Int)
    case invalid
    case loaded(FoundryFeed, modified: Date?)

    init(load: FoundryFeedLoad) {
        switch load {
        case .missing: self = .notFound
        case .rejected(let problem): self = .rejected(problem)
        case .unsupportedVersion(let version): self = .unsupported(version)
        case .invalid: self = .invalid
        case .loaded(let feed, let modified): self = .loaded(feed, modified: modified)
        }
    }

    var feed: FoundryFeed? {
        if case .loaded(let feed, _) = self { return feed }
        return nil
    }

    /// The most recent sign of life: when Foundry's data last changed, or when
    /// the file was last written, whichever is later.
    var lastUpdated: Date? {
        guard case .loaded(let feed, let modified) = self else { return nil }
        return [feed.updatedAt, modified].compactMap { $0 }.max()
    }
}

// MARK: - Time

enum FoundryTime {
    /// Foundry only rewrites the feed when something changes, so a quiet feed
    /// gets old without being wrong. After this long the tab says so, and leaves
    /// the judgement to the reader.
    static let staleAfter: TimeInterval = 24 * 3600

    static func isStale(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > staleAfter
    }

    /// "just now", "12 min ago", "3 h ago", "yesterday", "5 days ago".
    static func relative(from date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return String(localized: "just now")
        case ..<3600:
            return String(localized: "\(max(1, Int((seconds / 60).rounded()))) min ago")
        case ..<86_400:
            return String(localized: "\(Int((seconds / 3600).rounded(.down))) h ago")
        case ..<(2 * 86_400):
            return String(localized: "yesterday")
        default:
            return String(localized: "\(Int(seconds / 86_400)) days ago")
        }
    }
}

// MARK: - Health

/// A project's health as the notch draws it: a shape first, a hint of colour second.
enum FoundryHealth: Equatable {
    case healthy, atRisk, behind, blocked, paused, done, notStarted, unknown

    init(raw: String) {
        switch raw {
        case "onTrack": self = .healthy
        case "atRisk": self = .atRisk
        case "behind": self = .behind
        case "blocked": self = .blocked
        case "onHold": self = .paused
        case "completed": self = .done
        case "notStarted": self = .notStarted
        default: self = .unknown
        }
    }

    /// Distinct silhouettes, so health reads without colour.
    var glyph: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .atRisk: return "exclamationmark.triangle.fill"
        case .behind: return "clock.badge.exclamationmark.fill"
        case .blocked: return "xmark.octagon.fill"
        case .paused: return "pause.circle.fill"
        case .done: return "checkmark.seal.fill"
        case .notStarted: return "circle.dashed"
        case .unknown: return "questionmark.circle"
        }
    }

    enum Tone: Equatable { case neutral, good, caution, bad }

    /// Colour carries meaning only where there is some to carry.
    var tone: Tone {
        switch self {
        case .healthy: return .good
        case .atRisk, .behind: return .caution
        case .blocked: return .bad
        case .paused, .done, .notStarted, .unknown: return .neutral
        }
    }

    var fallbackLabel: String {
        switch self {
        case .healthy: return String(localized: "On track")
        case .atRisk: return String(localized: "At risk")
        case .behind: return String(localized: "Behind")
        case .blocked: return String(localized: "Blocked")
        case .paused: return String(localized: "On hold")
        case .done: return String(localized: "Done")
        case .notStarted: return String(localized: "Not started")
        case .unknown: return String(localized: "Unknown")
        }
    }
}

/// How serious a warning is. Anything Foundry says that isn't recognised is
/// treated as a quiet note.
enum FoundrySeverity: Int, Comparable, Equatable {
    case info = 0
    case warning = 1
    case critical = 2

    init(raw: String?) {
        switch raw {
        case "critical": self = .critical
        case "warning": self = .warning
        default: self = .info
        }
    }

    static func < (lhs: FoundrySeverity, rhs: FoundrySeverity) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Only a warning or worse is worth interrupting for.
    var isActionable: Bool { self >= .warning }
}

// MARK: - Actions

/// How long a suggested next step is put off.
enum FoundryDeferOption: CaseIterable, Equatable {
    case oneDay, threeDays, oneWeek

    var days: Int {
        switch self {
        case .oneDay: return 1
        case .threeDays: return 3
        case .oneWeek: return 7
        }
    }

    var title: String {
        switch self {
        case .oneDay: return String(localized: "1 day")
        case .threeDays: return String(localized: "3 days")
        case .oneWeek: return String(localized: "1 week")
        }
    }

    func link(forKey key: String) -> URL? { FoundryLink.deferRecommendation(key, days: days) }
}

/// "Press again to confirm": the first tap arms, a second tap inside the window
/// confirms, and an armed state that nobody confirmed lapses by itself. A single
/// click therefore never changes anything in Foundry.
struct FoundryTwoStep: Equatable {
    static let window: TimeInterval = 3

    enum Outcome: Equatable { case armed, confirmed }

    private(set) var armedAt: Date?

    func isArmed(at now: Date) -> Bool {
        guard let armedAt else { return false }
        let elapsed = now.timeIntervalSince(armedAt)
        return elapsed >= 0 && elapsed < Self.window
    }

    mutating func tap(at now: Date) -> Outcome {
        if isArmed(at: now) {
            armedAt = nil
            return .confirmed
        }
        armedAt = now
        return .armed
    }

    mutating func cancel() { armedAt = nil }
}

// MARK: - Tab model

enum FoundryNoFeedReason: Equatable {
    case off
    case notFound
    case unsupported(Int)
    case invalid
    case rejected(FoundryFeedFilePolicy.Problem)

    var title: String {
        switch self {
        case .off: return String(localized: "Foundry is switched off here")
        case .notFound: return String(localized: "Foundry isn't running or sharing a summary")
        case .unsupported: return String(localized: "This Foundry feed is newer than Notchly understands")
        case .invalid, .rejected: return String(localized: "Notchly couldn't read Foundry's summary")
        }
    }

    var detail: String {
        switch self {
        case .off: return String(localized: "Turn on \u{201C}Show Foundry in Notchly\u{201D} in settings.")
        case .notFound: return String(localized: "Open Foundry and turn on the glance summary in its General settings.")
        case .unsupported: return String(localized: "Update Notchly to read it.")
        case .invalid: return String(localized: "The file isn't a valid Foundry summary.")
        case .rejected: return String(localized: "The file isn't owned by you or can be changed by others, so it is ignored.")
        }
    }
}

struct FoundryTabModel: Equatable {
    struct Hero: Equatable {
        var title: String
        var projectName: String
        var projectId: String
        /// At most two reasons, joined for one line.
        var reasons: String
        var key: String
        /// The task `Complete` applies to; nil when the next step isn't a task.
        var completableTaskId: String?
    }

    struct Row: Equatable, Identifiable {
        var id: String
        var name: String
        var health: FoundryHealth
        var healthLabel: String
        var phase: String?
        /// 0...1, or nil when nothing is estimated.
        var progress: Double?
        var progressText: String?
        var forecast: String?
    }

    struct Banner: Equatable {
        var count: Int
        var title: String
        var severity: FoundrySeverity
        var projectName: String?
        var projectId: String?
    }

    enum Mode: Equatable {
        case content
        /// A valid feed with nothing in it.
        case empty
        case noFeed(FoundryNoFeedReason)
    }

    var mode: Mode
    var hero: Hero?
    var rows: [Row]
    var banner: Banner?
    var lastUpdated: Date?
    var isStale: Bool

    /// "Updated 3 h ago", or nil when the feed carries no time.
    func updatedText(now: Date) -> String? {
        lastUpdated.map { String(localized: "Updated \(FoundryTime.relative(from: $0, now: now))") }
    }

    static func make(state: FoundryFeedState, now: Date) -> FoundryTabModel {
        switch state {
        case .off:
            return noFeed(.off)
        case .notFound:
            return noFeed(.notFound)
        case .unsupported(let version):
            return noFeed(.unsupported(version))
        case .invalid:
            return noFeed(.invalid)
        case .rejected(let problem):
            return noFeed(.rejected(problem))
        case .loaded(let feed, _):
            let lastUpdated = state.lastUpdated
            let hero = hero(from: feed.nextUp)
            let rows = feed.projects.prefix(FoundryFeed.maxProjects).map(row(from:))
            let banner = banner(from: feed)
            let isEmpty = hero == nil && rows.isEmpty && banner == nil
            return FoundryTabModel(
                mode: isEmpty ? .empty : .content,
                hero: hero,
                rows: Array(rows),
                banner: banner,
                lastUpdated: lastUpdated,
                isStale: FoundryTime.isStale(lastUpdated: lastUpdated, now: now)
            )
        }
    }

    private static func noFeed(_ reason: FoundryNoFeedReason) -> FoundryTabModel {
        FoundryTabModel(mode: .noFeed(reason), hero: nil, rows: [], banner: nil, lastUpdated: nil, isStale: false)
    }

    private static func hero(from next: FoundryFeed.NextUp?) -> Hero? {
        guard let next else { return nil }
        let title = next.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let reasons = next.reasons
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " \u{00B7} ")
        return Hero(
            title: title,
            projectName: next.projectName,
            projectId: next.projectId,
            reasons: reasons,
            key: next.key,
            completableTaskId: next.canComplete ? next.subjectId : nil
        )
    }

    private static func row(from project: FoundryFeed.Project) -> Row {
        let health = FoundryHealth(raw: project.health)
        let label = project.healthLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let progress = project.scopeCompletion.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
        let forecast = project.forecast?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phase = project.phase?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Row(
            id: project.id,
            name: project.name,
            health: health,
            healthLabel: (label?.isEmpty == false ? label : nil) ?? health.fallbackLabel,
            phase: (phase?.isEmpty == false) ? phase : nil,
            progress: progress,
            progressText: progress.map { "\(Int(($0 * 100).rounded()))%" },
            forecast: (forecast?.isEmpty == false) ? forecast : nil
        )
    }

    private static func banner(from feed: FoundryFeed) -> Banner? {
        let attention = feed.attention
        guard attention.count > 0 else { return nil }
        let severity = FoundrySeverity(raw: attention.topSeverity)
        let top = attention.topTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (top?.isEmpty == false ? top : nil)
            ?? String(localized: "\(attention.count) items need attention")
        return Banner(
            count: attention.count,
            title: title,
            severity: severity,
            projectName: attention.topProjectName,
            projectId: feed.projects.first { $0.name == attention.topProjectName }?.id
        )
    }
}

// MARK: - Layout budget

/// The open notch gives a tab about this much room; the Foundry tab is laid out
/// to fit inside it with nothing behind the hardware notch (the header sits in
/// the strip the shell already reserves above tab content).
enum FoundryTabMetrics {
    static let padding: CGFloat = 8
    static let headerHeight: CGFloat = 24
    static let sectionSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 20
    static let rowSpacing: CGFloat = 2.5
    static let heroWidth: CGFloat = 228
    /// Below this width the project rows leave the phase out so the name and
    /// forecast keep their room; the open notch's minimum width lands just under it.
    static let phaseColumnMinimumWidth: CGFloat = 372

    static func showsPhase(rowsWidth: CGFloat) -> Bool { rowsWidth >= phaseColumnMinimumWidth }

    static var rowsHeight: CGFloat {
        CGFloat(FoundryFeed.maxProjects) * rowHeight + CGFloat(FoundryFeed.maxProjects - 1) * rowSpacing
    }

    /// Height of the body (hero card and project rows side by side).
    static var bodyHeight: CGFloat { rowsHeight }

    /// Total height of the tab's content.
    static var contentHeight: CGFloat { padding * 2 + headerHeight + sectionSpacing + bodyHeight }

    /// The most the open notch can give tab content: its 200pt minus the header
    /// strip (about 34pt) and a little air at the bottom edge.
    static let availableHeight: CGFloat = 162
}

// MARK: - Settings status

/// The status rows on the Foundry settings page.
struct FoundryStatusSummary: Equatable {
    var feedFound: Bool
    var feedText: String
    var updatedText: String?
    var projectCount: Int?
    var versionText: String
    var versionSupported: Bool?

    static func make(state: FoundryFeedState, installed: Bool, feedExists: Bool = false, now: Date) -> FoundryStatusSummary {
        switch state {
        case .off:
            return FoundryStatusSummary(
                feedFound: feedExists,
                feedText: feedExists
                    ? String(localized: "Found (switched off, so not read)")
                    : (installed ? String(localized: "No summary yet") : String(localized: "Foundry isn't installed")),
                updatedText: nil, projectCount: nil,
                versionText: String(localized: "Not checked"), versionSupported: nil
            )
        case .notFound:
            return FoundryStatusSummary(
                feedFound: false,
                feedText: installed ? String(localized: "No summary yet") : String(localized: "Foundry isn't installed"),
                updatedText: nil, projectCount: nil,
                versionText: String(localized: "Not checked"), versionSupported: nil
            )
        case .rejected:
            return FoundryStatusSummary(
                feedFound: true, feedText: String(localized: "Found, but ignored for safety"),
                updatedText: nil, projectCount: nil,
                versionText: String(localized: "Not checked"), versionSupported: nil
            )
        case .invalid:
            return FoundryStatusSummary(
                feedFound: true, feedText: String(localized: "Found, but not readable"),
                updatedText: nil, projectCount: nil,
                versionText: String(localized: "Not checked"), versionSupported: nil
            )
        case .unsupported(let version):
            return FoundryStatusSummary(
                feedFound: true, feedText: String(localized: "Found"),
                updatedText: nil, projectCount: nil,
                versionText: String(localized: "Version \(version) isn't supported"), versionSupported: false
            )
        case .loaded(let feed, _):
            return FoundryStatusSummary(
                feedFound: true, feedText: String(localized: "Found"),
                updatedText: state.lastUpdated.map { FoundryTime.relative(from: $0, now: now) },
                projectCount: feed.projects.count,
                versionText: String(localized: "Version \(feed.version) is supported"), versionSupported: true
            )
        }
    }
}

// MARK: - Menu

/// What the status-bar menu shows about Foundry.
struct FoundryMenuState: Equatable {
    var nextUpTitle: String?
    var nextUpProjectName: String?
    var attentionCount = 0

    init(nextUpTitle: String? = nil, nextUpProjectName: String? = nil, attentionCount: Int = 0) {
        self.nextUpTitle = nextUpTitle
        self.nextUpProjectName = nextUpProjectName
        self.attentionCount = attentionCount
    }

    init(feed: FoundryFeed?) {
        self.init(
            nextUpTitle: feed?.nextUp?.title,
            nextUpProjectName: feed?.nextUp?.projectName,
            attentionCount: feed?.attention.count ?? 0
        )
    }
}
