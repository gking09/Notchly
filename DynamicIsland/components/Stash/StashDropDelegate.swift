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

/// Receives drags over the notch window. The notch layer decides what a drag
/// entering or leaving means (opening the tab, closing again); this only
/// reports it and hands dropped items to the manager.
struct StashDropDelegate: DropDelegate {
    /// Whether the Stash currently takes drops (enabled, unlocked, not minimalistic).
    let isEnabled: () -> Bool
    let onTargetChange: (Bool) -> Void
    let onDrop: ([NSItemProvider]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled() && info.hasItemsConforming(to: StashDropReader.acceptedTypes)
    }

    func dropEntered(info: DropInfo) {
        onTargetChange(true)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        onTargetChange(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: StashDropReader.acceptedTypes)
        onTargetChange(false)
        guard !providers.isEmpty else { return false }
        onDrop(providers)
        return true
    }
}
