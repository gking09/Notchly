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

// MARK: - Pages
//
// Native pages (General, Appearance, Home & Hub, Music, About) are built from the
// `NotchlySettingsCard` components and register their rows with the search index
// through `NotchlySettingItem`. The pages that are still legacy `Form` sections
// are hosted below until stage 3 migrates them:
//
//   old tab          page             sub-section
//   ---------------  ---------------  ---------------------------
//   Live Activities  Live Activities  Activities
//   Battery          Live Activities  Battery
//   Controls (HUD)   Live Activities  Volume & Brightness
//   Devices          Live Activities  Devices
//   Lock Screen      Live Activities  Lock Screen
//   Downloads        Live Activities  Downloads
//   Stash            Stash            -
//   Shortcuts        Shortcuts        -

// MARK: - Navigation requests

/// Lets anything outside the window (menu items, deep links) ask it to show a page.
final class NotchlySettingsNavigator: ObservableObject {
    struct Request: Equatable, Identifiable {
        let id = UUID()
        var page: NotchlySettingsPage
        var section: SettingsTab?
        var highlightID: String?
    }

    static let shared = NotchlySettingsNavigator()

    @Published var request: Request?

    func open(_ page: NotchlySettingsPage, section: SettingsTab? = nil, highlightID: String? = nil) {
        request = Request(page: page, section: section, highlightID: highlightID)
    }
}

// MARK: - Window material

/// Behind-window vibrancy so the settings window reads as glass in light and dark.
struct NotchlyWindowBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - Shell

struct NotchlySettingsView: View {
    @ObservedObject private var navigator = NotchlySettingsNavigator.shared
    @StateObject private var highlightCoordinator = SettingsHighlightCoordinator()

    @State private var selectedPage: NotchlySettingsPage
    @State private var selectedSections: [NotchlySettingsPage: SettingsTab] = [:]
    @State private var searchText = ""

    private let searchIndex = SettingsSearchIndex.shared

    init(initialPage: NotchlySettingsPage = .general) {
        _selectedPage = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            NotchlySettingsSidebar(
                selectedPage: pageSelection,
                searchText: $searchText,
                results: searchResults,
                onSelectResult: open(result:)
            )
            .frame(width: 232)

            Rectangle()
                .fill(NotchlySettingsStyle.divider)
                .frame(width: NotchlyTheme.Stroke.hairline)
                .ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background { NotchlyWindowBackground().ignoresSafeArea() }
        .environmentObject(highlightCoordinator)
        .tint(NotchlySettingsStyle.accent)
        .onReceive(navigator.$request.compactMap { $0 }) { request in
            apply(request)
        }
    }

    // MARK: Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                NotchlyPageHeader(title: selectedPage.title, subtitle: selectedPage.subtitle)
                if sections.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        NotchlySegmentedControl(
                            selection: sectionBinding,
                            options: sections,
                            label: { $0.sectionTitle }
                        )
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 14)

            ZStack {
                pageBody
                    .id(pageBodyID)
                    .transition(.settingsPage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(NotchlyTheme.Motion.spring, value: pageBodyID)
        }
    }

    private var pageBodyID: String { "\(selectedPage.rawValue)/\(currentSection?.rawValue ?? "-")" }

    @ViewBuilder
    private var pageBody: some View {
        if selectedPage == .about {
            NotchlyAboutPage()
        } else if selectedPage == .general {
            NotchlyGeneralPage()
        } else if selectedPage == .appearance {
            NotchlyAppearancePage()
        } else if selectedPage == .homeHub {
            NotchlyHomeHubPage()
        } else if selectedPage == .music {
            NotchlyMusicPage()
        } else if selectedPage == .liveActivities {
            NotchlyLiveActivitiesPage()
        } else if selectedPage == .stash {
            NotchlyStashPage()
        } else if selectedPage == .shortcuts {
            NotchlyShortcutsPage()
        }
    }

    // MARK: Pages & sections

    private var sections: [SettingsTab] {
        selectedPage.legacySections
    }

    private var currentSection: SettingsTab? {
        let available = sections
        if let chosen = selectedSections[selectedPage], available.contains(chosen) { return chosen }
        return available.first
    }

    private var sectionBinding: Binding<SettingsTab> {
        Binding(
            get: { currentSection ?? .liveActivities },
            set: { selectedSections[selectedPage] = $0 }
        )
    }

    private var pageSelection: Binding<NotchlySettingsPage> {
        Binding(
            get: { selectedPage },
            set: { newValue in
                withAnimation(NotchlyTheme.Motion.spring) { selectedPage = newValue }
            }
        )
    }

    // MARK: Search

    private var searchResults: [SettingsSearchResult] {
        searchIndex.search(searchText, limit: 9)
    }

    private func open(result: SettingsSearchResult) {
        let entry = result.entry
        withAnimation(NotchlyTheme.Motion.spring) {
            selectedPage = entry.page
            if let sectionID = entry.sectionID, let section = SettingsTab(rawValue: sectionID) {
                selectedSections[entry.page] = section
            }
        }
        searchText = ""
        if let highlightID = entry.highlightID {
            focus(highlightID: highlightID, scope: entry.sectionID ?? entry.page.rawValue)
        }
    }

    private func apply(_ request: NotchlySettingsNavigator.Request) {
        withAnimation(NotchlyTheme.Motion.spring) {
            selectedPage = request.page
            if let section = request.section { selectedSections[request.page] = section }
        }
        if let highlightID = request.highlightID {
            let scope = (request.section ?? request.page.legacySections.first)?.rawValue ?? request.page.rawValue
            focus(highlightID: highlightID, scope: scope)
        }
    }

    /// Scroll + pulse the row once its page has had a moment to mount.
    private func focus(highlightID: String, scope: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            highlightCoordinator.focus(highlightID: highlightID, scope: scope)
        }
    }
}

// MARK: - Sidebar

private struct NotchlySettingsSidebar: View {
    @Binding var selectedPage: NotchlySettingsPage
    @Binding var searchText: String
    let results: [SettingsSearchResult]
    let onSelectResult: (SettingsSearchResult) -> Void

    @Namespace private var selectionNamespace
    @State private var hoveredPage: NotchlySettingsPage?
    @State private var hoveredResult: String?
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 38)
                .padding(.horizontal, 16)

            searchField
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 2) {
                    if isSearching {
                        searchResultsList
                    } else {
                        ForEach(NotchlySettingsPage.sidebarPages) { page in
                            pageRow(page)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)

            footer
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
        }
        .background(Color.primary.opacity(0.025))
        .animation(NotchlyTheme.Motion.spring, value: isSearching)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image("logo2")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Notchly")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(Bundle.main.releaseVersionNumberPretty)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchlySettingsStyle.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchlySettingsStyle.textSecondary)

            TextField("Search settings", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if let first = results.first { onSelectResult(first) }
                }
                .onExitCommand { searchText = "" }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchlySettingsStyle.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                .fill(NotchlySettingsStyle.controlFill)
                .overlay {
                    RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                        .strokeBorder(
                            searchFocused ? Color.primary.opacity(0.28) : NotchlySettingsStyle.cardStroke,
                            lineWidth: NotchlyTheme.Stroke.hairline
                        )
                }
        }
        .animation(NotchlyTheme.Motion.snappy, value: searchFocused)
        .animation(NotchlyTheme.Motion.snappy, value: searchText.isEmpty)
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if results.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .light))
                Text("No matching settings")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(NotchlySettingsStyle.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 28)
        } else {
            ForEach(results) { result in
                resultRow(result)
            }
        }
    }

    private func resultRow(_ result: SettingsSearchResult) -> some View {
        let entry = result.entry
        let isHovered = hoveredResult == result.id
        return Button {
            onSelectResult(result)
        } label: {
            HStack(spacing: 9) {
                symbolTile(entry.page.symbol, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !entry.isPageEntry {
                        Text(entry.page.title)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchlySettingsStyle.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                    .fill(isHovered ? NotchlySettingsStyle.controlFill : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredResult = inside ? result.id : (hoveredResult == result.id ? nil : hoveredResult)
        }
        .animation(NotchlyTheme.Motion.snappy, value: isHovered)
    }

    // MARK: Pages

    private func pageRow(_ page: NotchlySettingsPage) -> some View {
        let isSelected = selectedPage == page
        let isHovered = hoveredPage == page
        return Button {
            selectedPage = page
        } label: {
            HStack(spacing: 10) {
                symbolTile(page.symbol, size: 26, emphasized: isSelected)
                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.78))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                            .fill(NotchlySettingsStyle.rowHover)
                    }
                    if isSelected {
                        selectionCapsule
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredPage = inside ? page : (hoveredPage == page ? nil : hoveredPage)
        }
        .animation(NotchlyTheme.Motion.snappy, value: isHovered)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionCapsule: some View {
        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
            .fill(NotchlySettingsStyle.controlFillHover)
            .overlay {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
                    .strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
            }
            .matchedGeometryEffect(id: "sidebarSelection", in: selectionNamespace)
    }

    /// Monochrome rounded tile holding an SF Symbol.
    private func symbolTile(_ symbol: String, size: CGFloat, emphasized: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.sm, style: .continuous)
            .fill(emphasized ? NotchlySettingsStyle.accent : NotchlySettingsStyle.controlFill)
            .overlay {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.sm, style: .continuous)
                    .strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
            }
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(emphasized ? NotchlySettingsStyle.onAccent : Color.primary.opacity(0.82))
            }
            .animation(NotchlyTheme.Motion.snappy, value: emphasized)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(NotchlySettingsStyle.divider)
                .frame(height: NotchlyTheme.Stroke.hairline)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            HStack(spacing: 4) {
                creditsLink
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(NotchlyButtonStyle(variant: .quiet))
                .help("Quit Notchly")
                .accessibilityLabel("Quit Notchly")
            }
        }
    }

    private var creditsLink: some View {
        let isSelected = selectedPage == .about
        return Button {
            selectedPage = .about
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 12, weight: .semibold))
                Text("Credits & License")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.primary : NotchlySettingsStyle.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected { selectionCapsule }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
