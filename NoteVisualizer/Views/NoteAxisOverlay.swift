import SwiftUI

/// Invisible per-MIDI-row gesture targets aligned to the y-axis strip of PitchTimelineView.
/// Renders a column of Color.clear rectangles whose y positions match the Canvas's note grid.
struct NoteAxisOverlay: View {
    let axisWidth: CGFloat
    let lowestNote: Double
    let noteRange: Double
    let heldNotes: Set<Int>
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
                                isHighlighted: heldNotes.contains(midi),
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
    let isHighlighted: Bool
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    @State private var isHeld = false

    var body: some View {
        Rectangle()
            .fill(isHighlighted ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isHeld else { return }
                        isHeld = true
                        onNoteOn(midi)
                    }
                    .onEnded { _ in
                        guard isHeld else { return }
                        isHeld = false
                        onNoteOff(midi)
                    }
            )
    }
}
