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
import Combine
import Defaults
import Foundation
import SwiftUI

/// A short message for the closed notch (the "+1" confirmation and its cousins).
struct StashClosedNotice: Equatable, Identifiable {
    let id = UUID()
    let symbol: String
    let label: String

    static func added(_ count: Int) -> StashClosedNotice {
        StashClosedNotice(symbol: "tray.and.arrow.down.fill", label: "+\(max(count, 1))")
    }

    static var blocked: StashClosedNotice {
        StashClosedNotice(symbol: "lock.fill", label: String(localized: "Private"))
    }

    static var nothingToAdd: StashClosedNotice {
        StashClosedNotice(symbol: "tray", label: String(localized: "Empty"))
    }
}

/// A line of feedback inside the open Stash tab.
struct StashToast: Equatable, Identifiable {
    let id = UUID()
    let message: String
    /// Whether the toast carries an Undo button (a removal is waiting to be committed).
    let offersUndo: Bool
}

/// Owns the Stash for the running app: the store, its settings, the timers,
/// and every way an item arrives or leaves (drops, clipboard, drag-out).
///
/// It reads the pasteboard only when asked and never writes item contents to
/// the log.
@MainActor
final class StashManager: ObservableObject {
    static let shared = StashManager()

    let store: StashStore

    /// A drag carrying something we accept is over the notch.
    @Published var isDropTargeted = false
    /// Brief closed-notch confirmation, nil when none is showing.
    @Published private(set) var closedNotice: StashClosedNotice?
    @Published private(set) var toast: StashToast?
    /// The item that was just copied back; drives the "Copied" confirmation.
    @Published private(set) var copiedItemID: UUID?
    /// An item is being dragged out of the notch; keeps the notch from closing mid-drag.
    @Published private(set) var isDraggingOut = false

    static let undoWindow: TimeInterval = 5
    static let noticeDuration: TimeInterval = 1.5
    static let copiedDuration: TimeInterval = 1.3

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var observerTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var expiryTimer: Timer?
    private var noticeTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?
    private var copiedTask: Task<Void, Never>?
    private var dragEndTask: Task<Void, Never>?
    private var dragMonitors: [Any] = []

    init(store: StashStore? = nil) {
        self.store = store ?? StashStore(directory: Self.defaultDirectory, configuration: Self.currentConfiguration())
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Notchly", isDirectory: true).appendingPathComponent("Stash", isDirectory: true)
    }

    static func currentConfiguration() -> StashConfiguration {
        StashConfiguration(
            retention: Defaults[.stashRetention],
            maxItems: StashLimits.clampedMaxItems(Defaults[.stashMaxItems]),
            sizePolicy: StashSizePolicy(megabytes: Defaults[.stashLinkThresholdMB])
        )
    }

    var isEnabled: Bool { Defaults[.enableStash] }

    // MARK: Lifecycle

    /// Loads the saved items (purging what has expired) and starts the timers.
    func start() {
        guard !started else { return }
        started = true

        store.configuration = Self.currentConfiguration()
        store.load()

        Publishers.MergeMany(
            Defaults.publisher(.stashRetention, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.stashMaxItems, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.stashLinkThresholdMB, options: []).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            guard let self else { return }
            self.store.configuration = Self.currentConfiguration()
            self.store.purgeExpired()
        }
        .store(in: &cancellables)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.purgeExpired() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer

        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidSleepNotification)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
    }

    /// Makes the exit tidy: ends any undo window and, for "Until I quit", empties the tray.
    func appWillTerminate() {
        undoTask?.cancel()
        store.commitPendingRemoval()
        if store.configuration.retention.clearsOnLaunch {
            store.removeAllImmediately()
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.deviceDidSleepOrLock() }
        }
        observerTokens.append((center, token))
    }

    private func deviceDidSleepOrLock() {
        guard Defaults[.stashClearOnSleepOrLock] else { return }
        store.removeAllImmediately()
    }

    // MARK: Adding

    /// One-shot, user-initiated read of the pasteboard.
    func addFromClipboard() {
        guard isEnabled else { return }
        let snapshot = StashPasteboardSnapshot(pasteboard: .general)
        switch StashPasteboardReader.read(snapshot) {
        case .payloads(let payloads):
            ingest(payloads)
        case .concealed:
            announce(.blocked)
            showToast(String(localized: "Clipboard is marked private. Nothing was stashed."))
        case .empty:
            announce(.nothingToAdd)
            showToast(String(localized: "Nothing on the clipboard to stash."))
        }
    }

    /// Reads what a drag delivered and stashes it.
    func ingest(providers: [NSItemProvider]) {
        guard isEnabled, !providers.isEmpty else { return }
        Task {
            let payloads = await StashDropReader.payloads(from: providers)
            ingest(payloads)
        }
    }

    /// Stages the payloads off the main thread (big copies must not stall the
    /// UI), then inserts them. The first payload ends up first in the tray.
    func ingest(_ payloads: [StashPayload]) {
        guard isEnabled, !payloads.isEmpty else { return }
        let stager = store.makeStager()
        let base = Date()
        Task {
            let outcomes: [StashItem?] = await Task.detached(priority: .userInitiated) {
                payloads.enumerated().map { index, payload in
                    // Earlier payloads get later timestamps so they sort to the front.
                    let stamp = base.addingTimeInterval(Double(payloads.count - 1 - index) * 0.001)
                    return try? stager.stage(payload, now: stamp)
                }
            }.value

            var added = 0
            for item in outcomes.compactMap({ $0 }).reversed() {
                store.insert(item)
                added += 1
            }

            // A new item closes the undo window of any earlier removal.
            if toast?.offersUndo == true { dismissToast() }

            if added > 0 {
                announce(.added(added))
            } else {
                showToast(String(localized: "Couldn't stash that."))
            }
        }
    }

    // MARK: Removing

    func remove(_ item: StashItem) {
        guard store.remove(id: item.id) else { return }
        offerUndo(message: String(localized: "Removed"))
    }

    func clearAll() {
        guard store.clear() > 0 else { return }
        offerUndo(message: String(localized: "Cleared"))
    }

    func undo() {
        undoTask?.cancel()
        store.undoRemoval()
        dismissToast()
    }

    private func offerUndo(message: String) {
        showToast(message, offersUndo: true, duration: Self.undoWindow)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled else { return }
            self?.store.commitPendingRemoval()
        }
    }

    // MARK: Copy back

    func copy(_ item: StashItem) {
        let wrote = StashPasteboardWriter.write(item, fileURL: store.fileURL(for: item))
        guard wrote else {
            showToast(String(localized: "That file is no longer available."))
            return
        }
        withAnimation(NotchlyTheme.Motion.pop) { copiedItemID = item.id }
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.copiedDuration))
            guard !Task.isCancelled else { return }
            withAnimation(NotchlyTheme.Motion.spring) { self?.copiedItemID = nil }
        }
    }

    // MARK: Drag out

    /// What a card hands to another app when it is dragged out. Files go as
    /// copies (never a move of our stash copy or of a linked original).
    func dragProvider(for item: StashItem) -> NSItemProvider {
        beginDragOut()
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .url:
            if let url = item.webURL { return NSItemProvider(object: url as NSURL) }
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .file, .image:
            if let url = store.fileURL(for: item), FileManager.default.fileExists(atPath: url.path) {
                return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider(object: item.title as NSString)
        }
    }

    private func beginDragOut() {
        isDraggingOut = true
        dragEndTask?.cancel()
        // The drag loop swallows most events, so the mouse-up that ends it may
        // only be seen by a monitor; a timeout covers the case where it is not.
        if dragMonitors.isEmpty {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
                Task { @MainActor in self?.endDragOut(after: 0.4) }
            }) { dragMonitors.append(global) }
            if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
                Task { @MainActor in self?.endDragOut(after: 0.4) }
                return event
            }) { dragMonitors.append(local) }
        }
        endDragOut(after: 30)
    }

    private func endDragOut(after delay: TimeInterval) {
        dragEndTask?.cancel()
        dragEndTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.dragMonitors.forEach { NSEvent.removeMonitor($0) }
            self.dragMonitors.removeAll()
            self.isDraggingOut = false
        }
    }

    // MARK: Feedback

    private func announce(_ notice: StashClosedNotice) {
        noticeTask?.cancel()
        closedNotice = notice
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.noticeDuration))
            guard !Task.isCancelled else { return }
            self?.closedNotice = nil
        }
    }

    func showToast(_ message: String, offersUndo: Bool = false, duration: TimeInterval = 2.5) {
        toastTask?.cancel()
        withAnimation(NotchlyTheme.Motion.spring) {
            toast = StashToast(message: message, offersUndo: offersUndo)
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismissToast()
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(NotchlyTheme.Motion.spring) { toast = nil }
    }
}
