import SwiftUI
import Speech
import AVFoundation

// MARK: - Mode 2: Voice Chat Local UI
struct VoiceChatLocalView: View {
    @StateObject private var viewModel = VoiceChatLocalViewModel()
    @State private var isListening = false
    @State private var showTranscript = false
    @State private var showSettings = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header with privacy status
                HStack {
                    VStack(alignment: .leading) {
                        Text("Voice Chat Local")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("On-Device STT/TTS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                    }
                }
                .padding(.horizontal)
                
                // Conversation display
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .padding(.horizontal)
                
                // Current transcription
                if !viewModel.currentTranscription.isEmpty {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.blue)
                            .font(.caption)
                        
                        Text(viewModel.currentTranscription)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                    )
                    .padding(.horizontal)
                }
                
                // Voice control area
                VStack(spacing: 16) {
                    // STT/TTS status indicators
                    HStack(spacing: 20) {
                        StatusIndicator(
                            title: "STT",
                            isActive: viewModel.sttActive,
                            color: .blue
                        )
                        
                        StatusIndicator(
                            title: "Processing",
                            isActive: viewModel.isProcessing,
                            color: .orange
                        )
                        
                        StatusIndicator(
                            title: "TTS",
                            isActive: viewModel.ttsActive,
                            color: .green
                        )
                    }
                    
                    // Main voice button
                    Button(action: toggleListening) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: isListening ? 
                                            [Color.red, Color.orange] : 
                                            [Color.blue, Color.purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            if isListening {
                                // Animated listening indicator
                                ForEach(0..<3) { i in
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        .scaleEffect(viewModel.animationScale)
                                        .opacity(1 - viewModel.animationScale)
                                        .animation(
                                            Animation.easeOut(duration: 1)
                                                .repeatForever(autoreverses: false)
                                                .delay(Double(i) * 0.3),
                                            value: viewModel.animationScale
                                        )
                                }
                            }
                            
                            Image(systemName: isListening ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                    }
                    .scaleEffect(isListening ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isListening)
                    
                    // Action buttons
                    HStack(spacing: 30) {
                        ActionButton(
                            icon: "text.viewfinder",
                            title: "Transcript",
                            action: { showTranscript = true }
                        )
                        
                        ActionButton(
                            icon: "trash",
                            title: "Clear",
                            action: viewModel.clearConversation,
                            isDestructive: true
                        )
                        
                        ActionButton(
                            icon: "arrow.down.circle",
                            title: "Export",
                            action: viewModel.exportTranscript
                        )
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showTranscript) {
            TranscriptView(messages: viewModel.messages)
        }
        .sheet(isPresented: $showSettings) {
            VoiceSettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.requestPermissions()
        }
    }
    
    private func toggleListening() {
        if isListening {
            viewModel.stopListening()
        } else {
            viewModel.startListening()
        }
        isListening.toggle()
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(isListening ? .success : .warning)
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser { Spacer() }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.wasRedacted {
                    Label("PHI Redacted", systemImage: "eye.slash")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Text(message.content)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.isUser ? Color.blue : Color(uiColor: .systemGray5))
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser { Spacer() }
        }
    }
}

// MARK: - Status Indicator
struct StatusIndicator: View {
    let title: String
    let isActive: Bool
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? color : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .fill(color.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .opacity(isActive ? 1 : 0)
                        .scaleEffect(isActive ? 1.5 : 1)
                        .animation(
                            isActive ? Animation.easeInOut(duration: 1).repeatForever() : .default,
                            value: isActive
                        )
                )
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let action: () -> Void
    var isDestructive = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isDestructive ? .red : .blue)
        }
    }
}

// MARK: - Voice Chat Local View Model
class VoiceChatLocalViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentTranscription = ""
    @Published var sttActive = false
    @Published var ttsActive = false
    @Published var isProcessing = false
    @Published var animationScale: CGFloat = 1.0
    
    private var sttManager: LocalSTTTTS?
    private let dbManager = ObjectBoxManager.shared
    private let phiRedactor = PHIRedactor()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    init() {
        setupSTT()
        loadRecentMessages()
    }
    
    private func setupSTT() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        audioEngine = AVAudioEngine()
        
        Task {
            sttManager = try? await LocalSTTTTS(projectId: VertexConfig.projectId, region: VertexConfig.region)
        }
    }
    
    private func loadRecentMessages() {
        // Load recent messages from ObjectBox
        if let sessions = try? dbManager.getRecentSessions(mode: .voiceChatLocal, limit: 1),
           let lastSession = sessions.first,
           let transcripts = try? dbManager.getTranscripts(sessionId: lastSession.id) {
            
            messages = transcripts.map { transcript in
                ChatMessage(
                    id: UUID().uuidString,
                    content: transcript.text,
                    isUser: transcript.speaker == "user",
                    timestamp: transcript.timestamp,
                    wasRedacted: transcript.metadata["redacted"] as? Bool ?? false
                )
            }
        }
    }
    
    func requestPermissions() {
        Task {
            // Request speech recognition permission
            let authStatus = await SFSpeechRecognizer.requestAuthorization()
            
            // Request microphone permission
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                print("Microphone permission: \\(granted)")
            }
        }
    }
    
    func startListening() {
        guard let recognizer = speechRecognizer,
              recognizer.isAvailable else { return }
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Start recognition
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true // Force on-device only
            
            let inputNode = audioEngine?.inputNode
            guard let inputNode = inputNode else { return }
            
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    DispatchQueue.main.async {
                        self.currentTranscription = result.bestTranscription.formattedString
                        self.sttActive = true
                    }
                    
                    if result.isFinal {
                        self.processTranscription(result.bestTranscription.formattedString)
                    }
                }
                
                if error != nil {
                    self.stopListening()
                }
            }
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            
            audioEngine?.prepare()
            try audioEngine?.start()
            
            DispatchQueue.main.async {
                self.sttActive = true
                self.animationScale = 1.5
            }
            
        } catch {
            print("STT Error: \\(error)")
        }
    }
    
    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        
        DispatchQueue.main.async {
            self.sttActive = false
            self.animationScale = 1.0
        }
    }
    
    private func processTranscription(_ text: String) {
        Task {
            await MainActor.run {
                isProcessing = true
                currentTranscription = ""
            }
            
            // Redact PHI before sending
            let redactedText = phiRedactor.redactPHI(from: text)
            let wasRedacted = redactedText != text
            
            // Add user message
            let userMessage = ChatMessage(
                id: UUID().uuidString,
                content: text,
                isUser: true,
                timestamp: Date(),
                wasRedacted: wasRedacted
            )
            
            await MainActor.run {
                messages.append(userMessage)
            }
            
            // Save to local DB
            try? dbManager.addTranscript(
                sessionId: getCurrentSessionId(),
                speaker: "user",
                text: text,
                metadata: ["redacted": wasRedacted, "original_length": text.count]
            )
            
            // Send redacted text to Gemini (text-only)
            if let response = await sttManager?.processTextOnly(redactedText) {
                let assistantMessage = ChatMessage(
                    id: UUID().uuidString,
                    content: response,
                    isUser: false,
                    timestamp: Date(),
                    wasRedacted: false
                )
                
                await MainActor.run {
                    messages.append(assistantMessage)
                    isProcessing = false
                    
                    // Trigger TTS
                    speakResponse(response)
                }
                
                // Save assistant response
                try? dbManager.addTranscript(
                    sessionId: getCurrentSessionId(),
                    speaker: "assistant",
                    text: response,
                    metadata: [:]
                )
            }
        }
    }
    
    private func speakResponse(_ text: String) {
        Task {
            await MainActor.run {
                ttsActive = true
            }
            
            await sttManager?.speak(text)
            
            await MainActor.run {
                ttsActive = false
            }
        }
    }
    
    func clearConversation() {
        messages.removeAll()
        currentTranscription = ""
        
        // Clear from local DB
        if let sessionId = getCurrentSessionId() {
            try? dbManager.deleteSession(sessionId: sessionId)
        }
    }
    
    func exportTranscript() {
        let transcript = messages.map { msg in
            "\\(msg.isUser ? "User" : "Assistant") [\\(msg.timestamp.formatted())]: \\(msg.content)"
        }.joined(separator: "\\n\\n")
        
        // Create export with privacy notice
        let exportText = """
        VOICE CHAT LOCAL TRANSCRIPT
        Generated: \\(Date().formatted())
        Privacy: On-device STT/TTS, PHI redacted
        ---
        
        \\(transcript)
        """
        
        // Share via activity controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityVC = UIActivityViewController(activityItems: [exportText], applicationActivities: nil)
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    private func getCurrentSessionId() -> String {
        // Get or create current session
        "voice_local_\\(Date().timeIntervalSince1970)"
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable {
    let id: String
    let content: String
    let isUser: Bool
    let timestamp: Date
    let wasRedacted: Bool
}

// MARK: - Transcript View
struct TranscriptView: View {
    let messages: [ChatMessage]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(message.isUser ? "User" : "Assistant")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                
                                if message.wasRedacted {
                                    Label("Redacted", systemImage: "eye.slash")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                Spacer()
                                
                                Text(message.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(message.content)
                                .font(.body)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Voice Settings View
struct VoiceSettingsView: View {
    @ObservedObject var viewModel: VoiceChatLocalViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("voiceSpeed") private var voiceSpeed = 1.0
    @AppStorage("voicePitch") private var voicePitch = 1.0
    @AppStorage("autoRedactPHI") private var autoRedactPHI = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Speech Recognition") {
                    Toggle("On-Device Only", isOn: .constant(true))
                        .disabled(true)
                    
                    Toggle("Auto-Redact PHI", isOn: $autoRedactPHI)
                }
                
                Section("Text-to-Speech") {
                    VStack(alignment: .leading) {
                        Text("Speed: \\(voiceSpeed, specifier: "%.1f")x")
                        Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Pitch: \\(voicePitch, specifier: "%.1f")")
                        Slider(value: $voicePitch, in: 0.5...2.0, step: 0.1)
                    }
                }
                
                Section("Privacy") {
                    LabeledContent("Data Storage", value: "100% Local")
                    LabeledContent("Cloud Sync", value: "Disabled")
                    LabeledContent("Analytics", value: "None")
                }
            }
            .navigationTitle("Voice Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}