import XCTest
@testable import NoteVisualizer

final class SmokeTests: XCTestCase {
    func testCanInstantiateAppSettings() {
        _ = AppSettings()
    }
}
