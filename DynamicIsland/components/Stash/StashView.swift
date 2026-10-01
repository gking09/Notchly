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
import QuickLookThumbnailing
import SwiftUI

// MARK: - Transition

private struct StashCardEffect: ViewModifier {
    let isPresent: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPresent ? 1 : 0)
            .scaleEffect(isPresent ? 1 : 0.8)
            .blur(radius: isPresent ? 0 : 6)
    }
}

extension AnyTransition {
    /// A card springing in (scale, blur, opacity) and shrinking away again.
    static var stashCard: AnyTransition {
        if NotchlyTheme.Motion.reduceMotion {
            return .opacity.animation(.easeOut(duration: 0.12))
        }
        return .modifier(
            active: StashCardEffect(isPresent: false),
            identity: StashCardEffect(isPresent: true)
        )
    }
}

// MARK: - Thumbnails

/// QuickLook thumbnails for image cards, cached by item.
enum StashThumbnails {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func cached(for id: UUID) -> NSImage? {
        cache.object(forKey: id as NSUUID)
    }

    static func load(id: UUID, url: URL, side: CGFloat) async -> NSImage? {
        if let image = cached(for: id) { return image }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }

    static func evict(_ id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}

// MARK: - Tab

/// The Stash tab: a shelf of glass cards, newest first, that accepts drops.
struct StashView: View {
    @ObservedObject private var manager = StashManager.shared
    @ObservedObject private var store = StashManager.shared.store
    @Default(.stashHidePreviewsUntilHover) private var hidePreviews

    var body: some View {
        VStack(spacing: NotchlyTheme.Spacing.sm) {
            header
                .staggered(index: 0)

            ZStack {
                if store.items.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    shelf
                        .transition(.opacity)
                }

                if manager.isDropTargeted {
                    StashDropZone()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(NotchlyTheme.Spacing.sm)
        .animation(NotchlyTheme.Motion.spring, value: store.items.isEmpty)
        .animation(NotchlyTheme.Motion.spring, value: manager.isDropTargeted)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: NotchlyTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text("Stash")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary)
                Text("\(store.items.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                    .contentTransition(.numericText())
                    .animation(NotchlyTheme.Motion.spring, value: store.items.count)
            }

            Spacer(minLength: 0)

            if let toast = manager.toast {
                StashToastView(toast: toast, canUndo: store.pendingRemoval != nil) {
                    manager.undo()
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            Button {
                manager.addFromClipboard()
            } label: {
                headerLabel("Add from clipboard", symbol: "doc.on.clipboard")
            }
            .buttonStyle(.notchlyGlass)
            .help("Add what is on the clipboard right now")

            if !store.items.isEmpty {
                Button {
                    manager.clearAll()
                } label: {
                    headerLabel("Clear all", symbol: "trash")
                }
                .buttonStyle(.notchlyGlass)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .help("Remove everything; you can undo for a few seconds")
            }
        }
        .frame(height: 26)
        .animation(NotchlyTheme.Motion.spring, value: store.items.isEmpty)
    }

    private func headerLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .contentShape(Capsule())
    }

    // MARK: Shelf

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NotchlyTheme.Spacing.sm) {
                ForEach(store.items) { item in
                    StashCard(item: item, hidePreviews: hidePreviews)
                        .transition(.stashCard)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .animation(NotchlyTheme.Motion.spring, value: store.items.map(\.id))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
            Text("Nothing stashed yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.85))
            Text("Drop files, text or links on the notch, or add what is on the clipboard.")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Drop zone

/// The glass highlight shown while a drag is over the notch.
private struct StashDropZone: View {
    @State private var pulsing = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NotchlyTheme.Radius.lg, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(0.55))
            shape.fill(NotchlyTheme.Palette.glassFillHover)
            shape
                .strokeBorder(
                    Color.white.opacity(pulsing ? 0.75 : 0.35),
                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                )
            VStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 20, weight: .medium))
                    .scaleEffect(pulsing ? 1.08 : 1)
                Text("Drop to stash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(NotchlyTheme.Palette.textPrimary)
        }
        .onAppear {
            guard !NotchlyTheme.Motion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Toast

private struct StashToastView: View {
    let toast: StashToast
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(toast.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchlyTheme.Palette.textSecondary)
                .lineLimit(1)
            if toast.offersUndo && canUndo {
                Text("\u{00B7}")
                    .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                Button("Undo", action: onUndo)
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchlyTheme.Palette.textPrimary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .glassSurface(in: Capsule())
    }
}

// MARK: - Card

private struct StashCard: View {
    let item: StashItem
    let hidePreviews: Bool

    @ObservedObject private var manager = StashManager.shared
    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var isMissing = false

    private static let size = CGSize(width: 124, height: 100)

    private var isCopied: Bool { manager.copiedItemID == item.id }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.md, style: .continuous)
    }

    /// Text is blurred until the pointer is on the card when the privacy option is on.
    private var isObscured: Bool { hidePreviews && !isHovering }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                .opacity(isCopied ? 0.25 : 1)

            if isHovering && !isCopied {
                actions
                    .padding(5)
                    .transition(.scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
            }

            if isCopied {
                copiedBadge
                    .frame(width: Self.size.width, height: Self.size.height)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .glassSurface(
            cornerRadius: NotchlyTheme.Radius.md,
            fill: isHovering ? NotchlyTheme.Palette.glassFillHover : NotchlyTheme.Palette.glassFill
        )
        .clipShape(shape)
        .scaleEffect(isHovering ? 1.02 : 1)
        .contentShape(shape)
        .onHover { hovering in
            withAnimation(NotchlyTheme.Motion.snappy) { isHovering = hovering }
        }
        .onTapGesture { manager.copy(item) }
        .onDrag { manager.dragProvider(for: item) }
        .contextMenu { menu }
        .task(id: item.id) { await loadAppearance() }
        .animation(NotchlyTheme.Motion.spring, value: isCopied)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Click to copy. Drag to another app to move it there.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text: textContent
        case .url: linkContent
        case .file: fileContent
        case .image: imageContent
        }
    }

    private var textContent: some View {
        let multiline = (item.text ?? "").contains(where: \.isNewline)
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.previewText())
                .font(.system(size: 10.5, design: multiline ? .monospaced : .default))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .blur(radius: isObscured ? 6 : 0)
                .animation(NotchlyTheme.Motion.snappy, value: isObscured)
            Spacer(minLength: 0)
            footer(Text("\(item.characterCount) characters"))
        }
        .padding(8)
    }

    private var linkContent: some View {
        let host = item.webURL?.host ?? item.title
        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.silver)
            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(item.title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
            .blur(radius: isObscured ? 6 : 0)
            .animation(NotchlyTheme.Motion.snappy, value: isObscured)
            Spacer(minLength: 0)
            footer(Text("Link"))
        }
        .padding(8)
    }

    private var fileContent: some View {
        VStack(spacing: 4) {
            fileGlyph
                .frame(height: 44)
            Text(item.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchlyTheme.Palette.textPrimary.opacity(0.9))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            footer(fileDetail)
        }
        .padding(8)
    }

    private var imageContent: some View {
        ZStack(alignment: .bottomLeading) {
            fileGlyph
                .frame(width: Self.size.width, height: Self.size.height)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            footer(fileDetail)
                .padding(8)
        }
    }

    @ViewBuilder
    private var fileGlyph: some View {
        if let thumbnail, item.showsThumbnail {
            if item.kind == .image {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        } else {
            Image(nsImage: systemIcon)
                .resizable()
                .scaledToFit()
                .opacity(isMissing ? 0.4 : 1)
        }
    }

    private var systemIcon: NSImage {
        if let url = StashManager.shared.store.fileURL(for: item), !isMissing {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .data)
    }

    private var fileDetail: Text {
        guard let file = item.file else { return Text("") }
        if isMissing { return Text("Missing") }
        if file.isDirectory && file.isLinked { return Text("Folder") }
        return Text(ByteCountFormatter.string(fromByteCount: file.byteSize, countStyle: .file))
    }

    private func footer(_ label: Text) -> some View {
        HStack(spacing: 4) {
            label
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchlyTheme.Palette.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if item.isLinked {
                HStack(spacing: 2) {
                    Image(systemName: "link")
                    Text("Linked")
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(NotchlyTheme.Palette.silver)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .help("Too big to copy, so this points at the original file")
            }
        }
    }

    // MARK: Hover actions

    private var actions: some View {
        HStack(spacing: 4) {
            Button {
                manager.copy(item)
            } label: {
                actionGlyph(isCopied ? "checkmark" : "doc.on.doc")
            }
            .help("Copy")

            Button {
                withAnimation(NotchlyTheme.Motion.spring) { manager.remove(item) }
            } label: {
                actionGlyph("xmark")
            }
            .help("Remove")
        }
        .buttonStyle(.notchlyGlassCircle)
    }

    private func actionGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(NotchlyTheme.Palette.textPrimary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .contentShape(Circle())
    }

    private var copiedBadge: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .medium))
                .symbolEffect(.bounce, value: isCopied)
            Text("Copied")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(NotchlyTheme.Palette.textPrimary)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy") { manager.copy(item) }
        if let url = StashManager.shared.store.fileURL(for: item), item.kind == .file || item.kind == .image {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        if let link = item.webURL {
            Button("Open Link") { NSWorkspace.shared.open(link) }
        }
        Divider()
        Button("Remove") { withAnimation(NotchlyTheme.Motion.spring) { manager.remove(item) } }
    }

    // MARK: Loading

    private func loadAppearance() async {
        guard item.kind == .file || item.kind == .image,
              let url = StashManager.shared.store.fileURL(for: item) else { return }
        let exists = FileManager.default.fileExists(atPath: url.path)
        isMissing = !exists
        guard exists, item.showsThumbnail else { return }
        if let cached = StashThumbnails.cached(for: item.id) {
            thumbnail = cached
            return
        }
        thumbnail = await StashThumbnails.load(id: item.id, url: url, side: 240)
    }

    private var accessibilityTitle: String {
        switch item.kind {
        case .text: return String(localized: "Text, \(item.characterCount) characters")
        case .url: return String(localized: "Link, \(item.title)")
        case .file: return String(localized: "File, \(item.title)")
        case .image: return String(localized: "Image, \(item.title)")
        }
    }
}
