import SwiftUI

struct SoundFontSettingsSection: View {
    @Environment(AudioManager.self) private var audioManager
    @State private var downloadTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        Section("SoundFonts") {
            if SoundFontCatalog.entries.isEmpty {
                Text("No SoundFonts available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(SoundFontCatalog.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: SoundFontEntry) -> some View {
        let state = audioManager.soundFontStore.state(for: entry.id)
        HStack {
            VStack(alignment: .leading) {
                Text(entry.displayName)
                Text("\(entry.licenseName) · \(formatBytes(entry.byteSize))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .failed(let msg) = state {
                    Text(msg).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            switch state {
            case .notDownloaded:
                Button("Download") { startDownload(entry) }
            case .downloading(let p):
                HStack {
                    ProgressView(value: p).frame(width: 60)
                    Button {
                        cancelDownload(entry)
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                }
            case .downloaded:
                Menu {
                    Button("Delete", role: .destructive) {
                        audioManager.soundFontStore.delete(id: entry.id)
                    }
                } label: {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .failed:
                Button("Retry") { startDownload(entry) }
                    .foregroundStyle(.red)
            }
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
