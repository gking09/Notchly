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

/// Turns what a drag delivers (`NSItemProvider`s) into payloads to stash.
enum StashDropReader {
    /// The types the notch accepts. Wide on purpose: anything that carries a
    /// file, a link, text or an image.
    static let acceptedTypes: [UTType] = [.fileURL, .url, .image, .plainText, .text, .data]

    static func payloads(from providers: [NSItemProvider]) async -> [StashPayload] {
        var result: [StashPayload] = []
        for provider in providers {
            if let payload = await payload(from: provider) {
                result.append(payload)
            }
        }
        return result
    }

    private static func payload(from provider: NSItemProvider) async -> StashPayload? {
        // 1. A file or folder from Finder or anywhere that drags real files.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await loadFileURL(from: provider) {
            return .file(url)
        }

        // 2. Image bytes (a picture dragged out of a browser or a design app).
        if let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }),
           let data = await loadData(from: provider, identifier: identifier), !data.isEmpty {
            let ext = UTType(identifier)?.preferredFilenameExtension ?? "png"
            return .image(data, fileExtension: ext)
        }

        // 3. A web link.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = await loadURL(from: provider), !url.isFileURL {
            return .url(url)
        }

        // 4. Text; one that is only a link still becomes a link.
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           let text = await loadString(from: provider) {
            return StashPasteboardReader.payload(forText: text)
        }

        // 5. Any other data (a file promise, an attachment): take a copy of it.
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier),
           let url = await loadScratchFile(from: provider) {
            return .scratchFile(url)
        }
        return nil
    }

    // MARK: Loading

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                continuation.resume(returning: url(from: item))
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: url(from: item))
            }
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }

    private static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                if let string = item as? String {
                    continuation.resume(returning: string)
                } else if let data = item as? Data {
                    continuation.resume(returning: String(data: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, identifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// The provider's own file is deleted when its callback returns, so it is
    /// copied somewhere we own straight away.
    private static func loadScratchFile(from provider: NSItemProvider) async -> URL? {
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NotchlyStash-\(UUID().uuidString)", isDirectory: true)
                let name = suggested.map { $0.isEmpty ? url.lastPathComponent : $0 } ?? url.lastPathComponent
                let ext = (name as NSString).pathExtension.isEmpty ? url.pathExtension : ""
                let finalName = ext.isEmpty ? name : "\(name).\(ext)"
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent(finalName)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
