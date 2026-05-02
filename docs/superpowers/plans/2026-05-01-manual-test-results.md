# Tappable-Notes Manual Test Checklist (Task 20)

**Date:** 2026-05-01
**Build:** a1f9700df414448b8e24a5803781cb90d53f95b4
**Simulator:** iPhone 16 Pro Max (iOS 18.2, id: 0FF74470-CD90-47A0-BC52-F83ADAE0E189)
**App boot screenshot:** /tmp/notevisualizer-launch.png

## Automated checks

- [x] `xcodebuild build` — BUILD SUCCEEDED
- [x] `xcodebuild test -only-testing:NoteVisualizerTests_iOS` — 18 tests pass
- [x] App launches on iOS simulator without immediate crash

## Manual checks (user must run through these)

### Press-and-hold playback
- [ ] Press and hold a note label on the y-axis — sine tone plays.
- [ ] Release — sound stops.
- [ ] Multiple finger taps on different rows (iPad) — multiple pitches play simultaneously.

### Held-note visuals
- [ ] Held row's overlay rectangle has accent-colored tint.
- [ ] Held row's label brightens to white and bolds.
- [ ] Dashed accent-colored horizontal reference line drawn across the plot at the held pitch.
- [ ] All visuals disappear on release.

### Pan during a held note
- [ ] Hold a note, then pan vertically on the plot area — note keeps playing.
- [ ] Reference line stays drawn while the held note's row is in the visible MIDI range.
- [ ] If the held note scrolls out of range, audio still plays (line just disappears).
- [ ] On finger lift, sound stops.

### Source switching
- [ ] Open Settings → Reference Pitch.
- [ ] Switch source between Sine, Triangle, Square, Sawtooth — hear timbre change on next press.
- [ ] Adjust volume slider — slider value persists across app restarts.

### SoundFont download
(Only if SoundFontCatalog has at least one entry — currently 1 entry: "FluidR3 Mono GM")
- [ ] Open Settings → SoundFonts. Tap "Download" next to the entry.
- [ ] Progress bar appears and animates from 0% to 100%.
- [ ] On completion, "Installed" label with green checkmark appears.
- [ ] Pick the SF2 from the source picker — hear the sampled instrument on next press.
- [ ] Tap the "Installed" menu → Delete. SF2 is removed; selection falls back to sine.

### SoundFont download error handling
- [ ] Disable WiFi, tap Download. After delay, "Retry" button + red error text appears.
- [ ] Re-enable WiFi, tap Retry. Download succeeds.

### Picker tap-to-download
- [ ] After deleting the SF2, in the picker row tap "FluidR3 Mono GM (tap to download)".
- [ ] Picker briefly shows the new selection then snaps back. Row text changes to "FluidR3 Mono GM — N%" with progress.
- [ ] On completion, picker auto-switches to the SF2.

### Background and resume
- [ ] Hold a note. Without releasing, swipe up to home screen.
- [ ] Re-open the app. The held note has stopped (panic-stop fired on background).

### Pan and zoom interaction
- [ ] Drag vertically on the plot area (right of the y-axis strip) — timeline pans normally; no notes play.
- [ ] Drag on the axis strip — note plays, timeline does NOT pan.
- [ ] Pinch to zoom — visible MIDI range expands/contracts; existing pan behavior preserved.

### macOS (if applicable)
- [ ] Run on macOS scheme — same flows work with single mouse-down.

## Findings

[Empty — fill in as user runs the checklist.]
