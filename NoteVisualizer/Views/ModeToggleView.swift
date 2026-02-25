import SwiftUI

struct ModeToggleView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Picker("Mode", selection: $settings.detectionMode) {
            ForEach(AppSettings.DetectionMode.allCases, id: \.self) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 140)
    }
}
