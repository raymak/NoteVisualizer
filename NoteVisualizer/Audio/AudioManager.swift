import AudioKit
import AudioKitEX
import SoundpipeAudioKit
import AVFoundation
import SwiftUI
import QuartzCore

@Observable
@MainActor
class AudioManager {
    var settings: AppSettings?
    var detections: [PitchDetection] = []
    var isRunning = false

    // Recording — only keeps the latest
    var isRecording = false
    var latestRecording: Recording?
    private var currentRecordingDetections: [PitchDetection] = []
    private var recordingStartTime: TimeInterval = 0

    private var engine = AudioEngine()
    private var pitchTap: PitchTap?
    private var polyTap: RawBufferTap?
    private var startTime: TimeInterval = 0
    private let maxDetections = 3000

    private var polyMixer: Mixer?
    private var polyphonicDetector: PolyphonicDetector?

    let soundFontStore: SoundFontStore
    var referencePlayer: ReferencePitchPlayer

    init() {
        let store = SoundFontStore()
        self.soundFontStore = store
        self.referencePlayer = ReferencePitchPlayer(soundFontStore: store)
    }

    func start() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }
        #endif

        guard let input = engine.input else {
            print("No audio input available")
            return
        }

        startTime = CACurrentMediaTime()

        // Single mixer for poly tap — avoids stereo mismatch
        polyMixer = Mixer(input)

        polyphonicDetector = PolyphonicDetector(startTime: startTime) { [weak self] newDetections in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if self.settings?.detectionMode == .polyphonic {
                    self.addDetections(newDetections)
                }
            }
        }

        // PitchTap directly on input for monophonic detection
        pitchTap = PitchTap(input, bufferSize: 4096) { [weak self] frequency, amplitude in
            guard let self = self else { return }
            let freq = Double(frequency[0])
            let amp = Double(amplitude[0])
            guard freq > 50 && freq < 2000 && amp > 0.02 else { return }

            let timestamp = CACurrentMediaTime() - self.startTime
            let detection = FrequencyUtils.detectionFromFrequency(freq, amplitude: min(amp, 1.0), timestamp: timestamp)

            DispatchQueue.main.async {
                if self.settings?.detectionMode == .monophonic {
                    self.addDetections([detection])
                }
            }
        }

        // RawBufferTap on polyMixer for polyphonic detection
        polyTap = RawBufferTap(polyMixer!, bufferSize: 4096) { [weak self] buffer, _ in
            self?.polyphonicDetector?.processAudio(buffer: buffer)
        }

        // Combine the silenced mic-tap path with the reference-pitch output
        let silence = Fader(polyMixer!, gain: 0)
        engine.output = Mixer([silence, referencePlayer.outputNode])

        do {
            try engine.start()
            isRunning = true
            pitchTap?.start()
            polyTap?.start()
            print("[Audio] Engine started, both taps active")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }

    func applyReferenceSettings(source: ReferenceSource, volume: Double) {
        referencePlayer.volume = volume
        referencePlayer.setSource(source)
    }

    func stop() {
        pitchTap?.stop()
        polyTap?.stop()
        engine.stop()
        polyphonicDetector?.stop()
        isRunning = false
    }

    private func addDetections(_ newDetections: [PitchDetection]) {
        detections.append(contentsOf: newDetections)
        if detections.count > maxDetections {
            detections.removeFirst(detections.count - maxDetections)
        }

        // Record if active
        if isRecording {
            currentRecordingDetections.append(contentsOf: newDetections)
        }
    }

    // MARK: - Recording

    func startRecording() {
        currentRecordingDetections.removeAll()
        recordingStartTime = currentTimestamp
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
        guard !currentRecordingDetections.isEmpty else { return }

        // Normalize timestamps relative to recording start
        let normalizedDetections = currentRecordingDetections.map { detection in
            PitchDetection(
                timestamp: detection.timestamp - recordingStartTime,
                frequency: detection.frequency,
                amplitude: detection.amplitude,
                midiNote: detection.midiNote,
                noteName: detection.noteName,
                octave: detection.octave,
                centsOffset: detection.centsOffset
            )
        }

        let duration = (currentRecordingDetections.last?.timestamp ?? 0) - recordingStartTime
        let recording = Recording(
            date: Date(),
            duration: duration,
            detections: normalizedDetections,
            mode: settings?.detectionMode ?? .monophonic
        )
        latestRecording = recording
        currentRecordingDetections.removeAll()
    }

    func clearDetections() {
        detections.removeAll()
    }

    var currentTimestamp: TimeInterval {
        CACurrentMediaTime() - startTime
    }
}
