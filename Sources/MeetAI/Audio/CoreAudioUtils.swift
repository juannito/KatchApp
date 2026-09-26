// Core Audio property helpers.
// Adapted from AudioCap (https://github.com/insidegui/AudioCap), MIT License,
// Copyright (c) 2024 Guilherme Rambo.

import AudioToolbox
import CoreAudio
import Foundation

struct AudioError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)
    static let unknown = kAudioObjectUnknown
    var isValid: Bool { self != kAudioObjectUnknown }

    static func readDefaultSystemOutputDevice() throws -> AudioDeviceID {
        try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultSystemOutputDevice, defaultValue: AudioDeviceID.unknown)
    }

    func readDeviceUID() throws -> String {
        try read(kAudioDevicePropertyDeviceUID, defaultValue: "" as CFString) as String
    }

    func readAudioTapStreamBasicDescription() throws -> AudioStreamBasicDescription {
        try read(kAudioTapPropertyFormat, defaultValue: AudioStreamBasicDescription())
    }

    func read<T>(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
        defaultValue: T
    ) throws -> T {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(self, &address, 0, nil, &dataSize)
        guard err == noErr else { throw AudioError("AudioObjectGetPropertyDataSize failed: \(err)") }
        var value: T = defaultValue
        err = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(self, &address, 0, nil, &dataSize, ptr)
        }
        guard err == noErr else { throw AudioError("AudioObjectGetPropertyData failed: \(err)") }
        return value
    }
}
