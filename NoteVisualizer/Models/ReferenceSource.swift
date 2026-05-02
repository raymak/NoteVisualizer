import Foundation

enum ReferenceSource: Equatable, Hashable {
    case sine
    case triangle
    case square
    case sawtooth
    case soundFont(id: String)

    var encoded: String {
        switch self {
        case .sine: return "waveform.sine"
        case .triangle: return "waveform.triangle"
        case .square: return "waveform.square"
        case .sawtooth: return "waveform.sawtooth"
        case .soundFont(let id): return "sf.\(id)"
        }
    }

    init?(encoded: String) {
        switch encoded {
        case "waveform.sine": self = .sine
        case "waveform.triangle": self = .triangle
        case "waveform.square": self = .square
        case "waveform.sawtooth": self = .sawtooth
        default:
            guard encoded.hasPrefix("sf.") else { return nil }
            let id = String(encoded.dropFirst(3))
            guard !id.isEmpty else { return nil }
            self = .soundFont(id: id)
        }
    }
}
