import Foundation

protocol Downloader: Sendable {
    /// Downloads from the given URL, calling onProgress with values in [0, 1].
    /// Returns a temp file URL that the caller is responsible for moving.
    func download(from url: URL,
                  onProgress: @escaping (Double) -> Void) async throws -> URL
}

final class URLSessionDownloader: NSObject, Downloader, URLSessionDownloadDelegate, @unchecked Sendable {
    private lazy var session: URLSession = URLSession(configuration: .default,
                                                      delegate: self,
                                                      delegateQueue: nil)
    private struct PendingDownload {
        let onProgress: (Double) -> Void
        let continuation: CheckedContinuation<URL, Error>
    }
    private var pending: [Int: PendingDownload] = [:]
    private let lock = NSLock()

    func download(from url: URL,
                  onProgress: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url)
            lock.lock()
            pending[task.taskIdentifier] = PendingDownload(onProgress: onProgress,
                                                            continuation: continuation)
            lock.unlock()
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        let entry = pending[downloadTask.taskIdentifier]
        lock.unlock()
        entry?.onProgress(min(p, 1.0))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Move to a stable temp location before returning (URLSession deletes `location` after this delegate call)
        let stableTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sf2")
        do {
            try FileManager.default.moveItem(at: location, to: stableTemp)
            lock.lock()
            let entry = pending.removeValue(forKey: downloadTask.taskIdentifier)
            lock.unlock()
            entry?.continuation.resume(returning: stableTemp)
        } catch {
            lock.lock()
            let entry = pending.removeValue(forKey: downloadTask.taskIdentifier)
            lock.unlock()
            entry?.continuation.resume(throwing: error)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error = error else { return }
        lock.lock()
        let entry = pending.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        entry?.continuation.resume(throwing: error)
    }
}

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
    let defaultsForTesting: UserDefaults
    private let downloader: Downloader
    private var states: [String: DownloadState] = [:]

    private static let downloadedIDsKey = "soundFontStore.downloadedIDs"

    convenience init() {
        let appSupport = try! FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
        let dir = appSupport.appendingPathComponent("NoteVisualizer/SoundFonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(directory: dir, defaults: .standard, downloader: URLSessionDownloader())
    }

    init(directory: URL, defaults: UserDefaults, downloader: Downloader = URLSessionDownloader()) {
        self.directory = directory
        self.defaultsForTesting = defaults
        self.downloader = downloader
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        verifyExistingDownloads()
    }

    func state(for id: String) -> DownloadState {
        states[id] ?? .notDownloaded
    }

    func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).sf2")
    }

    func download(id: String, from url: URL) async throws {
        states[id] = .downloading(progress: 0)
        do {
            let tempURL = try await downloader.download(from: url) { [weak self] progress in
                Task { @MainActor [weak self] in
                    if case .downloading = self?.state(for: id) ?? .notDownloaded {
                        self?.states[id] = .downloading(progress: progress)
                    }
                }
            }
            let dest = fileURL(for: id)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            states[id] = .downloaded
            persistDownloadedID(id)
        } catch {
            states[id] = .failed(message: error.localizedDescription)
            throw error
        }
    }

    private func persistDownloadedID(_ id: String) {
        var existing = (defaultsForTesting.array(forKey: Self.downloadedIDsKey) as? [String]) ?? []
        if !existing.contains(id) { existing.append(id) }
        defaultsForTesting.set(existing, forKey: Self.downloadedIDsKey)
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

    func markPersistedAsDownloadedForTesting(id: String) {
        persistDownloadedID(id)
    }
}
