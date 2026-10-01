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

import Defaults
import SwiftUI

/// Cider's API token, needed only for the Favorite Song control.
///
/// Playback works without any of this -- it comes from macOS Now Playing. Only
/// favouriting has to ask Cider directly, so the section says so rather than
/// looking like a requirement for the source as a whole.
struct CiderFavoritingSettingsSection: View {
    @State private var token: String = CiderTokenStore.shared.token

    var body: some View {
        NotchlySettingsCard(
            "Favorite song in Cider",
            footer: "In Cider, open Settings > Connectivity > Manage External Application Access, switch the API on, and paste the token it generates. If you turn its authentication off instead, leave this empty."
        ) {
            NotchlySettingRow(
                "API token",
                subtitle: "Playback needs none of this. Only the Favorite Song control does, because macOS Now Playing cannot carry favourites."
            ) {
                NotchlyTextField(placeholder: String(localized: "API token"), text: $token, width: 220, isSecure: true)
                    .onChange(of: token) { _, value in
                        CiderTokenStore.shared.setToken(value)
                    }
            }
        }
    }
}
