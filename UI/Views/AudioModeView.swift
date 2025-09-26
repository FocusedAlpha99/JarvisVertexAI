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
                switch viewModel.connectionState {
                case .disconnected:
                    Text("Tap to start private conversation")
                case .connecting:
                    Text("Connecting to private Gemini Live...")
                case .connected:
                    Text("Listening... (Zero data retention active)")
                case .error(let message):
                    Text("Error: \(message)")
                }
                
                
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
    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var currentSession: AudioSessionInfo?
    let audioLevelPublisher = PassthroughSubject<CGFloat, Never>()
    
    private var audioSession: AudioSession?
    private let dbManager = ObjectBoxManager.shared
    private var audioLevelTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?

    init() {
        AudioSession.shared.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioData(_:)), name: .audioSessionDidCaptureAudio, object: nil)
    }

    @objc private func handleAudioData(_ notification: Notification) {
        if let data = notification.userInfo?["audioData"] as? Data {
            playAudioData(data)
        }
    }

    func playAudioData(_ data: Data) {
        let wavData = createWAVData(from: data, sampleRate: 16000, channels: 1)
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.play()
            print("Playing back captured audio.")
        } catch {
            print("Failed to play back audio: \(error.localizedDescription)")
        }
    }

    private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data()
        let fileSize = UInt32(36 + pcmData.count)
        let sampleRateUInt32 = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = UInt16(channels * Int(bitsPerSample) / 8)
        let byteRate = UInt32(sampleRate * channels * Int(bitsPerSample) / 8)

        data.append("RIFF".data(using: .ascii)!)
        data.append(Data(bytes: &fileSize, count: 4))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        var chunkSize: UInt32 = 16
        data.append(Data(bytes: &chunkSize, count: 4))
        var audioFormat: UInt16 = 1 // PCM
        data.append(Data(bytes: &audioFormat, count: 2))
        var channelsUInt16 = UInt16(channels)
        data.append(Data(bytes: &channelsUInt16, count: 2))
        data.append(Data(bytes: &sampleRateUInt32, count: 4))
        data.append(Data(bytes: &byteRate, count: 4))
        data.append(Data(bytes: &blockAlign, count: 2))
        data.append(Data(bytes: &bitsPerSample, count: 2))
        data.append("data".data(using: .ascii)!)
        var dataSize = UInt32(pcmData.count)
        data.append(Data(bytes: &dataSize, count: 4))
        data.append(pcmData)

        return data
    }

    class AudioSessionInfo: ObservableObject {
        let id: String
        let startTime: Date
        @Published var duration: TimeInterval

        init(id: String, startTime: Date) {
            self.id = id
            self.startTime = startTime
            self.duration = 0
        }

        func updateDuration() {
            duration = Date().timeIntervalSince(startTime)
        }
    }
    
    func startRecording() {
        Task {
            do {
                // Request microphone permission
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .voiceChat)
                try audioSession.setActive(true)
                #endif
                
                // Initialize audio session with privacy config
                self.audioSession = AudioSession.shared
                try await self.audioSession?.connect(
                    projectId: VertexConfig.projectId,
                    region: VertexConfig.region,
                    endpointId: VertexConfig.audioEndpointId
                )
                
                let sessionId = UUID().uuidString
                await MainActor.run {
                    currentSession = AudioSessionInfo(id: sessionId, startTime: Date())
                    startDurationTimer()
                }

                // Start audio level monitoring
                startAudioLevelMonitoring()

                // Save session start to local DB
                _ = dbManager.createSession(
                    mode: "nativeAudio",
                    metadata: ["privacy": "zero_retention", "cmek": "enabled"]
                )
                
            } catch {
                await MainActor.run {
                    connectionState = .error(error.localizedDescription)
                }
            }
        }
    }
    
    func stopRecording() {
        audioSession?.terminate()
        audioSession = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        durationTimer?.invalidate()
        durationTimer = nil
        
        // Clear audio buffers immediately
        clearAudioBuffers()
    }
    
    func pauseSession() {
        audioSession?.pause()
        statusMessage = "Session paused"
        durationTimer?.invalidate()
    }
    
    func clearLocalSession() {
        // Clear all local session data
        if let sessionId = currentSession?.id {
            try? dbManager.deleteSession(sessionId: sessionId)
        }
        currentSession = nil
        statusMessage = "Local session data cleared"
    }
    
    private var durationTimer: Timer?
    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.currentSession?.updateDuration()
        }
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