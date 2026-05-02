import AudioKit
import AVFoundation
import SwiftUI

@Observable
@MainActor
class ReferencePitchPlayer {
    private(set) var heldNotes: Set<Int> = []
    private(set) var loadError: String?

    /// Stable output mixer — attached to the engine once and never replaced.
    /// Its inputs swap when the source changes.
    let outputNode: Mixer

    private var currentSource: ReferenceSource = .sine
    var volume: Double = 0.5

    init() {
        outputNode = Mixer()
    }

    func setSource(_ source: ReferenceSource) {
        // Stop everything held under the previous source
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil
        // Mode-specific load happens in subsequent tasks.
    }

    func noteOn(midi: Int) {
        heldNotes.insert(midi)
        // Mode-specific routing in subsequent tasks.
    }

    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        // Mode-specific routing in subsequent tasks.
    }
}
