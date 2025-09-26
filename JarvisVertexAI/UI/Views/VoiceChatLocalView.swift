import SwiftUI
import Speech
import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Mode 2: Voice Chat Local UI
@available(iOS 17.0, macOS 12.0, *)
struct VoiceChatLocalView: View {
    @StateObject private var viewModel = VoiceChatLocalViewModel()
    @State private var isListening = false
    @State private var showTranscript = false
    @State private var showSettings = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            #if os(iOS)
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            #else
            Color(.controlBackgroundColor)
                .ignoresSafeArea()
            #endif
            
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
                        #if os(iOS)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        #else
                        .fill(Color(.controlBackgroundColor))
                        #endif
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
            if #available(macOS 13.0, *) {
                VoiceSettingsView(viewModel: viewModel)
            } else {
                Text("Settings not available")
            }
        }
        .alert("Voice Chat Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") {
                viewModel.showErrorAlert = false
            }
            Button("Settings") {
                #if os(iOS)
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
                #endif
            }
        } message: {
            Text(viewModel.errorMessage)
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
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(isListening ? .success : .warning)
        #endif
    }
}

// MARK: - Message Bubble
@available(iOS 17.0, macOS 11.0, *)
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
                            #if os(iOS)
                            .fill(message.isUser ? Color.blue : Color(uiColor: .systemGray5))
                            #else
                            .fill(message.isUser ? Color.blue : Color(.controlBackgroundColor))
                            #endif
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
@available(iOS 17.0, macOS 11.0, *)
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
@available(iOS 17.0, macOS 11.0, *)
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
@available(iOS 17.0, macOS 12.0, *)
class VoiceChatLocalViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentTranscription = ""
    @Published var sttActive = false
    @Published var ttsActive = false
    @Published var isProcessing = false
    @Published var animationScale: CGFloat = 1.0
    
    private let dbManager = SimpleDataManager.shared
    private let phiRedactor = PHIRedactor.shared
    private var cancellables = Set<AnyCancellable>()

    @Published var errorMessage = ""
    @Published var showErrorAlert = false
    @Published var permissionStatus: PermissionStatus = .notDetermined
    
    init() {
        loadRecentMessages()
        setupNotifications()
    }
    
    private func setupNotifications() {
        // Listen to Gemini Live API responses
        NotificationCenter.default.publisher(for: .voiceChatTranscript)
            .sink { notification in
                if let userInfo = notification.userInfo,
                   let text = userInfo["text"] as? String,
                   let speaker = userInfo["speaker"] as? String {

                    let message = ChatMessage(
                        id: UUID().uuidString,
                        content: text,
                        isUser: speaker == "user",
                        timestamp: Date(),
                        wasRedacted: false
                    )

                    DispatchQueue.main.async {
                        self.messages.append(message)

                        if !message.isUser {
                            self.isProcessing = false
                            self.ttsActive = true
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Listen to audio level updates
        NotificationCenter.default.publisher(for: .voiceChatAudioLevel)
            .sink { notification in
                if let userInfo = notification.userInfo,
                   let speaking = userInfo["speaking"] as? Bool {
                    DispatchQueue.main.async {
                        self.sttActive = speaking
                        if speaking {
                            self.isProcessing = true
                        }
                    }
                }
            }
            .store(in: &cancellables)

        // Listen to audio responses
        NotificationCenter.default.publisher(for: .voiceChatAudioResponse)
            .sink { _ in
                DispatchQueue.main.async {
                    self.ttsActive = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadRecentMessages() {
        // Load recent messages from ObjectBox
        if let sessions = try? dbManager.getRecentSessions(mode: "voiceChatLocal", limit: 1),
           let lastSession = sessions.first,
           let transcripts = try? dbManager.getTranscripts(sessionId: lastSession.sessionId) {
            
            messages = transcripts.map { transcript in
                ChatMessage(
                    id: UUID().uuidString,
                    content: transcript.text,
                    isUser: transcript.speaker == "user",
                    timestamp: transcript.timestamp,
                    wasRedacted: transcript.metadata["redacted"] == "true"
                )
            }
        }
    }
    
    func requestPermissions() {
        Task {
            // Request speech recognition permission
            SFSpeechRecognizer.requestAuthorization { authStatus in
                print("Speech recognition permission: \\(authStatus)")

                // Request microphone permission
                #if os(iOS)
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    print("Microphone permission: \\(granted)")
                }
                #endif
            }
        }
    }
    
    func startListening() {
        Task {
            do {
                // Check permissions first
                try await checkPermissions()

                // Use Local Speech Recognition for STT
                LocalSTTTTS.shared.startLocalSpeechRecognition()

                DispatchQueue.main.async {
                    self.sttActive = true
                    self.animationScale = 1.5
                }

                print("🎤 Voice Chat Local: STT started")

            } catch {
                DispatchQueue.main.async {
                    self.handleError(error)
                }
                print("Voice Chat Local Error: \(error)")
            }
        }
    }

    private func checkPermissions() async throws {
        // Check microphone permission
        #if os(iOS)
        let microphoneStatus = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        if !microphoneStatus {
            throw VoiceChatError.microphonePermissionDenied
        }
        #endif

        // Check speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        if !speechStatus {
            throw VoiceChatError.speechRecognitionPermissionDenied
        }
    }
    
    func stopListening() {
        LocalSTTTTS.shared.stopLocalSpeechRecognition()

        DispatchQueue.main.async {
            self.sttActive = false
            self.animationScale = 1.0
        }
    }
    
    
    
    func clearConversation() {
        messages.removeAll()
        currentTranscription = ""

        // Terminate current session
        LocalSTTTTS.shared.terminateVoiceSession()
    }
    
    func exportTranscript() {
        let transcript = messages.map { msg in
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return "\(msg.isUser ? "User" : "Assistant") [\(formatter.string(from: msg.timestamp))]: \(msg.content)"
        }.joined(separator: "\n\n")

        // Create export with privacy notice
        let exportText = """
        VOICE CHAT LOCAL TRANSCRIPT
        Generated: \({
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: Date())
        }())
        Privacy: On-device STT/TTS, PHI redacted
        ---

        \(transcript)
        """
        
        // Share via activity controller
        #if os(iOS)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityVC = UIActivityViewController(activityItems: [exportText], applicationActivities: [])
            window.rootViewController?.present(activityVC, animated: true)
        }
        #else
        // macOS: Print or save to file
        print("Export: \(exportText)")
        #endif
    }

    // MARK: - Error Handling

    func handleError(_ error: Error) {
        DispatchQueue.main.async {
            self.sttActive = false
            self.ttsActive = false
            self.isProcessing = false
            self.animationScale = 1.0

            if let voiceChatError = error as? VoiceChatError {
                self.errorMessage = voiceChatError.localizedDescription
            } else {
                self.errorMessage = error.localizedDescription
            }

            self.showErrorAlert = true
            print("❌ Voice Chat Error: \(self.errorMessage)")
        }
    }

    private func updatePermissionStatus() {
        Task {
            let micStatus = await checkMicrophonePermission()
            let speechStatus = await checkSpeechRecognitionPermission()

            await MainActor.run {
                if micStatus && speechStatus {
                    self.permissionStatus = .authorized
                } else {
                    self.permissionStatus = .denied
                }
            }
        }
    }

    private func checkMicrophonePermission() async -> Bool {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied, .undetermined:
            return await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
        #else
        return true // macOS handles permissions differently
        #endif
    }

    private func checkSpeechRecognitionPermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

// MARK: - Voice Chat Errors

enum VoiceChatError: LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case audioEngineError(Error)
    case networkError(Error)
    case configurationError(String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission is required for voice chat. Please enable it in Settings > Privacy & Security > Microphone."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission is required. Please enable it in Settings > Privacy & Security > Speech Recognition."
        case .speechRecognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .audioEngineError(let error):
            return "Audio engine error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted

    var displayText: String {
        switch self {
        case .notDetermined:
            return "Checking..."
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        }
    }

    var color: Color {
        switch self {
        case .notDetermined:
            return .orange
        case .authorized:
            return .green
        case .denied, .restricted:
            return .red
        }
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
@available(iOS 17.0, macOS 12.0, *)
struct TranscriptView: View {
    let messages: [ChatMessage]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        TranscriptMessageRow(message: message)
                    }
                }
                .padding()
            }
            .navigationTitle("Transcript")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }
}

// MARK: - Transcript Message Row
@available(iOS 17.0, macOS 11.0, *)
struct TranscriptMessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.isUser ? "User" : "Assistant")
                    .font(.caption)
                    .fontWeight(.semibold)

                if message.wasRedacted {
                    if #available(macOS 11.0, iOS 14.0, *) {
                        Label("Redacted", systemImage: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        Text("Redacted")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                if #available(macOS 12.0, iOS 15.0, *) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text({
                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        return formatter.string(from: message.timestamp)
                    }())
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Text(message.content)
                .font(.body)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(iOS)
                .fill(Color(uiColor: .secondarySystemBackground))
                #else
                .fill(Color(.controlBackgroundColor))
                #endif
        )
    }
}

// MARK: - Voice Settings View
@available(iOS 17.0, macOS 13.0, *)
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
                        Text("Speed: \(voiceSpeed, specifier: "%.1f")x")
                        Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.1)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Pitch: \(voicePitch, specifier: "%.1f")")
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
}