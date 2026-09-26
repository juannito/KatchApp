import AppKit
import CoreAudio
import Foundation

/// A process known to Core Audio (it has an audio client), with its live input/output state.
struct AudioProcess: Identifiable, Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String
    let name: String
    let isRunningOutput: Bool   // currently playing sound
    let isRunningInput: Bool    // currently using the microphone

    var id: AudioObjectID { objectID }
}

enum AudioProcesses {
    /// Browsers and Electron apps play audio from helper processes; fold them into the parent app
    /// so "Zoom", "Chrome" or "Safari" match whatever process actually carries the sound.
    static func canonicalBundleID(_ bundleID: String, name: String) -> String {
        if bundleID == "com.apple.WebKit.GPU" || bundleID == "com.apple.WebKit.WebContent" {
            return name.hasPrefix("Safari") ? "com.apple.Safari" : bundleID
        }
        for suffix in [".helper", ".Helper", ".helper.renderer", ".helper.plugin", ".ServiceExtension"] where bundleID.hasSuffix(suffix) {
            return String(bundleID.dropLast(suffix.count))
        }
        if let r = bundleID.range(of: ".helper.") { return String(bundleID[..<r.lowerBound]) }
        return bundleID
    }

    /// Snapshot of every process Core Audio knows about. Cheap (a few property reads).
    static func list() -> [AudioProcess] {
        guard let ids = try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)
        else { return [] }
        var out: [AudioProcess] = []
        for id in ids {
            let pid = (try? id.read(kAudioProcessPropertyPID, defaultValue: pid_t(0))) ?? 0
            let running = NSRunningApplication(processIdentifier: pid)
            var bundle = (try? id.read(kAudioProcessPropertyBundleID, defaultValue: "" as CFString) as String) ?? ""
            if bundle.isEmpty { bundle = running?.bundleIdentifier ?? "" }
            guard !bundle.isEmpty else { continue }
            let rawName = running?.localizedName ?? bundle
            bundle = canonicalBundleID(bundle, name: rawName)
            let name = running?.localizedName ?? bundle
            let output = ((try? id.read(kAudioProcessPropertyIsRunningOutput, defaultValue: UInt32(0))) ?? 0) != 0
            let input = ((try? id.read(kAudioProcessPropertyIsRunningInput, defaultValue: UInt32(0))) ?? 0) != 0
            out.append(AudioProcess(objectID: id, pid: pid, bundleID: bundle, name: name, isRunningOutput: output, isRunningInput: input))
        }
        return out
    }
}
