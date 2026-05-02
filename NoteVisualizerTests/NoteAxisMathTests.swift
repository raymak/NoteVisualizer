import XCTest
@testable import NoteVisualizer

final class NoteAxisMathTests: XCTestCase {
    func testMidiAtTopOfPlot() {
        let midi = FrequencyUtils.midiNote(forY: 0,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 72) // C5 at top of 4 octaves starting at C3
    }

    func testMidiAtBottomOfPlot() {
        let midi = FrequencyUtils.midiNote(forY: 480,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 48) // C3 at bottom
    }

    func testMidiAtMiddle() {
        let midi = FrequencyUtils.midiNote(forY: 240,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 60)
    }

    func testRoundTripWithExistingYPosition() {
        let lowestNote: Double = 48
        let noteRange: Double = 24
        let height: CGFloat = 480
        for midi in 48...72 {
            let y = yPositionForTest(midi: midi, lowestNote: lowestNote, noteRange: noteRange, height: height)
            let recovered = FrequencyUtils.midiNote(forY: y,
                                                    lowestNote: lowestNote,
                                                    noteRange: noteRange,
                                                    height: height)
            XCTAssertEqual(recovered, midi, "round-trip failed for MIDI \(midi)")
        }
    }

    // Mirrors the Canvas yPosition formula in PitchTimelineView
    private func yPositionForTest(midi: Int, lowestNote: Double, noteRange: Double, height: CGFloat) -> CGFloat {
        let notePosition = Double(midi) - lowestNote
        let normalized = notePosition / noteRange
        return height - CGFloat(normalized) * height
    }
}
