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

import SwiftUI

// MARK: - Colour

/// Foundry's tab is monochrome like the rest of the notch. Health and severity
/// get a hint of colour, muted and on top of a distinct shape, never instead of one.
enum FoundryPalette {
    static let good = Color(.sRGB, red: 0.56, green: 0.82, blue: 0.66, opacity: 0.95)
    static let caution = Color(.sRGB, red: 0.96, green: 0.76, blue: 0.42, opacity: 0.95)
    static let bad = Color(.sRGB, red: 0.96, green: 0.52, blue: 0.50, opacity: 0.95)

    static func color(for tone: FoundryHealth.Tone) -> Color {
        switch tone {
        case .good: return good
        case .caution: return caution
        case .bad: return bad
        case .neutral: return NotchlyTheme.Palette.silverDim
        }
    }

    static func color(for severity: FoundrySeverity) -> Color {
        switch severity {
        case .critical: return bad
        case .warning: return caution
        case .info: return NotchlyTheme.Palette.silverDim
        }
    }
}

// MARK: - Actions

/// What the tab can ask for. The live tab wires these to `FoundryBridge`; a
/// render test passes empty ones.
struct FoundryTabActions {
    var openApp: () -> Void = {}
    var openProject: (String) -> Void = { _ in }
    var completeTask: (String) -> Void = { _ in }
    var deferRecommendation: (String, Int) -> Void = { _, _ in }
    var openSettings: () -> Void = {}

    @MainActor static func live(_ bridge: FoundryBridge) -> FoundryTabActions {
        FoundryTabActions(
            openApp: { bridge.openApp() },
            openProject: { bridge.openProject($0) },
            completeTask: { bridge.completeTask($0) },
            deferRecommendation: { bridge.deferRecommendation(key: $0, days: $1) },
            openSettings: { SettingsWindowController.shared.showWindow(page: .foundry) }
        )
    }
}

// MARK: - Tab

/// The Foundry tab: the next step as a hero card, up to five projects, and a
/// banner when something needs attention.
struct FoundryView: View {
    @ObservedObject private var bridge = FoundryBridge.shared

    var body: some View {
        let now = Date()
        FoundryTabContent(
            model: FoundryTabModel.make(state: bridge.state, now: now),
            now: now,
            actions: .live(bridge)
        )
    }
}

/// A state of the hero card to start in, for drawing it without clicking.
enum FoundryHeroPreview {
    case none
    /// Complete has been tapped once and reads "Confirm?".
    case confirming
    /// Later is open, offering how long.
    case choosingDelay
}

/// The tab's content, driven by a model alone so it can be drawn without the live store.
struct FoundryTabContent: View {
    let model: FoundryTabModel
    var now: Date = Date()
    var actions = FoundryTabActions()
    var heroPreview: FoundryHeroPreview = .none

    var body: some View {
        VStack(spacing: FoundryTabMetrics.sectionSpacing) {
            FoundryHeader(model: model, now: now, actions: actions)
                .staggered(index: 0)

            ZStack {
                switch model.mode {
                case .content:
                    FoundryBody(model: model, actions: actions, heroPreview: heroPreview)
                        .transition(.opacity)
                case .empty:
                    FoundryMessage(
                        symbol: "square.stack.3d.up",
                        title: String(localized: "Nothing to show yet"),
                        detail: String(localized: "Add a project in Foundry and it will show up here."),
                        actions: actions,
                        showsSettings: false
                    )
                    .transition(.opacity)
                case .noFeed(let reason):
                    FoundryMessage(
                        symbol: "square.stack.3d.up.slash",
                        title: reason.title,
                        detail: reason.detail,
                        actions: actions,
                        showsSettings: true
                    )
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(FoundryTabMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchlyTheme.Motion.spring, value: model.mode)
    }
}

// MARK: - Header

private struct FoundryHeader: View {
    let model: FoundryTabModel
    let now: Date
    let actions: FoundryTabActions

    var body: some View {
        HStack(spacing: NotchlyTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("Foundry")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                if !model.rows.isEmpty {
                    Text("\(model.rows.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                        .contentTransition(.numericText())
                        .animation(NotchlyTheme.Motion.spring, value: model.rows.count)
                }
            }

            if model.isStale, let text = model.updatedText(now: now) {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(text)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                }
                .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                .help("Foundry only rewrites its summary when something changes, so a quiet summary gets old.")
                .transition(.opacity)
            }

            if let banner = model.banner {
                FoundryBanner(banner: banner) { actions.openProject(banner.projectId ?? "") }
                    .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            // The empty and no-summary states carry their own Open Foundry button.
            if model.mode == .content {
                Button(action: actions.openApp) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Open Foundry")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .contentShape(Capsule())
                }
                .buttonStyle(.notchlyGlass)
                .help("Open Foundry")
                .transition(.opacity)
            }
        }
        .frame(height: FoundryTabMetrics.headerHeight)
        .animation(NotchlyTheme.Motion.spring, value: model.banner)
        .animation(NotchlyTheme.Motion.spring, value: model.isStale)
    }
}

/// The attention strip: the most severe warning, how many more there are, and a
/// tap through to its project.
private struct FoundryBanner: View {
    let banner: FoundryTabModel.Banner
    let action: () -> Void

    /// As wide as its contents, never more than 300pt, and free to shrink.
    static func naturalWidth(of banner: FoundryTabModel.Banner) -> CGFloat {
        let title = NotchWingLayout.textWidth(banner.title, font: .systemFont(ofSize: 11, weight: .medium))
        let more = banner.count > 1 ? 6 + NotchWingLayout.textWidth("+\(banner.count - 1)", font: .systemFont(ofSize: 10, weight: .semibold)) : 0
        return min(300, 20 + 10 + 6 + title + more + 4)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: banner.severity == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FoundryPalette.color(for: banner.severity))
                Text(banner.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if banner.count > 1 {
                    Text("+\(banner.count - 1)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .frame(maxWidth: Self.naturalWidth(of: banner))
            .contentShape(Capsule())
        }
        .buttonStyle(.notchlyGlass)
        .animation(NotchlyTheme.Motion.spring, value: banner.count)
        .help(banner.projectName.map { "\($0): \(banner.title)" } ?? banner.title)
        .accessibilityLabel(Text(banner.projectName.map { "\($0): \(banner.title)" } ?? banner.title))
    }
}

// MARK: - Body

private struct FoundryBody: View {
    let model: FoundryTabModel
    let actions: FoundryTabActions
    var heroPreview: FoundryHeroPreview = .none

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let hero = model.hero {
                    FoundryHeroCard(hero: hero, actions: actions, preview: heroPreview)
                } else {
                    FoundryQuietCard(text: String(localized: "Nothing suggested right now"))
                }
            }
            .frame(width: FoundryTabMetrics.heroWidth, height: FoundryTabMetrics.bodyHeight)
            .staggered(index: 1)

            Group {
                if model.rows.isEmpty {
                    FoundryQuietCard(text: String(localized: "No active projects"))
                } else {
                    GeometryReader { geo in
                        let showsPhase = FoundryTabMetrics.showsPhase(rowsWidth: geo.size.width)
                        VStack(spacing: FoundryTabMetrics.rowSpacing) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                                FoundryProjectRow(row: row, showsPhase: showsPhase) { actions.openProject(row.id) }
                                    .staggered(index: index + 2, offset: 6, blur: 3)
                                    .transition(NotchlyTheme.Motion.reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .leading)))
                            }
                        }
                        .animation(NotchlyTheme.Motion.spring, value: model.rows.map(\.id))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: FoundryTabMetrics.bodyHeight, alignment: .top)
        }
        .frame(height: FoundryTabMetrics.bodyHeight)
    }
}

private struct FoundryQuietCard: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(NotchlyTheme.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassSurface(cornerRadius: NotchlyTheme.Radius.md)
    }
}

// MARK: - Hero

/// What the hero card's button row is doing.
private enum FoundryHeroPhase: Equatable {
    case idle
    /// "Later" is open, offering how long.
    case choosingDelay
    /// Something was sent to Foundry.
    case sent(String)
}

private struct FoundryHeroCard: View {
    let hero: FoundryTabModel.Hero
    let actions: FoundryTabActions

    @State private var phase: FoundryHeroPhase
    @State private var completion: FoundryTwoStep
    @State private var disarmTask: Task<Void, Never>?
    @State private var resetTask: Task<Void, Never>?
    @Namespace private var glass

    init(hero: FoundryTabModel.Hero, actions: FoundryTabActions, preview: FoundryHeroPreview = .none) {
        self.hero = hero
        self.actions = actions
        var step = FoundryTwoStep()
        if preview == .confirming { _ = step.tap(at: Date()) }
        _completion = State(initialValue: step)
        _phase = State(initialValue: preview == .choosingDelay ? .choosingDelay : .idle)
    }

    private var isArmed: Bool { completion.isArmed(at: Date()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("NEXT UP")
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(NotchlyTheme.Palette.textTertiary)

            Text(hero.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text(hero.projectName)
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .layoutPriority(2)
                if !hero.reasons.isEmpty {
                    Text("\u{00B7}").foregroundStyle(NotchlyTheme.Palette.textTertiary)
                    Text(hero.reasons).foregroundStyle(NotchlyTheme.Palette.textTertiary)
                }
            }
            .font(.system(size: 10.5))
            .lineLimit(1)
            .truncationMode(.tail)

            Spacer(minLength: 2)

            buttons
                .frame(height: 24)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassSurface(cornerRadius: NotchlyTheme.Radius.md)
        .animation(NotchlyTheme.Motion.spring, value: phase)
        .animation(NotchlyTheme.Motion.snappy, value: isArmed)
        .onDisappear {
            disarmTask?.cancel()
            resetTask?.cancel()
        }
    }

    // MARK: Buttons

    @ViewBuilder private var buttons: some View {
        switch phase {
        case .idle:
            HStack(spacing: 6) {
                pill(String(localized: "Open"), symbol: "arrow.up.forward") {
                    actions.openProject(hero.projectId)
                }

                if let taskId = hero.completableTaskId {
                    completeButton(taskId: taskId)
                }

                Button {
                    disarm()
                    phase = .choosingDelay
                } label: {
                    label(String(localized: "Later"), symbol: "clock", filled: false)
                        .background {
                            Capsule().fill(NotchlyTheme.Palette.glassFill)
                                .matchedGeometryEffect(id: "later.glass", in: glass)
                        }
                }
                .buttonStyle(.notchlyPress)
                .help("Put this off for a while")
                Spacer(minLength: 0)
            }
            .transition(.opacity)

        case .choosingDelay:
            HStack(spacing: 2) {
                Button {
                    phase = .idle
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                        .frame(width: 22, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.notchlyPress)
                .accessibilityLabel(Text("Back"))

                ForEach(FoundryDeferOption.allCases, id: \.days) { option in
                    Button {
                        defer_(option)
                    } label: {
                        Text(option.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.92))
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(GlassButtonStyle(variant: .capsule, alwaysVisible: false))
                    .help("Hide this suggestion for \(option.title)")
                }
            }
            .padding(.horizontal, 2)
            .background {
                Capsule().fill(NotchlyTheme.Palette.glassFill)
                    .overlay { Capsule().strokeBorder(NotchlyTheme.Palette.glassStroke, lineWidth: NotchlyTheme.Stroke.hairline) }
                    .matchedGeometryEffect(id: "later.glass", in: glass, isSource: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)

        case .sent(let message):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
            .transition(.scale(scale: 0.95, anchor: .leading).combined(with: .opacity))
        }
    }

    private func label(_ title: String, symbol: String?, filled: Bool) -> some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(filled ? Color.black : NotchlyTheme.Palette.textPrimary.opacity(0.92))
        .padding(.horizontal, 8)
        .frame(height: 24)
        .contentShape(Capsule())
    }

    private func pill(_ title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label(title, symbol: symbol, filled: false)
        }
        .buttonStyle(.notchlyGlass)
    }

    /// Complete changes data, so it takes two taps: the first turns the button
    /// into "Confirm?" for three seconds, the second sends the request.
    private func completeButton(taskId: String) -> some View {
        Button {
            switch completion.tap(at: Date()) {
            case .armed:
                scheduleDisarm()
            case .confirmed:
                disarm()
                actions.completeTask(taskId)
                sent(String(localized: "Sent to Foundry"))
            }
        } label: {
            label(isArmed ? String(localized: "Confirm?") : String(localized: "Complete"),
                  symbol: isArmed ? "checkmark" : "checkmark.circle",
                  filled: isArmed)
                .background {
                    Capsule()
                        .fill(isArmed ? Color.white : NotchlyTheme.Palette.glassFill)
                }
                .contentTransition(.interpolate)
        }
        .buttonStyle(.notchlyPress)
        .help(isArmed ? "Click again to mark this task done in Foundry" : "Mark this task done (asks to confirm)")
    }

    // MARK: State

    private func scheduleDisarm() {
        disarmTask?.cancel()
        disarmTask = Task {
            try? await Task.sleep(for: .seconds(FoundryTwoStep.window))
            guard !Task.isCancelled else { return }
            await MainActor.run { disarm() }
        }
    }

    private func disarm() {
        disarmTask?.cancel()
        withAnimation(NotchlyTheme.Motion.snappy) { completion.cancel() }
    }

    private func defer_(_ option: FoundryDeferOption) {
        actions.deferRecommendation(hero.key, option.days)
        sent(String(localized: "Later: \(option.title)"))
    }

    private func sent(_ message: String) {
        phase = .sent(message)
        resetTask?.cancel()
        resetTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run { phase = .idle }
        }
    }
}

// MARK: - Project row

private struct FoundryProjectRow: View {
    let row: FoundryTabModel.Row
    var showsPhase = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: row.health.glyph)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(FoundryPalette.color(for: row.health.tone))
                    .frame(width: 12)
                    .help(row.healthLabel)

                Text(row.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.94))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if showsPhase, let phase = row.phase {
                    Text(phase)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 58, alignment: .trailing)
                }

                NotchlyProgressBar(progress: row.progress ?? 0, height: 3)
                    .frame(width: 34)
                    .opacity(row.progress == nil ? 0.5 : 1)
                    .animation(NotchlyTheme.Motion.spring, value: row.progress)

                Text(row.progressText ?? "\u{2013}")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .contentTransition(.numericText())
                    .animation(NotchlyTheme.Motion.spring, value: row.progressText)
                    .frame(width: 26, alignment: .trailing)

                Text(row.forecast ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 80, alignment: .trailing)
            }
            .padding(.horizontal, 6)
            .frame(height: FoundryTabMetrics.rowHeight)
            .background {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.xs, style: .continuous)
                    .fill(isHovering ? NotchlyTheme.Palette.glassFillHover : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.notchlyPress)
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(row.name), \(row.healthLabel)"))
        .accessibilityValue(Text([row.phase, row.progressText, row.forecast].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text("Opens the project in Foundry"))
    }
}

// MARK: - Messages

/// Empty, stale-free "no summary" and error states: a glyph, what is going on,
/// and the two things to do about it.
private struct FoundryMessage: View {
    let symbol: String
    let title: String
    let detail: String
    let actions: FoundryTabActions
    let showsSettings: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.88))
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button(action: actions.openApp) {
                    Text("Open Foundry")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .contentShape(Capsule())
                }
                .buttonStyle(.notchlyGlass)

                if showsSettings {
                    Button(action: actions.openSettings) {
                        Text("Foundry settings")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.notchlyPress)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
