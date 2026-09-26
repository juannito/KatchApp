// Captures everything the Mac is playing (Zoom, Meet, Teams, browser...) with a
// Core Audio process tap (macOS 14.4+). No virtual driver needed.
// Setup sequence adapted from AudioCap (MIT, Guilherme Rambo).

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

final class SystemAudioTap {
    typealias Handler = ([Float]) -> Void

    private var tapID: AudioObjectID = .unknown
    private var aggregateID: AudioObjectID = .unknown
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "meetai.systemtap", qos: .userInitiated)
    private var format: AVAudioFormat?
    private var resampler: StreamResampler?
    private let handler: Handler
    private(set) var isRunning = false

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() throws {
        guard !isRunning else { return }

        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.name = "MeetAI system audio"

        var newTapID: AudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(description, &newTapID)
        guard err == noErr else {
            throw AudioError(L("Could not create the system audio tap (error %d). Check System Settings > Privacy & Security > System Audio Recording.", Int(err)))
        }
        tapID = newTapID

        do {
            let outputID = try AudioObjectID.readDefaultSystemOutputDevice()
            let outputUID = try outputID.readDeviceUID()
            var asbd = try tapID.readAudioTapStreamBasicDescription()
            guard let fmt = AVAudioFormat(streamDescription: &asbd) else {
                throw AudioError("Invalid tap stream format")
            }
            format = fmt
            resampler = try StreamResampler(inputFormat: fmt)

            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "MeetAI Tap",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: description.uuid.uuidString,
                    ]
                ],
            ]

            var newAggregateID: AudioObjectID = .unknown
            err = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &newAggregateID)
            guard err == noErr else { throw AudioError("No se pudo crear el aggregate device (error \(err))") }
            aggregateID = newAggregateID

            err = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
                guard let self, let fmt = self.format else { return }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: fmt, bufferListNoCopy: inInputData, deallocator: nil) else {
                    return
                }
                if let out = try? self.resampler?.process(buffer), !out.isEmpty {
                    self.handler(out)
                }
            }
            guard err == noErr else { throw AudioError("No se pudo crear el IOProc (error \(err))") }

            err = AudioDeviceStart(aggregateID, procID)
            guard err == noErr else { throw AudioError("No se pudo iniciar el aggregate device (error \(err))") }
            isRunning = true
        } catch {
            teardown()
            throw error
        }
    }

    func stop() {
        teardown()
    }

    private func teardown() {
        if aggregateID.isValid {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                self.procID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = .unknown
        }
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = .unknown
        }
        isRunning = false
    }

    deinit { teardown() }
}
