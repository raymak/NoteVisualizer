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
}
