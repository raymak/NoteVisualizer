import SwiftUI

@Observable
class AppSettings {
    var detectionMode: DetectionMode {
        didSet { UserDefaults.standard.set(detectionMode.rawValue, forKey: "detectionMode") }
    }
    var timelineWindowSeconds: Double {
        didSet { UserDefaults.standard.set(timelineWindowSeconds, forKey: "timelineWindowSeconds") }
    }
    var lowestOctave: Int {
        didSet { UserDefaults.standard.set(lowestOctave, forKey: "lowestOctave") }
    }
    var visibleOctaves: Int {
        didSet { UserDefaults.standard.set(visibleOctaves, forKey: "visibleOctaves") }
    }
    var colorMode: ColorMode {
        didSet { UserDefaults.standard.set(colorMode.rawValue, forKey: "colorMode") }
    }

    var lowestMidiNote: Int {
        FrequencyUtils.midiNote(name: "C", octave: lowestOctave)
    }

    var highestMidiNote: Int {
        FrequencyUtils.midiNote(name: "B", octave: lowestOctave + visibleOctaves - 1)
    }

    init() {
        let mode = UserDefaults.standard.string(forKey: "detectionMode") ?? DetectionMode.monophonic.rawValue
        self.detectionMode = DetectionMode(rawValue: mode) ?? .monophonic
        self.timelineWindowSeconds = UserDefaults.standard.object(forKey: "timelineWindowSeconds") as? Double ?? 10.0
        self.lowestOctave = UserDefaults.standard.object(forKey: "lowestOctave") as? Int ?? 3
        self.visibleOctaves = UserDefaults.standard.object(forKey: "visibleOctaves") as? Int ?? 2
        let color = UserDefaults.standard.string(forKey: "colorMode") ?? ColorMode.volume.rawValue
        self.colorMode = ColorMode(rawValue: color) ?? .volume
    }

    enum DetectionMode: String, CaseIterable {
        case monophonic = "monophonic"
        case polyphonic = "polyphonic"

        var label: String {
            switch self {
            case .monophonic: "Mono"
            case .polyphonic: "Poly"
            }
        }
    }

    enum ColorMode: String, CaseIterable {
        case volume = "volume"
        case monochrome = "monochrome"

        var label: String {
            switch self {
            case .volume: "Volume Color"
            case .monochrome: "Monochrome"
            }
        }
    }
}
