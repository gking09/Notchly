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

/// What Notchly stands on: the projects it descends from and the libraries it ships with.
enum NotchlyCredits {
    struct Credit: Identifiable, Equatable {
        let name: String
        let author: String
        let url: URL
        var id: String { name }
    }

    static let licenseURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!

    /// Notchly is a fork of Atoll...
    static let atoll = Credit(
        name: "Atoll",
        author: "Ebullioscopic",
        url: URL(string: "https://github.com/Ebullioscopic/Atoll")!
    )

    /// ...which builds on boring.notch.
    static let boringNotch = Credit(
        name: "boring.notch",
        author: "TheBoredTeam",
        url: URL(string: "https://github.com/TheBoredTeam/boring.notch")!
    )

    /// Dependencies that are still part of the project (Swift packages and bundled code).
    static let dependencies: [Credit] = [
        Credit(name: "Defaults", author: "Sindre Sorhus", url: URL(string: "https://github.com/sindresorhus/Defaults")!),
        Credit(name: "KeyboardShortcuts", author: "Sindre Sorhus", url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!),
        Credit(name: "LaunchAtLogin-Modern", author: "Sindre Sorhus", url: URL(string: "https://github.com/sindresorhus/LaunchAtLogin-Modern")!),
        Credit(name: "SkyLightWindow", author: "Lakr233", url: URL(string: "https://github.com/Lakr233/SkyLightWindow")!),
        Credit(name: "lottie-spm", author: "Airbnb", url: URL(string: "https://github.com/airbnb/lottie-spm")!),
        Credit(name: "LottieUI", author: "jasudev", url: URL(string: "https://github.com/jasudev/LottieUI")!),
        Credit(name: "swiftui-introspect", author: "Siteline", url: URL(string: "https://github.com/siteline/swiftui-introspect")!),
        Credit(name: "MacroVisionKit", author: "TheBoredTeam", url: URL(string: "https://github.com/TheBoredTeam/MacroVisionKit")!),
        Credit(name: "mediaremote-adapter", author: "ungive", url: URL(string: "https://github.com/ungive/mediaremote-adapter")!),
    ]
}

/// The About page: identity, version, and a visible Credits & License card.
struct NotchlyAboutPage: View {
    @State private var showBuild = false

    private var versionText: String {
        let version = Bundle.main.releaseVersionNumber ?? "-"
        guard showBuild, let build = Bundle.main.buildVersionNumber else { return String(localized: "Version \(version)") }
        return String(localized: "Version \(version) (\(build))")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero
                licenseCard
                lineageCard
                acknowledgementsCard
                welcomeCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 4)
            .padding(.bottom, 28)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image("logo2")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(NotchlySettingsStyle.cardStroke, lineWidth: NotchlyTheme.Stroke.hairline)
                }
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                .accessibilityHidden(true)

            Text("Notchly")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Button {
                withAnimation(NotchlyTheme.Motion.spring) { showBuild.toggle() }
            } label: {
                Text(versionText)
                    .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    .contentTransition(.numericText())
            }
            .buttonStyle(.plain)
            .help("Click to show the build number")

            Text("A calm, glass-and-silver home for everything the notch can do.")
                .font(.system(size: 13))
                .foregroundStyle(NotchlySettingsStyle.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Cards

    private var licenseCard: some View {
        NotchlySettingsCard("Credits & License") {
            NotchlySettingRow(
                "Free software, GPL-3.0",
                subtitle: "Notchly is released under the GNU General Public License, version 3. You are free to use, study, share and change it under the same terms."
            ) {
                Button("View license") { NSWorkspace.shared.open(NotchlyCredits.licenseURL) }
                    .buttonStyle(.notchly(.standard))
            }
        }
    }

    private var lineageCard: some View {
        NotchlySettingsCard(
            "Built on",
            footer: "Thank you to both projects and everyone who contributed to them."
        ) {
            creditRow(NotchlyCredits.atoll, subtitle: "Notchly is a fork of Atoll by \(NotchlyCredits.atoll.author)")
            creditRow(NotchlyCredits.boringNotch, subtitle: "Atoll builds on boring.notch by \(NotchlyCredits.boringNotch.author)")
        }
    }

    private var acknowledgementsCard: some View {
        NotchlySettingsCard(
            "Acknowledgements",
            footer: "The \"Fingerprint Scan\" animation is by Eddy Gann, used under the Lottie Simple License."
        ) {
            ForEach(NotchlyCredits.dependencies) { credit in
                creditRow(credit, subtitle: credit.author)
            }
        }
    }

    private var welcomeCard: some View {
        NotchlySettingsCard {
            NotchlyActionRow(
                title: "Show Welcome Again",
                subtitle: "Replay the first-launch introduction.",
                symbol: "arrow.counterclockwise"
            ) {
                AppDelegate.shared?.showOnboardingWindow(isReplay: true)
            }
        }
    }

    private func creditRow(_ credit: NotchlyCredits.Credit, subtitle: String) -> some View {
        NotchlyActionRow(title: credit.name, subtitle: subtitle) {
            NSWorkspace.shared.open(credit.url)
        }
    }
}
