//
//  SettingsView.swift
//  DynamicIsland
//
//  Created by Richard Kunkli on 07/08/2024.
//
import AppKit
import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import LaunchAtLogin
import LottieUI
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case liveActivities
    case lockScreen
    case devices
    case hudAndOSD
    case battery
    case downloads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveActivities: return String(localized: "Live Activities")
        case .lockScreen: return String(localized: "Lock Screen")
        case .devices: return String(localized: "Devices")
        case .hudAndOSD: return String(localized: "Controls")
        case .battery: return String(localized: "Battery")
        case .downloads: return String(localized: "Downloads")
        }
    }

    var systemImage: String {
        switch self {
        case .liveActivities: return "waveform.path.ecg"
        case .lockScreen: return "lock.laptopcomputer"
        case .devices: return "headphones"
        case .hudAndOSD: return "dial.medium.fill"
        case .battery: return "battery.100.bolt"
        case .downloads: return "square.and.arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .liveActivities: return .pink
        case .lockScreen: return .orange
        case .devices: return Color(red: 0.1, green: 0.11, blue: 0.12)
        case .hudAndOSD: return .indigo
        case .battery: return Color(red: 0.202, green: 0.783, blue: 0.348, opacity: 1.000)
        case .downloads: return .gray
        }
    }

    func highlightID(for title: String) -> String {
        "\(rawValue)-\(title)"
    }
}

private struct LegacySettingsSearchEntry: Identifiable {
    let tab: SettingsTab
    let title: String
    let keywords: [String]
    let highlightID: String?

    init(
        tab: SettingsTab,
        title: String,
        keywords: [String],
        highlightID: String?
    ) {
        self.tab = tab
        self.title = title
        self.keywords = keywords
        self.highlightID = highlightID
    }

    var id: String { "\(tab.rawValue)-\(title)" }
}

private enum LegacySettingsSearchCatalog {
    static let entries: [LegacySettingsSearchEntry] = []
}

final class SettingsHighlightCoordinator: ObservableObject {
    struct ScrollRequest: Identifiable, Equatable {
        let id: String
        /// Which page body should scroll: a legacy tab's raw value, or a native page's raw value.
        let scope: String
        /// Where in the viewport the target should land.
        var anchor: UnitPoint = .center
    }

    @Published var pendingScrollRequest: ScrollRequest?
    @Published private(set) var activeHighlightID: String?

    private var clearWorkItem: DispatchWorkItem?

    func focus(highlightID: String, scope: String) {
        pendingScrollRequest = ScrollRequest(id: highlightID, scope: scope)
        activateHighlight(id: highlightID)
    }

    func focus(highlightID: String, tab: SettingsTab) {
        focus(highlightID: highlightID, scope: tab.rawValue)
    }

    func consumeScrollRequest(_ request: ScrollRequest) {
        guard pendingScrollRequest?.id == request.id else { return }
        pendingScrollRequest = nil
    }

    private func activateHighlight(id: String) {
        activeHighlightID = id
        clearWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.activeHighlightID == id else { return }
            self?.activeHighlightID = nil
        }

        clearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private struct SettingsHighlightModifier: ViewModifier {
    let id: String
    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator
    @State private var animatePulse = false

    private var isActive: Bool {
        highlightCoordinator.activeHighlightID == id
    }

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(highlightBackground)
            .onChange(of: isActive) { _, active in
                animatePulse = active
            }
            .onAppear {
                if isActive {
                    animatePulse = true
                }
            }
    }

    private var highlightBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                NotchlySettingsStyle.accent.opacity(isActive ? (animatePulse ? 0.8 : 0.3) : 0),
                lineWidth: 1.5
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NotchlySettingsStyle.accent.opacity(isActive ? 0.08 : 0))
            )
            .padding(2)
            .animation(
                isActive ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                value: animatePulse
            )
    }
}

extension View {
    func settingsHighlight(id: String) -> some View {
        modifier(SettingsHighlightModifier(id: id))
    }

    @ViewBuilder
    func settingsHighlightIfPresent(_ id: String?) -> some View {
        if let id {
            settingsHighlight(id: id)
        } else {
            self
        }
    }
}

struct SettingsForm<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    @EnvironmentObject private var highlightCoordinator: SettingsHighlightCoordinator

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .onReceive(highlightCoordinator.$pendingScrollRequest.compactMap { request -> SettingsHighlightCoordinator.ScrollRequest? in
                    guard let request, request.scope == tab.rawValue else { return nil }
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

struct SettingsSegmentedControl<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> String
    /// Segments share the width equally instead of sizing to their text. Used
    /// where the control is a tab bar rather than a row's right-hand control.
    var fillsWidth: Bool = false

    @Namespace private var selectionNamespace
    @State private var hovered: Item?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                segment(for: item)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        // Driven from the value, not only from `withAnimation` at the tap: a
        // selection changed from anywhere else -- settings search switching
        // segments, a Defaults write from another window -- should slide too,
        // and inside a Form row the tap's transaction does not always reach
        // the row's own content.
        .animation(selectionAnimation, value: selection)
    }

    private var selectionAnimation: Animation { .spring(response: 0.32, dampingFraction: 0.82) }

    @ViewBuilder
    private func segment(for item: Item) -> some View {
        let isSelected = selection == item
        let isHovered = hovered == item

        Button {
            guard selection != item else { return }
            withAnimation(selectionAnimation) { selection = item }
        } label: {
            Text(label(item))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? NotchlySettingsStyle.onAccent : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: 24)
                .background {
                    if isSelected {
                        // The system accent colour, so the control follows
                        // System Settings > Appearance the way the stock
                        // segmented picker did.
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside {
                    hovered = item
                } else if hovered == item {
                    hovered = nil
                }
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A settings row whose control is a ``SettingsSegmentedControl``.
///
/// Drop-in for `Picker(title, selection:).pickerStyle(.segmented)`: label on
/// the left, control on the right, same as every other row in the form.
struct SettingsSegmentedPicker<Item: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Item
    let items: [Item]
    let label: (Item) -> String

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Item>,
        items: [Item],
        label: @escaping (Item) -> String
    ) {
        self.title = title
        self._selection = selection
        self.items = items
        self.label = label
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 8)
            SettingsSegmentedControl(items: items, selection: $selection, label: label)
        }
    }
}

func proFeatureBadge() -> some View {
    Text("Upgrade to Pro")
        .foregroundStyle(Color(red: 0.545, green: 0.196, blue: 0.98))
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 0.545, green: 0.196, blue: 0.98), lineWidth: 1))
}

func comingSoonTag() -> some View {
    Text("Coming soon")
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func customBadge(text: String) -> some View {
    Text(LocalizedStringKey(text))
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func alphaBadge() -> some View {
    Text("ALPHA")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.orange.opacity(0.9))
        )
}

func warningBadge(_ text: String, _ description: String) -> some View {
    Section {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.yellow)
            VStack(alignment: .leading) {
                Text(text)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Reusable App Icon View

/// Fetches the real app icon from the system using bundle identifiers,
/// falling back to an asset catalog image or an SF Symbol.
struct AppIconImage: View {
    let bundleIdentifiers: [String]
    var assetFallback: String? = nil
    var symbolFallback: String = "app.fill"
    var symbolColor: Color = .accentColor
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let nsImage = resolvedIcon() {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else if let assetFallback, let nsImage = NSImage(named: NSImage.Name(assetFallback)) {
                Image(nsImage: nsImage.fitted(toSide: size))
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
            } else {
                Image(systemName: symbolFallback)
                    .foregroundColor(symbolColor)
            }
        }
        .frame(width: size, height: size)
    }

    private func resolvedIcon() -> NSImage? {
        for bundleID in bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                // NSWorkspace returns a valid icon even for generic apps;
                // redraw it small to keep memory low. At twice the size it is
                // asked for, so it stays sharp on a Retina display -- the old
                // flat 32 was being scaled *up* wherever this is drawn larger
                // than that, which is why the bigger icons looked soft.
                let side = max(32, size * 2)
                let thumb = NSImage(size: NSSize(width: side, height: side))
                thumb.lockFocus()
                icon.draw(in: NSRect(origin: .zero, size: NSSize(width: side, height: side)),
                          from: NSRect(origin: .zero, size: icon.size),
                          operation: .copy, fraction: 1.0)
                thumb.unlockFocus()
                return thumb
            }
        }
        return nil
    }
}

// MARK: - Bridge to the Notchly settings shell
//
// The pages themselves are still the legacy section views (stages 2-3 migrate
// them row by row); the shell reaches them, their search entries and their
// highlight anchors through the declarations below.

extension SettingsTab {
    /// The Notchly page this legacy tab now lives on.
    var page: NotchlySettingsPage {
        switch self {
        case .liveActivities, .lockScreen, .devices, .battery, .hudAndOSD, .downloads: return .liveActivities
        }
    }

    /// Label used by the sub-section picker on pages that hold several legacy tabs.
    var sectionTitle: String {
        switch self {
        case .liveActivities: return String(localized: "Activities")
        case .hudAndOSD: return String(localized: "Volume & Brightness")
        default: return title
        }
    }
}

extension NotchlySettingsPage {
    /// Legacy tabs hosted on this page, in display order.
    var legacySections: [SettingsTab] {
        switch self {
        case .general: return []
        case .appearance: return []
        case .homeHub: return []
        case .music: return []
        case .liveActivities: return []
        case .stash: return []
        case .shortcuts: return []
        case .about: return []
        }
    }
}

extension SettingsSearchIndex {
    /// Every page, plus every legacy row (mapped onto its page and section).
    static let shared: SettingsSearchIndex = {
        let pages = NotchlySettingsPage.allCases.map(SettingsSearchEntry.entry(for:))
        let native = NotchlySettingsPage.allCases.flatMap { $0.nativeItems.map(\.searchEntry) }
        let rows = LegacySettingsSearchCatalog.entries.map { entry in
            SettingsSearchEntry(
                title: entry.title,
                keywords: entry.keywords,
                page: entry.tab.page,
                sectionID: entry.tab.rawValue,
                highlightID: entry.highlightID
            )
        }
        return SettingsSearchIndex(entries: pages + native + rows)
    }()
}
