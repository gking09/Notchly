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
import AppKit
import Combine
import SwiftUI
import Defaults

/// Runs the Quick Actions row's buttons and owns the little state they share:
/// which inline panel is open, the mute / appearance toggles, and a transient
/// message when something cannot be done.
@MainActor
final class QuickActionsManager: ObservableObject {
    static let shared = QuickActionsManager()

    enum Panel: Equatable {
        case timer
        case stopwatch
    }

    /// The inline panel that has grown out of the row, if any.
    @Published private(set) var openPanel: Panel?
    @Published private(set) var isMicMuted = false
    @Published private(set) var isDarkMode = false
    /// Short, transient message shown in place of the row.
    @Published private(set) var feedback: String?
    /// Minutes the timer picker will start with. Kept for the session only.
    @Published var timerMinutes: Int = 10

    private var feedbackTask: Task<Void, Never>?
    private var appearanceObserver: NSObjectProtocol?

    private init() {
        isDarkMode = Self.systemIsDark()
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isDarkMode = Self.systemIsDark()
            }
        }
    }

    deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    // MARK: State

    private static func systemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Re-reads the state of the toggle actions. Called whenever the row
    /// appears, since the microphone or appearance may have changed elsewhere.
    func refreshSystemState() {
        isMicMuted = MicrophoneMuteController.shared.isMuted()
        isDarkMode = Self.systemIsDark()
    }

    /// Whether the button should draw in its filled ("on") state.
    func isActive(_ action: QuickAction) -> Bool {
        switch action {
        case .timer:
            return openPanel == .timer || TimerManager.shared.isTimerActive
        case .stopwatch:
            return openPanel == .stopwatch || StopwatchManager.shared.isActive
        case .muteMicrophone:
            return isMicMuted
        case .darkMode:
            return isDarkMode
        case .screenshot, .sleepDisplay, .shortcut:
            return false
        }
    }

    // MARK: Panel

    func closePanel() {
        guard openPanel != nil else { return }
        withAnimation(NotchlyTheme.Motion.spring) {
            openPanel = nil
        }
    }

    /// Grows `panel` out of the row (the Hub's timer chip uses this). Leaves an
    /// already-open panel alone rather than closing it, unlike a button press.
    func showPanel(_ panel: Panel) {
        guard openPanel != panel else { return }
        withAnimation(NotchlyTheme.Motion.spring) {
            openPanel = panel
        }
    }

    private func togglePanel(_ panel: Panel) {
        withAnimation(NotchlyTheme.Motion.spring) {
            openPanel = (openPanel == panel) ? nil : panel
        }
    }

    // MARK: Perform

    /// `closeNotch` is called for actions that need the screen clear (the
    /// screenshot selector) so the notch does not sit in the shot.
    func perform(_ action: QuickAction, closeNotch: @escaping () -> Void) {
        switch action {
        case .timer:
            togglePanel(.timer)

        case .stopwatch:
            if openPanel != .stopwatch, StopwatchManager.shared.phase == .idle {
                StopwatchManager.shared.start()
            }
            togglePanel(.stopwatch)

        case .muteMicrophone:
            let target = !isMicMuted
            if MicrophoneMuteController.shared.setMuted(target) {
                withAnimation(NotchlyTheme.Motion.snappy) {
                    isMicMuted = MicrophoneMuteController.shared.isMuted()
                }
            } else {
                showFeedback(String(localized: "This microphone can't be muted from here."))
            }

        case .darkMode:
            toggleDarkMode()

        case .screenshot:
            closeNotch()
            // Let the notch finish closing before the selector appears.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                await self?.run("/usr/sbin/screencapture", ["-i", "-c"]) { _ in }
            }

        case .sleepDisplay:
            closeNotch()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                await self?.run("/usr/bin/pmset", ["displaysleepnow"]) { _ in }
            }

        case .shortcut:
            runShortcut()
        }
    }

    // MARK: Actions

    private func toggleDarkMode() {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        Task { [weak self] in
            await self?.run("/usr/bin/osascript", ["-e", script]) { result in
                guard let self else { return }
                if result.status == 0 {
                    withAnimation(NotchlyTheme.Motion.snappy) {
                        self.isDarkMode.toggle()
                    }
                    // The system notification confirms the real value shortly after.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(500))
                        self?.isDarkMode = Self.systemIsDark()
                    }
                } else if result.stderr.contains("-1743") || result.stderr.localizedCaseInsensitiveContains("not authorized") {
                    self.showFeedback(String(localized: "Allow Notchly to control System Events in Privacy & Security > Automation."))
                } else {
                    self.showFeedback(String(localized: "Couldn't change the appearance."))
                }
            }
        }
    }

    private func runShortcut() {
        let name = Defaults[.quickActionsShortcutName].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            showFeedback(String(localized: "Set a shortcut name in Settings > Quick Actions."))
            return
        }
        Task { [weak self] in
            await self?.run("/usr/bin/shortcuts", ["run", name]) { result in
                guard result.status != 0 else { return }
                self?.showFeedback(String(localized: "Shortcut \"\(name)\" couldn't run."))
            }
        }
    }

    // MARK: Plumbing

    struct CommandResult {
        var status: Int32
        var stderr: String
    }

    /// Runs a command off the main thread and hands the result back on it.
    private func run(
        _ executable: String,
        _ arguments: [String],
        completion: @escaping @MainActor (CommandResult) -> Void
    ) async {
        let result: CommandResult = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            let errorPipe = Pipe()
            process.standardError = errorPipe
            do {
                try process.run()
            } catch {
                return CommandResult(status: -1, stderr: error.localizedDescription)
            }
            // Read before waiting so a chatty process cannot fill the pipe and stall.
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(
                status: process.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }.value
        completion(result)
    }

    private func showFeedback(_ message: String) {
        feedbackTask?.cancel()
        withAnimation(NotchlyTheme.Motion.spring) {
            feedback = message
        }
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(NotchlyTheme.Motion.spring) {
                    self?.feedback = nil
                }
            }
        }
    }
}
