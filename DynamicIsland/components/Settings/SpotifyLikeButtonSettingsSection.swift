/*
 * Atoll (DynamicIsland)
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

struct SpotifyLikeButtonSettingsSection: View {
    @Default(.spotifyLibraryClientID) private var clientID
    @ObservedObject private var libraryManager = SpotifyLibraryManager.shared

    var body: some View {
        NotchlySettingsCard(
            "Spotify like button",
            footer: "Uses Spotify's official Web API with access limited to reading and changing your Liked Songs. Add the Like Song control to a media slot to show the button."
        ) {
            NotchlySettingRow(
                "Client ID",
                subtitle: "The like button needs its own free Spotify app (the Canvas cookie cannot change your library). Create one at developer.spotify.com, add the redirect URI below, and paste its Client ID."
            ) {
                NotchlyTextField(placeholder: "Client ID", text: $clientID, width: 220, monospaced: true)
            }

            NotchlySettingRow("Redirect URI", subtitle: "Add this exactly in your Spotify app settings.") {
                Text(SpotifyLibraryManager.redirectURI)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(NotchlySettingsStyle.textSecondary)
                    .textSelection(.enabled)
            }

            NotchlySettingRow("Status", subtitle: statusText) {
                Circle()
                    .fill(libraryManager.isAuthenticated ? Color(nsColor: .systemGreen) : NotchlySettingsStyle.textTertiary)
                    .frame(width: 9, height: 9)
            }

            if let error = libraryManager.error, !message(for: error).isEmpty {
                NotchlyNoticeRow(text: message(for: error), isError: true)
            }

            NotchlySettingRow("Account") {
                HStack(spacing: 6) {
                    Button(libraryManager.isAuthorizing ? "Connecting..." : "Connect") {
                        libraryManager.connect()
                    }
                    .buttonStyle(.notchly(.prominent))
                    .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || libraryManager.isAuthorizing)

                    Button("Disconnect") {
                        libraryManager.disconnect()
                    }
                    .buttonStyle(.notchly(.standard))
                    .disabled(!libraryManager.isAuthenticated)
                }
            }

            NotchlyActionRow(title: "Open Developer Dashboard") {
                NSWorkspace.shared.open(URL(string: "https://developer.spotify.com/dashboard")!)
            }
        }
    }

    /// Derived from the view's own client ID binding rather than the manager's
    /// copy, so the line updates while the user is still typing.
    private var statusText: String {
        if libraryManager.isAuthenticated {
            return String(localized: "Connected — like button ready.")
        }
        if clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Not connected.")
        }
        return String(localized: "Client ID saved. Connect your Spotify account.")
    }

    private func message(for error: SpotifyLibraryError) -> String {
        switch error {
        case .missingClientID:
            return String(localized: "Paste the Client ID of your Spotify Developer app first.")
        case .secureRandomUnavailable:
            return String(localized: "Unable to generate secure random data for the login.")
        case .canceled:
            return ""
        case .missingAuthorizationCode:
            return String(localized: "Spotify did not return an authorization code.")
        case .authSessionFailed(let description):
            return String(localized: "Spotify login failed: \(description)")
        case .tokenExchangeFailed(let description):
            return String(localized: "Token exchange failed: \(description)")
        case .refreshTokenRevoked:
            return String(localized: "Spotify revoked access. Connect your account again.")
        }
    }
}
