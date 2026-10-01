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
import Defaults
import SwiftUI

// MARK: - Adaptive tokens
//
// The notch is always black, so `NotchlyTheme.Palette` is white-on-black. The
// settings window follows the system appearance instead, so these tokens are the
// same soft-glass, monochrome language expressed as dynamic colours: silver-white
// on dark, graphite on light. Radii, spacing, hairlines and springs still come from
// `NotchlyTheme`.

enum NotchlySettingsStyle {
    /// A colour that resolves differently in light and dark appearances.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    /// The single "accent": near-white on dark, near-black on light. Never a hue.
    static let accent = adaptive(
        light: NSColor(white: 0.12, alpha: 1),
        dark: NSColor(red: 0.93, green: 0.94, blue: 0.97, alpha: 1)
    )
    /// Text / glyph colour that sits on top of `accent`.
    static let onAccent = adaptive(
        light: NSColor(white: 0.98, alpha: 1),
        dark: NSColor(white: 0.08, alpha: 1)
    )

    static let cardFill = adaptive(light: NSColor(white: 1, alpha: 0.58), dark: NSColor(white: 1, alpha: 0.06))
    static let cardStroke = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.11))
    static let cardHighlight = adaptive(light: NSColor(white: 1, alpha: 0.7), dark: NSColor(white: 1, alpha: 0.09))
    static let rowHover = adaptive(light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.045))
    static let divider = adaptive(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.08))
    static let controlFill = adaptive(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.10))
    static let controlFillHover = adaptive(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.16))
    static let controlFillPressed = adaptive(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.21))
    static let track = adaptive(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.16))

    static let textSecondary = Color.primary.opacity(0.62)
    static let textTertiary = Color.primary.opacity(0.4)
}

// MARK: - Page header

/// Large page title with a quiet subtitle underneath.
struct NotchlyPageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card

/// A glass card holding a group of rows, with an optional section title above
/// and footnote below. Rows draw a hairline at their top edge; the card shifts its
/// content up by that hairline so the first row's line is clipped away.
struct NotchlySettingsCard<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.lg, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title, !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(NotchlySettingsStyle.textTertiary)
                    .padding(.horizontal, 6)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                content()
            }
            .offset(y: -NotchlyTheme.Stroke.hairline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(shape)
            .background {
                shape
                    .fill(NotchlySettingsStyle.cardFill)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [NotchlySettingsStyle.cardHighlight, .clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.5)
                            )
                        )
                    }
                    .overlay {
                        shape.strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
                    }
            }
            .clipShape(shape)

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchlySettingsStyle.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
    }
}

// MARK: - Row

/// One setting: a title (with optional subtitle and help tooltip) on the left and
/// whatever control it needs on the right. Highlights softly on hover.
struct NotchlySettingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var help: String?
    var highlightID: String?
    var isEnabled: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    @State private var isHovering = false

    init(
        _ title: String,
        subtitle: String? = nil,
        help: String? = nil,
        highlightID: String? = nil,
        isEnabled: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.highlightID = highlightID
        self.isEnabled = isEnabled
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    if let help, !help.isEmpty {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NotchlySettingsStyle.textTertiary)
                            .help(help)
                            .accessibilityLabel(Text(help))
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchlySettingsStyle.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? NotchlySettingsStyle.rowHover : Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(NotchlySettingsStyle.divider)
                .frame(height: NotchlyTheme.Stroke.hairline)
                .padding(.leading, 14)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
        .animation(NotchlyTheme.Motion.snappy, value: isHovering)
        .onHover { isHovering = $0 }
        .settingsHighlightIfPresent(highlightID)
    }
}

// MARK: - Native page container

/// Scrolling body of a native settings page: a padded column of cards that also
/// scrolls to (and lets rows pulse) whichever row a search result points at.
struct NotchlyPageScroll<Content: View>: View {
    let page: NotchlySettingsPage
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    content()
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 32)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                guard let request, request.scope == page.rawValue else { return nil }
                return request
            }) { request in
                withAnimation(.easeInOut(duration: 0.45)) {
                    proxy.scrollTo(request.id, anchor: .center)
                }
                highlightCoordinator.consumeScrollRequest(request)
            }
        }
    }
}

// MARK: - Defaults binding helper

/// Reads a `Defaults` key reactively and hands the content a `Binding` to it.
struct NotchlyDefaultsBound<Value: Defaults.Serializable, Content: View>: View {
    @Default private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ key: Defaults.Key<Value>, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = Default(key)
        self.content = content
    }

    var body: some View { content($value) }
}

// MARK: - Switch

/// Monochrome pill switch: silver track with a dark knob when on, a faint track
/// with a light knob when off. The knob springs between positions.
struct NotchlySwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: ToggleStyleConfiguration
        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let on = configuration.isOn
            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(on ? NotchlySettingsStyle.accent : NotchlySettingsStyle.track)
                    .frame(width: 40, height: 24)
                    .overlay(alignment: on ? .trailing : .leading) {
                        Circle()
                            .fill(on ? NotchlySettingsStyle.onAccent : Color.primary.opacity(0.78))
                            .frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 0.5)
                            .padding(3)
                    }
                    .overlay {
                        Capsule().strokeBorder(Color.primary.opacity(isHovering ? 0.22 : 0.12), lineWidth: NotchlyTheme.Stroke.hairline)
                    }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .animation(NotchlyTheme.Motion.spring, value: on)
            .animation(NotchlyTheme.Motion.snappy, value: isHovering)
            .onHover { isHovering = $0 }
            .opacity(isEnabled ? 1 : 0.5)
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

extension ToggleStyle where Self == NotchlySwitchStyle {
    static var notchly: NotchlySwitchStyle { NotchlySwitchStyle() }
}

/// Title + subtitle on the left, the Notchly switch on the right.
struct NotchlyToggleRow: View {
    let title: String
    var subtitle: String?
    var help: String?
    var highlightID: String?
    var isEnabled: Bool = true
    @Binding var isOn: Bool

    init(
        _ title: String,
        subtitle: String? = nil,
        help: String? = nil,
        highlightID: String? = nil,
        isEnabled: Bool = true,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self.help = help
        self.highlightID = highlightID
        self.isEnabled = isEnabled
        self._isOn = isOn
    }

    var body: some View {
        NotchlySettingRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.notchly)
        }
    }
}

extension NotchlyToggleRow {
    /// Bound straight to a `Defaults` key.
    static func defaults(
        _ title: String,
        subtitle: String? = nil,
        help: String? = nil,
        highlightID: String? = nil,
        isEnabled: Bool = true,
        key: Defaults.Key<Bool>
    ) -> some View {
        NotchlyDefaultsBound(key) { binding in
            NotchlyToggleRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled, isOn: binding)
        }
    }
}

// MARK: - Slider

/// A slim monochrome slider: soft track, solid fill, a round thumb that grows on hover.
struct NotchlySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?

    @State private var isHovering = false
    @State private var isDragging = false

    private let trackHeight: CGFloat = 5
    private let thumb: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - thumb, 1)
            let fraction = progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(NotchlySettingsStyle.track)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(NotchlySettingsStyle.accent)
                    .frame(width: thumb / 2 + width * fraction, height: trackHeight)
                Circle()
                    .fill(NotchlySettingsStyle.accent)
                    .frame(width: thumb, height: thumb)
                    .overlay { Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: NotchlyTheme.Stroke.hairline) }
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .scaleEffect(isDragging ? 1.12 : (isHovering ? 1.06 : 1))
                    .offset(x: width * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let raw = min(max((drag.location.x - thumb / 2) / width, 0), 1)
                        value = snapped(range.lowerBound + raw * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(NotchlyTheme.Motion.snappy, value: isHovering)
            .animation(NotchlyTheme.Motion.snappy, value: isDragging)
            .onHover { isHovering = $0 }
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue(Text(value, format: .number.precision(.fractionLength(0...2))))
        .accessibilityAdjustableAction { direction in
            let delta = step ?? (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
        }
    }

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    private func snapped(_ raw: Double) -> Double {
        guard let step, step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let stepped = ((raw - range.lowerBound) / step).rounded() * step + range.lowerBound
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}

/// Title, live value readout, and a `NotchlySlider` underneath.
struct NotchlySliderRow: View {
    let title: String
    var subtitle: String?
    var help: String?
    var highlightID: String?
    var isEnabled: Bool = true
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    var valueLabel: (Double) -> String = { String(format: "%g", ($0 * 100).rounded() / 100) }

    var body: some View {
        NotchlySettingRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled) {
            HStack(spacing: 10) {
                NotchlySlider(value: $value, range: range, step: step)
                    .frame(width: 170)
                Text(valueLabel(value))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}

extension NotchlySliderRow {
    static func defaults(
        _ title: String,
        subtitle: String? = nil,
        help: String? = nil,
        highlightID: String? = nil,
        isEnabled: Bool = true,
        key: Defaults.Key<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        valueLabel: @escaping (Double) -> String = { String(format: "%g", ($0 * 100).rounded() / 100) }
    ) -> some View {
        NotchlyDefaultsBound(key) { binding in
            NotchlySliderRow(
                title: title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled,
                value: binding, range: range, step: step, valueLabel: valueLabel
            )
        }
    }
}

// MARK: - Segmented control

/// A glass capsule segmented control whose selection slides between options.
struct NotchlySegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var symbol: ((Value) -> String?)?

    @Namespace private var selectionNamespace
    @State private var hovered: Value?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(NotchlyTheme.Motion.spring) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        if let name = symbol?(option) {
                            Image(systemName: name).font(.system(size: 11, weight: .semibold))
                        }
                        Text(label(option))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? NotchlySettingsStyle.onAccent : Color.primary.opacity(hovered == option ? 0.9 : 0.68))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(minHeight: 26)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(NotchlySettingsStyle.accent)
                                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                        } else if hovered == option {
                            Capsule().fill(NotchlySettingsStyle.controlFill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    withAnimation(NotchlyTheme.Motion.snappy) {
                        hovered = inside ? option : (hovered == option ? nil : hovered)
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(NotchlySettingsStyle.controlFill)
                .overlay { Capsule().strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline) }
        }
    }
}

// MARK: - Picker row

/// A row with a choice on the right, as a pop-up menu or an inline segmented control.
struct NotchlyPickerRow<Value: Hashable>: View {
    enum Style { case menu, segmented }

    let title: String
    var subtitle: String?
    var help: String?
    var highlightID: String?
    var isEnabled: Bool = true
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var style: Style = .menu

    var body: some View {
        NotchlySettingRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled) {
            switch style {
            case .menu:
                NotchlyMenuButton(selection: $selection, options: options, label: label)
            case .segmented:
                NotchlySegmentedControl(selection: $selection, options: options, label: label)
            }
        }
    }
}

extension NotchlyPickerRow {
    static func defaults(
        _ title: String,
        subtitle: String? = nil,
        help: String? = nil,
        highlightID: String? = nil,
        isEnabled: Bool = true,
        key: Defaults.Key<Value>,
        options: [Value],
        style: Style = .menu,
        label: @escaping (Value) -> String
    ) -> some View where Value: Defaults.Serializable {
        NotchlyDefaultsBound(key) { binding in
            NotchlyPickerRow(
                title: title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled,
                selection: binding, options: options, label: label, style: style
            )
        }
    }
}

/// Pop-up menu in glass: the current choice plus a chevron.
struct NotchlyMenuButton<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label(option), systemImage: "checkmark")
                    } else {
                        Text(label(option))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .frame(minHeight: 26)
            .background {
                Capsule()
                    .fill(isHovering ? NotchlySettingsStyle.controlFillHover : NotchlySettingsStyle.controlFill)
                    .overlay { Capsule().strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline) }
            }
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .animation(NotchlyTheme.Motion.snappy, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Buttons

/// Glass button for settings. Adapts to light and dark, brightens on hover and
/// dips on press like `GlassButtonStyle` does in the notch.
struct NotchlyButtonStyle: ButtonStyle {
    enum Variant {
        /// Soft glass capsule.
        case standard
        /// Solid silver capsule for the one primary action.
        case prominent
        /// Text only; glass appears on hover.
        case quiet
    }

    var variant: Variant = .standard
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, variant: variant, destructive: destructive)
    }

    private struct ButtonBody: View {
        let configuration: Configuration
        let variant: Variant
        let destructive: Bool

        @State private var isHovering = false
        @Environment(\.isEnabled) private var isEnabled

        private var fill: Color {
            switch variant {
            case .prominent:
                return NotchlySettingsStyle.accent.opacity(configuration.isPressed ? 0.8 : (isHovering ? 0.94 : 1))
            case .standard:
                if configuration.isPressed { return NotchlySettingsStyle.controlFillPressed }
                return isHovering ? NotchlySettingsStyle.controlFillHover : NotchlySettingsStyle.controlFill
            case .quiet:
                if configuration.isPressed { return NotchlySettingsStyle.controlFillPressed }
                return isHovering ? NotchlySettingsStyle.controlFill : .clear
            }
        }

        private var foreground: Color {
            if destructive { return Color(nsColor: .systemRed) }
            return variant == .prominent ? NotchlySettingsStyle.onAccent : .primary
        }

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .frame(minHeight: 28)
                .background {
                    Capsule()
                        .fill(fill)
                        .overlay {
                            if variant != .quiet || isHovering {
                                Capsule().strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
                            }
                        }
                }
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? NotchlyTheme.Motion.pressedScale : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(NotchlyTheme.Motion.pop, value: configuration.isPressed)
                .animation(NotchlyTheme.Motion.snappy, value: isHovering)
                .onHover { isHovering = $0 }
        }
    }
}

extension ButtonStyle where Self == NotchlyButtonStyle {
    static var notchly: NotchlyButtonStyle { NotchlyButtonStyle() }
    static func notchly(_ variant: NotchlyButtonStyle.Variant, destructive: Bool = false) -> NotchlyButtonStyle {
        NotchlyButtonStyle(variant: variant, destructive: destructive)
    }
}

/// A full-width tappable row (open a link, run an action) with a trailing glyph.
struct NotchlyActionRow: View {
    let title: String
    var subtitle: String?
    var symbol: String = "arrow.up.right"
    var destructive = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(destructive ? Color(nsColor: .systemRed) : Color.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(NotchlySettingsStyle.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    .offset(x: isHovering ? 1.5 : 0, y: isHovering && symbol == "arrow.up.right" ? -1.5 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovering ? NotchlySettingsStyle.rowHover : Color.clear)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(NotchlySettingsStyle.divider)
                    .frame(height: NotchlyTheme.Stroke.hairline)
                    .padding(.leading, 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(NotchlyTheme.Motion.snappy, value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Rows built from a search item

/// Row builders that take their title and highlight anchor from a
/// `NotchlySettingItem`, so a row and its search entry always agree.
extension NotchlySettingItem {
    func toggle(_ subtitle: String? = nil, help: String? = nil, isEnabled: Bool = true, isOn: Binding<Bool>) -> NotchlyToggleRow {
        NotchlyToggleRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled, isOn: isOn)
    }

    func toggle(_ subtitle: String? = nil, help: String? = nil, isEnabled: Bool = true, key: Defaults.Key<Bool>) -> some View {
        NotchlyToggleRow.defaults(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled, key: key)
    }

    func slider(
        _ subtitle: String? = nil,
        isEnabled: Bool = true,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        valueLabel: @escaping (Double) -> String = { String(format: "%g", ($0 * 100).rounded() / 100) }
    ) -> NotchlySliderRow {
        NotchlySliderRow(
            title: title, subtitle: subtitle, highlightID: highlightID, isEnabled: isEnabled,
            value: value, range: range, step: step, valueLabel: valueLabel
        )
    }

    func slider(
        _ subtitle: String? = nil,
        isEnabled: Bool = true,
        key: Defaults.Key<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        valueLabel: @escaping (Double) -> String = { String(format: "%g", ($0 * 100).rounded() / 100) }
    ) -> some View {
        NotchlySliderRow.defaults(
            title, subtitle: subtitle, highlightID: highlightID, isEnabled: isEnabled,
            key: key, range: range, step: step, valueLabel: valueLabel
        )
    }

    func picker<Value: Hashable>(
        _ subtitle: String? = nil,
        isEnabled: Bool = true,
        selection: Binding<Value>,
        options: [Value],
        style: NotchlyPickerRow<Value>.Style = .menu,
        label: @escaping (Value) -> String
    ) -> NotchlyPickerRow<Value> {
        NotchlyPickerRow(
            title: title, subtitle: subtitle, highlightID: highlightID, isEnabled: isEnabled,
            selection: selection, options: options, label: label, style: style
        )
    }

    func picker<Value: Hashable & Defaults.Serializable>(
        _ subtitle: String? = nil,
        isEnabled: Bool = true,
        key: Defaults.Key<Value>,
        options: [Value],
        style: NotchlyPickerRow<Value>.Style = .menu,
        label: @escaping (Value) -> String
    ) -> some View {
        NotchlyPickerRow.defaults(
            title, subtitle: subtitle, highlightID: highlightID, isEnabled: isEnabled,
            key: key, options: options, style: style, label: label
        )
    }

    func row<Trailing: View>(
        _ subtitle: String? = nil,
        help: String? = nil,
        isEnabled: Bool = true,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> NotchlySettingRow<Trailing> {
        NotchlySettingRow(title, subtitle: subtitle, help: help, highlightID: highlightID, isEnabled: isEnabled, trailing: trailing)
    }
}
