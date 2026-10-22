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

// Pure logic for everything Notchly shows from Foundry (the project-management
// app): the Hub chip, the Foundry tab, closed-notch alerts and the menu.
//
// Foundry writes a small read-only summary to
// ~/Library/Application Support/Foundry/notch.json and pings
// `FoundryFeed.changedNotification`. Notchly only ever reads that file; anything
// that changes data goes back to Foundry as a `foundry://` URL, so Foundry stays
// the only thing that writes its database.

// MARK: - Feed model

/// The parts of Foundry's `notch.json` that Notchly uses. Unknown fields are
/// ignored, so newer Foundry versions keep working, and a damaged part of the
/// file costs only that part: a malformed project is dropped, not the whole feed.
struct FoundryFeed: Equatable {
    static let supportedVersion = 1
    static let changedNotification = Notification.Name("io.github.gking09.foundry.notch-feed-changed")
    /// Foundry never writes more than this many projects.
    static let maxProjects = 5

    struct NextUp: Equatable {
        var key: String
        var subjectId: String
        var title: String
        var projectId: String
        var projectName: String
        var reasons: [String] = []
        var canComplete: Bool
    }

    struct Attention: Equatable {
        var count: Int
        var topTitle: String?
        /// "info", "warning" or "critical".
        var topSeverity: String?
        var topProjectName: String?

        static let none = Attention(count: 0, topTitle: nil, topSeverity: nil, topProjectName: nil)
    }

    struct Project: Equatable {
        var id: String
        var name: String
        /// `onTrack`, `atRisk`, `behind`, `blocked`, `onHold`, `completed`, `notStarted` or `unknown`.
        var health: String
        var healthLabel: String? = nil
        var phase: String? = nil
        /// Effort-weighted scope completion, 0...1.
        var scopeCompletion: Double? = nil
        var forecast: String? = nil
    }

    var version: Int
    /// When Foundry's data last changed (not when the file was written), if it said.
    var updatedAt: Date? = nil
    var nextUp: NextUp?
    var projects: [Project]
    var attention: Attention

    /// Where Foundry writes the feed.
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Foundry/notch.json")
    }

    /// Whether this build understands `version`.
    static func supports(version: Int) -> Bool {
        version >= 1 && version <= supportedVersion
    }
}

// MARK: - Tolerant decoding

extension FoundryFeed: Decodable {
    private enum CodingKeys: String, CodingKey { case version, updatedAt, nextUp, projects, attention }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)).flatMap(FoundryFeed.parseDate)
        nextUp = try? c.decodeIfPresent(NextUp.self, forKey: .nextUp)
        let boxes = (try? c.decodeIfPresent([Lossy<Project>].self, forKey: .projects)) ?? []
        projects = Array(boxes.compactMap(\.value).prefix(FoundryFeed.maxProjects))
        attention = (try? c.decodeIfPresent(Attention.self, forKey: .attention)) ?? .none
    }

    /// Decodes an element or yields nil instead of failing the whole array.
    private struct Lossy<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// Foundry writes ISO 8601 with fractional seconds. The epoch placeholder it
    /// writes while it has no data at all counts as "unknown".
    static func parseDate(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: string) ?? plain.date(from: string) else { return nil }
        return date.timeIntervalSince1970 > 86_400 ? date : nil
    }
}

extension FoundryFeed.NextUp: Decodable {
    private enum CodingKeys: String, CodingKey { case key, subjectId, title, projectId, projectName, reasons, canComplete }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        subjectId = try c.decode(String.self, forKey: .subjectId)
        title = try c.decode(String.self, forKey: .title)
        projectId = try c.decode(String.self, forKey: .projectId)
        projectName = try c.decode(String.self, forKey: .projectName)
        reasons = (try? c.decodeIfPresent([String].self, forKey: .reasons)) ?? []
        canComplete = (try? c.decodeIfPresent(Bool.self, forKey: .canComplete)) ?? false
    }
}

extension FoundryFeed.Attention: Decodable {
    private enum CodingKeys: String, CodingKey { case count, topTitle, topSeverity, topProjectName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = max(0, (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0)
        topTitle = try? c.decodeIfPresent(String.self, forKey: .topTitle)
        topSeverity = try? c.decodeIfPresent(String.self, forKey: .topSeverity)
        topProjectName = try? c.decodeIfPresent(String.self, forKey: .topProjectName)
    }
}

extension FoundryFeed.Project: Decodable {
    private enum CodingKeys: String, CodingKey { case id, name, health, healthLabel, phase, scopeCompletion, forecast }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        health = (try? c.decodeIfPresent(String.self, forKey: .health)) ?? "unknown"
        healthLabel = try? c.decodeIfPresent(String.self, forKey: .healthLabel)
        phase = try? c.decodeIfPresent(String.self, forKey: .phase)
        scopeCompletion = try? c.decodeIfPresent(Double.self, forKey: .scopeCompletion)
        forecast = try? c.decodeIfPresent(String.self, forKey: .forecast)
    }
}

// MARK: - Parsing

/// The outcome of reading feed bytes.
enum FoundryFeedParse: Equatable {
    case ok(FoundryFeed)
    /// Valid JSON from a Foundry that speaks a version this build doesn't.
    case unsupportedVersion(Int)
    case invalid
}

extension FoundryFeed {
    private struct VersionProbe: Decodable { var version: Int? }

    /// Reads feed bytes. Rejects a `version` this build doesn't understand, and
    /// anything that isn't a feed at all; tolerates damage inside a feed.
    static func parse(_ data: Data) -> FoundryFeedParse {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data), let version = probe.version else {
            return .invalid
        }
        guard supports(version: version) else { return .unsupportedVersion(version) }
        guard let feed = try? JSONDecoder().decode(FoundryFeed.self, from: data) else { return .invalid }
        return .ok(feed)
    }

    /// Decodes a feed, rejecting versions this build doesn't understand.
    static func decode(_ data: Data) -> FoundryFeed? {
        if case .ok(let feed) = parse(data) { return feed }
        return nil
    }
}

// MARK: - The file

/// Facts about the feed file that decide whether it may be read at all.
struct FoundryFeedFileInfo: Equatable {
    var isRegularFile: Bool
    var ownerID: UInt32
    var permissions: UInt16
    var size: Int
    var modified: Date?
}

/// Foundry writes the feed with mode 0600 as the signed-in user. A file anyone
/// else could have written is not Foundry's, and is not trusted.
enum FoundryFeedFilePolicy {
    /// Far more than a feed of five projects ever needs.
    static let maxBytes = 256 * 1024

    enum Problem: Equatable {
        case notAFile
        case wrongOwner
        case writableByOthers
        case tooLarge
        case unreadable
    }

    static func problem(for info: FoundryFeedFileInfo, currentUserID: UInt32) -> Problem? {
        if !info.isRegularFile { return .notAFile }
        if info.ownerID != currentUserID { return .wrongOwner }
        if info.permissions & 0o022 != 0 { return .writableByOthers }
        if info.size > maxBytes { return .tooLarge }
        return nil
    }
}

/// Everything a read of the feed can come to.
enum FoundryFeedLoad: Equatable {
    case missing
    case rejected(FoundryFeedFilePolicy.Problem)
    case unsupportedVersion(Int)
    case invalid
    case loaded(FoundryFeed, modified: Date?)
}

enum FoundryFeedLoader {
    /// Whether the file is there. A stat, not a read.
    static func exists(at url: URL = FoundryFeed.defaultURL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Stats the file without following links or opening it.
    static func info(at url: URL) -> FoundryFeedFileInfo? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return FoundryFeedFileInfo(
            isRegularFile: (attributes[.type] as? FileAttributeType) == .typeRegular,
            ownerID: (attributes[.ownerAccountID] as? NSNumber)?.uint32Value ?? UInt32.max,
            permissions: (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777,
            size: (attributes[.size] as? NSNumber)?.intValue ?? Int.max,
            modified: attributes[.modificationDate] as? Date
        )
    }

    /// Blocking file I/O: call it off the main thread.
    static func load(at url: URL = FoundryFeed.defaultURL, currentUserID: UInt32 = getuid()) -> FoundryFeedLoad {
        guard let info = info(at: url) else { return .missing }
        if let problem = FoundryFeedFilePolicy.problem(for: info, currentUserID: currentUserID) { return .rejected(problem) }
        guard let data = try? Data(contentsOf: url) else { return .rejected(.unreadable) }
        switch FoundryFeed.parse(data) {
        case .ok(let feed): return .loaded(feed, modified: info.modified)
        case .unsupportedVersion(let version): return .unsupportedVersion(version)
        case .invalid: return .invalid
        }
    }
}

// MARK: - Chip

/// What the Foundry chip says, worked out from the feed.
struct FoundryChipContent: Equatable {
    enum Kind: Equatable {
        /// A project needs attention; the text is the warning.
        case attention(critical: Bool)
        /// The suggested next action.
        case nextUp
    }

    var kind: Kind
    var text: String
    /// Longer description for the tooltip and VoiceOver.
    var detail: String
    /// The project the chip refers to, opened on click.
    var projectId: String?
    /// The task that "Mark Done" completes; nil when the next step isn't a task.
    var completableTaskId: String?
    /// Recommendation key for "Later".
    var recommendationKey: String?

    /// Warnings win over the next action, but only ones Foundry rates as a real
    /// warning or worse; notes stay quiet.
    static func make(from feed: FoundryFeed?) -> FoundryChipContent? {
        guard let feed else { return nil }
        if let title = feed.attention.topTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
           let severity = feed.attention.topSeverity, severity == "warning" || severity == "critical" {
            let project = feed.attention.topProjectName.map { "\($0): " } ?? ""
            let more = feed.attention.count > 1 ? " (+\(feed.attention.count - 1) more)" : ""
            let projectId = feed.projects.first { $0.name == feed.attention.topProjectName }?.id
            return FoundryChipContent(
                kind: .attention(critical: severity == "critical"),
                text: title,
                detail: "\(project)\(title)\(more)",
                projectId: projectId,
                completableTaskId: nil,
                recommendationKey: nil
            )
        }
        if let next = feed.nextUp {
            let title = next.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return FoundryChipContent(
                kind: .nextUp,
                text: title,
                detail: "Next up in \(next.projectName): \(title)",
                projectId: next.projectId,
                completableTaskId: next.canComplete ? next.subjectId : nil,
                recommendationKey: next.key
            )
        }
        return nil
    }
}

/// `foundry://` URLs that ask Foundry to act. Foundry validates each one again.
enum FoundryLink {
    static let open = URL(string: "foundry://open")!

    /// Ids are UUIDs and recommendation keys look like `task:<uuid>`. Anything
    /// else (a slash, a query, a space) is refused rather than escaped, so a
    /// damaged feed can't turn into a different action.
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80
            && id.unicodeScalars.allSatisfy { ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == ":" }
    }

    static func project(_ id: String) -> URL? {
        isValidID(id) ? URL(string: "foundry://project/\(id)") : nil
    }

    static func completeTask(_ id: String) -> URL? {
        isValidID(id) ? URL(string: "foundry://task/\(id)/complete") : nil
    }

    /// Foundry accepts 1...30 days; the value is clamped to that.
    static func deferRecommendation(_ key: String, days: Int = 1) -> URL? {
        isValidID(key) ? URL(string: "foundry://recommendation/\(key)/defer?days=\(min(max(days, 1), 30))") : nil
    }
}
