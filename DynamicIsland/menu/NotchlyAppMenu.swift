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

/// The standard macOS About panel, filled in for Notchly.
enum NotchlyAboutPanel {
    static let copyright = "Free software under the GNU GPL-3.0"

    /// Short credits line with links. The plain string is what tests and VoiceOver read.
    static func credits() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]

        let result = NSMutableAttributedString(string: "", attributes: base)

        func append(_ text: String, link: URL? = nil) {
            var attributes = base
            if let link { attributes[.link] = link }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }

        append("Notchly is free software, released under the ")
        append("GPL-3.0", link: NotchlyCredits.licenseURL)
        append(". It is a fork of ")
        append(NotchlyCredits.atoll.name, link: NotchlyCredits.atoll.url)
        append(" by \(NotchlyCredits.atoll.author), which builds on ")
        append(NotchlyCredits.boringNotch.name, link: NotchlyCredits.boringNotch.url)
        append(" by \(NotchlyCredits.boringNotch.author).")
        return result
    }

    @MainActor
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Notchly",
            .credits: credits(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright,
        ])
    }
}

/// Helpers for the "Export Logs" tool.
enum NotchlyLogExport {
    /// Crash reports are named after the executable, which was "Atoll" before it was Notchly.
    static func isCrashReport(_ fileName: String) -> Bool {
        fileName.contains("Notchly") || fileName.contains("Atoll")
    }
}
