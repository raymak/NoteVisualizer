import SwiftUI

struct SoundFontsCard: View {
    @Environment(AudioManager.self) private var audioManager
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        SettingsCard(title: "SoundFonts") {
            if SoundFontCatalog.entries.isEmpty {
                Text("No SoundFonts available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(SoundFontCatalog.entries) { entry in
                        row(for: entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: SoundFontEntry) -> some View {
        let state = audioManager.soundFontStore.state(for: entry.id)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.subheadline)
                Text("\(entry.licenseName) · \(formatBytes(entry.byteSize))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if case .failed(let msg) = state {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            actionView(state: state, entry: entry)
        }
    }

    @ViewBuilder
    private func actionView(state: SoundFontStore.DownloadState, entry: SoundFontEntry) -> some View {
        switch state {
        case .notDownloaded:
            Button("Download") { startDownload(entry) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .downloading(let p):
            HStack(spacing: 6) {
                ProgressView(value: p).frame(width: 50)
                Button { cancelDownload(entry) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
        case .downloaded:
            Menu {
                Button("Delete", role: .destructive) {
                    audioManager.soundFontStore.delete(id: entry.id)
                }
            } label: {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }
        case .failed:
            Button("Retry") { startDownload(entry) }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func startDownload(_ entry: SoundFontEntry) {
        downloadTasks[entry.id]?.cancel()
        let store = audioManager.soundFontStore
        downloadTasks[entry.id] = Task { @MainActor in
            try? await store.download(id: entry.id, from: entry.url)
        }
    }

    private func cancelDownload(_ entry: SoundFontEntry) {
        downloadTasks[entry.id]?.cancel()
        audioManager.soundFontStore.cancel(id: entry.id)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
