import CoreGraphics
import Foundation

enum FrequencyUtils {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static let a4Frequency: Double = 440.0
    static let a4MidiNote: Int = 69

    static func midiNoteFromFrequency(_ frequency: Double) -> Double {
        guard frequency > 0 else { return 0 }
        return 69.0 + 12.0 * log2(frequency / a4Frequency)
    }

    static func frequencyFromMidiNote(_ midiNote: Double) -> Double {
        a4Frequency * pow(2.0, (midiNote - 69.0) / 12.0)
    }

    static func nearestMidiNote(_ frequency: Double) -> Int {
        Int(round(midiNoteFromFrequency(frequency)))
    }

    static func centsOffset(frequency: Double, fromMidiNote midiNote: Int) -> Double {
        let exactMidi = midiNoteFromFrequency(frequency)
        return (exactMidi - Double(midiNote)) * 100.0
    }

    static func noteName(for midiNote: Int) -> String {
        let index = ((midiNote % 12) + 12) % 12
        return noteNames[index]
    }

    static func octave(for midiNote: Int) -> Int {
        (midiNote / 12) - 1
    }

    static func fullNoteName(for midiNote: Int) -> String {
        "\(noteName(for: midiNote))\(octave(for: midiNote))"
    }

    static func detectionFromFrequency(_ frequency: Double, amplitude: Double, timestamp: TimeInterval) -> PitchDetection {
        let midi = nearestMidiNote(frequency)
        let cents = centsOffset(frequency: frequency, fromMidiNote: midi)
        return PitchDetection(
            timestamp: timestamp,
            frequency: frequency,
            amplitude: amplitude,
            midiNote: midi,
            noteName: noteName(for: midi),
            octave: octave(for: midi),
            centsOffset: cents
        )
    }

    static func midiNote(name: String, octave: Int) -> Int {
        guard let index = noteNames.firstIndex(of: name) else { return 60 }
        return (octave + 1) * 12 + index
    }

    /// Inverse of the yPosition computation used by PitchTimelineView's Canvas.
    /// Returns the rounded MIDI note for a y coordinate within the plot.
    static func midiNote(forY y: CGFloat,
                         lowestNote: Double,
                         noteRange: Double,
                         height: CGFloat) -> Int {
        guard height > 0 else { return Int(lowestNote.rounded()) }
        let normalized = 1.0 - Double(y / height)
        let exact = lowestNote + normalized * noteRange
        return Int(exact.rounded())
    }
}
