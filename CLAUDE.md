# NoteVisualizer

Real-time pitch visualizer for singing practice. iOS/iPadOS/macOS app.

## Tech Stack
- **UI:** SwiftUI (single codebase, iOS 17+ / macOS 14+)
- **Audio:** AudioKit 5.6+ / SoundpipeAudioKit / AudioKitEX (SPM)
- **Monophonic detection:** AudioKit's PitchTap (YIN-based)
- **Polyphonic detection:** Spotify Basic Pitch CoreML model (`nmp.mlpackage`)
- **Reference-pitch playback:** AudioKit `Oscillator` (waveforms) + `MIDISampler` (.sf2 SoundFonts)
- **Project generation:** XcodeGen (`xcodegen generate` from project root)
- **Tests:** XCTest target `NoteVisualizerTests_iOS` / `NoteVisualizerTests_macOS`

## Project Structure
```
NoteVisualizer/
  App/NoteVisualizerApp.swift        # Entry point; injects env; .onChange wires reference settings; scenePhase panic-stop
  Models/
    PitchDetection.swift             # Detected note data (freq, midi, cents, amplitude)
    AppSettings.swift                # @Observable settings with UserDefaults (clamped referenceVolume)
    Recording.swift                  # Recorded pitch data for playback
    ReferenceSource.swift            # Enum: .sine/.triangle/.square/.sawtooth/.soundFont(id)
  Audio/
    AudioManager.swift               # @MainActor; AudioKit engine, mic capture, recording, owns ReferencePitchPlayer
    PolyphonicDetector.swift         # Basic Pitch CoreML streaming inference
    MonophonicDetector.swift         # PitchTap wrapper (standalone, unused)
    ReferencePitchPlayer.swift       # Stable Mixer outputNode; Oscillator-per-voice or MIDISampler; allNotesOff()
    SoundFontStore.swift             # @Observable download state machine; URLSession-backed Downloader protocol
    SoundFontCatalog.swift           # Static curated SF2 entries (id, url, license, byteSize, sha256)
  Views/
    ContentView.swift                # Two-tab layout (Visualize / Playback); custom dim-overlay for settings
    PitchTimelineView.swift          # 60fps Canvas timeline with dots; held-note + octave reference lines
    RecordingPlaybackView.swift      # Playback with scrubber and Canvas
    SettingsView.swift               # Compact custom settings panel (no Form chrome)
    SoundFontSettingsSection.swift   # SoundFontsList view: per-entry download/cancel/delete UI
    NoteAxisOverlay.swift            # Per-MIDI-row press-and-hold targets aligned to the axis grid
    ModeToggleView.swift             # Mono/Poly picker
  Utilities/
    FrequencyUtils.swift             # Hz ↔ MIDI ↔ note name conversions; midiNote(forY:...) inverse helper
  Resources/
    nmp.mlpackage                    # Spotify Basic Pitch CoreML model
    Assets.xcassets/                 # App icon
NoteVisualizerTests/
  SmokeTests.swift                   # AppSettings instantiation
  ReferenceSourceTests.swift         # Codec round-trip
  NoteAxisMathTests.swift            # y↔MIDI inverse
  SoundFontStoreTests.swift          # Download state machine with mock Downloader
docs/superpowers/
  specs/                             # Design specs (e.g. tappable-notes-soundfonts)
  plans/                             # Implementation plans + manual test checklists
```

## Key Architecture Decisions
- Audio pipeline splits input via separate Mixer nodes (mono vs poly) to avoid AVAudioEngine single-tap-per-bus limitation
- Poly detector uses ring buffer + hop-based sliding window for streaming CoreML inference
- Contour output (264 bins, 3 per semitone) provides sub-semitone pitch accuracy
- MLShapedArray used for reliable CoreML data access (not raw pointers)
- Canvas-based rendering for 60fps timeline performance
- Only latest recording is kept (no history)
- `ReferencePitchPlayer.outputNode` is a stable AudioKit `Mixer` attached once to `engine.output` alongside the silenced mic path; its inputs swap when the source changes (oscillators ↔ MIDISampler)
- Pan and zoom gestures live on a `Color.clear` hit-test layer covering only the plot area (right of axisWidth=40), so they never collide with the per-row note-tap targets in `NoteAxisOverlay`
- `MagnificationGesture` updates a transient `pinchScale` state in real time; commits to `settings.visibleOctaves` (snapped to whole octaves) on `.onEnded`
- `.onChange(of: scenePhase)` calls `referencePlayer.allNotesOff()` so a held note can't leak when the app backgrounds and the gesture is cancelled
- Settings overlay is a custom dim-and-card view (replaces `.popover`); tap outside dismisses, X button in header dismisses, ESC works on macOS

## Reference-pitch playback (tappable note axis)
- y-axis labels are press-and-hold targets via `NoteAxisOverlay` (one invisible row per visible MIDI semitone, `DragGesture(minimumDistance: 0)` wrapped in `.highPriorityGesture` with a per-row `isHeld` idempotency guard)
- Held notes draw a strong dashed accent line across the plot; same-pitch-class octaves draw a faded orange dashed line
- Source picker in Settings: 4 built-in waveforms plus any downloaded SoundFonts
- Tapping an undownloaded SF2 in the picker triggers a download; on success, the source auto-switches to it
- SoundFonts are downloaded into `~/Library/Application Support/NoteVisualizer/SoundFonts/{id}.sf2`
- Active catalog: 1 entry (FluidR3 Mono GM, MIT, ~118 MB) — re-curate via the Task 4 verification process in `docs/superpowers/plans/`

## Build & Run
```bash
xcodegen generate    # Regenerate .xcodeproj from project.yml
# Then open NoteVisualizer.xcodeproj in Xcode and build
```

For macOS local development (avoid universal-binary issue with AudioKit on x86_64):
```bash
xcodebuild -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_macOS \
  -destination 'platform=macOS' ONLY_ACTIVE_ARCH=YES build
```
Or just run the macOS scheme from Xcode (Debug defaults `ONLY_ACTIVE_ARCH=YES`).

Run unit tests:
```bash
xcodebuild test -project NoteVisualizer.xcodeproj -scheme NoteVisualizer_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:NoteVisualizerTests_iOS
```

## Common Patterns
- State management uses Swift `@Observable` (not `ObservableObject`)
- Environment injection: `@Environment(AppSettings.self)`, `@Environment(AudioManager.self)`
- Dark mode only, enforced via `.preferredColorScheme(.dark)`
- Audio starts automatically on launch after mic permission
- `@MainActor` is applied to anything that owns `@Observable` state read from views (e.g. `AudioManager`, `SoundFontStore`, `ReferencePitchPlayer`)
- Volume / settings values clamped at the model boundary in `didSet` so a poisoned `UserDefaults` value can't propagate
