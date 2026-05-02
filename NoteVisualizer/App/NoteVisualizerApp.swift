import SwiftUI

@main
struct NoteVisualizerApp: App {
    @State private var settings = AppSettings()
    @State private var audioManager = AudioManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(audioManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    audioManager.settings = settings
                    audioManager.start()
                }
                .task {
                    audioManager.applyReferenceSettings(source: settings.referenceSource,
                                                        volume: settings.referenceVolume)
                }
                .onChange(of: settings.referenceSource) { _, newValue in
                    audioManager.applyReferenceSettings(source: newValue, volume: settings.referenceVolume)
                }
                .onChange(of: settings.referenceVolume) { _, newValue in
                    audioManager.applyReferenceSettings(source: settings.referenceSource, volume: newValue)
                }
        }
    }
}
