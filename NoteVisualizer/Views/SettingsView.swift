import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AudioManager.self) private var audioManager

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

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section("Detection") {
                    Picker("Mode", selection: $settings.detectionMode) {
                        ForEach(AppSettings.DetectionMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Reference Pitch") {
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

                    VStack(alignment: .leading) {
                        Text("Volume: \(Int(settings.referenceVolume * 100))%")
                        Slider(value: $settings.referenceVolume, in: 0...1)
                    }
                }

                SoundFontSettingsSection()

                Section("Display Range") {
                    Stepper("Lowest Octave: \(settings.lowestOctave)", value: $settings.lowestOctave, in: 1...6)

                    Stepper("Visible Octaves: \(settings.visibleOctaves)", value: $settings.visibleOctaves, in: 1...5)

                    Text("Showing \(FrequencyUtils.fullNoteName(for: settings.lowestMidiNote)) to \(FrequencyUtils.fullNoteName(for: settings.highestMidiNote))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timeline") {
                    VStack(alignment: .leading) {
                        Text("Window: \(Int(settings.timelineWindowSeconds))s")
                        Slider(value: $settings.timelineWindowSeconds, in: 5...30, step: 1)
                    }
                }

                Section("Appearance") {
                    Picker("Color Mode", selection: $settings.colorMode) {
                        ForEach(AppSettings.ColorMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
