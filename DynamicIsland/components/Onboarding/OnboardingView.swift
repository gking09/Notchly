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


import SwiftUI

/// The first-launch flow: Welcome, optional Permissions, Done. Styled like the settings
/// window (adaptive soft glass, one monochrome accent) so the app feels like one thing.
struct OnboardingView: View {
    static let windowSize = CGSize(width: 480, height: 600)

    let applyFirstLaunchDefaults: Bool
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    @State private var step: OnboardingStep
    @StateObject private var permissions: OnboardingPermissionsController

    init(
        initialStep: OnboardingStep = .welcome,
        permissions: OnboardingPermissionsController? = nil,
        applyFirstLaunchDefaults: Bool = true,
        onFinish: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        _step = State(initialValue: initialStep)
        _permissions = StateObject(wrappedValue: permissions ?? OnboardingPermissionsController())
        self.applyFirstLaunchDefaults = applyFirstLaunchDefaults
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case .welcome:
                    OnboardingWelcomeStep()
                case .permissions:
                    OnboardingPermissionsStep(permissions: permissions)
                case .done:
                    OnboardingDoneStep()
                }
            }
            .id(step)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .background { NotchlyWindowBackground() }
        .animation(NotchlyTheme.Motion.spring, value: step)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 18) {
            OnboardingProgressDots(current: step)

            HStack(spacing: 10) {
                switch step {
                case .welcome:
                    Button("Continue") { advance() }
                        .buttonStyle(.notchly(.prominent))
                        .keyboardShortcut(.defaultAction)

                case .permissions:
                    Button("Back") { goBack() }
                        .buttonStyle(.notchly(.quiet))
                    Button("Continue") { advance() }
                        .buttonStyle(.notchly(.prominent))
                        .keyboardShortcut(.defaultAction)

                case .done:
                    Button("Open Settings") { finish(openSettings: true) }
                        .buttonStyle(.notchly(.standard))
                    Button("Start using Notchly") { finish(openSettings: false) }
                        .buttonStyle(.notchly(.prominent))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func advance() {
        guard let next = step.next else { return }
        step = next
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        step = previous
    }

    private func finish(openSettings: Bool) {
        if applyFirstLaunchDefaults {
            OnboardingDefaults.applyFirstLaunchDefaults(hasNotch: Self.mainScreenHasNotch())
        }
        permissions.stopPolling()
        if openSettings {
            onOpenSettings()
        } else {
            onFinish()
        }
    }

    /// True when the main screen has a physical notch (safe-area inset at the top).
    private static func mainScreenHasNotch() -> Bool {
        (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
    }
}

// MARK: - Progress

/// Three dots; the current one stretches into a capsule.
struct OnboardingProgressDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? NotchlySettingsStyle.accent : NotchlySettingsStyle.track)
                    .frame(width: step == current ? 18 : 6, height: 6)
            }
        }
        .animation(NotchlyTheme.Motion.spring, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current.number) of \(OnboardingStep.count)"))
    }
}

// MARK: - Step 1: Welcome

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image("logo2")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            Text("Notchly")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(OnboardingCopy.tagline)
                .font(.system(size: 14))
                .foregroundStyle(NotchlySettingsStyle.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Step 2: Permissions

struct OnboardingPermissionsStep: View {
    @ObservedObject var permissions: OnboardingPermissionsController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NotchlyPageHeader(
                title: OnboardingCopy.permissionsTitle,
                subtitle: OnboardingCopy.permissionsSubtitle
            )

            NotchlySettingsCard(footer: OnboardingCopy.permissionsFooter) {
                ForEach(OnboardingPermission.allCases) { permission in
                    row(for: permission)
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear { permissions.stopPolling() }
    }

    private func row(for permission: OnboardingPermission) -> some View {
        let status = permissions.status(for: permission)
        return NotchlySettingRow(permission.title, subtitle: permission.detail, symbol: permission.symbol) {
            trailing(for: permission, status: status)
        }
    }

    @ViewBuilder
    private func trailing(for permission: OnboardingPermission, status: OnboardingPermissionStatus) -> some View {
        if status.isGranted {
            Label(status.label, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchlySettingsStyle.textSecondary)
                .labelStyle(.titleAndIcon)
        } else if let title = permission.actionTitle(for: status) {
            Button(title) { permissions.performAction(for: permission) }
                .buttonStyle(.notchly(status == .denied ? .standard : .prominent))
        } else {
            Text(status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchlySettingsStyle.textTertiary)
        }
    }
}

// MARK: - Step 3: Done

struct OnboardingDoneStep: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NotchlySettingsStyle.onAccent)
                .frame(width: 76, height: 76)
                .background {
                    Circle()
                        .fill(NotchlySettingsStyle.accent)
                        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                }
                .accessibilityHidden(true)
                .padding(.bottom, 8)

            Text("You're all set")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.78))
                    .frame(width: 28, height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.sm, style: .continuous)
                            .fill(NotchlySettingsStyle.controlFill)
                    }
                    .accessibilityHidden(true)
                Text(OnboardingCopy.tip)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: 340, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: NotchlyTheme.Radius.lg, style: .continuous)
                    .fill(NotchlySettingsStyle.cardFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: NotchlyTheme.Radius.lg, style: .continuous)
                            .strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
                    }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
