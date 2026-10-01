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

/// Settings card for the Spotify Canvas cookie session.
struct SpotifyAuthSettingsSection: View {
    @Default(.spotifySPDCCookie) private var spotifySPDCCookie
    @ObservedObject private var spotifyAuthManager = SpotifyAuthManager.shared
    @State private var showingLoginSheet = false
    @State private var showingManualSteps = false

    private var hasCookie: Bool {
        !SpotifyAuthManager.sanitizeCookie(spotifySPDCCookie).isEmpty
    }

    private var statusColor: Color {
        if spotifyAuthManager.isAuthenticated { return Color(nsColor: .systemGreen) }
        return hasCookie ? Color(nsColor: .systemOrange) : NotchlySettingsStyle.textTertiary
    }

    var body: some View {
        NotchlySettingsCard(
            "Spotify canvas session",
            footer: "Notchly uses the local sp_dc cookie only to ask Spotify's web player for a token and fetch the Canvas of the current track."
        ) {
            NotchlySettingRow("Sign in with Spotify", subtitle: "Captures the sp_dc cookie for you.") {
                Button {
                    showingLoginSheet = true
                } label: {
                    Label("Sign in", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.notchly(.prominent))
            }

            NotchlySettingRow("Session", subtitle: spotifyAuthManager.sessionStatusText) {
                Circle().fill(statusColor).frame(width: 9, height: 9)
            }

            NotchlySettingRow("sp_dc cookie", subtitle: "Signing in fills this in, or paste it yourself.") {
                NotchlyTextField(placeholder: "sp_dc cookie", text: $spotifySPDCCookie, width: 220, monospaced: true)
            }

            if let authErrorMessage = spotifyAuthManager.authErrorMessage, !authErrorMessage.isEmpty {
                NotchlyNoticeRow(text: authErrorMessage, isError: true)
            }

            NotchlySettingRow("Cookie") {
                HStack(spacing: 6) {
                    Button("Paste") { pasteCookieFromClipboard() }
                        .buttonStyle(.notchly(.standard))

                    Button(spotifyAuthManager.isAuthorizing ? "Validating..." : "Validate") {
                        spotifySPDCCookie = SpotifyAuthManager.sanitizeCookie(spotifySPDCCookie)
                        Task { await spotifyAuthManager.validateSession() }
                    }
                    .buttonStyle(.notchly(.standard))
                    .disabled(!hasCookie || spotifyAuthManager.isAuthorizing)

                    Button("Clear") {
                        spotifySPDCCookie = ""
                        spotifyAuthManager.clearSession()
                    }
                    .buttonStyle(.notchly(.quiet))
                    .disabled(!hasCookie && !spotifyAuthManager.isAuthenticated)
                }
            }

            NotchlyActionRow(
                title: "Get the cookie manually",
                subtitle: showingManualSteps ? nil : "Steps for copying it from your browser.",
                symbol: showingManualSteps ? "chevron.up" : "chevron.down"
            ) {
                withAnimation(NotchlyTheme.Motion.snappy) { showingManualSteps.toggle() }
            }

            if showingManualSteps {
                VStack(alignment: .leading, spacing: 6) {
                    Text("1. Open Spotify in a browser and log in")
                    Text("2. Developer Tools, Application or Storage, Cookies, https://open.spotify.com")
                    Text("3. Copy the value of sp_dc and paste it above")
                    HStack(spacing: 14) {
                        Link("Open Spotify Web Player", destination: URL(string: "https://open.spotify.com")!)
                        Link("Method source", destination: URL(string: "https://github.com/Paxsenix0/Spotify-Canvas-API")!)
                    }
                    .padding(.top, 2)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(NotchlySettingsStyle.textSecondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingLoginSheet) {
            SpotifyLoginSheet { capturedValue in
                let sanitized = SpotifyAuthManager.sanitizeCookie(capturedValue)
                spotifySPDCCookie = sanitized
                Task { await spotifyAuthManager.validateSession() }
            }
        }
    }

    private func pasteCookieFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else { return }
        spotifySPDCCookie = SpotifyAuthManager.sanitizeCookie(clipboardText)
    }
}
