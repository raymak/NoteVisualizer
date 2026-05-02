# Tappable Note Axis with Reference-Pitch Playback

**Status:** Design
**Date:** 2026-05-01

## Summary

Make the y-axis note labels in `PitchTimelineView` press-and-hold tappable. While a row is held, play a continuous reference tone at that pitch. The pitch source is configurable in Settings: four built-in synth waveforms (sine, triangle, square, sawtooth), or one of a small curated list of SoundFont (.sf2) files that the user downloads from the internet.

The feature is for ear training and pitch comparison: while a reference note is held, the user sings into the mic and visually compares their sung pitch dots against a horizontal reference line drawn at the held pitch.

## User-facing decisions

| Decision | Choice |
|---|---|
| Sound source | Built-in waveforms **and** downloadable SoundFonts |
| SoundFont distribution | Curated list baked into the app; no user-supplied URLs or file import |
| Polyphony | Multi-touch (multiple fingers play multiple notes) |
| Tap target | Full y-axis strip row (axisWidth × pixelsPerSemitone) |
| Visual feedback while held | Highlight the row label **and** draw a horizontal reference line across the plot |
| Picker behaviour for undownloaded SF2 | Tapping in the picker triggers download; on success, source auto-switches to that SF2 |

## Architecture

### New components

- **`SoundFontCatalog`** (`Audio/SoundFontCatalog.swift`)
  Static `let entries: [SoundFontEntry]` of 3–5 curated SF2s. Each entry has `id` (stable string), `displayName`, `url`, `licenseName`, `byteSize`, `sha256` (for integrity check). The first implementation step is to research and select the URLs; an entry only ships if it satisfies all of: (a) MIT or CC-BY license confirmed in writing on the source page, (b) hosted on a stable mirror with direct binary access (GitHub release asset, Internet Archive item, or institutional CDN — not a redirect that hits a download portal), (c) file size ≤ 200 MB, (d) opens successfully via `MIDISampler.loadSoundFont`. Initial candidate pool to evaluate against these criteria: MuseScore_General (MIT), FluidR3_GM (MIT), GeneralUser GS (CC-BY).

- **`SoundFontStore`** (`Audio/SoundFontStore.swift`, `@Observable`)
  Owns the per-entry download state machine: `notDownloaded | downloading(progress: Double) | downloaded | failed(message: String)`. Persists "downloaded IDs" set in UserDefaults; verifies file existence at launch. Files are stored at `Application Support/NoteVisualizer/SoundFonts/{id}.sf2`. Methods: `download(id:)`, `cancel(id:)`, `delete(id:)`. Backed by a `URLSession` with a `URLSessionDownloadDelegate` that posts progress to the main actor.

- **`ReferencePitchPlayer`** (`Audio/ReferencePitchPlayer.swift`, `@Observable`)
  Owns the audio output graph for reference pitches. Public API:
  - `noteOn(midi: Int)`
  - `noteOff(midi: Int)`
  - `setSource(_: ReferenceSource)`
  - `var heldNotes: Set<Int>` (observed by views for highlight + line drawing)
  - `var outputNode: Node` (stable AudioKit `Mixer`; attached once to engine output)

  Internally:
  - SF2 mode: a single AudioKit `MIDISampler` (which wraps `AVAudioUnitSampler`) with the active SF2 loaded via `loadSoundFont(_:preset:bank:)`. Notes are triggered with `play(noteNumber:velocity:channel:)` / `stop(noteNumber:channel:)`. `MIDISampler` is an AudioKit `Node`, so it slots cleanly into the AudioKit graph.
  - Waveform mode: an AudioKit `Oscillator` instantiated per held MIDI note (Oscillator is monophonic; one voice per finger). Voices are tracked in a dictionary keyed by MIDI note.
  - The stable `outputNode` is an AudioKit `Mixer` whose input membership swaps when the source changes (sampler attached for SF2 mode, the per-voice oscillators attached for waveform mode). Switching source stops all held voices, detaches the previous inputs, attaches the new ones, and clears `heldNotes`.

- **`NoteAxisOverlay`** (`Views/NoteAxisOverlay.swift`)
  SwiftUI view rendered as a sibling of the existing Canvas inside `PitchTimelineView`. A `ZStack` of one `Color.clear` rectangle per visible MIDI semitone, each with `.contentShape(Rectangle())` and a `DragGesture(minimumDistance: 0)` wrapped in `.highPriorityGesture(...)`. Each row owns a per-row `@State var isHeld: Bool`. `.onChanged` fires repeatedly during a touch; the row guards on `isHeld == false` to call `noteOn` exactly once and sets `isHeld = true`. `.onEnded` calls `noteOff` and clears `isHeld`. Each rectangle's frame is computed with the same y-math the Canvas grid uses (`yPosition(for:lowestNote:noteRange:height:)`).

- **`SoundFontSettingsSection`** (`Views/SoundFontSettingsSection.swift`)
  Settings UI: a "SoundFonts" section listing each catalog entry with download/cancel/delete/retry affordances, plus the source picker (rendered above this section, in a parent view).

- **`Models/ReferenceSource.swift`**
  ```swift
  enum ReferenceSource: Equatable, Hashable {
      case sine
      case triangle
      case square
      case sawtooth
      case soundFont(id: String)
  }
  ```
  With UserDefaults codec helpers (encode as a single string, e.g. `"waveform.sine"` or `"sf.musescore_general"`).

### Existing components touched

- **`AppSettings`**
  Add `referenceSource: ReferenceSource` (default `.sine`) and `referenceVolume: Double` (0–1, default 0.5). UserDefaults-persisted via `didSet` like other settings.

- **`AudioManager`**
  Instantiates and owns `ReferencePitchPlayer`. Engine output graph changes from
  ```swift
  let silence = Fader(polyMixer!, gain: 0)
  engine.output = silence
  ```
  to
  ```swift
  let silence = Fader(polyMixer!, gain: 0)
  engine.output = Mixer([silence, referencePlayer.outputNode])
  ```
  `referencePlayer.outputNode` is stable across source switches.

- **`PitchTimelineView`**
  Wrap existing Canvas in a `ZStack` with `NoteAxisOverlay`. Read `referencePlayer.heldNotes` to:
  - Tint the held row's overlay rectangle with `Color.accentColor.opacity(0.18)`.
  - In `drawGrid`, when `midi ∈ heldNotes`, render the label brighter (`.white`) and bold; draw a dashed horizontal reference line (`Color.accentColor.opacity(0.5)`, lineWidth 1, dash `[4, 3]`) across the plot at that y.

- **`SettingsView`**
  New "Reference Pitch" section between "Detection" and "Display Range":
  - Source picker — all four waveforms always present; each catalog SF2 entry appears as a row regardless of download state. Tapping an undownloaded SF2 starts a download (state visible inline as `"<name> — 42%"` while in progress); on completion, source auto-switches.
  - Volume slider (0–1).
  Plus a separate "SoundFonts" section listing each catalog entry with full state management UI (download / progress + cancel / installed + delete / failed + retry).

## Data flow

### Press-and-hold

1. Finger lands on a `NoteAxisOverlay` row's invisible rectangle.
2. The row's `DragGesture(minimumDistance: 0)` `.onChanged` fires. The row guards on its per-row `isHeld` flag to ensure `noteOn` runs once per gesture, then calls `referencePlayer.noteOn(midi: rowMidi)` and sets `isHeld = true`.
3. `ReferencePitchPlayer` inserts `rowMidi` into `heldNotes` and routes audio:
   - Waveform: allocate `Oscillator(waveform:, frequency:)` for that MIDI note, attach to its mixer, set amplitude to `settings.referenceVolume`, start.
   - SF2: `midiSampler.play(noteNumber: UInt8(rowMidi), velocity: 100, channel: 0)`.
4. `heldNotes` is `@Observable` → `PitchTimelineView` rerenders highlight + reference line.
5. Finger lifts → `.onEnded` → row clears `isHeld` and calls `referencePlayer.noteOff(midi: rowMidi)` → remove from `heldNotes`, stop+detach the Oscillator (or `midiSampler.stop(noteNumber: UInt8(rowMidi), channel: 0)`).

Multi-touch falls out naturally: each row owns its own gesture; two fingers on two rows produce two independent gesture streams; `heldNotes` accumulates both.

### Settings change

- `settings.referenceSource` change → `ReferencePitchPlayer.setSource(_:)` is invoked from a top-level `.onChange` observer wired in `AudioManager`.
- On switch: stop all held voices, clear `heldNotes`, swap the active inner node (sampler vs oscillator-mixer). The stable `outputNode` keeps the engine graph intact.
- If switching to an SF2, load via `midiSampler.loadSoundFont(url.path, preset: 0, bank: 0)`. On failure, fall back to `.sine` and surface an error to settings.

### Download

1. User taps "Download" (or taps an undownloaded SF2 in the picker).
2. `SoundFontStore.download(id:)` creates a `URLSessionDownloadTask`. Delegate callbacks update `state[id] = .downloading(progress)` on the main actor.
3. On success: move file from temp to `Application Support/NoteVisualizer/SoundFonts/{id}.sf2`; `state[id] = .downloaded`; persist downloaded IDs to UserDefaults.
4. If the download was triggered from the picker, the settings view's `.onChange(of: store.state[id])` auto-sets `settings.referenceSource = .soundFont(id)` once state becomes `.downloaded`.
5. On failure: `state[id] = .failed(message)`. UI shows error with Retry.
6. `cancel(id:)` cancels the task and resets state to `.notDownloaded`. `delete(id:)` removes the file; if it was the active source, fall back to `.sine`.

### Pan/zoom interaction

- Existing `DragGesture` (vertical pan) and `MagnificationGesture` (zoom) stay on the Canvas.
- `NoteAxisOverlay` rectangles use `.highPriorityGesture(DragGesture(minimumDistance: 0))` so a touch on the axis strip plays a note instead of panning.
- A touch on the plot area to the right pans as today.
- When the user pans, the overlay rebuilds for the new visible MIDI range. A held note that scrolls off-screen continues to play (its `noteOff` only fires on finger lift); the reference line stops drawing for off-range rows but reappears if they scroll back. On finger lift, `noteOff` fires regardless of row visibility.

## Error handling and edge cases

- **No network / 5xx / 404 download error** → `.failed(human-readable)`. Red "Retry" beneath the row.
- **Corrupt SF2 (sampler load throws)** → delete the file, set `.failed("File appears corrupt")`, allow retry.
- **Disk full at write-time** → `.failed("Not enough disk space")`. No partial files left behind (write to a temp file in the same volume, atomic move on success).
- **Selected-but-deleted SF2 race at launch** → `ReferencePitchPlayer` falls back to `.sine` and writes that back to settings.
- **`noteOn` failure** (sampler not loaded yet, etc.) → silently no-op; no UI banner.
- **Source switch mid-hold** → all held notes stop; `heldNotes` cleared. (Confirmed during brainstorming.)
- **Held note scrolls off-screen** → keeps playing until finger lift. (Confirmed during brainstorming.)

## Audio session

iOS audio session is already `.playAndRecord` with `.defaultToSpeaker` — output is permitted today. No session changes required. macOS doesn't use AVAudioSession.

## Concurrency

- All `@Observable` state (`heldNotes`, `SoundFontStore.state`, settings) is mutated on the main actor.
- Audio engine calls (`startNote`, `stopNote`, oscillator start/stop, sampler load) are made from the main actor. `AVAudioUnitSampler` note methods are safe enough for this.
- `URLSession` callbacks dispatch their state mutations to the main actor.

## Microphone feedback note

When the device speaker plays the reference pitch, the mic will pick it up and the timeline's PitchTap will draw dots for the played pitch. With headphones, this doesn't happen. We do nothing about this — the dots are useful confirmation that the right pitch is playing, and any mitigation (frequency-keyed dot suppression) is fragile (cents drift, harmonics).

## Testing

The project doesn't have a test target today. This feature adds an XCTest target with focused unit tests for state-machine logic; gesture and audio paths are validated manually.

### Unit tests (new XCTest target)

- `SoundFontStore` state machine: download success, failure, cancel, delete, launch-time file-existence verification. Uses a mock `URLSessionDownloadTaskProtocol` and a temporary directory.
- y↔MIDI math: factor the inverse y→MIDI conversion into a pure helper used by `NoteAxisOverlay`; round-trip test against `yPosition(for:)`.

### Manual test plan

- [ ] Press a row on iOS sim — sine plays; release — silence.
- [ ] Two-finger press on iPad — two pitches simultaneously.
- [ ] Hold a note while panning vertically — note keeps playing; reference line stays drawn while in range.
- [ ] Switch source sine → triangle → square → sawtooth — hear waveform change on next press.
- [ ] Download MuseScore_General over real network — progress shows in both the picker row and the SoundFonts list; on completion source auto-switches and SF2 plays.
- [ ] Cancel mid-download — state resets; no orphaned file.
- [ ] Kill network mid-download — failed state shows; Retry works.
- [ ] Delete a downloaded SF2 that's currently selected — source falls back to sine; picker reflects.
- [ ] macOS click-and-hold — same flows work with single-touch.

## Out of scope

- Custom SF2 import (file picker / pasted URL).
- Per-source volume; per-note velocity sensitivity (one global volume slider).
- Sustain envelope tweaks; release tail beyond SF2/oscillator natural release.
- MIDI input or external controller support.
- Reference melody overlay (separate future feature).
- Headphone-detection prompts.
- User-editable SF2 catalog (catalog is hardcoded for v1; adding new fonts requires an app update).
- iOS background audio (audio stops on background as today).

## Non-functional

- App-binary size impact: zero (SF2s download on demand).
- Disk: largest curated font is ~140 MB; UI shows size before download.
- Battery: marginal cost over today's always-on engine.

## Files added

- `NoteVisualizer/Models/ReferenceSource.swift`
- `NoteVisualizer/Audio/SoundFontCatalog.swift`
- `NoteVisualizer/Audio/SoundFontStore.swift`
- `NoteVisualizer/Audio/ReferencePitchPlayer.swift`
- `NoteVisualizer/Views/NoteAxisOverlay.swift`
- `NoteVisualizer/Views/SoundFontSettingsSection.swift`

## Files modified

- `NoteVisualizer/Models/AppSettings.swift`
- `NoteVisualizer/Audio/AudioManager.swift`
- `NoteVisualizer/Views/PitchTimelineView.swift`
- `NoteVisualizer/Views/SettingsView.swift`
- `project.yml` (XcodeGen — add test target)
