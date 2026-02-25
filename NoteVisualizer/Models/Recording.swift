import Foundation

struct Recording: Identifiable {
    let id = UUID()
    let date: Date
    let duration: TimeInterval
    let detections: [PitchDetection]
    let mode: AppSettings.DetectionMode

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
