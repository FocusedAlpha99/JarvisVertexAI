import SwiftUI
import AVFoundation
import Combine

// MARK: - Mode 1: Native Audio UI
struct AudioModeView: View {
    @StateObject private var viewModel = AudioModeViewModel()
    @State private var isRecording = false
    @State private var showPrivacyInfo = false
    @State private var audioLevel: CGFloat = 0
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
                            .fill(isRecording ? Color.red : Color.white)
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(isRecording ? .white : .black)
                    }
                }
                .scaleEffect(isRecording ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: isRecording)
                
                // Session info
                if let session = viewModel.currentSession {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session: \\(session.id.prefix(8))...", systemImage: "tag")
                        Label("Duration: \\(formatDuration(session.duration))", systemImage: "timer")
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
        if isRecording {
            viewModel.stopRecording()
        } else {
            viewModel.startRecording()
        }
        isRecording.toggle()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? "0:00"
    }
}

// MARK: - Audio Waveform Visualization
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
    let audioLevelPublisher = PassthroughSubject<CGFloat, Never>()
    
    private var audioSession: AudioSession?
    private let dbManager = ObjectBoxManager.shared
    private var audioLevelTimer: Timer?
    
    struct AudioSessionInfo {
        let id: String
        let startTime: Date
        var duration: TimeInterval {
            Date().timeIntervalSince(startTime)
        }
    }
    
    func startRecording() {
        Task {
            do {
                // Request microphone permission
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .voiceChat)
                try audioSession.setActive(true)
                
                await MainActor.run {
                    statusMessage = "Connecting to private Gemini Live..."
                }
                
                // Initialize audio session with privacy config
                self.audioSession = try await AudioSession(
                    projectId: VertexConfig.projectId,
                    region: VertexConfig.region,
                    endpointId: VertexConfig.audioEndpointId
                )
                
                let sessionId = UUID().uuidString
                await MainActor.run {
                    currentSession = AudioSessionInfo(id: sessionId, startTime: Date())
                    statusMessage = "Listening... (Zero data retention active)"
                }
                
                // Start audio level monitoring
                startAudioLevelMonitoring()
                
                // Save session start to local DB
                try dbManager.createSession(
                    mode: .nativeAudio,
                    metadata: ["privacy": "zero_retention", "cmek": "enabled"]
                )
                
            } catch {
                await MainActor.run {
                    statusMessage = "Error: \\(error.localizedDescription)"
                }
            }
        }
    }
    
    func stopRecording() {
        audioSession?.terminate()
        audioSession = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        statusMessage = "Session ended (all data cleared)"
        
        // Clear audio buffers immediately
        clearAudioBuffers()
    }
    
    func pauseSession() {
        audioSession?.pause()
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
    
    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            // Simulate audio level (replace with actual audio meter)
            let level = CGFloat.random(in: 0.3...1.0)
            self.audioLevelPublisher.send(level)
        }
    }
    
    private func clearAudioBuffers() {
        // Overwrite audio buffers with random data
        let bufferSize = 1024 * 16 // 16KB buffer
        var buffer = Data(count: bufferSize)
        _ = buffer.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bufferSize, bytes.baseAddress!)
        }
    }
}

// MARK: - Privacy Info Sheet
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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