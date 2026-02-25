import SwiftUI

struct RecordingPlaybackView: View {
    let recording: Recording
    @Environment(AppSettings.self) private var settings

    @State private var playbackTime: TimeInterval = 0
    @State private var isPlaying = false
    @State private var dragOffset: CGFloat = 0
    @State private var lastDragOffset: CGFloat = 0
    @State private var timer: Timer?

    private let axisWidth: CGFloat = 50
    private let dotRadius: CGFloat = 3.0
    private let voiceHues: [Double] = [0.55, 0.0, 0.3, 0.15, 0.75, 0.45]

    var body: some View {
        VStack(spacing: 0) {
            // Playback controls
            HStack {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)

                Text(formatTime(playbackTime))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("/")
                    .foregroundStyle(.secondary)

                Text(formatTime(recording.duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(recording.mode.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.gray.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            // Scrubber
            Slider(value: $playbackTime, in: 0...max(recording.duration, 0.1))
                .padding(.horizontal)
                .onChange(of: playbackTime) {
                    if !isPlaying {
                        // Manual scrub
                    }
                }

            // Timeline visualization
            GeometryReader { geometry in
                let size = geometry.size

                Canvas { context, canvasSize in
                    let plotWidth = canvasSize.width - axisWidth
                    let plotHeight = canvasSize.height

                    let totalSemitones = settings.highestMidiNote - settings.lowestMidiNote
                    let pixelsPerSemitone = plotHeight / CGFloat(totalSemitones)
                    let semitoneOffset = dragOffset / pixelsPerSemitone

                    let lowestNote = Double(settings.lowestMidiNote) - semitoneOffset
                    let highestNote = Double(settings.highestMidiNote) - semitoneOffset
                    let noteRange = highestNote - lowestNote

                    // Draw grid
                    drawGrid(
                        context: &context,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight,
                        lowestNote: lowestNote,
                        highestNote: highestNote,
                        noteRange: noteRange
                    )

                    // Draw all detections with playhead
                    let windowDuration = settings.timelineWindowSeconds
                    let windowStart = playbackTime - windowDuration
                    let visible = recording.detections.filter {
                        $0.timestamp >= windowStart && $0.timestamp <= playbackTime
                    }

                    drawDots(
                        context: &context,
                        detections: visible,
                        windowStart: windowStart,
                        windowEnd: playbackTime,
                        windowDuration: windowDuration,
                        plotWidth: plotWidth,
                        plotHeight: plotHeight,
                        lowestNote: lowestNote,
                        noteRange: noteRange
                    )

                    // Draw playhead
                    var playhead = Path()
                    playhead.move(to: CGPoint(x: axisWidth + plotWidth, y: 0))
                    playhead.addLine(to: CGPoint(x: axisWidth + plotWidth, y: plotHeight))
                    context.stroke(playhead, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
                .frame(width: size.width, height: size.height)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = lastDragOffset + value.translation.height
                        }
                        .onEnded { _ in
                            lastDragOffset = dragOffset
                        }
                )
            }
        }
        .onAppear {
            startPlayback()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        if playbackTime >= recording.duration {
            playbackTime = 0
        }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            playbackTime += 1.0 / 60.0
            if playbackTime >= recording.duration {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

            if isNatural || noteRange <= 24 {
                let octave = FrequencyUtils.octave(for: midi)
                let label = "\(name)\(octave)"
                let text = Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isNatural ? .gray : .gray.opacity(0.6))
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
        windowStart: TimeInterval,
        windowEnd: TimeInterval,
        windowDuration: Double,
        plotWidth: CGFloat,
        plotHeight: CGFloat,
        lowestNote: Double,
        noteRange: Double
    ) {
        var voiceAssignment: [UUID: Int] = [:]
        var currentVoice = 0
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
            let normalized = (detection.timestamp - windowStart) / windowDuration
            let x = axisWidth + CGFloat(normalized) * plotWidth
            let pitchValue = Double(detection.midiNote) + detection.centsOffset / 100.0
            let notePosition = pitchValue - lowestNote
            let normalizedY = notePosition / noteRange
            let y = plotHeight - CGFloat(normalizedY) * plotHeight

            guard y >= 0 && y <= plotHeight else { continue }

            let color = dotColor(
                amplitude: detection.amplitude,
                voiceIndex: voiceAssignment[detection.id] ?? 0
            )

            let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            context.fill(Ellipse().path(in: rect), with: .color(color))
        }
    }

    private func yPosition(for midiNote: Int, lowestNote: Double, noteRange: Double, height: CGFloat) -> CGFloat {
        let notePosition = Double(midiNote) - lowestNote
        let normalized = notePosition / noteRange
        return height - CGFloat(normalized) * height
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
