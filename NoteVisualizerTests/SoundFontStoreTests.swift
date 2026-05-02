import XCTest
@testable import NoteVisualizer

@MainActor
final class SoundFontStoreTests: XCTestCase {
    var tempDir: URL!
    var store: SoundFontStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = SoundFontStore(directory: tempDir, defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInitialStateIsNotDownloaded() {
        XCTAssertEqual(store.state(for: "any_id"), .notDownloaded)
    }

    func testFileURLForId() {
        let url = store.fileURL(for: "musescore_general")
        XCTAssertEqual(url.lastPathComponent, "musescore_general.sf2")
        XCTAssertTrue(url.path.hasPrefix(tempDir.path))
    }

    func testLaunchVerificationDetectsExistingFile() {
        // Simulate a previously-downloaded file present on disk
        let id = "fluidr3_gm"
        let fileURL = store.fileURL(for: id)
        try! Data("fake sf2".utf8).write(to: fileURL)
        // Persist that this id was marked downloaded in defaults
        store.markPersistedAsDownloadedForTesting(id: id)

        // Re-create the store (simulates fresh launch)
        let defaults = store.defaultsForTesting
        store = SoundFontStore(directory: tempDir, defaults: defaults)

        XCTAssertEqual(store.state(for: id), .downloaded)
    }

    func testLaunchVerificationCleansUpMissingFile() {
        let id = "fluidr3_gm"
        // Mark in defaults but DON'T put a file on disk
        store.markPersistedAsDownloadedForTesting(id: id)

        let defaults = store.defaultsForTesting
        store = SoundFontStore(directory: tempDir, defaults: defaults)

        XCTAssertEqual(store.state(for: id), .notDownloaded)
        // Persistence should have been cleaned up too
        XCTAssertFalse(defaults.array(forKey: "soundFontStore.downloadedIDs")?.contains(where: { ($0 as? String) == id }) ?? false)
    }

    func testDownloadHappyPath() async throws {
        // Mock downloader writes a fake file and returns its URL on demand
        let mock = MockDownloader()
        store = SoundFontStore(directory: tempDir,
                               defaults: UserDefaults(suiteName: UUID().uuidString)!,
                               downloader: mock)

        let id = "test_font"
        let url = URL(string: "https://example.com/test.sf2")!

        // Schedule progress callbacks then completion
        mock.scheduledProgress = [0.25, 0.5, 0.75, 1.0]

        let exp = expectation(description: "download complete")
        Task { @MainActor in
            try await store.download(id: id, from: url)
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: 2)

        XCTAssertEqual(store.state(for: id), .downloaded)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL(for: id).path))
    }

    func testDownloadFailureSetsFailedState() async {
        let mock = MockDownloader()
        mock.failure = NSError(domain: "test", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "no network"])
        store = SoundFontStore(directory: tempDir,
                               defaults: UserDefaults(suiteName: UUID().uuidString)!,
                               downloader: mock)
        do {
            try await store.download(id: "x", from: URL(string: "https://example.com")!)
            XCTFail("should throw")
        } catch {
            // expected
        }
        if case .failed(let msg) = store.state(for: "x") {
            XCTAssertTrue(msg.contains("no network"))
        } else {
            XCTFail("expected .failed, got \(store.state(for: "x"))")
        }
    }

    func testDeleteRemovesFileAndState() throws {
        let id = "to_delete"
        try Data("content".utf8).write(to: store.fileURL(for: id))
        store.markPersistedAsDownloadedForTesting(id: id)
        // Re-init to pick up the file
        store = SoundFontStore(directory: tempDir, defaults: store.defaultsForTesting)
        XCTAssertEqual(store.state(for: id), .downloaded)

        store.delete(id: id)
        XCTAssertEqual(store.state(for: id), .notDownloaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL(for: id).path))
        XCTAssertFalse(
            store.defaultsForTesting.array(forKey: "soundFontStore.downloadedIDs")?
                .contains(where: { ($0 as? String) == id }) ?? false
        )
    }
}

// MARK: - Mock downloader

final class MockDownloader: Downloader, @unchecked Sendable {
    var scheduledProgress: [Double] = []
    var failure: Error?

    func download(from url: URL,
                  onProgress: @escaping (Double) -> Void) async throws -> URL {
        if let failure = failure { throw failure }
        for p in scheduledProgress {
            await MainActor.run { onProgress(p) }
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".sf2")
        try Data("fake content".utf8).write(to: temp)
        return temp
    }
}
