import Foundation

@Observable
@MainActor
class SoundFontStore {
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(message: String)
    }

    private let directory: URL
    let defaultsForTesting: UserDefaults  // exposed for tests; treat as private elsewhere
    private var states: [String: DownloadState] = [:]

    private static let downloadedIDsKey = "soundFontStore.downloadedIDs"

    /// Production initializer: uses Application Support / NoteVisualizer / SoundFonts
    convenience init() {
        let appSupport = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
        let dir = appSupport.appendingPathComponent("NoteVisualizer/SoundFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir, defaults: .standard)
    }

    init(directory: URL, defaults: UserDefaults) {
        self.directory = directory
        self.defaultsForTesting = defaults
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        verifyExistingDownloads()
    }

    func state(for id: String) -> DownloadState {
        states[id] ?? .notDownloaded
    }

    func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).sf2")
    }

    private func verifyExistingDownloads() {
        let ids = (defaultsForTesting.array(forKey: Self.downloadedIDsKey) as? [String]) ?? []
        var stillValid: [String] = []
        for id in ids {
            if FileManager.default.fileExists(atPath: fileURL(for: id).path) {
                states[id] = .downloaded
                stillValid.append(id)
            }
        }
        if stillValid.count != ids.count {
            defaultsForTesting.set(stillValid, forKey: Self.downloadedIDsKey)
        }
    }

    // MARK: - Test helpers

    func markPersistedAsDownloadedForTesting(id: String) {
        var existing = (defaultsForTesting.array(forKey: Self.downloadedIDsKey) as? [String]) ?? []
        if !existing.contains(id) { existing.append(id) }
        defaultsForTesting.set(existing, forKey: Self.downloadedIDsKey)
    }
}
