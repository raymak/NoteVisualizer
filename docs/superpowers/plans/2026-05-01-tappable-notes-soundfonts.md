# Tappable Note Axis with Reference-Pitch Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the y-axis note labels in `PitchTimelineView` press-and-hold tappable; while held, play a continuous reference tone at that pitch using either a built-in waveform or a user-downloaded SoundFont (.sf2).

**Architecture:** Per-row invisible `DragGesture` overlay views fire `noteOn`/`noteOff` to a new `ReferencePitchPlayer` that owns the audio output graph. The player has two backends behind a stable AudioKit `Mixer` output node: AudioKit `Oscillator`-per-voice for waveforms, AudioKit `MIDISampler` (wraps `AVAudioUnitSampler`) for SF2. A `SoundFontStore` manages a `URLSessionDownloadTask`-backed download state machine for a hardcoded `SoundFontCatalog` of 1-3 curated MIT/CC-BY licensed fonts. New `Reference Pitch` and `SoundFonts` sections in `SettingsView`.

**Tech Stack:** SwiftUI, Swift @Observable, AudioKit 5.6+, SoundpipeAudioKit, AVFoundation (`AVAudioUnitSampler`), URLSession, XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-05-01-tappable-notes-soundfonts-design.md`

---

## File Structure

**New source files:**
- `NoteVisualizer/Models/ReferenceSource.swift` — enum + UserDefaults string codec
- `NoteVisualizer/Audio/SoundFontCatalog.swift` — static curated entries
- `NoteVisualizer/Audio/SoundFontStore.swift` — `@Observable` download state machine
- `NoteVisualizer/Audio/ReferencePitchPlayer.swift` — output graph + note routing
- `NoteVisualizer/Views/NoteAxisOverlay.swift` — invisible row gesture views
- `NoteVisualizer/Views/SoundFontSettingsSection.swift` — settings UI for fonts

**New test files:**
- `NoteVisualizerTests/ReferenceSourceTests.swift`
- `NoteVisualizerTests/NoteAxisMathTests.swift`
- `NoteVisualizerTests/SoundFontStoreTests.swift`

**Modified files:**
- `project.yml` — add test target
- `NoteVisualizer/Models/AppSettings.swift` — `referenceSource` + `referenceVolume`
- `NoteVisualizer/Utilities/FrequencyUtils.swift` — `midiNote(forY:lowestNote:noteRange:height:)` inverse helper
- `NoteVisualizer/Audio/AudioManager.swift` — instantiate `ReferencePitchPlayer`, rewire `engine.output`
- `NoteVisualizer/Views/PitchTimelineView.swift` — `ZStack` with `NoteAxisOverlay`; held-note highlight + reference line
- `NoteVisualizer/Views/SettingsView.swift` — add Reference Pitch section + SoundFonts section

---

## Task 1: Add XCTest target via XcodeGen

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add the test target**

Edit `project.yml`. Add a new target under `targets:` after the existing `NoteVisualizer` target:

```yaml
  NoteVisualizerTests:
    type: bundle.unit-test
    platform: [iOS, macOS]
    sources:
      - NoteVisualizerTests
    dependencies:
      - target: NoteVisualizer
    settings:
      base:
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/NoteVisualizer.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/NoteVisualizer
```

- [ ] **Step 2: Create the test directory with a smoke test**

Create `NoteVisualizerTests/SmokeTests.swift`:

```swift
import XCTest
@testable import NoteVisualizer

final class SmokeTests: XCTestCase {
    func testCanInstantiateAppSettings() {
        _ = AppSettings()
    }
}
```

- [ ] **Step 3: Regenerate the project**

Run: `cd "/Users/kardekani/Dropbox/Codes/Mobile Apps/NoteVisualizer" && xcodegen generate`
Expected: `Generated project successfully`

- [ ] **Step 4: Run the smoke test**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SmokeTests/testCanInstantiateAppSettings`
Expected: TEST SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add project.yml NoteVisualizerTests/
git commit -m "Add XCTest target with smoke test"
```

---

## Task 2: Add ReferenceSource enum with UserDefaults codec (TDD)

**Files:**
- Create: `NoteVisualizer/Models/ReferenceSource.swift`
- Create: `NoteVisualizerTests/ReferenceSourceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `NoteVisualizerTests/ReferenceSourceTests.swift`:

```swift
import XCTest
@testable import NoteVisualizer

final class ReferenceSourceTests: XCTestCase {
    func testEncodeWaveform() {
        XCTAssertEqual(ReferenceSource.sine.encoded, "waveform.sine")
        XCTAssertEqual(ReferenceSource.triangle.encoded, "waveform.triangle")
        XCTAssertEqual(ReferenceSource.square.encoded, "waveform.square")
        XCTAssertEqual(ReferenceSource.sawtooth.encoded, "waveform.sawtooth")
    }

    func testEncodeSoundFont() {
        XCTAssertEqual(ReferenceSource.soundFont(id: "musescore_general").encoded,
                       "sf.musescore_general")
    }

    func testDecodeWaveform() {
        XCTAssertEqual(ReferenceSource(encoded: "waveform.sine"), .sine)
        XCTAssertEqual(ReferenceSource(encoded: "waveform.sawtooth"), .sawtooth)
    }

    func testDecodeSoundFont() {
        XCTAssertEqual(ReferenceSource(encoded: "sf.fluidr3_gm"),
                       .soundFont(id: "fluidr3_gm"))
    }

    func testDecodeUnknownReturnsNil() {
        XCTAssertNil(ReferenceSource(encoded: "garbage"))
        XCTAssertNil(ReferenceSource(encoded: ""))
        XCTAssertNil(ReferenceSource(encoded: "waveform.xyz"))
    }

    func testRoundTrip() {
        let cases: [ReferenceSource] = [
            .sine, .triangle, .square, .sawtooth,
            .soundFont(id: "musescore_general"),
            .soundFont(id: "fluidr3_gm")
        ]
        for source in cases {
            XCTAssertEqual(ReferenceSource(encoded: source.encoded), source)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/ReferenceSourceTests`
Expected: BUILD FAILED (`Cannot find 'ReferenceSource' in scope`)

- [ ] **Step 3: Implement ReferenceSource**

Create `NoteVisualizer/Models/ReferenceSource.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/ReferenceSourceTests
```
Expected: TEST SUCCEEDED, 6 passed

- [ ] **Step 5: Commit**

```bash
git add NoteVisualizer/Models/ReferenceSource.swift NoteVisualizerTests/ReferenceSourceTests.swift
git commit -m "Add ReferenceSource enum with UserDefaults codec"
```

---

## Task 3: Add y→MIDI inverse helper to FrequencyUtils (TDD)

**Files:**
- Modify: `NoteVisualizer/Utilities/FrequencyUtils.swift` (append new method)
- Create: `NoteVisualizerTests/NoteAxisMathTests.swift`

The Canvas uses `yPosition(for: midi, lowestNote: lowestNote, noteRange: noteRange, height: plotHeight)`. We need the inverse for hit-testing in `NoteAxisOverlay`.

- [ ] **Step 1: Write the failing tests**

Create `NoteVisualizerTests/NoteAxisMathTests.swift`:

```swift
import XCTest
@testable import NoteVisualizer

final class NoteAxisMathTests: XCTestCase {
    func testMidiAtTopOfPlot() {
        // y=0 corresponds to highest note (lowestNote + noteRange)
        let midi = FrequencyUtils.midiNote(forY: 0,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 72) // C5 at top of 4 octaves starting at C3
    }

    func testMidiAtBottomOfPlot() {
        let midi = FrequencyUtils.midiNote(forY: 480,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 48) // C3 at bottom
    }

    func testMidiAtMiddle() {
        let midi = FrequencyUtils.midiNote(forY: 240,
                                           lowestNote: 48,
                                           noteRange: 24,
                                           height: 480)
        XCTAssertEqual(midi, 60) // halfway = midpoint MIDI
    }

    func testRoundTripWithExistingYPosition() {
        // Round-trip: the inverse of yPosition for integer MIDI values
        let lowestNote: Double = 48
        let noteRange: Double = 24
        let height: CGFloat = 480
        for midi in 48...72 {
            let y = yPositionForTest(midi: midi, lowestNote: lowestNote, noteRange: noteRange, height: height)
            let recovered = FrequencyUtils.midiNote(forY: y,
                                                    lowestNote: lowestNote,
                                                    noteRange: noteRange,
                                                    height: height)
            XCTAssertEqual(recovered, midi, "round-trip failed for MIDI \(midi)")
        }
    }

    // Mirrors the Canvas yPosition formula in PitchTimelineView
    private func yPositionForTest(midi: Int, lowestNote: Double, noteRange: Double, height: CGFloat) -> CGFloat {
        let notePosition = Double(midi) - lowestNote
        let normalized = notePosition / noteRange
        return height - CGFloat(normalized) * height
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/NoteAxisMathTests`
Expected: BUILD FAILED (`No member 'midiNote(forY:...)' in 'FrequencyUtils'`)

- [ ] **Step 3: Add the helper**

Append to `NoteVisualizer/Utilities/FrequencyUtils.swift`, inside the `enum FrequencyUtils` block before its closing brace:

```swift
    /// Inverse of the yPosition computation used by PitchTimelineView's Canvas.
    /// Returns the rounded MIDI note for a y coordinate within the plot.
    static func midiNote(forY y: CGFloat,
                         lowestNote: Double,
                         noteRange: Double,
                         height: CGFloat) -> Int {
        guard height > 0 else { return Int(lowestNote.rounded()) }
        let normalized = 1.0 - Double(y / height)
        let exact = lowestNote + normalized * noteRange
        return Int(exact.rounded())
    }
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/NoteAxisMathTests
```
Expected: TEST SUCCEEDED, 4 passed

- [ ] **Step 5: Commit**

```bash
git add NoteVisualizer/Utilities/FrequencyUtils.swift NoteVisualizerTests/NoteAxisMathTests.swift
git commit -m "Add y→MIDI inverse helper for axis hit-testing"
```

---

## Task 4: Curate and add SoundFontCatalog (research + implementation)

**Files:**
- Create: `NoteVisualizer/Audio/SoundFontCatalog.swift`

This task has a research component: pick 1-3 SF2 URLs that satisfy the spec's acceptance criteria. **The catalog ships with whatever passes verification.** If only one font passes, ship one. If none, ship an empty array (the feature still works with built-in waveforms).

- [ ] **Step 1: Research candidate SF2s**

For each candidate (initial pool: MuseScore_General, FluidR3_GM, GeneralUser GS), verify ALL of:

- (a) MIT or CC-BY license confirmed in writing on the source page (link from the GitHub release / Internet Archive / institutional CDN landing page)
- (b) Hosted on a stable mirror with **direct binary access** — must be a URL that returns the SF2 bytes with `Content-Type: application/octet-stream` or similar, not a redirect to a download portal
- (c) File size ≤ 200 MB
- (d) Loads cleanly via `AVAudioUnitSampler.loadSoundBankInstrument(at:program:bankMSB:bankLSB:)` (smoke-test in a scratch playground or CLI script)

Record for each passing entry: stable id (e.g. `musescore_general`), display name, URL, license name, byte size (use `curl -sIL <url> | grep -i content-length`), and SHA-256 hash (`curl -L <url> | shasum -a 256`).

- [ ] **Step 2: Implement the catalog with verified entries**

Create `NoteVisualizer/Audio/SoundFontCatalog.swift`:

```swift
import Foundation

struct SoundFontEntry: Identifiable, Equatable {
    let id: String
    let displayName: String
    let url: URL
    let licenseName: String
    let byteSize: Int64
    let sha256: String
}

enum SoundFontCatalog {
    /// Curated catalog. Each entry was verified at implementation time against the
    /// criteria in docs/superpowers/specs/2026-05-01-tappable-notes-soundfonts-design.md.
    /// To add a new entry: re-run the research/verification process from Task 4.
    static let entries: [SoundFontEntry] = [
        // INSERT VERIFIED ENTRIES HERE.
        // Example shape (replace url/size/sha256 with verified values, then uncomment):
        //
        // SoundFontEntry(
        //     id: "musescore_general",
        //     displayName: "MuseScore General",
        //     url: URL(string: "<verified URL>")!,
        //     licenseName: "MIT",
        //     byteSize: <verified bytes>,
        //     sha256: "<verified hex>"
        // ),
    ]

    static func entry(id: String) -> SoundFontEntry? {
        entries.first { $0.id == id }
    }
}
```

If verification produced one or more entries, replace the commented example with real `SoundFontEntry(...)` literals. If none passed, leave the array empty — the feature degrades to waveforms-only.

- [ ] **Step 3: Build the project**

Run: `xcodegen generate && xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Audio/SoundFontCatalog.swift
git commit -m "Add SoundFontCatalog with verified curated entries"
```

If catalog ships empty, commit message: `Add SoundFontCatalog scaffold (no entries verified yet)`.

---

## Task 5: SoundFontStore — types and persistence init (TDD)

**Files:**
- Create: `NoteVisualizer/Audio/SoundFontStore.swift`
- Create: `NoteVisualizerTests/SoundFontStoreTests.swift`

This task adds the `SoundFontStore` skeleton: state types, the on-disk directory, and launch-time verification that previously-downloaded files still exist.

- [ ] **Step 1: Write the failing tests**

Create `NoteVisualizerTests/SoundFontStoreTests.swift`:

```swift
import XCTest
@testable import NoteVisualizer

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests`
Expected: BUILD FAILED (`Cannot find 'SoundFontStore' in scope`)

- [ ] **Step 3: Implement the skeleton**

Create `NoteVisualizer/Audio/SoundFontStore.swift`:

```swift
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
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests
```
Expected: TEST SUCCEEDED, 4 passed

- [ ] **Step 5: Commit**

```bash
git add NoteVisualizer/Audio/SoundFontStore.swift NoteVisualizerTests/SoundFontStoreTests.swift
git commit -m "Add SoundFontStore skeleton with launch-time verification"
```

---

## Task 6: SoundFontStore — download happy path with mock URLSession (TDD)

**Files:**
- Modify: `NoteVisualizer/Audio/SoundFontStore.swift`
- Modify: `NoteVisualizerTests/SoundFontStoreTests.swift`

To make the download mockable, we inject a `Downloader` protocol that mirrors just the slice of `URLSession` we need.

- [ ] **Step 1: Add the failing test**

Append to `NoteVisualizerTests/SoundFontStoreTests.swift`, inside the `SoundFontStoreTests` class:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests/testDownloadHappyPath`
Expected: BUILD FAILED (`No type named 'Downloader'`, `No method 'download(id:from:)'`)

- [ ] **Step 3: Add Downloader protocol and download method**

Replace the contents of `NoteVisualizer/Audio/SoundFontStore.swift` with:

```swift
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
```

- [ ] **Step 4: Regenerate and run all SoundFontStore tests**

```bash
xcodegen generate
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests
```
Expected: TEST SUCCEEDED, 5 passed

- [ ] **Step 5: Commit**

```bash
git add NoteVisualizer/Audio/SoundFontStore.swift NoteVisualizerTests/SoundFontStoreTests.swift
git commit -m "Add SoundFontStore download path with mockable downloader"
```

---

## Task 7: SoundFontStore — failure, cancel, delete (TDD)

**Files:**
- Modify: `NoteVisualizer/Audio/SoundFontStore.swift`
- Modify: `NoteVisualizerTests/SoundFontStoreTests.swift`

- [ ] **Step 1: Add failing tests**

Append inside `SoundFontStoreTests` (before the closing `}`):

```swift
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
    }
```

(Cancel is implementation-coupled to the live `URLSession`, so we cover it through manual testing rather than a dedicated unit test.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests/testDeleteRemovesFileAndState`
Expected: BUILD FAILED (`No method 'delete'`)

- [ ] **Step 3: Add `delete(id:)` and (best-effort) `cancel(id:)`**

In `SoundFontStore.swift`, add inside the class (after `download(id:from:)`):

```swift
    func delete(id: String) {
        let url = fileURL(for: id)
        try? FileManager.default.removeItem(at: url)
        states[id] = .notDownloaded
        var existing = (defaultsForTesting.array(forKey: Self.downloadedIDsKey) as? [String]) ?? []
        existing.removeAll { $0 == id }
        defaultsForTesting.set(existing, forKey: Self.downloadedIDsKey)
    }

    func cancel(id: String) {
        // The current Downloader API doesn't expose per-id cancellation
        // because URLSessionDownloader returns one continuation per call.
        // For now we just flip state back; the in-flight task will complete
        // and its result will be ignored because the state isn't .downloading.
        // (When migrating to a richer cancellation model, replace this.)
        if case .downloading = state(for: id) {
            states[id] = .notDownloaded
        }
    }
```

Also update the progress callback inside `download(id:from:)` so that cancelled downloads stop publishing progress — replace the existing `if case .downloading = ...` block in the closure with the same guard (already correct in Task 6 code; verify).

- [ ] **Step 4: Run all tests**

```bash
xcodegen generate
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NoteVisualizerTests/SoundFontStoreTests
```
Expected: TEST SUCCEEDED, 7 passed

- [ ] **Step 5: Commit**

```bash
git add NoteVisualizer/Audio/SoundFontStore.swift NoteVisualizerTests/SoundFontStoreTests.swift
git commit -m "Add delete and cancel to SoundFontStore"
```

---

## Task 8: Extend AppSettings with referenceSource and referenceVolume

**Files:**
- Modify: `NoteVisualizer/Models/AppSettings.swift`

- [ ] **Step 1: Edit AppSettings**

In `NoteVisualizer/Models/AppSettings.swift`, add inside the `class AppSettings` body, alongside the other `var` properties:

```swift
    var referenceSource: ReferenceSource {
        didSet { UserDefaults.standard.set(referenceSource.encoded, forKey: "referenceSource") }
    }
    var referenceVolume: Double {
        didSet { UserDefaults.standard.set(referenceVolume, forKey: "referenceVolume") }
    }
```

Then in `init()`, append:

```swift
        let sourceEncoded = UserDefaults.standard.string(forKey: "referenceSource") ?? ReferenceSource.sine.encoded
        self.referenceSource = ReferenceSource(encoded: sourceEncoded) ?? .sine
        self.referenceVolume = UserDefaults.standard.object(forKey: "referenceVolume") as? Double ?? 0.5
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Models/AppSettings.swift
git commit -m "Add referenceSource and referenceVolume to AppSettings"
```

---

## Task 9: ReferencePitchPlayer skeleton with stable outputNode

**Files:**
- Create: `NoteVisualizer/Audio/ReferencePitchPlayer.swift`

This task creates the player object with the stable output graph but no note routing yet. We'll add waveform and SF2 modes in the next two tasks.

- [ ] **Step 1: Create the file**

```swift
import AudioKit
import AVFoundation
import SwiftUI

@Observable
@MainActor
class ReferencePitchPlayer {
    private(set) var heldNotes: Set<Int> = []
    private(set) var loadError: String?

    /// Stable output mixer — attached to the engine once and never replaced.
    /// Its inputs swap when the source changes.
    let outputNode: Mixer

    private var currentSource: ReferenceSource = .sine
    var volume: Double = 0.5

    init() {
        outputNode = Mixer()
    }

    func setSource(_ source: ReferenceSource) {
        // Stop everything held under the previous source
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil
        // Mode-specific load happens in subsequent tasks.
    }

    func noteOn(midi: Int) {
        heldNotes.insert(midi)
        // Mode-specific routing in subsequent tasks.
    }

    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        // Mode-specific routing in subsequent tasks.
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Audio/ReferencePitchPlayer.swift
git commit -m "Add ReferencePitchPlayer skeleton"
```

---

## Task 10: ReferencePitchPlayer — waveform mode (oscillator-per-voice)

**Files:**
- Modify: `NoteVisualizer/Audio/ReferencePitchPlayer.swift`

- [ ] **Step 1: Add waveform routing**

Replace the contents of `NoteVisualizer/Audio/ReferencePitchPlayer.swift` with:

```swift
import AudioKit
import SoundpipeAudioKit
import AVFoundation
import SwiftUI

@Observable
@MainActor
class ReferencePitchPlayer {
    private(set) var heldNotes: Set<Int> = []
    private(set) var loadError: String?

    let outputNode: Mixer

    private var currentSource: ReferenceSource = .sine
    var volume: Double = 0.5

    /// One oscillator per held MIDI note when in waveform mode.
    private var oscillators: [Int: Oscillator] = [:]

    init() {
        outputNode = Mixer()
    }

    func setSource(_ source: ReferenceSource) {
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil
    }

    func noteOn(midi: Int) {
        heldNotes.insert(midi)
        switch currentSource {
        case .sine, .triangle, .square, .sawtooth:
            startOscillator(midi: midi, waveform: currentSource)
        case .soundFont:
            break  // implemented in next task
        }
    }

    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        if let osc = oscillators.removeValue(forKey: midi) {
            osc.stop()
            outputNode.removeInput(osc)
        }
    }

    private func startOscillator(midi: Int, waveform: ReferenceSource) {
        let table = Self.table(for: waveform)
        let freq = AUValue(FrequencyUtils.frequencyFromMidiNote(Double(midi)))
        let osc = Oscillator(waveform: table, frequency: freq, amplitude: AUValue(volume))
        outputNode.addInput(osc)
        osc.start()
        oscillators[midi] = osc
    }

    private static func table(for waveform: ReferenceSource) -> Table {
        switch waveform {
        case .sine: return Table(.sine)
        case .triangle: return Table(.triangle)
        case .square: return Table(.square)
        case .sawtooth: return Table(.sawtooth)
        case .soundFont: return Table(.sine)  // unused
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Audio/ReferencePitchPlayer.swift
git commit -m "Add waveform mode to ReferencePitchPlayer"
```

---

## Task 11: ReferencePitchPlayer — SoundFont mode via MIDISampler

**Files:**
- Modify: `NoteVisualizer/Audio/ReferencePitchPlayer.swift`

- [ ] **Step 1: Add SF2 support**

Edit `NoteVisualizer/Audio/ReferencePitchPlayer.swift`:

Replace the `import` block with:

```swift
import AudioKit
import SoundpipeAudioKit
import AVFoundation
import SwiftUI
import CoreAudio
```

Add a new property below `oscillators`:

```swift
    private var midiSampler: MIDISampler?
    private var soundFontStore: SoundFontStore?
```

Add initializer parameter (replace the existing `init()`):

```swift
    init(soundFontStore: SoundFontStore? = nil) {
        outputNode = Mixer()
        self.soundFontStore = soundFontStore
    }
```

Replace `setSource(_:)` with:

```swift
    func setSource(_ source: ReferenceSource) {
        let toStop = heldNotes
        for midi in toStop { noteOff(midi: midi) }
        heldNotes.removeAll()
        currentSource = source
        loadError = nil

        // Tear down sampler if leaving SF2 mode
        if let sampler = midiSampler, !source.isSoundFont {
            outputNode.removeInput(sampler)
            midiSampler = nil
        }

        // Load SF2 if entering SF2 mode
        if case .soundFont(let id) = source,
           let store = soundFontStore,
           store.state(for: id) == .downloaded {
            let sampler = MIDISampler()
            do {
                try sampler.loadSoundFont(store.fileURL(for: id).path,
                                           preset: 0,
                                           bank: 0)
                outputNode.addInput(sampler)
                midiSampler = sampler
            } catch {
                loadError = error.localizedDescription
                // Fall back to sine
                currentSource = .sine
            }
        } else if case .soundFont = source {
            // Selected SF2 not actually downloaded — fall back to sine
            loadError = "SoundFont not available"
            currentSource = .sine
        }
    }
```

Replace `noteOn(midi:)` with:

```swift
    func noteOn(midi: Int) {
        heldNotes.insert(midi)
        switch currentSource {
        case .sine, .triangle, .square, .sawtooth:
            startOscillator(midi: midi, waveform: currentSource)
        case .soundFont:
            midiSampler?.play(noteNumber: UInt8(midi), velocity: UInt8(round(volume * 127)), channel: 0)
        }
    }
```

Replace `noteOff(midi:)` with:

```swift
    func noteOff(midi: Int) {
        heldNotes.remove(midi)
        if let osc = oscillators.removeValue(forKey: midi) {
            osc.stop()
            outputNode.removeInput(osc)
        }
        midiSampler?.stop(noteNumber: UInt8(midi), channel: 0)
    }
```

Add a small helper to `ReferenceSource` (at the bottom of `Models/ReferenceSource.swift`):

```swift
extension ReferenceSource {
    var isSoundFont: Bool {
        if case .soundFont = self { return true }
        return false
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Audio/ReferencePitchPlayer.swift NoteVisualizer/Models/ReferenceSource.swift
git commit -m "Add SoundFont mode to ReferencePitchPlayer via MIDISampler"
```

---

## Task 12: AudioManager — own ReferencePitchPlayer and rewire engine output

**Files:**
- Modify: `NoteVisualizer/Audio/AudioManager.swift`
- Modify: `NoteVisualizer/App/NoteVisualizerApp.swift` (env injection of SoundFontStore)

- [ ] **Step 1: Edit AudioManager**

In `NoteVisualizer/Audio/AudioManager.swift`:

Add new properties below `polyphonicDetector`:

```swift
    let soundFontStore = SoundFontStore()
    lazy var referencePlayer = ReferencePitchPlayer(soundFontStore: soundFontStore)
```

Replace this section in `start()`:

```swift
        // Only route the polyMixer to output (single mono path)
        let silence = Fader(polyMixer!, gain: 0)
        engine.output = silence
```

with:

```swift
        // Combine the silenced mic-tap path with the reference-pitch output
        let silence = Fader(polyMixer!, gain: 0)
        engine.output = Mixer([silence, referencePlayer.outputNode])
```

Add a method to apply settings whenever the source/volume changes (called from the App layer with `.onChange`):

```swift
    func applyReferenceSettings(source: ReferenceSource, volume: Double) {
        referencePlayer.volume = volume
        referencePlayer.setSource(source)
    }
```

- [ ] **Step 2: Wire `.onChange` in the app entry point**

Find `NoteVisualizer/App/NoteVisualizerApp.swift`. Read the file first to see its current shape, then add `.onChange(of:)` modifiers on the root view that call `audioManager.applyReferenceSettings(...)` whenever `settings.referenceSource` or `settings.referenceVolume` changes. Also call it once on `.task` to initialize the player with the persisted settings on launch.

Example (adapt to the file's actual root-view structure):

```swift
.task {
    audioManager.applyReferenceSettings(source: settings.referenceSource,
                                        volume: settings.referenceVolume)
}
.onChange(of: settings.referenceSource) { _, newValue in
    audioManager.applyReferenceSettings(source: newValue, volume: settings.referenceVolume)
}
.onChange(of: settings.referenceVolume) { _, newValue in
    audioManager.applyReferenceSettings(source: settings.referenceSource, volume: newValue)
}
```

- [ ] **Step 3: Build and run, manually verify the engine starts**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

Manual: Launch the app on a simulator. Confirm the audio engine starts (the existing `[Audio] Engine started, both taps active` log appears, and live mic detection still works in the timeline).

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Audio/AudioManager.swift NoteVisualizer/App/NoteVisualizerApp.swift
git commit -m "Wire ReferencePitchPlayer into AudioManager and engine output"
```

---

## Task 13: NoteAxisOverlay — layout (no gestures yet)

**Files:**
- Create: `NoteVisualizer/Views/NoteAxisOverlay.swift`

- [ ] **Step 1: Create the overlay**

```swift
import SwiftUI

/// Invisible per-MIDI-row gesture targets aligned to the y-axis strip of PitchTimelineView.
/// Renders a column of Color.clear rectangles whose y positions match the Canvas's note grid.
struct NoteAxisOverlay: View {
    let axisWidth: CGFloat
    let lowestNote: Double
    let noteRange: Double
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
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            // Gestures wired in the next task.
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Views/NoteAxisOverlay.swift
git commit -m "Add NoteAxisOverlay layout (no gestures yet)"
```

---

## Task 14: NoteAxisOverlay — gesture wiring with isHeld guard

**Files:**
- Modify: `NoteVisualizer/Views/NoteAxisOverlay.swift`

- [ ] **Step 1: Add per-row gestures**

Replace `NoteAxisRow` in `NoteVisualizer/Views/NoteAxisOverlay.swift` with:

```swift
private struct NoteAxisRow: View {
    let midi: Int
    let height: CGFloat
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    @State private var isHeld = false

    var body: some View {
        Color.clear
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
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add NoteVisualizer/Views/NoteAxisOverlay.swift
git commit -m "Wire press-and-hold gestures into NoteAxisOverlay rows"
```

---

## Task 15: Integrate NoteAxisOverlay into PitchTimelineView

**Files:**
- Modify: `NoteVisualizer/Views/PitchTimelineView.swift`

- [ ] **Step 1: Wrap Canvas in a ZStack and add the overlay**

Open `NoteVisualizer/Views/PitchTimelineView.swift`. Replace the body of the `TimelineView` block — specifically the section starting `Canvas { context, canvasSize in` and ending at `.frame(width: size.width, height: size.height)` — with a ZStack:

```swift
                ZStack(alignment: .topLeading) {
                    Canvas { context, canvasSize in
                        let plotWidth = canvasSize.width - axisWidth
                        let plotHeight = canvasSize.height

                        let totalSemitones = settings.highestMidiNote - settings.lowestMidiNote
                        let pixelsPerSemitone = plotHeight / CGFloat(totalSemitones)
                        let semitoneOffset = dragOffset / pixelsPerSemitone

                        let lowestNote = Double(settings.lowestMidiNote) - semitoneOffset
                        let highestNote = Double(settings.highestMidiNote) - semitoneOffset
                        let noteRange = highestNote - lowestNote

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

                    NoteAxisOverlay(
                        axisWidth: axisWidth,
                        lowestNote: Double(settings.lowestMidiNote) - dragOffset / max(1, size.height / CGFloat(settings.highestMidiNote - settings.lowestMidiNote)),
                        noteRange: Double(settings.highestMidiNote - settings.lowestMidiNote),
                        onNoteOn: { audioManager.referencePlayer.noteOn(midi: $0) },
                        onNoteOff: { audioManager.referencePlayer.noteOff(midi: $0) }
                    )
                    .frame(width: axisWidth, height: size.height)
                }
```

(Keep the existing `.gesture(DragGesture()...)` and `.gesture(MagnificationGesture()...)` modifiers attached *outside* the ZStack — they'll fire only for touches that bubble up past the overlay. The overlay's `.highPriorityGesture` ensures touches on the axis strip don't reach them.)

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification**

Run the app on an iOS simulator. Verify:
1. Tap-and-hold on a note label on the y-axis: a sine tone plays.
2. Release: tone stops.
3. Tap on a label, hold, drag finger horizontally onto the plot area: tone keeps playing until release.
4. Drag vertically *on the plot area* (right of the axis): timeline still pans (overlay isn't covering it).

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Views/PitchTimelineView.swift
git commit -m "Integrate NoteAxisOverlay into PitchTimelineView"
```

---

## Task 16: Held-note visuals — row tint, label highlight, reference line

**Files:**
- Modify: `NoteVisualizer/Views/PitchTimelineView.swift`
- Modify: `NoteVisualizer/Views/NoteAxisOverlay.swift`

- [ ] **Step 1: Add held-note tint to overlay rows**

Modify `NoteAxisOverlay.swift`. Update the `NoteAxisOverlay` struct to take a held-set:

Replace the `NoteAxisOverlay` struct's properties at the top with:

```swift
    let axisWidth: CGFloat
    let lowestNote: Double
    let noteRange: Double
    let heldNotes: Set<Int>
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void
```

In the `ForEach` block, pass the `isHeld` state into the row:

```swift
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
```

Replace `NoteAxisRow` with a version that tints when highlighted:

```swift
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
```

- [ ] **Step 2: Update PitchTimelineView to pass heldNotes and draw the reference line**

In `PitchTimelineView.swift`, update the `NoteAxisOverlay(...)` invocation to pass `heldNotes`:

```swift
                    NoteAxisOverlay(
                        axisWidth: axisWidth,
                        lowestNote: Double(settings.lowestMidiNote) - dragOffset / max(1, size.height / CGFloat(settings.highestMidiNote - settings.lowestMidiNote)),
                        noteRange: Double(settings.highestMidiNote - settings.lowestMidiNote),
                        heldNotes: audioManager.referencePlayer.heldNotes,
                        onNoteOn: { audioManager.referencePlayer.noteOn(midi: $0) },
                        onNoteOff: { audioManager.referencePlayer.noteOff(midi: $0) }
                    )
                    .frame(width: axisWidth, height: size.height)
```

In `drawGrid`, change the label rendering and add the held-line drawing. Replace this block:

```swift
            if isNatural || noteRange <= 24 {
                let octave = FrequencyUtils.octave(for: midi)
                let label = "\(name)\(octave)"
                let fontSize: CGFloat = noteRange > 30 ? 9 : 11
                let text = Text(label)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundColor(isNatural ? .gray : .gray.opacity(0.6))
                context.draw(
                    context.resolve(text),
                    at: CGPoint(x: axisWidth - 6, y: y),
                    anchor: .trailing
                )
            }
```

with:

```swift
            let isHeld = audioManager.referencePlayer.heldNotes.contains(midi)

            if isHeld {
                var line = Path()
                line.move(to: CGPoint(x: axisWidth, y: y))
                line.addLine(to: CGPoint(x: axisWidth + plotWidth, y: y))
                context.stroke(line,
                               with: .color(Color.accentColor.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if isNatural || noteRange <= 24 || isHeld {
                let octave = FrequencyUtils.octave(for: midi)
                let label = "\(name)\(octave)"
                let fontSize: CGFloat = noteRange > 30 ? 9 : 11
                let labelColor: Color = isHeld ? .white : (isNatural ? .gray : .gray.opacity(0.6))
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
```

- [ ] **Step 3: Build and manually verify**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

Manual: Tap-and-hold a note. Verify:
1. The label brightens and goes bold.
2. A dashed accent-colored horizontal line appears across the plot at that pitch.
3. The row's overlay rectangle gets a faint accent tint.
4. All three disappear on release.
5. Multi-touch (use a two-finger gesture on iPad sim or two simultaneous mouse-downs not possible — verify on physical iPad if available, otherwise note that single-touch verification suffices on iOS simulator).

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Views/NoteAxisOverlay.swift NoteVisualizer/Views/PitchTimelineView.swift
git commit -m "Draw held-note highlight and reference line"
```

---

## Task 17: Settings — Reference Pitch section (source picker + volume)

**Files:**
- Modify: `NoteVisualizer/Views/SettingsView.swift`

- [ ] **Step 1: Add the section**

Open `NoteVisualizer/Views/SettingsView.swift`. After the "Detection" section (and before "Display Range"), add:

```swift
                Section("Reference Pitch") {
                    Picker("Source", selection: $settings.referenceSource) {
                        Text("Sine").tag(ReferenceSource.sine)
                        Text("Triangle").tag(ReferenceSource.triangle)
                        Text("Square").tag(ReferenceSource.square)
                        Text("Sawtooth").tag(ReferenceSource.sawtooth)
                        ForEach(SoundFontCatalog.entries) { entry in
                            soundFontPickerRow(entry: entry)
                                .tag(ReferenceSource.soundFont(id: entry.id))
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(settings.referenceVolume * 100))%")
                        Slider(value: $settings.referenceVolume, in: 0...1)
                    }
                }
```

Add this private builder inside the `SettingsView` struct:

```swift
    @Environment(AudioManager.self) private var audioManager

    @ViewBuilder
    private func soundFontPickerRow(entry: SoundFontEntry) -> some View {
        switch audioManager.soundFontStore.state(for: entry.id) {
        case .downloaded:
            Text(entry.displayName)
        case .downloading(let p):
            Text("\(entry.displayName) — \(Int(p * 100))%")
        case .notDownloaded:
            Text("\(entry.displayName) (tap to download)")
        case .failed:
            Text("\(entry.displayName) (download failed)")
        }
    }
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification**

Open Settings (gear icon). Confirm a "Reference Pitch" section is visible with a source picker (4 waveforms always; SF2 entries only if the catalog has any) and a volume slider. Switch sources and verify the held-note tone changes timbre on the next press.

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Views/SettingsView.swift
git commit -m "Add Reference Pitch settings section"
```

---

## Task 18: SoundFontSettingsSection with download / cancel / delete UI

**Files:**
- Create: `NoteVisualizer/Views/SoundFontSettingsSection.swift`
- Modify: `NoteVisualizer/Views/SettingsView.swift`

- [ ] **Step 1: Create the section view**

```swift
import SwiftUI

struct SoundFontSettingsSection: View {
    @Environment(AudioManager.self) private var audioManager
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        Section("SoundFonts") {
            if SoundFontCatalog.entries.isEmpty {
                Text("No SoundFonts available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(SoundFontCatalog.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: SoundFontEntry) -> some View {
        let state = audioManager.soundFontStore.state(for: entry.id)
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName)
                Text("\(entry.licenseName) · \(formatBytes(entry.byteSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let msg) = state {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            switch state {
            case .notDownloaded:
                Button("Download") { startDownload(entry) }
            case .downloading(let p):
                HStack {
                    ProgressView(value: p).frame(width: 60)
                    Button {
                        cancelDownload(entry)
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
            case .downloaded:
                Menu {
                    Button("Delete", role: .destructive) {
                        audioManager.soundFontStore.delete(id: entry.id)
                    }
                } label: {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .failed:
                Button("Retry") { startDownload(entry) }
                    .foregroundStyle(.red)
            }
        }
    }

    private func startDownload(_ entry: SoundFontEntry) {
        downloadTasks[entry.id]?.cancel()
        let store = audioManager.soundFontStore
        downloadTasks[entry.id] = Task { @MainActor in
            try? await store.download(id: entry.id, from: entry.url)
        }
    }

    private func cancelDownload(_ entry: SoundFontEntry) {
        downloadTasks[entry.id]?.cancel()
        audioManager.soundFontStore.cancel(id: entry.id)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
```

- [ ] **Step 2: Add the section to SettingsView**

In `NoteVisualizer/Views/SettingsView.swift`, append this section after "Reference Pitch":

```swift
                SoundFontSettingsSection()
```

- [ ] **Step 3: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Views/SoundFontSettingsSection.swift NoteVisualizer/Views/SettingsView.swift
git commit -m "Add SoundFonts settings section with download/cancel/delete UI"
```

---

## Task 19: Picker tap-to-download with auto-switch on completion

**Files:**
- Modify: `NoteVisualizer/Views/SettingsView.swift`

When the user taps an undownloaded SF2 in the source picker, the picker setter fires with that source. We intercept that selection: kick off a download, and snap the actual `referenceSource` back to its previous value. When the download completes, switch to the new source.

- [ ] **Step 1: Replace the source picker with one that uses a derived binding**

In `NoteVisualizer/Views/SettingsView.swift`, replace the `Picker("Source", selection: $settings.referenceSource)` block with:

```swift
                    Picker("Source", selection: pickerBinding) {
                        Text("Sine").tag(ReferenceSource.sine)
                        Text("Triangle").tag(ReferenceSource.triangle)
                        Text("Square").tag(ReferenceSource.square)
                        Text("Sawtooth").tag(ReferenceSource.sawtooth)
                        ForEach(SoundFontCatalog.entries) { entry in
                            soundFontPickerRow(entry: entry)
                                .tag(ReferenceSource.soundFont(id: entry.id))
                        }
                    }
```

Add to `SettingsView`:

```swift
    @State private var pendingSourceForDownload: String?

    private var pickerBinding: Binding<ReferenceSource> {
        Binding(
            get: { settings.referenceSource },
            set: { newValue in
                if case .soundFont(let id) = newValue,
                   case .notDownloaded = audioManager.soundFontStore.state(for: id) {
                    // Don't actually switch yet; trigger download instead
                    guard let entry = SoundFontCatalog.entry(id: id) else { return }
                    pendingSourceForDownload = id
                    Task { @MainActor in
                        do {
                            try await audioManager.soundFontStore.download(id: id, from: entry.url)
                            if pendingSourceForDownload == id {
                                settings.referenceSource = .soundFont(id: id)
                                pendingSourceForDownload = nil
                            }
                        } catch {
                            pendingSourceForDownload = nil
                        }
                    }
                } else {
                    settings.referenceSource = newValue
                }
            }
        )
    }
```

- [ ] **Step 2: Build**

```bash
xcodegen generate
xcodebuild build -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS -destination 'generic/platform=iOS Simulator'
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Manual verification (only if SoundFontCatalog has entries)**

If the catalog ships with at least one entry, on a real-network build:
1. Open Settings, tap an undownloaded SF2 in the picker.
2. Picker shows progress next to the entry; current source remains the previous value.
3. On completion, picker auto-snaps to the new SF2 and SF2 plays on next press.
4. If you tap a different option mid-download, the auto-switch is canceled (the in-flight download still completes and is cached, but it doesn't override your new selection).

If catalog is empty, this verification is skipped — only waveform options are visible.

- [ ] **Step 4: Commit**

```bash
git add NoteVisualizer/Views/SettingsView.swift
git commit -m "Picker tap-to-download with auto-switch on completion"
```

---

## Task 20: Final manual test pass

**Files:** none (verification only)

Run through the manual test plan from the spec. If any issue surfaces, file it as a follow-up commit.

- [ ] **Step 1: Run the simulator**

```bash
xcodegen generate
open NoteVisualizer.xcodeproj
```
Then run on iPhone 15 simulator from Xcode.

- [ ] **Step 2: Execute the test plan**

Verify each item from `docs/superpowers/specs/2026-05-01-tappable-notes-soundfonts-design.md` "Manual test plan" section:

- [ ] Press a row on iOS sim — sine plays; release — silence.
- [ ] Multi-finger press (iPad sim) — multiple pitches. (Skip if no iPad sim available; note the limitation.)
- [ ] Hold a note while panning vertically — note keeps playing; reference line stays drawn while in range; off-range row's audio still plays.
- [ ] Switch source sine → triangle → square → sawtooth — hear waveform change on next press.
- [ ] Download a SF2 (if catalog non-empty) — progress shows; on completion source auto-switches and SF2 plays.
- [ ] Cancel mid-download — state resets; no orphaned file in `Application Support/NoteVisualizer/SoundFonts/`.
- [ ] Kill network mid-download — failed state shows; Retry works.
- [ ] Delete a downloaded SF2 currently selected — source falls back to sine; picker reflects.
- [ ] macOS click-and-hold — same flows work (single-touch).

- [ ] **Step 3: Commit any fixes**

If issues surfaced, fix them and commit per-fix. If everything works:

```bash
git commit --allow-empty -m "Verify tappable-notes feature against manual test plan"
```

---

## Self-Review (for plan authors)

**Spec coverage check** (every spec section has at least one task):

- ReferenceSource enum + codec → Task 2 ✓
- SoundFontCatalog with verification criteria → Task 4 ✓
- SoundFontStore (state machine, persistence, download, cancel, delete) → Tasks 5, 6, 7 ✓
- ReferencePitchPlayer (skeleton, waveform, SF2, setSource) → Tasks 9, 10, 11 ✓
- AppSettings additions → Task 8 ✓
- AudioManager rewiring → Task 12 ✓
- NoteAxisOverlay (layout, gestures, isHeld guard) → Tasks 13, 14 ✓
- PitchTimelineView ZStack + held visuals → Tasks 15, 16 ✓
- SettingsView Reference Pitch section → Task 17 ✓
- SoundFontSettingsSection → Task 18 ✓
- Picker tap-to-download + auto-switch → Task 19 ✓
- y→MIDI inverse helper → Task 3 ✓
- Test target → Task 1 ✓
- Manual test plan execution → Task 20 ✓

**Type consistency check:**
- `ReferencePitchPlayer.heldNotes: Set<Int>` — referenced consistently in Tasks 9, 10, 15, 16.
- `SoundFontStore.state(for:)`, `.fileURL(for:)`, `.download(id:from:)`, `.delete(id:)`, `.cancel(id:)` — all match across tasks 5-19.
- `MIDISampler.loadSoundFont(_:preset:bank:)` and `.play(noteNumber:velocity:channel:)` — AudioKit API; verify against installed AudioKit version when starting Task 11. If signatures differ, adjust to whatever the installed version exposes.

**Open implementation-time decisions:**
- Final SF2 URLs (Task 4) — must satisfy the four spec criteria; if zero pass, ship empty catalog.
- App layer wiring of `.onChange` (Task 12 Step 2) — adapt to the actual `NoteVisualizerApp.swift` shape, which the engineer should read first.
