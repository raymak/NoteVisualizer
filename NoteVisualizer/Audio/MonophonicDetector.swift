import AudioKit
import SoundpipeAudioKit
import Foundation
import QuartzCore

// Monophonic detection is handled directly in AudioManager via PitchTap.
// This file provides a standalone wrapper if needed for testing or alternative configurations.

class MonophonicDetector {
    private var pitchTap: PitchTap?
    private let startTime: TimeInterval
    var onDetection: (([PitchDetection]) -> Void)?

    init(input: AudioEngine.InputNode, startTime: TimeInterval) {
        self.startTime = startTime
        pitchTap = PitchTap(input, bufferSize: 4096) { [weak self] frequency, amplitude in
            guard let self = self else { return }
            let freq = Double(frequency[0])
            let amp = Double(amplitude[0])
            guard freq > 50 && freq < 2000 && amp > 0.02 else { return }

            let timestamp = CACurrentMediaTime() - self.startTime
            let detection = FrequencyUtils.detectionFromFrequency(freq, amplitude: min(amp, 1.0), timestamp: timestamp)
            self.onDetection?([detection])
        }
    }

    func start() {
        pitchTap?.start()
    }

    func stop() {
        pitchTap?.stop()
    }
}
