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

// MARK: - Item

/// One thing held in the Stash: a snippet of text, a link, a file or folder, or
/// an image. Codable so the whole tray can be saved as JSON.
struct StashItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case url
        case file
        case image
    }

    let id: UUID
    var kind: Kind
    var createdAt: Date
    /// The text itself (`.text`) or the link's absolute string (`.url`).
    var text: String?
    /// The stored or linked file (`.file`, `.image`).
    var file: StashFileRef?

    init(id: UUID = UUID(), kind: Kind, createdAt: Date, text: String? = nil, file: StashFileRef? = nil) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.text = text
        self.file = file
    }

    // MARK: Derived

    /// Short label: file name, link, or the first line of text.
    var title: String {
        switch kind {
        case .file, .image:
            return file?.displayName ?? ""
        case .url:
            return text ?? ""
        case .text:
            return StashText.firstLine(of: text ?? "")
        }
    }

    var characterCount: Int { text?.count ?? 0 }

    var webURL: URL? {
        guard kind == .url, let text else { return nil }
        return URL(string: text)
    }

    /// Whether the card should show a thumbnail rather than a file icon.
    var showsThumbnail: Bool {
        kind == .image || (file?.isImage ?? false)
    }

    var isLinked: Bool { file?.isLinked ?? false }

    /// The first `lineLimit` lines of text, for a card preview.
    func previewText(lineLimit: Int = 4, characterLimit: Int = 220) -> String {
        StashText.preview(of: text ?? "", lineLimit: lineLimit, characterLimit: characterLimit)
    }
}

// MARK: - File reference

/// Where a stashed file lives. Small files are copied into the stash folder
/// (`storedPath`); big ones are only linked (`bookmark` + `originalPath`).
struct StashFileRef: Codable, Equatable {
    var displayName: String
    var byteSize: Int64
    var isDirectory: Bool
    var isImage: Bool
    /// Path of the copy, relative to the stash directory. `nil` when linked.
    var storedPath: String?
    /// Where the file was when it was stashed.
    var originalPath: String?
    /// Bookmark to the original, kept for linked files so they survive a move.
    var bookmark: Data?

    var isLinked: Bool { storedPath == nil }

    /// The file's current location. For a linked file this follows the bookmark,
    /// falling back to the original path; `nil` if neither is known.
    func resolvedURL(in directory: URL) -> URL? {
        if let storedPath {
            return directory.appendingPathComponent(storedPath)
        }
        if let bookmark {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        return originalPath.map { URL(fileURLWithPath: $0) }
    }
}

// MARK: - Text helpers

enum StashText {
    /// First non-empty line, trimmed.
    static func firstLine(of text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Up to `lineLimit` lines and `characterLimit` characters, with an ellipsis
    /// when anything was cut.
    static func preview(of text: String, lineLimit: Int, characterLimit: Int) -> String {
        guard lineLimit > 0, characterLimit > 0 else { return "" }
        let lines = text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var kept = Array(lines.drop(while: { $0.isEmpty }).prefix(lineLimit))
        var truncated = lines.drop(while: { $0.isEmpty }).count > kept.count
        while let last = kept.last, last.isEmpty { kept.removeLast() }
        var result = kept.joined(separator: "\n")
        if result.count > characterLimit {
            result = String(result.prefix(characterLimit))
            truncated = true
        }
        return truncated ? result.trimmingCharacters(in: .whitespacesAndNewlines) + "\u{2026}" : result
    }
}
