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
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Detection")
                    pickerRow("Mode", selection: Binding(get: { settings.detectionMode },
                                                          set: { settings.detectionMode = $0 }),
                              cases: AppSettings.DetectionMode.allCases,
                              segmented: true)
                    pickerRow("Color", selection: Binding(get: { settings.colorMode },
                                                           set: { settings.colorMode = $0 }),
                              cases: AppSettings.ColorMode.allCases,
                              segmented: true)

                    sectionHeader("Reference Pitch")
                    HStack(spacing: 8) {
                        Text("Source").font(.footnote).foregroundStyle(.primary)
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
                        .controlSize(.small)
                    }
                    sliderRow("Volume",
                              value: Binding(get: { settings.referenceVolume },
                                             set: { settings.referenceVolume = $0 }),
                              in: 0...1,
                              suffix: "\(Int(settings.referenceVolume * 100))%")

                    if !SoundFontCatalog.entries.isEmpty {
                        sectionHeader("SoundFonts")
                        SoundFontsList()
                    }

                    sectionHeader("Display")
                    stepperRow("Lowest octave",
                               value: settings.lowestOctave,
                               range: 1...6,
                               set: { settings.lowestOctave = $0 })
                    stepperRow("Visible octaves",
                               value: settings.visibleOctaves,
                               range: 1...5,
                               set: { settings.visibleOctaves = $0 })
                    HStack {
                        Spacer()
                        Text("\(FrequencyUtils.fullNoteName(for: settings.lowestMidiNote)) – \(FrequencyUtils.fullNoteName(for: settings.highestMidiNote))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    sectionHeader("Timeline")
                    sliderRow("Window",
                              value: Binding(get: { settings.timelineWindowSeconds },
                                             set: { settings.timelineWindowSeconds = $0 }),
                              in: 5...30,
                              step: 1,
                              suffix: "\(Int(settings.timelineWindowSeconds))s")
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 16)
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
                        .font(.body)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .padding(.top, 4)
    }

    // MARK: - Reusable rows

    @ViewBuilder
    private func pickerRow<T: Hashable & RawRepresentable>(_ label: String,
                                                            selection: Binding<T>,
                                                            cases: [T],
                                                            segmented: Bool) -> some View where T.RawValue == String {
        HStack(spacing: 8) {
            Text(label).font(.footnote)
            Spacer()
            if segmented {
                Picker(label, selection: selection) {
                    ForEach(cases, id: \.self) { c in
                        Text(displayLabel(for: c)).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            } else {
                Picker(label, selection: selection) {
                    ForEach(cases, id: \.self) { c in
                        Text(displayLabel(for: c)).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    private func displayLabel<T>(for value: T) -> String {
        if let m = value as? AppSettings.DetectionMode { return m.label }
        if let m = value as? AppSettings.ColorMode { return m.label }
        return String(describing: value)
    }

    private func sliderRow(_ label: String,
                            value: Binding<Double>,
                            in range: ClosedRange<Double>,
                            step: Double = 0,
                            suffix: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.footnote)
                .frame(width: 56, alignment: .leading)
            if step > 0 {
                Slider(value: value, in: range, step: step)
            } else {
                Slider(value: value, in: range)
            }
            Text(suffix)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func stepperRow(_ label: String,
                             value: Int,
                             range: ClosedRange<Int>,
                             set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label).font(.footnote)
            Spacer()
            HStack(spacing: 4) {
                tinyButton(systemName: "minus", disabled: value <= range.lowerBound) {
                    if value > range.lowerBound { set(value - 1) }
                }
                Text("\(value)")
                    .font(.footnote.monospacedDigit())
                    .frame(minWidth: 14)
                tinyButton(systemName: "plus", disabled: value >= range.upperBound) {
                    if value < range.upperBound { set(value + 1) }
                }
            }
        }
    }

    private func tinyButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(disabled ? 0.04 : 0.10))
                .clipShape(Circle())
                .foregroundStyle(disabled ? Color.white.opacity(0.3) : .white)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
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
}
