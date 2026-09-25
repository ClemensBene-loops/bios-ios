import SwiftUI

/// Placeholder home screen. Phase 3 replaces the body with the latest
/// Whoop check and outlook loaded from the BIOS server.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.teal)
            Text("BIOS")
                .font(.largeTitle.bold())
            Text("Version \(AppConfig.version) (\(AppConfig.build))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label(
                AppConfig.isServerConfigured ? "Server konfiguriert" : "Server nicht konfiguriert",
                systemImage: AppConfig.isServerConfigured ? "checkmark.circle" : "exclamationmark.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
