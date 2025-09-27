import SwiftUI
import Speech
import AVFoundation

// MARK: - Simple Hold-to-Speak Voice Chat
@available(iOS 17.0, *)
struct VoiceChatLocalView: View {
    @StateObject private var speechManager = SimpleSpeechManager()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Status Section
                VStack(spacing: 16) {
                    Text(speechManager.statusMessage)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(speechManager.isListening ? .green : speechManager.isProcessing ? .orange : .primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 32)

                    // Transcript Section
                    if !speechManager.transcript.isEmpty {
                        ScrollView {
                            Text(speechManager.transcript)
                                .font(.body)
                                .lineLimit(nil)
                                .padding(20)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(.systemGray6))
                                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                                )
                        }
                        .frame(maxHeight: min(geometry.size.height * 0.35, 250))
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                }

                Spacer()

                // Button Section
                VStack(spacing: 24) {
                    // Hold-to-Speak Button
                    Button(action: {}) {
                        ZStack {
                            // Background circle
                            Circle()
                                .fill(speechManager.buttonBackgroundColor)
                                .frame(width: speechManager.isListening ? 140 : 120, height: speechManager.isListening ? 140 : 120)
                                .shadow(color: speechManager.buttonColor.opacity(0.3), radius: speechManager.isListening ? 20 : 8, x: 0, y: 4)

                            // Processing pulse ring
                            if speechManager.isProcessing {
                                Circle()
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 3)
                                    .frame(width: 135, height: 135)
                                    .scaleEffect(speechManager.pulseScale)
                                    .opacity(speechManager.pulseOpacity)
                            }

                            // Icon
                            Image(systemName: speechManager.buttonIconName)
                                .font(.system(size: speechManager.isListening ? 50 : 44, weight: .medium))
                                .foregroundColor(speechManager.iconColor)
                        }
                    }
                    .disabled(speechManager.isProcessing)
                    .scaleEffect(speechManager.isListening ? 1.05 : 1.0)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !speechManager.isProcessing {
                                    speechManager.startRecording()
                                }
                            }
                            .onEnded { _ in
                                speechManager.stopRecordingAndProcess()
                            }
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: speechManager.isListening)

                    // Instruction text
                    Text(speechManager.instructionText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, max(geometry.safeAreaInsets.bottom + 32, 48))
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            speechManager.requestPermissions()
        }
    }
}

// MARK: - Simple Speech Manager
@MainActor
class SimpleSpeechManager: NSObject, ObservableObject {

    @Published var isListening = false
    @Published var isProcessing = false
    @Published var transcript = ""
    @Published var statusMessage = "Hold button to speak"
    @Published var pulseScale: CGFloat = 1.0
    @Published var pulseOpacity: Double = 1.0

    var buttonColor: Color {
        if isProcessing { return .orange }
        if isListening { return .red }
        return .blue
    }

    var buttonBackgroundColor: Color {
        if isProcessing { return Color.orange.opacity(0.15) }
        if isListening { return Color.red.opacity(0.15) }
        return Color.blue.opacity(0.15)
    }

    var iconColor: Color {
        if isProcessing { return .orange }
        if isListening { return .red }
        return .blue
    }

    var instructionText: String {
        if isProcessing { return "Processing your request..." }
        if isListening { return "Release to send" }
        return "Hold to speak"
    }

    var buttonIconName: String {
        if isProcessing { return "brain.head.profile" }
        if isListening { return "mic.fill" }
        return "mic.circle.fill"
    }

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let speechSynthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        speechSynthesizer.delegate = self
    }

    // MARK: - Permission Handling
    func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.statusMessage = "Hold button to speak"
                case .denied, .restricted, .notDetermined:
                    self.statusMessage = "Speech permission required"
                @unknown default:
                    self.statusMessage = "Permission error"
                }
            }
        }
    }

    // MARK: - Recording Control
    func startRecording() {
        guard !isListening && !isProcessing else { return }
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            statusMessage = "Speech recognition not available"
            return
        }

        // Setup audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            statusMessage = "Audio setup failed"
            return
        }

        // Clean up previous session
        cleanupRecognition()

        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            statusMessage = "Failed to create request"
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false // Allow network for better accuracy

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let result = result {
                    let newTranscript = result.bestTranscription.formattedString
                    if !newTranscript.isEmpty {
                        self.transcript = newTranscript
                    }
                }

                if let error = error {
                    print("Recognition error: \(error)")
                }
            }
        }

        // Setup audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
            statusMessage = "Recording..."

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } catch {
            statusMessage = "Failed to start recording"
        }
    }

    func stopRecordingAndProcess() {
        guard isListening else { return }

        cleanupRecognition()
        isListening = false

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Process the transcript immediately
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            processWithGemini(trimmed)
        } else {
            statusMessage = "No speech detected - try again"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.statusMessage = "Hold button to speak"
            }
        }
    }

    private func cleanupRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    // MARK: - Gemini API Integration
    private func processWithGemini(_ text: String) {
        isProcessing = true
        statusMessage = "Thinking..."
        startPulseAnimation()

        Task {
            do {
                let response = try await callGeminiAPI(prompt: text)
                await MainActor.run {
                    self.speak(response)
                }
            } catch {
                await MainActor.run {
                    print("Gemini API Error: \(error)")
                    self.statusMessage = "API call failed: \(error.localizedDescription)"
                    self.stopPulseAnimation()
                    self.isProcessing = false

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.statusMessage = "Hold button to speak"
                    }
                }
            }
        }
    }

    private func startPulseAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
            pulseOpacity = 0.3
        }
    }

    private func stopPulseAnimation() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.0
            pulseOpacity = 1.0
        }
    }

    private func callGeminiAPI(prompt: String) async throws -> String {
        // Use the direct Gemini API (not Vertex AI)
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 1024,
                "temperature": 0.7
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            print("Gemini API Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                if let errorString = String(data: data, encoding: .utf8) {
                    print("Gemini API Error Response: \(errorString)")
                }
                throw GeminiError.httpError(httpResponse.statusCode)
            }
        }

        // Parse JSON response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {

            // Log response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Gemini API Response: \(responseString)")
            }
            throw GeminiError.invalidResponse
        }

        return text
    }

    // MARK: - Text to Speech
    private func speak(_ text: String) {
        // Setup audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to set playback audio session")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        speechSynthesizer.speak(utterance)
        statusMessage = "Speaking..."
    }
}

// MARK: - Speech Synthesizer Delegate
extension SimpleSpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.handleSpeechFinished()
        }
    }

    private func handleSpeechFinished() {
        stopPulseAnimation()
        isProcessing = false
        transcript = ""

        // Reset audio session for next recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to reset audio session")
        }

        statusMessage = "Hold button to speak"
    }
}

// MARK: - Error Types
enum GeminiError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "GEMINI_API_KEY environment variable not set"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}

#Preview {
    VoiceChatLocalView()
}