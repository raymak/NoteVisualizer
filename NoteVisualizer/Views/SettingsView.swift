import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

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
