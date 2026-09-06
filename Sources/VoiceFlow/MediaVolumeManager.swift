import Foundation
import CoreAudio
import AudioToolbox
import os.log

public final class MediaVolumeManager: @unchecked Sendable {
    public static let shared = MediaVolumeManager()

    private let logger = Config.logger
    private let queue = DispatchQueue(label: "com.dakshhiran.plume.mediavolume", qos: .userInteractive)
    private var originalSystemVolume: Float32?
    private var isDucked = false

    private init() {}

    private func getDefaultOutputDevice() -> AudioDeviceID {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID
        )
        return defaultOutputDeviceID
    }

    private func getSystemVolume() -> Float32 {
        let deviceID = getDefaultOutputDevice()
        guard deviceID != 0 else { return 0.5 }

        var volume = Float32(0.0)
        var volumeSize = UInt32(MemoryLayout.size(ofValue: volume))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &volumeSize,
            &volume
        )
        return status == noErr ? volume : 0.5
    }

    private func setSystemVolume(_ volume: Float32) {
        let deviceID = getDefaultOutputDevice()
        guard deviceID != 0 else { return }

        var vol = max(0.0, min(1.0, volume))
        let volumeSize = UInt32(MemoryLayout.size(ofValue: vol))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(
            deviceID,
            &address,
            0, nil,
            volumeSize,
            &vol
        )
    }

    /// Ducks active media (Spotify, YouTube, Apple Music, browsers) during active dictation
    /// so the microphone captures speech clearly without speaker feedback.
    public func duckIfPlaying() {
        queue.async { [weak self] in
            guard let self = self, !self.isDucked else { return }

            let currentVol = self.getSystemVolume()
            // Only duck if volume is audible (> 10%)
            guard currentVol > 0.10 else { return }

            self.originalSystemVolume = currentVol
            self.isDucked = true

            // Reduce volume to 20% of current level (minimum 0.06 so it's not completely muted)
            let duckedVol = max(0.06, currentVol * 0.20)
            self.setSystemVolume(duckedVol)
            self.logger.info("Ducked system audio volume from \(currentVol) to \(duckedVol) for active dictation.")
        }
    }

    /// Restores active media volume immediately after dictation completes or cancels.
    public func restore() {
        queue.async { [weak self] in
            guard let self = self, self.isDucked, let orig = self.originalSystemVolume else { return }

            self.isDucked = false
            self.originalSystemVolume = nil
            self.setSystemVolume(orig)
            self.logger.info("Restored system audio volume back to \(orig).")
        }
    }
}
