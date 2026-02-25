# NoteVisualizer

Real-time pitch visualizer for singing practice. iOS/iPadOS/macOS app.

## Tech Stack
- **UI:** SwiftUI (single codebase, iOS 17+ / macOS 14+)
- **Audio:** AudioKit 5.6+ / SoundpipeAudioKit / AudioKitEX (SPM)
- **Monophonic detection:** AudioKit's PitchTap (YIN-based)
- **Polyphonic detection:** Spotify Basic Pitch CoreML model (`nmp.mlpackage`)
- **Project generation:** XcodeGen (`xcodegen generate` from project root)

## Project Structure
```
NoteVisualizer/
  App/NoteVisualizerApp.swift        # Entry point, injects environments
  Models/
    PitchDetection.swift             # Detected note data (freq, midi, cents, amplitude)
    AppSettings.swift                # @Observable settings with UserDefaults
    Recording.swift                  # Recorded pitch data for playback
  Audio/
    AudioManager.swift               # AudioKit engine, mic capture, recording
    PolyphonicDetector.swift         # Basic Pitch CoreML streaming inference
    MonophonicDetector.swift         # PitchTap wrapper (standalone, unused)
  Views/
    ContentView.swift                # Two-tab layout (Visualize / Playback)
    PitchTimelineView.swift          # 60fps Canvas timeline with dots
    RecordingPlaybackView.swift      # Playback with scrubber and Canvas
    SettingsView.swift               # Settings popover
    ModeToggleView.swift             # Mono/Poly picker
  Utilities/
    FrequencyUtils.swift             # Hz ↔ MIDI ↔ note name conversions
  Resources/
    nmp.mlpackage                    # Spotify Basic Pitch CoreML model
    Assets.xcassets/                 # App icon
```

## Key Architecture Decisions
- Audio pipeline splits input via separate Mixer nodes (mono vs poly) to avoid AVAudioEngine single-tap-per-bus limitation
- Poly detector uses ring buffer + hop-based sliding window for streaming CoreML inference
- Contour output (264 bins, 3 per semitone) provides sub-semitone pitch accuracy
- MLShapedArray used for reliable CoreML data access (not raw pointers)
- Canvas-based rendering for 60fps timeline performance
- Only latest recording is kept (no history)

## Build & Run
```bash
xcodegen generate    # Regenerate .xcodeproj from project.yml
# Then open NoteVisualizer.xcodeproj in Xcode and build
```

## Common Patterns
- State management uses Swift @Observable (not ObservableObject)
- Environment injection: `@Environment(AppSettings.self)`, `@Environment(AudioManager.self)`
- Dark mode only, enforced via `.preferredColorScheme(.dark)`
- Audio starts automatically on launch after mic permission
