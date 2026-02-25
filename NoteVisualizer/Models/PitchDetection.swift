import Foundation

struct PitchDetection: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let frequency: Double
    let amplitude: Double
    let midiNote: Int
    let noteName: String
    let octave: Int
    let centsOffset: Double

    var pitchValue: Double {
        Double(midiNote) + centsOffset / 100.0
    }
}
