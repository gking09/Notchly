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

/// The one place Notchly reads Foundry's `notch.json`. The Hub chip, the Foundry
/// tab, closed-notch alerts, the quick actions and the status-bar menu all read
/// from this single store, so there is one watcher and one parse.
///
/// Rules it keeps:
/// - Foundry is the only writer. Notchly reads a summary file and never opens
///   Foundry's database; changes go back as `foundry://` URLs.
/// - With the integration switched off (or nothing on screen wanting it), the
///   file is not read, no timer runs and the state is `.off`.
/// - File I/O happens off the main thread; a file that isn't owned by the user,
///   is writable by others, is oversized, is damaged or comes from a newer
///   Foundry is rejected rather than half-trusted.
/// - The refresh is Foundry's ping, plus a slow fallback poll that pauses while
///   the display sleeps (`ActivityGate`). A poll that finds the file unchanged
///   costs one `stat`.
@MainActor
final class FoundryBridge: ObservableObject {
    static let shared = FoundryBridge()

    /// An alert on its way to the wings. The id re-triggers the arrival animation.
    struct ClosedNotice: Equatable, Identifiable {
        let id = UUID()
        let alert: FoundryAlert
    }

    @Published private(set) var state: FoundryFeedState = .off
    @Published private(set) var settings: FoundrySettings
    @Published private(set) var closedAlert: ClosedNotice?

    private let url: URL
    private var pingObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var pingTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var lastInfo: FoundryFeedFileInfo?
    private var lastPollInterval: TimeInterval?
    /// The last good feed this session; the first one only sets it.
    private var baseline: FoundryFeed?
    private var history = FoundryAlertHistory()

    init(url: URL = FoundryFeed.defaultURL) {
        self.url = url
        settings = FoundrySettings.current()

        pingObserver = DistributedNotificationCenter.default().addObserver(
            forName: FoundryFeed.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.foundryPinged() }
        }

        Publishers.MergeMany([
            Defaults.publisher(.foundryIntegration, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.foundryShowTab, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.foundryShowAlerts, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.foundryShowQuickActions, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.foundryShowInMenu, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.hubHiddenChips, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableHub, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableMinimalisticUI, options: []).map { _ in () }.eraseToAnyPublisher(),
        ])
        .debounce(for: .milliseconds(60), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in self?.refreshSettings() }
        .store(in: &cancellables)

        // Re-time the poll when the power state changes, and catch up after the display wakes.
        var wasSuspended = ActivityMonitor.currentGate.isSuspended
        ActivityMonitor.shared.$gate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] gate in
                guard let self else { return }
                let woke = wasSuspended && !gate.isSuspended
                wasSuspended = gate.isSuspended
                self.schedulePoll(gate: gate)
                if woke, self.settings.wantsFeed { self.reload() }
            }
            .store(in: &cancellables)

        refreshSettings()
    }

    // MARK: Derived

    var feed: FoundryFeed? { state.feed }
    var hasFeed: Bool { feed != nil }
    var isInstalled: Bool { FoundryAvailability.snapshot().installed }

    /// The Hub chip, or nil when it is hidden or there is nothing to say.
    var content: FoundryChipContent? {
        settings.showsChip ? FoundryChipContent.make(from: feed) : nil
    }

    /// The Foundry tab shows only when it is allowed and there is a valid feed to show.
    var tabVisible: Bool { settings.allowsTab && hasFeed }

    /// What the status-bar menu shows, or nil while the menu entry is off.
    var menuState: FoundryMenuState? {
        settings.showsInMenu ? FoundryMenuState(feed: feed) : nil
    }

    // MARK: Settings

    /// Re-reads the settings and starts or stops everything accordingly.
    func refreshSettings() {
        let updated = FoundrySettings.current()
        let wasWanting = settings.wantsFeed
        if updated != settings { settings = updated }

        guard updated.wantsFeed else {
            if wasWanting || state != .off { stop() }
            return
        }
        schedulePoll(gate: ActivityMonitor.currentGate)
        if !wasWanting || state == .off {
            reload(force: true)
        }
    }

    /// Switches everything off: nothing read, nothing scheduled, nothing kept.
    private func stop() {
        loadTask?.cancel()
        pingTask?.cancel()
        alertTask?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        lastPollInterval = nil
        lastInfo = nil
        baseline = nil
        history = FoundryAlertHistory()
        closedAlert = nil
        state = .off
    }

    // MARK: Reading

    /// Foundry says the feed changed. Several pings in a burst collapse into one read.
    private func foundryPinged() {
        // A first feed in `auto` mode is what turns the integration on.
        FoundryAvailability.invalidate()
        refreshSettings()
        guard settings.wantsFeed else { return }
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    /// Reads the feed off the main thread. Skipped entirely while nothing wants it.
    func reload(force: Bool = false) {
        guard settings.wantsFeed else {
            if state != .off { stop() }
            return
        }
        loadTask?.cancel()
        let url = url
        let previous = lastInfo
        let skipUnchanged = !force && state.feed != nil
        loadTask = Task { [weak self] in
            let outcome: (load: FoundryFeedLoad, info: FoundryFeedFileInfo?)? = await Task.detached(priority: .utility) {
                let info = FoundryFeedLoader.info(at: url)
                if skipUnchanged, let info, let previous, info.modified == previous.modified, info.size == previous.size {
                    return nil
                }
                return (FoundryFeedLoader.load(at: url), info)
            }.value
            guard !Task.isCancelled, let self, let outcome, self.settings.wantsFeed else { return }
            self.apply(outcome.load, info: outcome.info)
        }
    }

    private func apply(_ load: FoundryFeedLoad, info: FoundryFeedFileInfo?) {
        lastInfo = info
        let new = FoundryFeedState(load: load)
        if new != state { state = new }
        if case .loaded(let feed, _) = new { considerAlert(for: feed) }
    }

    // MARK: Fallback poll

    private func schedulePoll(gate: ActivityGate) {
        let interval = FoundryPolling.interval(wantsFeed: settings.wantsFeed, gate: gate)
        guard interval != lastPollInterval || (interval != nil && pollTimer == nil) else { return }
        lastPollInterval = interval
        pollTimer?.invalidate()
        pollTimer = nil
        guard let interval else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        timer.tolerance = ActivityGate.tolerance(for: interval, fraction: 0.2, minimum: 10)
        pollTimer = timer
    }

    // MARK: Alerts

    private func considerAlert(for feed: FoundryFeed) {
        let previous = baseline
        baseline = feed
        guard settings.alertsEnabled else { return }
        let now = Date()
        guard let alert = FoundryAlertPlanner.plan(previous: previous, new: feed, history: history, now: now) else { return }
        history.record(alert, at: now)
        present(alert)
    }

    private func present(_ alert: FoundryAlert) {
        alertTask?.cancel()
        closedAlert = ClosedNotice(alert: alert)
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(FoundryAlertPlanner.displayDuration))
            guard !Task.isCancelled else { return }
            self?.closedAlert = nil
        }
    }

    // MARK: Actions (Foundry does the work and confirms in its own window)

    /// Brings Foundry forward.
    func openApp() {
        NSWorkspace.shared.open(FoundryLink.open)
    }

    func openProject(_ id: String?) {
        NSWorkspace.shared.open(id.flatMap(FoundryLink.project) ?? FoundryLink.open)
    }

    /// The chip's click: the project it is about, or Foundry itself.
    func openInFoundry() {
        openProject(content?.projectId)
    }

    /// Opens the project of the suggested next step (or Foundry, when there is none).
    func openNextUp() {
        if let feed {
            openProject(feed.nextUp?.projectId)
            return
        }
        // Not loaded (the integration is idle): read once, off the main thread, then go.
        let url = url
        Task { [weak self] in
            let load = await Task.detached(priority: .userInitiated) { FoundryFeedLoader.load(at: url) }.value
            if case .loaded(let feed, _) = load {
                self?.openProject(feed.nextUp?.projectId)
            } else {
                self?.openApp()
            }
        }
    }

    /// Asks Foundry to complete a task. Foundry confirms in its own window, with Undo.
    func completeTask(_ id: String) {
        guard let link = FoundryLink.completeTask(id) else { return }
        openInBackground(link)
    }

    /// Asks Foundry to put a suggestion off.
    func deferRecommendation(key: String, days: Int) {
        guard let link = FoundryLink.deferRecommendation(key, days: days) else { return }
        openInBackground(link)
    }

    func markDone() {
        guard let id = content?.completableTaskId else { return }
        completeTask(id)
    }

    func later() {
        guard let key = content?.recommendationKey else { return }
        deferRecommendation(key: key, days: 1)
    }

    /// Sends an action without taking focus from whatever the user is doing.
    private func openInBackground(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error { NSLog("Notchly: couldn't reach Foundry: \(error.localizedDescription)") }
        }
    }
}
