import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showSettings = false
    @State private var showPrivacyDashboard = false

    var body: some View {
        TabView(selection: $coordinator.selectedMode) {
            // Mode 1: Native Audio
            NavigationStack {
                AudioModeView()
                    .navigationTitle("Audio Mode")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Audio", systemImage: "waveform")
            }
            .tag(AppCoordinator.ConversationMode.nativeAudio)

            // Mode 2: Voice Chat Local (ElevenLabs - pending integration)
            NavigationStack {
                VoiceChatLocalView()
                    .navigationTitle("Voice Chat")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Voice", systemImage: "mic.circle")
            }
            .tag(AppCoordinator.ConversationMode.voiceChatLocal)

            // Mode 3: Text + Multimodal
            NavigationStack {
                TextMultimodalView()
                    .navigationTitle("Text & Multimodal")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Text", systemImage: "keyboard")
            }
            .tag(AppCoordinator.ConversationMode.textMultimodal)
        }
        .accentColor(.blue)
        .onAppear {
            if ProcessInfo.processInfo.environment["AUTO_MODE1_CONNECT"] == "1" {
                coordinator.selectedMode = .nativeAudio
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppCoordinator())
}
