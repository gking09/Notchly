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

import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Snapshot

/// What the pasteboard held when the user asked to stash it, as plain values so
/// the decision about what to take is testable without AppKit.
struct StashPasteboardSnapshot: Equatable {
    /// Every type identifier present on the pasteboard.
    var types: [String] = []
    var fileURLs: [URL] = []
    var string: String?
    var imageData: Data?
    var imageExtension: String = "png"
}

enum StashPasteboardReadResult: Equatable {
    case payloads([StashPayload])
    /// The source marked the contents concealed or transient (password managers
    /// and the like); nothing was taken.
    case concealed
    case empty
}

// MARK: - Reader

enum StashPasteboardReader {
    /// Types a source adds to say "do not keep this": nspasteboard.org's
    /// concealed and transient markers, plus 1Password's.
    static let privateTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "com.agilebits.onepassword",
    ]

    static func isPrivate(_ snapshot: StashPasteboardSnapshot) -> Bool {
        snapshot.types.contains { privateTypes.contains($0) }
    }

    /// Picks what to stash: files first (Finder puts a name and an icon on the
    /// pasteboard too, which would only get in the way), then an image, then a
    /// link, then text.
    static func read(_ snapshot: StashPasteboardSnapshot) -> StashPasteboardReadResult {
        if isPrivate(snapshot) { return .concealed }

        if !snapshot.fileURLs.isEmpty {
            return .payloads(snapshot.fileURLs.filter(\.isFileURL).map { .file($0) })
        }
        if let data = snapshot.imageData, !data.isEmpty {
            return .payloads([.image(data, fileExtension: snapshot.imageExtension)])
        }
        if let string = snapshot.string,
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .payloads([payload(forText: string)])
        }
        return .empty
    }

    /// A string that is just one web link becomes a link item; anything else is text.
    static func payload(forText text: String) -> StashPayload {
        if let url = singleLink(in: text) { return .url(url) }
        return .text(text)
    }

    static let linkSchemes: Set<String> = ["http", "https", "ftp", "ftps", "mailto"]

    static func singleLink(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), linkSchemes.contains(scheme)
        else { return nil }
        if scheme.hasPrefix("http") || scheme.hasPrefix("ftp") {
            guard let host = url.host, !host.isEmpty else { return nil }
        }
        return url
    }
}

// MARK: - AppKit bridge

extension StashPasteboardSnapshot {
    /// Reads the pasteboard once. Called only when the user asks (button or shortcut).
    init(pasteboard: NSPasteboard) {
        self.init()
        types = pasteboard.types?.map(\.rawValue) ?? []
        fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        string = pasteboard.string(forType: .string)

        if let png = pasteboard.data(forType: .png) {
            imageData = png
            imageExtension = "png"
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) {
            imageData = png
            imageExtension = "png"
        }
    }
}

// MARK: - Writer

enum StashPasteboardWriter {
    /// Puts `item` back on the pasteboard. Returns `false` if it could not be
    /// written (e.g. the file has gone).
    @discardableResult
    static func write(_ item: StashItem, fileURL: URL?, to pasteboard: NSPasteboard = .general) -> Bool {
        switch item.kind {
        case .text:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            return pasteboard.setString(text, forType: .string)

        case .url:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            pasteboard.declareTypes([.URL, .string], owner: nil)
            let wroteURL = pasteboard.setString(text, forType: .URL)
            let wroteString = pasteboard.setString(text, forType: .string)
            return wroteURL || wroteString

        case .image:
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            pasteboard.clearContents()
            if let image = NSImage(contentsOf: fileURL), pasteboard.writeObjects([image]) { return true }
            return pasteboard.writeObjects([fileURL as NSURL])

        case .file:
            guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return false }
            pasteboard.clearContents()
            return pasteboard.writeObjects([fileURL as NSURL])
        }
    }
}
