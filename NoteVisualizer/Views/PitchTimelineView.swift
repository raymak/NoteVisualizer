import SwiftUI

struct PitchTimelineView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AudioManager.self) private var audioManager

    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat = 0

    private let axisWidth: CGFloat = 40
    private let dotRadius: CGFloat = 3.0

    // Polyphonic voice colors
    private let voiceHues: [Double] = [0.55, 0.0, 0.3, 0.15, 0.75, 0.45]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let now = audioManager.currentTimestamp
                let windowStart = now - settings.timelineWindowSeconds
                let visibleDetections = audioManager.detections.filter { $0.timestamp >= windowStart }

                ZStack(alignment: .topLeading) {
                    Canvas { context, canvasSize in
                        let plotWidth = canvasSize.width - axisWidth
                        let plotHeight = canvasSize.height

                        let lowestNote = lowestNote(forHeight: plotHeight)
                        let noteRange = Double(settings.highestMidiNote - settings.lowestMidiNote)
                        let highestNote = lowestNote + noteRange

                        drawGrid(
                            context: &context,
                            plotWidth: plotWidth,
                            plotHeight: plotHeight,
                            lowestNote: lowestNote,
                            highestNote: highestNote,
                            noteRange: noteRange
                        )

                        drawDots(
                            context: &context,
                            detections: visibleDetections,
                            now: now,
                            windowStart: windowStart,
                            plotWidth: plotWidth,
                            plotHeight: plotHeight,
                            lowestNote: lowestNote,
                            noteRange: noteRange
                        )
                    }
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                    NoteAxisOverlay(
                        axisWidth: axisWidth,
                        lowestNote: lowestNote(forHeight: size.height),
                        noteRange: Double(settings.highestMidiNote - settings.lowestMidiNote),
                        heldNotes: audioManager.referencePlayer.heldNotes,
                        onNoteOn: { audioManager.referencePlayer.noteOn(midi: $0) },
                        onNoteOff: { audioManager.referencePlayer.noteOff(midi: $0) }
                    )
                    .frame(width: axisWidth, height: size.height)
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = lastDragOffset + value.translation.height
                    }
                    .onEnded { value in
                        lastDragOffset = dragOffset
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onEnded { scale in
                        let newOctaves = max(1, min(5, Int(round(Double(settings.visibleOctaves) / scale))))
                        settings.visibleOctaves = newOctaves
                    }
            )
        }
    }

    private func drawGrid(
        context: inout GraphicsContext,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        lowestNote: Double,
        highestNote: Double,
        noteRange: Double
    ) {
        let startMidi = Int(floor(lowestNote))
        let endMidi = Int(ceil(highestNote))

        let held = audioManager.referencePlayer.heldNotes
        let heldPitchClasses = Set(held.map { ((($0 % 12) + 12) % 12) })

        for midi in startMidi...endMidi {
            let y = yPosition(for: midi, lowestNote: lowestNote, noteRange: noteRange, height: plotHeight)
            guard y >= -20 && y <= plotHeight + 20 else { continue }

            let name = FrequencyUtils.noteName(for: midi)
            let isNatural = !name.contains("#")

            let lineColor: Color = isNatural ? .gray.opacity(0.3) : .gray.opacity(0.12)
            let lineWidth: CGFloat = isNatural ? 0.8 : 0.4
            var path = Path()
            path.move(to: CGPoint(x: axisWidth, y: y))
            path.addLine(to: CGPoint(x: axisWidth + plotWidth, y: y))
            context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)

            let isHeld = held.contains(midi)
            let pitchClass = ((midi % 12) + 12) % 12
            let isOctaveOfHeld = !isHeld && heldPitchClasses.contains(pitchClass)

            if isHeld {
                var line = Path()
                line.move(to: CGPoint(x: axisWidth, y: y))
                line.addLine(to: CGPoint(x: axisWidth + plotWidth, y: y))
                context.stroke(line,
                               with: .color(Color.accentColor.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else if isOctaveOfHeld {
                var line = Path()
                line.move(to: CGPoint(x: axisWidth, y: y))
                line.addLine(to: CGPoint(x: axisWidth + plotWidth, y: y))
                context.stroke(line,
                               with: .color(Color.orange.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
            }

            if isNatural || noteRange <= 24 || isHeld || isOctaveOfHeld {
                let octave = FrequencyUtils.octave(for: midi)
                let label = "\(name)\(octave)"
                let fontSize: CGFloat = noteRange > 30 ? 9 : 11
                let labelColor: Color
                if isHeld {
                    labelColor = .white
                } else if isOctaveOfHeld {
                    labelColor = Color.orange.opacity(0.85)
                } else {
                    labelColor = isNatural ? .gray : .gray.opacity(0.6)
                }
                let labelWeight: Font.Weight = isHeld ? .bold : .regular
                let text = Text(label)
                    .font(.system(size: fontSize, weight: labelWeight, design: .monospaced))
                    .foregroundColor(labelColor)
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: axisWidth - 6, y: y),
                    anchor: .trailing
                )
            }
        }

        var axisLine = Path()
        axisLine.move(to: CGPoint(x: axisWidth, y: 0))
        axisLine.addLine(to: CGPoint(x: axisWidth, y: plotHeight))
        context.stroke(axisLine, with: .color(.gray.opacity(0.5)), lineWidth: 1)
    }

    private func drawDots(
        context: inout GraphicsContext,
        detections: [PitchDetection],
        now: TimeInterval,
        windowStart: TimeInterval,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        lowestNote: Double,
        noteRange: Double
    ) {
        // Group detections by approximate timestamp for polyphonic voice assignment
        var voiceAssignment: [UUID: Int] = [:]
        var currentVoice = 0

        // Sort by timestamp for voice tracking
        let sorted = detections.sorted { $0.timestamp < $1.timestamp }
        var lastTimestamp: TimeInterval = -1

        for detection in sorted {
            if abs(detection.timestamp - lastTimestamp) < 0.001 {
                currentVoice += 1
            } else {
                currentVoice = 0
            }
            voiceAssignment[detection.id] = currentVoice % voiceHues.count
            lastTimestamp = detection.timestamp
        }

        for detection in detections {
            let x = axisWidth + xPosition(
                timestamp: detection.timestamp,
                windowStart: windowStart,
                windowDuration: settings.timelineWindowSeconds,
                width: plotWidth
            )
            let y = yPosition(
                for: detection.midiNote,
                centsOffset: detection.centsOffset,
                lowestNote: lowestNote,
                noteRange: noteRange,
                height: plotHeight
            )

            guard y >= 0 && y <= plotHeight else { continue }

            let color = dotColor(
                amplitude: detection.amplitude,
                voiceIndex: voiceAssignment[detection.id] ?? 0
            )

            let rect = CGRect(
                x: x - dotRadius,
                y: y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            context.fill(Ellipse().path(in: rect), with: .color(color))
        }
    }

    private func xPosition(timestamp: TimeInterval, windowStart: TimeInterval, windowDuration: Double, width: CGFloat) -> CGFloat {
        let normalized = (timestamp - windowStart) / windowDuration
        return CGFloat(normalized) * width
    }

    private func yPosition(for midiNote: Int, centsOffset: Double = 0, lowestNote: Double, noteRange: Double, height: CGFloat) -> CGFloat {
        let notePosition = Double(midiNote) - lowestNote + centsOffset / 100.0
        let normalized = notePosition / noteRange
        return height - CGFloat(normalized) * height
    }

    private func lowestNote(forHeight height: CGFloat) -> Double {
        let totalSemitones = CGFloat(settings.highestMidiNote - settings.lowestMidiNote)
        let pixelsPerSemitone = max(1, height / totalSemitones)
        return Double(settings.lowestMidiNote) - dragOffset / pixelsPerSemitone
    }

    private func dotColor(amplitude: Double, voiceIndex: Int) -> Color {
        if settings.colorMode == .monochrome {
            return Color.white.opacity(0.3 + 0.7 * amplitude)
        }

        let hue = voiceHues[voiceIndex % voiceHues.count]
        let saturation = 0.6 + 0.4 * amplitude
        let brightness = 0.4 + 0.6 * amplitude
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}
