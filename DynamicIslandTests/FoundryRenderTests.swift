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
import SwiftUI
import XCTest
@testable import Notchly

/// Draws the Foundry surfaces to PNGs for eyeballing. Skipped unless
/// `NOTCHLY_RENDER_DIR` is set (pass it as `TEST_RUNNER_NOTCHLY_RENDER_DIR=/some/dir`).
final class FoundryRenderTests: XCTestCase {

    private func directory() throws -> String {
        guard let directory = ProcessInfo.processInfo.environment["NOTCHLY_RENDER_DIR"], !directory.isEmpty else {
            throw XCTSkip("NOTCHLY_RENDER_DIR not set")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Draws `view` over the notch's black, scaled 2x so small type can be read.
    private func render<V: View>(_ view: V, size: CGSize, name: String, in directory: String, wait: TimeInterval = 1.4) throws {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: framed)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }

    private let now = Date()

    private func project(_ name: String, _ health: String, _ phase: String?, _ completion: Double?, _ forecast: String?) -> FoundryFeed.Project {
        FoundryFeed.Project(id: name, name: name, health: health, healthLabel: nil, phase: phase, scopeCompletion: completion, forecast: forecast)
    }

    private func feed(attention: FoundryFeed.Attention = .none, updated: Date? = nil) -> FoundryFeed {
        FoundryFeed(
            version: 1,
            updatedAt: updated ?? now.addingTimeInterval(-600),
            nextUp: .init(key: "task:abc", subjectId: "abc", title: "Finish \u{201C}Lightbox viewer\u{201D} keyboard navigation",
                          projectId: "p1", projectName: "Harper Photography site", reasons: ["In progress", "Due Friday"], canComplete: true),
            projects: [
                project("Placely", "blocked", "Building", 0.35, "9 Nov \u{2013} 10 Dec"),
                project("Harper Photography site", "atRisk", "Review", 0.82, "12 Nov \u{2013} 26 Nov"),
                project("Notchly", "onTrack", "Polish", 0.64, "30 Nov"),
                project("Foundry", "onTrack", "Building", 0.4, "Needs estimates"),
                project("Receipts", "onHold", nil, nil, "On hold"),
            ],
            attention: attention
        )
    }

    private var tabSize: CGSize { CGSize(width: 592, height: 162) }

    func testRenderFoundryTabStatesToPNG() throws {
        let dir = try directory()
        let critical = FoundryFeed.Attention(count: 3, topTitle: "\u{201C}Beta\u{201D} is 6 days overdue", topSeverity: "critical", topProjectName: "Placely")
        let warning = FoundryFeed.Attention(count: 1, topTitle: "Quiet for 15 days", topSeverity: "warning", topProjectName: "Notchly")

        func tab(_ state: FoundryFeedState, preview: FoundryHeroPreview = .none) -> some View {
            FoundryTabContent(model: FoundryTabModel.make(state: state, now: now), now: now, heroPreview: preview)
        }

        try render(tab(.loaded(feed(), modified: now)), size: tabSize, name: "tab-1-normal", in: dir)
        try render(tab(.loaded(feed(attention: critical), modified: now)), size: tabSize, name: "tab-2-attention-critical", in: dir)
        try render(tab(.loaded(feed(attention: warning), modified: now)), size: tabSize, name: "tab-3-attention-warning", in: dir)
        try render(tab(.loaded(feed(), modified: now), preview: .confirming), size: tabSize, name: "tab-4-confirming", in: dir)
        try render(tab(.loaded(feed(), modified: now), preview: .choosingDelay), size: tabSize, name: "tab-5-later", in: dir)
        let old = now.addingTimeInterval(-3 * 86_400)
        try render(tab(.loaded(feed(updated: old), modified: old)), size: tabSize, name: "tab-6-stale", in: dir)
        try render(tab(.notFound), size: tabSize, name: "tab-7-nofeed", in: dir)
        try render(tab(.unsupported(2)), size: tabSize, name: "tab-8-unsupported", in: dir)
        let empty = FoundryFeed(version: 1, updatedAt: now, nextUp: nil, projects: [], attention: .none)
        try render(tab(.loaded(empty, modified: now)), size: tabSize, name: "tab-9-empty", in: dir)
        // The narrowest the notch gets (640 less its insets) and a long next step.
        try render(tab(.loaded(feed(attention: critical), modified: now)), size: CGSize(width: 520, height: 162), name: "tab-10-narrow", in: dir)
    }

    func testRenderFoundryClosedAlertToPNG() throws {
        let dir = try directory()
        func wings(_ alert: FoundryAlert) -> some View {
            let notch: CGFloat = 190
            let wing: CGFloat = 120
            return HStack(spacing: 0) {
                HStack { Spacer(minLength: 0); FoundryAlertGlyph(severity: alert.severity, size: 20) }
                    .frame(width: wing)
                Color(white: 0.12).frame(width: notch)
                HStack { FoundryAlertLabel(text: alert.label); Spacer(minLength: 0) }
                    .frame(width: wing)
            }
            .frame(height: 38)
        }
        let critical = FoundryAlert(key: "k", severity: .critical, title: "\u{201C}Beta\u{201D} is 6 days overdue", projectName: "Placely", count: 1)
        let several = FoundryAlert(key: "k", severity: .warning, title: "x", projectName: nil, count: 3)
        let info = FoundryAlert(key: "k", severity: .info, title: "Quiet", projectName: nil, count: 1)
        try render(wings(critical), size: CGSize(width: 440, height: 38), name: "alert-1-critical", in: dir, wait: 0.3)
        try render(wings(several), size: CGSize(width: 440, height: 38), name: "alert-2-several", in: dir, wait: 0.3)
        try render(wings(info), size: CGSize(width: 440, height: 38), name: "alert-3-info", in: dir, wait: 0.3)
    }
}
