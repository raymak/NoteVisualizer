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
        // FluidR3Mono_GM2.SF2 — verified 2026-04-25
        // License: MIT (https://raw.githubusercontent.com/nwsw/FluidR3Mono_GM/master/FluidR3Mono_License.md)
        // Size: 124,419,622 bytes (~118 MB)
        // SHA-256: a54a4b9bdc7401a3a7ae153450f7f39fab2f8bb8c9102c68e9052860dfe466d3
        // URL returns application/octet-stream with content-length header (no redirect to portal)
        SoundFontEntry(
            id: "fluid_r3_mono_gm",
            displayName: "FluidR3 Mono GM",
            url: URL(string: "https://media.githubusercontent.com/media/nwsw/FluidR3Mono_GM/master/FluidR3Mono_GM2.SF2")!,
            licenseName: "MIT",
            byteSize: 124_419_622,
            sha256: "a54a4b9bdc7401a3a7ae153450f7f39fab2f8bb8c9102c68e9052860dfe466d3"
        ),
    ]

    static func entry(id: String) -> SoundFontEntry? {
        entries.first { $0.id == id }
    }
}
