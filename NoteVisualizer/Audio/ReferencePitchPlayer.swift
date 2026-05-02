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
    var volume: Double = 0.5 {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume { volume = clamped }
        }
    }

    /// One oscillator per held MIDI note when in waveform mode.
    private var oscillators: [Int: Oscillator] = [:]

    private var midiSampler: MIDISampler?
    private var soundFontStore: SoundFontStore?

    init(soundFontStore: SoundFontStore? = nil) {
        outputNode = Mixer()
        self.soundFontStore = soundFontStore
    }

    func setSource(_ source: ReferenceSource) {
        guard source != currentSource else { return }
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil

        // Tear down sampler if leaving SF2 mode
        if let sampler = midiSampler, !source.isSoundFont {
            outputNode.removeInput(sampler)
            midiSampler = nil
        }

        // Load SF2 if entering SF2 mode
        if case .soundFont(let id) = source,
           let store = soundFontStore,
           store.state(for: id) == .downloaded {
            let sampler = MIDISampler()
            do {
                // Use URL-based load since the file is outside the app bundle
                try sampler.loadMelodicSoundFont(url: store.fileURL(for: id), preset: 0)
                outputNode.addInput(sampler)
                midiSampler = sampler
            } catch {
                loadError = error.localizedDescription
                // Fall back to sine
                currentSource = .sine
            }
        } else if case .soundFont = source {
            // Selected SF2 not actually downloaded — fall back to sine
            loadError = "SoundFont not available"
            currentSource = .sine
        }
    }

    func noteOn(midi: Int) {
        guard !heldNotes.contains(midi) else { return }
        heldNotes.insert(midi)
        switch currentSource {
        case .sine, .triangle, .square, .sawtooth:
            startOscillator(midi: midi, waveform: currentSource)
        case .soundFont:
            midiSampler?.play(noteNumber: UInt8(midi),
                              velocity: UInt8(round(volume * 127)),
                              channel: 0)
        }
    }

    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        if let osc = oscillators.removeValue(forKey: midi) {
            osc.stop()
            outputNode.removeInput(osc)
        }
        midiSampler?.stop(noteNumber: UInt8(midi), channel: 0)
    }

    /// Stop every held note. Used to recover from gesture cancellation
    /// (e.g. app backgrounding, scene becoming inactive).
    func allNotesOff() {
        let snapshot = heldNotes
        for midi in snapshot {
            noteOff(midi: midi)
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
