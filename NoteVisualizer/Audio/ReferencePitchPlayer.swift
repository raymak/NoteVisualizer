import AudioKit
import SoundpipeAudioKit
import AVFoundation

@Observable
@MainActor
class ReferencePitchPlayer {
    private(set) var heldNotes: Set<Int> = []
    private(set) var loadError: String?

    let outputNode: Mixer

    private var currentSource: ReferenceSource = .sine
    var volume: Double = 0.5

    /// One oscillator per held MIDI note when in waveform mode.
    private var oscillators: [Int: Oscillator] = [:]

    init() {
        outputNode = Mixer()
    }

    func setSource(_ source: ReferenceSource) {
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil
    }

    func noteOn(midi: Int) {
        heldNotes.insert(midi)
        switch currentSource {
        case .sine, .triangle, .square, .sawtooth:
            startOscillator(midi: midi, waveform: currentSource)
        case .soundFont:
            break  // implemented in next task
        }
    }

    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        if let osc = oscillators.removeValue(forKey: midi) {
            osc.stop()
            outputNode.removeInput(osc)
        }
    }

    private func startOscillator(midi: Int, waveform: ReferenceSource) {
        let table = Self.table(for: waveform)
        let freq = AUValue(FrequencyUtils.frequencyFromMidiNote(Double(midi)))
        let osc = Oscillator(waveform: table, frequency: freq, amplitude: AUValue(volume))
        outputNode.addInput(osc)
        osc.start()
        oscillators[midi] = osc
    }

    private static func table(for waveform: ReferenceSource) -> Table {
        switch waveform {
        case .sine: return Table(.sine)
        case .triangle: return Table(.triangle)
        case .square: return Table(.square)
        case .sawtooth: return Table(.sawtooth)
        case .soundFont: return Table(.sine)  // unused
        }
    }
}
