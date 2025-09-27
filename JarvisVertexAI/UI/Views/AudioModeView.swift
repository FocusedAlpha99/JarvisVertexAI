import SwiftUI
import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Mode 1: Native Audio UI
@available(iOS 17.0, macOS 12.0, *)
struct AudioModeView: View {
    @StateObject private var viewModel = AudioModeViewModel()
    @State private var showPrivacyInfo = false
    @State private var audioLevel: CGFloat = 0
    @State private var didAutoStart = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.black, Color.gray.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Privacy indicator
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("100% Private Audio")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    Button(action: { showPrivacyInfo = true }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Audio visualization
                AudioWaveformView(audioLevel: audioLevel)
                    .frame(height: 120)
                    .padding(.horizontal)
                
                // Status text
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .animation(.easeInOut, value: viewModel.statusMessage)
                
                // Recording button
                Button(action: toggleRecording) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isRecording ? Color.red : Color.white)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: viewModel.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(viewModel.isRecording ? .white : .black)
                    }
                }
                .scaleEffect(viewModel.isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: viewModel.isRecording)
                
                // Session info
                if let session = viewModel.currentSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session: \(session.id.prefix(8))...", systemImage: "tag")
                        Label("Duration: \(formatDuration(session.duration))", systemImage: "timer")
                        Label("Privacy: Zero Retention", systemImage: "eye.slash")
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(10)
                }
                
                Spacer()
                
                // Clear session button
                Button(action: viewModel.clearLocalSession) {
                    Label("Clear Local Session", systemImage: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                .padding(.bottom)
            }
        }
        .onAppear {
            // Auto-start Mode 1 when env var is set (for CI/terminal-driven tests)
            if !didAutoStart,
               ProcessInfo.processInfo.environment["AUTO_MODE1_CONNECT"] == "1" {
                didAutoStart = true
                if !viewModel.isRecording {
                    toggleRecording()
                }
            }
        }
        .sheet(isPresented: $showPrivacyInfo) {
            PrivacyInfoSheet(mode: .audio)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                viewModel.pauseSession()
            }
        }
        .onReceive(viewModel.audioLevelPublisher) { level in
            withAnimation(.linear(duration: 0.1)) {
                audioLevel = level
            }
        }
    }
    
    private func toggleRecording() {
        viewModel.toggleRecording()
        
        // Haptic feedback (iOS only)
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "0:00"
    }
}

// MARK: - Audio Waveform Visualization
@available(iOS 17.0, macOS 12.0, *)
struct AudioWaveformView: View {
    let audioLevel: CGFloat
    @State private var bars: [CGFloat] = Array(repeating: 0.2, count: 30)
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 3) {
                ForEach(0..<bars.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: (geometry.size.width / CGFloat(bars.count)) - 3,
                               height: geometry.size.height * bars[index])
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.6),
                            value: bars[index]
                        )
                }
            }
        }
        .onAppear {
            animateBars()
        }
        .onChange(of: audioLevel) { _ in
            updateBars()
        }
    }
    
    private func animateBars() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBars()
        }
    }
    
    private func updateBars() {
        for i in 0..<bars.count {
            let randomHeight = CGFloat.random(in: 0.1...1.0) * audioLevel
            bars[i] = max(0.2, min(1.0, randomHeight))
        }
    }
}

// MARK: - Audio Mode View Model
class AudioModeViewModel: ObservableObject {
    @Published var statusMessage = "Tap to start private conversation"
    @Published var currentSession: AudioSessionInfo?
    @Published var isRecording = false
    @Published var connectionState: ConnectionState = .disconnected
    let audioLevelPublisher = PassthroughSubject<CGFloat, Never>()

    // Use the AudioConnectionState from the Core AudioSession
    typealias ConnectionState = AudioConnectionState
    
    private let dbManager = SimpleDataManager.shared
    private var audioLevelTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    struct AudioSessionInfo {
        let id: String
        let startTime: Date
        var duration: TimeInterval {
            Date().timeIntervalSince(startTime)
        }
    }
    
    init() {
        // Listen to AudioSession connection state changes
        AudioSession.shared.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)

        // Legacy notification support for backward compatibility
        NotificationCenter.default.publisher(for: NSNotification.Name("audioSessionConnected"))
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.isRecording = true
                self.statusMessage = "Listening... (Zero data retention active)"
                self.startAudioLevelMonitoring()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("audioSessionDisconnected"))
            .receive(on: DispatchQueue.main)
            .sink { _ in
                self.isRecording = false
                self.statusMessage = "Session ended (all data cleared)"
                self.currentSession = nil
                self.audioLevelTimer?.invalidate()
                self.audioLevelTimer = nil
            }
            .store(in: &cancellables)
    }

    private func handleConnectionStateChange(_ state: ConnectionState) {
        switch state {
        case .disconnected:
            isRecording = false
            statusMessage = "Tap to start private conversation"
            currentSession = nil
            audioLevelTimer?.invalidate()
            audioLevelTimer = nil

        case .connecting:
            statusMessage = "Connecting to Gemini Live API..."

        case .connected:
            isRecording = true
            statusMessage = "Connected! (Zero data retention active)"
            startAudioLevelMonitoring()

            // Create session info if we don't have one
            if currentSession == nil {
                let sessionId = UUID().uuidString
                currentSession = AudioSessionInfo(id: sessionId, startTime: Date())
            }

        case .error(let message):
            isRecording = false
            statusMessage = "Error: \(message)"
            currentSession = nil
            audioLevelTimer?.invalidate()
            audioLevelTimer = nil
        }
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        Task {
            do {
                // The connection state publisher will handle UI updates
                try await AudioSession.shared.connect()
            } catch {
                print("❌ Failed to start recording: \(error)")
                handleAudioError(error)
            }
        }
    }
    
    func stopRecording() {
        AudioSession.shared.terminate()
    }
    
    func pauseSession() {
        AudioSession.shared.terminate()
        statusMessage = "Session paused"
    }
    
    func clearLocalSession() {
        // Clear all local session data
        if let sessionId = currentSession?.id {
            try? dbManager.deleteSession(sessionId: sessionId)
        }
        currentSession = nil
        statusMessage = "Local session data cleared"
    }

    // MARK: - Error Handling

    private func handleAudioError(_ error: Error) {
        print("🚨 MODE 1 UI ERROR: \(error)")
        print("🚨 MODE 1 ERROR TYPE: \(String(describing: type(of: error)))")
        print("🚨 MODE 1 ERROR LOCALIZED: \(error.localizedDescription)")

        // Check specific error types
        if let audioError = error as? AudioSessionError {
            print("🚨 AUDIO SESSION SPECIFIC ERROR: \(audioError)")
            switch audioError {
            case .noAuthToken:
                statusMessage = "DEBUG: No authentication token - check VERTEX_ACCESS_TOKEN"
            case .connectionFailed:
                statusMessage = "DEBUG: Connection failed - check network and credentials"
            case .invalidResponse:
                statusMessage = "DEBUG: Invalid API response - check Vertex AI configuration"
            case .tokenExpired:
                statusMessage = "DEBUG: Access token expired - needs refresh"
            }
        } else if let configError = error as? ConfigurationError {
            print("🚨 CONFIGURATION ERROR: \(configError)")
            switch configError {
            case .missingRequiredVariable(let variable):
                statusMessage = "DEBUG: Missing config - \(variable) not set"
            case .projectNotConfigured:
                statusMessage = "DEBUG: Project ID not configured"
            case .authenticationRequired:
                statusMessage = "DEBUG: Authentication method not configured"
            default:
                statusMessage = "DEBUG: Config error - \(configError.localizedDescription)"
            }
        } else {
            // Generic error with full details
            statusMessage = "DEBUG: \(error.localizedDescription) [\(String(describing: type(of: error)))]"
        }

        print("🚨 MODE 1 STATUS MESSAGE SET TO: \(statusMessage)")
    }

    private func startAudioLevelMonitoring() {
        self.audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            let level = CGFloat.random(in: 0.3...1.0)
            self.audioLevelPublisher.send(level)
        }
    }
    
}

// MARK: - Privacy Info Sheet
@available(iOS 17.0, macOS 12.0, *)
struct PrivacyInfoSheet: View {
    enum Mode {
        case audio, voice, text
    }
    
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Mode-specific info
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(modeTitle, systemImage: modeIcon)
                                .font(.headline)
                            
                            Text(modeDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Privacy guarantees
                    GroupBox("Privacy Guarantees") {
                        VStack(alignment: .leading, spacing: 8) {
                            PrivacyRow(icon: "lock.shield", text: "Zero data retention")
                            PrivacyRow(icon: "key", text: "CMEK encryption (HSM)")
                            PrivacyRow(icon: "network.slash", text: "VPC Service Controls")
                            PrivacyRow(icon: "eye.slash", text: "No prompt logging")
                            PrivacyRow(icon: "iphone", text: "100% local database")
                            PrivacyRow(icon: "xmark.icloud", text: "No cloud backup")
                        }
                    }
                    
                    // Compliance
                    GroupBox("Compliance") {
                        VStack(alignment: .leading, spacing: 8) {
                            PrivacyRow(icon: "checkmark.seal", text: "HIPAA compliant")
                            PrivacyRow(icon: "flag.2.crossed", text: "GDPR Article 32")
                            PrivacyRow(icon: "doc.badge.gearshape", text: "PHI/PII protection")
                            PrivacyRow(icon: "clock.arrow.circlepath", text: "6-year audit logs")
                        }
                    }
                    
                    // Data handling
                    GroupBox("Data Handling") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("• All data stored in ObjectBox (local only)")
                            Text("• Automatic cleanup after 30 days")
                            Text("• Encrypted with device-specific key")
                            Text("• No network sync or cloud backup")
                            Text("• PHI redaction before API calls")
                        }
                        .font(.caption)
                    }
                }
                .padding()
            }
            .navigationTitle("Privacy Information")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private var modeTitle: String {
        switch mode {
        case .audio: return "Native Audio Mode"
        case .voice: return "Voice Chat Local Mode"
        case .text: return "Text + Multimodal Mode"
        }
    }
    
    private var modeIcon: String {
        switch mode {
        case .audio: return "waveform"
        case .voice: return "mic.circle"
        case .text: return "keyboard"
        }
    }
    
    private var modeDescription: String {
        switch mode {
        case .audio:
            return "Direct audio streaming to Gemini Live API with zero retention and CMEK encryption"
        case .voice:
            return "On-device speech recognition, text-only API calls, local TTS synthesis"
        case .text:
            return "Keyboard input with multimodal support, ephemeral file storage"
        }
    }
}

@available(iOS 17.0, macOS 11.0, *)
struct PrivacyRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
        }
    }
}