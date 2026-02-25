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
        }
    }
}
