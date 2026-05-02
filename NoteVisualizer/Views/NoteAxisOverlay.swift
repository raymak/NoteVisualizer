import SwiftUI

/// Invisible per-MIDI-row gesture targets aligned to the y-axis strip of PitchTimelineView.
/// Renders a column of Color.clear rectangles whose y positions match the Canvas's note grid.
struct NoteAxisOverlay: View {
    let axisWidth: CGFloat
    let lowestNote: Double
    let noteRange: Double
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let pixelsPerSemitone = height / CGFloat(noteRange)
            let startMidi = Int(floor(lowestNote))
            let endMidi = Int(ceil(lowestNote + noteRange))

            ZStack(alignment: .topLeading) {
                ForEach(startMidi...endMidi, id: \.self) { midi in
                    NoteAxisRow(midi: midi,
                                height: pixelsPerSemitone,
                                onNoteOn: onNoteOn,
                                onNoteOff: onNoteOff)
                        .frame(width: axisWidth, height: pixelsPerSemitone)
                        .position(
                            x: axisWidth / 2,
                            y: yCenter(midi: midi,
                                       lowestNote: lowestNote,
                                       noteRange: noteRange,
                                       height: height)
                        )
                }
            }
            .frame(width: axisWidth, height: height, alignment: .topLeading)
        }
    }

    private func yCenter(midi: Int, lowestNote: Double, noteRange: Double, height: CGFloat) -> CGFloat {
        let notePosition = Double(midi) - lowestNote
        let normalized = notePosition / noteRange
        return height - CGFloat(normalized) * height
    }
}

private struct NoteAxisRow: View {
    let midi: Int
    let height: CGFloat
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            // Gestures wired in the next task.
    }
}
