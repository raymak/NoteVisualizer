import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AudioManager.self) private var audioManager

    @State private var pendingSourceForDownload: String?

    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    private var pickerBinding: Binding<ReferenceSource> {
        Binding(
            get: { settings.referenceSource },
            set: { newValue in
                if case .soundFont(let id) = newValue,
                   case .notDownloaded = audioManager.soundFontStore.state(for: id) {
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
                    pendingSourceForDownload = nil
                    settings.referenceSource = newValue
                }
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    detectionSection(settings: settings)
                    referenceSection(settings: settings)
                    SoundFontsCard()
                    displayRangeSection(settings: settings)
                    timelineSection(settings: settings)
                    appearanceSection(settings: settings)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Sections

    private func detectionSection(settings: AppSettings) -> some View {
        SettingsCard(title: "Detection") {
            Picker("Mode", selection: Binding(get: { settings.detectionMode },
                                              set: { settings.detectionMode = $0 })) {
                ForEach(AppSettings.DetectionMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func referenceSection(settings: AppSettings) -> some View {
        SettingsCard(title: "Reference Pitch") {
            VStack(spacing: 8) {
                HStack {
                    Text("Source")
                        .font(.subheadline)
                    Spacer()
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
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(spacing: 10) {
                    Text("Volume")
                        .font(.subheadline)
                        .frame(width: 56, alignment: .leading)
                    Slider(value: Binding(get: { settings.referenceVolume },
                                          set: { settings.referenceVolume = $0 }),
                           in: 0...1)
                    Text("\(Int(settings.referenceVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
    }

    private func displayRangeSection(settings: AppSettings) -> some View {
        SettingsCard(title: "Display Range") {
            VStack(spacing: 6) {
                compactStepperRow(label: "Lowest octave",
                                  value: settings.lowestOctave,
                                  range: 1...6,
                                  set: { settings.lowestOctave = $0 })
                compactStepperRow(label: "Visible octaves",
                                  value: settings.visibleOctaves,
                                  range: 1...5,
                                  set: { settings.visibleOctaves = $0 })
                HStack {
                    Spacer()
                    Text("\(FrequencyUtils.fullNoteName(for: settings.lowestMidiNote)) – \(FrequencyUtils.fullNoteName(for: settings.highestMidiNote))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func timelineSection(settings: AppSettings) -> some View {
        SettingsCard(title: "Timeline") {
            HStack(spacing: 10) {
                Text("Window")
                    .font(.subheadline)
                    .frame(width: 56, alignment: .leading)
                Slider(value: Binding(get: { settings.timelineWindowSeconds },
                                      set: { settings.timelineWindowSeconds = $0 }),
                       in: 5...30, step: 1)
                Text("\(Int(settings.timelineWindowSeconds))s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func appearanceSection(settings: AppSettings) -> some View {
        SettingsCard(title: "Appearance") {
            Picker("Color", selection: Binding(get: { settings.colorMode },
                                                set: { settings.colorMode = $0 })) {
                ForEach(AppSettings.ColorMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: - Sub-components

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

    private func compactStepperRow(label: String,
                                   value: Int,
                                   range: ClosedRange<Int>,
                                   set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 6) {
                Button {
                    if value > range.lowerBound { set(value - 1) }
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(value <= range.lowerBound)

                Text("\(value)")
                    .font(.subheadline.monospacedDigit())
                    .frame(minWidth: 18)

                Button {
                    if value < range.upperBound { set(value + 1) }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(value >= range.upperBound)
            }
        }
    }
}

// MARK: - SettingsCard

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
