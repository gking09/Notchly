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

import Combine
import Foundation
import UniformTypeIdentifiers

// MARK: - Payload

/// Something about to be stashed, before it has been copied or saved anywhere.
enum StashPayload: Equatable {
    case text(String)
    /// A web (non-file) link.
    case url(URL)
    /// A file or folder that exists on disk: copied, or linked when big.
    case file(URL)
    /// A temporary file we own (e.g. delivered by a drag): moved into the stash.
    case scratchFile(URL)
    /// Raw image bytes with the extension they should be saved under.
    case image(Data, fileExtension: String)
}

enum StashStageError: Error, Equatable {
    case empty
    case textTooLarge
    case unreadable
}

// MARK: - Stager

/// Turns a payload into an item, copying files into the stash directory. Free
/// of main-actor state so large copies can run off the main thread.
struct StashFileStager {
    let directory: URL
    var sizePolicy: StashSizePolicy

    private var fileManager: FileManager { .default }

    /// Folder (relative to `directory`) that holds copied files, one subfolder per item.
    static let filesFolder = "Files"

    func stage(_ payload: StashPayload, id: UUID = UUID(), now: Date) throws -> StashItem {
        switch payload {
        case .text(let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StashStageError.empty
            }
            guard text.utf8.count <= StashLimits.maximumTextBytes else {
                throw StashStageError.textTooLarge
            }
            return StashItem(id: id, kind: .text, createdAt: now, text: text)

        case .url(let url):
            let string = url.absoluteString
            guard !string.isEmpty else { throw StashStageError.empty }
            return StashItem(id: id, kind: .url, createdAt: now, text: string)

        case .file(let url):
            return try stageFile(at: url, id: id, now: now, move: false)

        case .scratchFile(let url):
            return try stageFile(at: url, id: id, now: now, move: true)

        case .image(let data, let fileExtension):
            guard !data.isEmpty else { throw StashStageError.empty }
            let cleanExtension = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            let name = "Image \(Self.timestamp(now)).\(cleanExtension.isEmpty ? "png" : cleanExtension)"
            let folder = directory.appendingPathComponent(Self.filesFolder).appendingPathComponent(id.uuidString)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            } catch {
                try? fileManager.removeItem(at: folder)
                throw error
            }
            let ref = StashFileRef(
                displayName: name,
                byteSize: Int64(data.count),
                isDirectory: false,
                isImage: true,
                storedPath: "\(Self.filesFolder)/\(id.uuidString)/\(name)",
                originalPath: nil,
                bookmark: nil
            )
            return StashItem(id: id, kind: .image, createdAt: now, file: ref)
        }
    }

    // MARK: Files

    private func stageFile(at source: URL, id: UUID, now: Date, move: Bool) throws -> StashItem {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw StashStageError.unreadable
        }
        let name = source.lastPathComponent.isEmpty ? "Item" : source.lastPathComponent
        let isDir = isDirectory.boolValue
        let isImage = !isDir && Self.isImageFile(source)
        let size = Self.byteSize(of: source, isDirectory: isDir, stopAfter: move ? nil : sizePolicy.linkThresholdBytes)

        let decision: StashSizePolicy.Decision = move ? .copy : sizePolicy.decision(forByteSize: size)

        if decision == .copy {
            let folder = directory.appendingPathComponent(Self.filesFolder).appendingPathComponent(id.uuidString)
            do {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(name)
                if move {
                    try fileManager.moveItem(at: source, to: destination)
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
                let ref = StashFileRef(
                    displayName: name,
                    byteSize: size,
                    isDirectory: isDir,
                    isImage: isImage,
                    storedPath: "\(Self.filesFolder)/\(id.uuidString)/\(name)",
                    originalPath: move ? nil : source.path,
                    bookmark: nil
                )
                return StashItem(id: id, kind: .file, createdAt: now, file: ref)
            } catch {
                try? fileManager.removeItem(at: folder)
                // A scratch file has nowhere to be linked to; a real file can still be.
                if move { throw error }
            }
        }

        // Linked: remember where it is, and keep a bookmark so it survives a move.
        let bookmark = try? source.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil)
        let ref = StashFileRef(
            displayName: name,
            byteSize: size,
            isDirectory: isDir,
            isImage: isImage,
            storedPath: nil,
            originalPath: source.path,
            bookmark: bookmark
        )
        return StashItem(id: id, kind: .file, createdAt: now, file: ref)
    }

    /// Size of a file, or of a folder's contents. With `stopAfter`, a folder
    /// scan stops once the total passes it (the exact size no longer matters).
    static func byteSize(of url: URL, isDirectory: Bool, stopAfter limit: Int64?) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if !isDirectory {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if let limit, total > limit { break }
        }
        return total
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }
}

// MARK: - Store

/// What a removal leaves behind until it is committed or undone.
struct StashPendingRemoval: Equatable {
    enum Reason: Equatable {
        case removed
        case cleared
    }

    let reason: Reason
    let items: [StashItem]
}

enum StashAddResult: Equatable {
    case added(StashItem)
    /// Identical text or link already stashed; it was moved to the front.
    case refreshed(StashItem)
    case failed(StashStageError)
}

/// The tray's contents and everything that happens to them: adding, removing
/// with undo, expiry, the item cap, and saving to JSON.
///
/// The directory and the clock are injected so tests can run against a scratch
/// folder and a fake time. Items are newest first.
@MainActor
final class StashStore: ObservableObject {
    @Published private(set) var items: [StashItem] = []
    /// Items removed but not yet deleted from disk; `undoRemoval()` brings them back.
    @Published private(set) var pendingRemoval: StashPendingRemoval?

    let directory: URL
    var configuration: StashConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            if enforceCap() { save() }
        }
    }

    private let now: () -> Date
    private let fileManager = FileManager.default

    static let metadataFileName = "stash.json"
    private static let formatVersion = 1

    init(
        directory: URL,
        configuration: StashConfiguration = StashConfiguration(),
        now: @escaping () -> Date = Date.init
    ) {
        self.directory = directory
        self.configuration = configuration
        self.now = now
    }

    var metadataURL: URL { directory.appendingPathComponent(Self.metadataFileName) }

    func makeStager() -> StashFileStager {
        StashFileStager(directory: directory, sizePolicy: configuration.sizePolicy)
    }

    func fileURL(for item: StashItem) -> URL? {
        item.file?.resolvedURL(in: directory)
    }

    // MARK: Adding

    /// Stages `payload` on the calling thread and inserts it. Use `makeStager()`
    /// plus `insert(_:)` to keep a big copy off the main thread.
    @discardableResult
    func add(_ payload: StashPayload) -> StashAddResult {
        do {
            let item = try makeStager().stage(payload, now: now())
            return insert(item)
        } catch let error as StashStageError {
            return .failed(error)
        } catch {
            return .failed(.unreadable)
        }
    }

    /// Puts a staged item at the front, evicting the oldest past the cap.
    @discardableResult
    func insert(_ item: StashItem) -> StashAddResult {
        // A fresh add ends the undo window of any earlier removal.
        commitPendingRemoval()

        if item.kind == .text || item.kind == .url,
           let index = items.firstIndex(where: { $0.kind == item.kind && $0.text == item.text }) {
            var existing = items.remove(at: index)
            existing.createdAt = item.createdAt
            items.insert(existing, at: 0)
            save()
            return .refreshed(existing)
        }

        items.insert(item, at: 0)
        enforceCap()
        save()
        return .added(item)
    }

    // MARK: Removing

    /// Takes one item out. Its files stay on disk until `commitPendingRemoval()`
    /// so `undoRemoval()` can bring it back.
    @discardableResult
    func remove(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        commitPendingRemoval()
        let item = items.remove(at: index)
        pendingRemoval = StashPendingRemoval(reason: .removed, items: [item])
        save()
        return true
    }

    /// Empties the tray, undoably. Returns how many items went.
    @discardableResult
    func clear() -> Int {
        guard !items.isEmpty else { return 0 }
        commitPendingRemoval()
        let removed = items
        items.removeAll()
        pendingRemoval = StashPendingRemoval(reason: .cleared, items: removed)
        save()
        return removed.count
    }

    /// Brings back whatever the last removal took. Returns how many items came back.
    @discardableResult
    func undoRemoval() -> Int {
        guard let pending = pendingRemoval else { return 0 }
        pendingRemoval = nil
        items = (items + pending.items).sorted { $0.createdAt > $1.createdAt }
        enforceCap()
        save()
        return pending.items.count
    }

    /// Ends the undo window: deletes the files of the last removal.
    func commitPendingRemoval() {
        guard let pending = pendingRemoval else { return }
        pendingRemoval = nil
        for item in pending.items { deleteFiles(of: item) }
    }

    /// Empties the tray for good, with no undo (sleep/lock, quit-time retention).
    func removeAllImmediately() {
        commitPendingRemoval()
        let removed = items
        items.removeAll()
        for item in removed { deleteFiles(of: item) }
        save()
    }

    // MARK: Expiry and cap

    /// Drops everything past its retention, files included. Returns how many went.
    @discardableResult
    func purgeExpired() -> Int {
        let current = now()
        let retention = configuration.retention
        let expired = items.filter { retention.isExpired(createdAt: $0.createdAt, now: current) }
        guard !expired.isEmpty else { return 0 }
        let expiredIDs = Set(expired.map(\.id))
        items.removeAll { expiredIDs.contains($0.id) }
        for item in expired { deleteFiles(of: item) }
        save()
        return expired.count
    }

    /// Evicts the oldest items past the cap. Returns whether anything went.
    @discardableResult
    private func enforceCap() -> Bool {
        let limit = max(1, configuration.maxItems)
        guard items.count > limit else { return false }
        let evicted = Array(items.suffix(items.count - limit))
        items.removeLast(items.count - limit)
        for item in evicted { deleteFiles(of: item) }
        return true
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var version: Int
        var items: [StashItem]
    }

    /// Reads the saved items, then tidies: with "Until I quit" everything goes,
    /// expired items go, items whose copy has vanished go, and any file the
    /// list does not refer to (an interrupted undo window, a crash) is deleted.
    func load() {
        items = []
        pendingRemoval = nil
        if let data = try? Data(contentsOf: metadataURL),
           let snapshot = try? Self.decoder.decode(Snapshot.self, from: data) {
            items = snapshot.items.sorted { $0.createdAt > $1.createdAt }
        }

        let current = now()
        let retention = configuration.retention
        var dropped: [StashItem] = []
        items = items.filter { item in
            if retention.clearsOnLaunch || retention.isExpired(createdAt: item.createdAt, now: current) {
                dropped.append(item)
                return false
            }
            if let file = item.file, !file.isLinked,
               let url = file.resolvedURL(in: directory), !fileManager.fileExists(atPath: url.path) {
                dropped.append(item)
                return false
            }
            return true
        }
        for item in dropped { deleteFiles(of: item) }
        enforceCap()
        sweepOrphans()
        save()
    }

    func save() {
        let snapshot = Snapshot(version: Self.formatVersion, items: items)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            // Never log contents; the failure itself is all that is worth knowing.
            NSLog("Stash: could not save item list (%@)", String(describing: type(of: error)))
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: Files

    private func deleteFiles(of item: StashItem) {
        guard let file = item.file, !file.isLinked else { return }
        let folder = directory
            .appendingPathComponent(StashFileStager.filesFolder)
            .appendingPathComponent(item.id.uuidString)
        try? fileManager.removeItem(at: folder)
    }

    /// Deletes copied-file folders that no item (or pending removal) owns.
    private func sweepOrphans() {
        let root = directory.appendingPathComponent(StashFileStager.filesFolder)
        guard let children = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
        var owned = Set(items.map(\.id.uuidString))
        if let pending = pendingRemoval { owned.formUnion(pending.items.map(\.id.uuidString)) }
        for child in children where !owned.contains(child) {
            try? fileManager.removeItem(at: root.appendingPathComponent(child))
        }
    }
}
