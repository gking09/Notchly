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
import CoreAudio

/// Mutes and unmutes the default input device through public CoreAudio
/// properties.
///
/// Devices differ in what they expose: many have a hardware mute switch
/// (`kAudioDevicePropertyMute`), others only an input gain. The controller
/// prefers the mute switch and falls back to driving the gain to zero,
/// remembering the level to restore. A device with neither cannot be muted, and
/// `setMuted` reports that by returning false.
final class MicrophoneMuteController {
    static let shared = MicrophoneMuteController()

    /// Input gain to restore when un-muting a device that has no mute switch.
    private var savedVolumes: [AudioDeviceID: Float32] = [:]

    private let scope = kAudioObjectPropertyScopeInput
    /// Main element first, then the first few channels: some devices only
    /// expose the property per channel.
    private let candidateElements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2]

    private init() {}

    // MARK: Device

    private func defaultInputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private func address(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    /// First element of `selector` the device has and lets us write.
    private func settableElement(
        _ selector: AudioObjectPropertySelector,
        on device: AudioDeviceID
    ) -> AudioObjectPropertyElement? {
        for element in candidateElements {
            var addr = address(selector, element: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue {
                return element
            }
        }
        return nil
    }

    private func readUInt32(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        on device: AudioDeviceID
    ) -> UInt32? {
        var addr = address(selector, element: element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func readFloat(
        _ selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement,
        on device: AudioDeviceID
    ) -> Float32? {
        var addr = address(selector, element: element)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    // MARK: State

    /// Whether the default input is currently muted (or at zero gain).
    /// False when there is no input device or it exposes neither control.
    func isMuted() -> Bool {
        guard let device = defaultInputDevice() else { return false }

        if let element = settableElement(kAudioDevicePropertyMute, on: device),
           let value = readUInt32(kAudioDevicePropertyMute, element: element, on: device) {
            return value != 0
        }
        if let element = settableElement(kAudioDevicePropertyVolumeScalar, on: device),
           let value = readFloat(kAudioDevicePropertyVolumeScalar, element: element, on: device) {
            return value <= 0.001
        }
        return false
    }

    /// True if the default input has a control we can drive.
    func canMute() -> Bool {
        guard let device = defaultInputDevice() else { return false }
        return settableElement(kAudioDevicePropertyMute, on: device) != nil
            || settableElement(kAudioDevicePropertyVolumeScalar, on: device) != nil
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultInputDevice() else { return false }

        if let element = settableElement(kAudioDevicePropertyMute, on: device) {
            var addr = address(kAudioDevicePropertyMute, element: element)
            var value: UInt32 = muted ? 1 : 0
            let status = AudioObjectSetPropertyData(
                device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value
            )
            return status == noErr
        }

        if let element = settableElement(kAudioDevicePropertyVolumeScalar, on: device) {
            var addr = address(kAudioDevicePropertyVolumeScalar, element: element)
            if muted {
                if let current = readFloat(kAudioDevicePropertyVolumeScalar, element: element, on: device),
                   current > 0.001 {
                    savedVolumes[device] = current
                }
                var zero: Float32 = 0
                return AudioObjectSetPropertyData(
                    device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &zero
                ) == noErr
            } else {
                var restored: Float32 = savedVolumes[device] ?? 0.75
                return AudioObjectSetPropertyData(
                    device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &restored
                ) == noErr
            }
        }

        return false
    }
}
