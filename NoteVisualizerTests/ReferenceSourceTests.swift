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
