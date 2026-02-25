import AVFoundation
import CoreML
import Accelerate
import Foundation
import QuartzCore

/// Polyphonic pitch detector using Spotify's Basic Pitch CoreML model.
/// Receives audio buffers from AudioManager (does not install its own tap).
class PolyphonicDetector {
    // Basic Pitch model constants
    private static let modelSampleRate: Double = 22050.0
    private static let audioNSamples = 43844
    private static let annotNFrames = 172
    private static let nSemitones = 88
    private static let nContourBins = 264
    private static let contourBinsPerSemitone = 3
    private static let fftHop = 256
    private static let overlappingFrames = 30
    private static let overlapLength = overlappingFrames * fftHop
    private static let hopSize = audioNSamples - overlapLength
    private static let halfOverlapFrames = 15
    private static let framesPerSecond: Double = 86.0 // 22050 / 256
    // A0 = MIDI 21 is the base note
    private static let baseMidiNote = 21

    // Thresholds
    private static let noteThreshold: Float = 0.5
    private static let onsetThreshold: Float = 0.5
    private static let contourThreshold: Float = 0.3

    private let startTime: TimeInterval
    private let onDetections: ([PitchDetection]) -> Void

    private var model: MLModel?
    private var ringBuffer: [Float] = []
    private let processingQueue = DispatchQueue(label: "com.notevisualizer.polyphonic", qos: .userInteractive)
    private var isProcessing = false
    private var windowTimestamp: TimeInterval = 0
    private var windowCount = 0

    init(startTime: TimeInterval, onDetections: @escaping ([PitchDetection]) -> Void) {
        self.startTime = startTime
        self.onDetections = onDetections
        loadModel()
    }

    private func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "nmp", withExtension: "mlmodelc") ??
              Bundle.main.url(forResource: "nmp", withExtension: "mlpackage") else {
            print("[Poly] Basic Pitch model not found in bundle")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try MLModel(contentsOf: modelURL, configuration: config)
            print("[Poly] Model loaded")
        } catch {
            do {
                let compiledURL = try MLModel.compileModel(at: modelURL)
                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: compiledURL, configuration: config)
                print("[Poly] Model compiled and loaded")
            } catch {
                print("[Poly] Failed to load model: \(error)")
            }
        }
    }

    /// Called by AudioManager to feed audio data.
    func processAudio(buffer: AVAudioPCMBuffer) {
        guard model != nil else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let inputSampleRate = buffer.format.sampleRate
        let monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        let resampled = downsample(monoSamples, fromRate: inputSampleRate, toRate: Self.modelSampleRate)
        guard !resampled.isEmpty else { return }

        processingQueue.async { [weak self] in
            guard let self = self else { return }
            self.ringBuffer.append(contentsOf: resampled)

            guard !self.isProcessing, self.ringBuffer.count >= Self.audioNSamples else { return }

            self.isProcessing = true
            let window = Array(self.ringBuffer.prefix(Self.audioNSamples))
            self.ringBuffer.removeFirst(Self.hopSize)

            // Record timestamp for this window
            self.windowTimestamp = CACurrentMediaTime() - self.startTime
            self.runInference(on: window)
            self.isProcessing = false
        }
    }

    private func downsample(_ samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        guard fromRate > 0, toRate > 0 else { return [] }
        if abs(fromRate - toRate) < 1.0 { return samples }

        let ratio = fromRate / toRate
        let outputCount = Int(Double(samples.count) / ratio)
        guard outputCount > 0 else { return [] }

        var output = [Float](repeating: 0, count: outputCount)
        var control = [Float](repeating: 0, count: outputCount)
        var rampStart: Float = 0
        var rampStep = Float(ratio)
        vDSP_vramp(&rampStart, &rampStep, &control, 1, vDSP_Length(outputCount))

        let maxIndex = Float(samples.count - 2)
        var low: Float = 0
        var high = maxIndex
        vDSP_vclip(control, 1, &low, &high, &control, 1, vDSP_Length(outputCount))

        vDSP_vlint(samples, control, 1, &output, 1, vDSP_Length(outputCount), vDSP_Length(samples.count))
        return output
    }

    private func runInference(on audioWindow: [Float]) {
        guard let model = model else { return }

        // Check audio has content
        let rms = sqrt(audioWindow.map { $0 * $0 }.reduce(0, +) / Float(audioWindow.count))
        guard rms > 0.005 else { return } // Skip silence

        do {
            // Use MLShapedArray for reliable data layout
            var shaped = MLShapedArray<Float>(repeating: 0, shape: [1, Self.audioNSamples, 1])
            for i in 0..<min(audioWindow.count, Self.audioNSamples) {
                shaped[scalarAt: 0, i, 0] = audioWindow[i]
            }
            let inputArray = MLMultiArray(shaped)

            let provider = try MLDictionaryFeatureProvider(
                dictionary: ["input_2": MLFeatureValue(multiArray: inputArray)]
            )

            let result = try model.prediction(from: provider)

            guard let noteOutput = result.featureValue(for: "Identity_1")?.multiArrayValue,
                  let contourOutput = result.featureValue(for: "Identity")?.multiArrayValue,
                  let onsetOutput = result.featureValue(for: "Identity_2")?.multiArrayValue else {
                return
            }

            let detections = extractPerFrameDetections(
                noteOutput: noteOutput,
                contourOutput: contourOutput,
                onsetOutput: onsetOutput
            )

            windowCount += 1
            if windowCount % 5 == 0 {
                print("[Poly] Window \(windowCount): \(detections.count) detections, RMS: \(String(format: "%.4f", rms))")
            }

            if !detections.isEmpty {
                self.onDetections(detections)
            }
        } catch {
            print("[Poly] Inference error: \(error)")
        }
    }

    private func extractPerFrameDetections(
        noteOutput: MLMultiArray,
        contourOutput: MLMultiArray,
        onsetOutput: MLMultiArray
    ) -> [PitchDetection] {
        let noteData = MLShapedArray<Float>(noteOutput)
        let contourData = MLShapedArray<Float>(contourOutput)

        let startFrame = Self.halfOverlapFrames
        let endFrame = Self.annotNFrames - Self.halfOverlapFrames
        let frameDuration = 1.0 / Self.framesPerSecond

        // The window covers ~2 seconds ending at windowTimestamp
        let windowDuration = Double(Self.audioNSamples) / Self.modelSampleRate
        let windowStartTime = windowTimestamp - windowDuration

        var detections: [PitchDetection] = []

        for frame in startFrame..<endFrame {
            let frameTime = windowStartTime + Double(frame) * frameDuration

            for note in 0..<Self.nSemitones {
                let noteActivation = noteData[scalarAt: 0, frame, note]
                guard noteActivation > Self.noteThreshold else { continue }

                // Use contour output for fine pitch (3 bins per semitone)
                let contourBase = note * Self.contourBinsPerSemitone
                var bestContourBin = contourBase
                var bestContourVal: Float = 0
                for b in 0..<Self.contourBinsPerSemitone {
                    let binIdx = contourBase + b
                    guard binIdx < Self.nContourBins else { break }
                    let val = contourData[scalarAt: 0, frame, binIdx]
                    if val > bestContourVal {
                        bestContourVal = val
                        bestContourBin = binIdx
                    }
                }

                // Fine pitch from contour bin
                let finePitch = Double(Self.baseMidiNote) + Double(bestContourBin) / Double(Self.contourBinsPerSemitone)
                let frequency = FrequencyUtils.frequencyFromMidiNote(finePitch)
                let amplitude = Double(min(noteActivation / 0.8, 1.0))

                let midiNote = Self.baseMidiNote + note
                let centsFromContour = (finePitch - Double(midiNote)) * 100.0

                let detection = PitchDetection(
                    timestamp: frameTime,
                    frequency: frequency,
                    amplitude: amplitude,
                    midiNote: midiNote,
                    noteName: FrequencyUtils.noteName(for: midiNote),
                    octave: FrequencyUtils.octave(for: midiNote),
                    centsOffset: centsFromContour
                )
                detections.append(detection)
            }
        }

        return detections
    }

    func stop() {}
}
