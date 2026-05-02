import SwiftUI

enum AppTab: String, CaseIterable {
    case visualize = "Visualize"
    case playback = "Playback"

    var icon: String {
        switch self {
        case .visualize: "waveform"
        case .playback: "play.rectangle"
        }
    }
}

struct ContentView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AudioManager.self) private var audioManager
    @State private var showSettings = false
    @State private var selectedTab: AppTab = .visualize

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar

                switch selectedTab {
                case .visualize:
                    visualizeSection
                case .playback:
                    playbackSection
                }
            }

            if showSettings {
                settingsOverlay
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showSettings)
    }

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeSettings() }
                .transition(.opacity)

            SettingsView(onClose: { closeSettings() })
                .frame(maxWidth: 460, maxHeight: 620)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
                .padding(20)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func closeSettings() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showSettings = false
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.subheadline)
                        Text(tab.rawValue)
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .gray)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? Color.white.opacity(0.1) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            settingsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black)
    }

    // MARK: - Visualize Section

    private var visualizeSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ModeToggleView()

                recordButton

                statusIndicator

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            PitchTimelineView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        Group {
            if let recording = audioManager.latestRecording {
                RecordingPlaybackView(recording: recording)
                    .id(recording.id)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray.opacity(0.5))
                    Text("No Recording Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap Record in Visualize to capture a pitch visualization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Components

    private var recordButton: some View {
        Button {
            if audioManager.isRecording {
                audioManager.stopRecording()
            } else {
                audioManager.startRecording()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(audioManager.isRecording ? Color.red : Color.red.opacity(0.6))
                    .frame(width: 10, height: 10)

                ZStack {
                    Text("Stop").hidden()
                    Text(audioManager.isRecording ? "Stop" : "Rec")
                        .foregroundStyle(audioManager.isRecording ? .red : .white)
                }
                .font(.caption.weight(.semibold))
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(audioManager.isRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.1))
                    .stroke(audioManager.isRecording ? Color.red.opacity(0.4) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(audioManager.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            ZStack {
                Text("Listening").hidden()
                Text(audioManager.isRunning ? "Listening" : "Stopped")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize()
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "gear")
                .font(.title3)
                .foregroundStyle(.gray)
        }
        .buttonStyle(.plain)
    }
}
