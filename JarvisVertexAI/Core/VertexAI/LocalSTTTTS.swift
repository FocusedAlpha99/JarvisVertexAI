//
//  LocalSTTTTS.swift
//  JarvisVertexAI
//
//  Mode 2: Gemini Live API with Voice Activity Detection
//  Real-time streaming with interruption support and conversation management
//

import Foundation
import Speech
import AVFoundation
import NaturalLanguage

final class LocalSTTTTS: NSObject {

    // MARK: - Properties

    static let shared = LocalSTTTTS()

    // Live API WebSocket connection
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.jarvisvertexai.liveapi", qos: .userInteractive)

    // iOS Speech Framework Integration
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()

    // Text-to-Speech
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var currentUtterance: AVSpeechUtterance?

    // Ephemeral token authentication
    private var ephemeralToken: String = ""
    private var tokenExpiryTime: Date?

    // Session management with conversation context
    private var currentSessionId: String?
    private var isActive = false
    private var conversationHistory: [[String: Any]] = []

    // Voice Activity Detection
    private var isUserSpeaking = false
    private var lastAudioLevel: Float = 0.0
    private let vadThreshold: Float = 0.02

    // Audio configuration
    private let sampleRate: Double = 24000
    private let channelCount: Int = 1

    // Live API configuration with Voice Activity Detection
    private let liveApiConfig: [String: Any] = [
        "model": "gemini-2.0-flash-exp",
        "generationConfig": [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": "Charon"  // Different voice for this mode
                    ]
                ]
            ]
        ],
        "systemInstruction": [
            "parts": [
                [
                    "text": "You are a conversational AI assistant. Engage naturally and allow for interruptions. Keep responses concise and interactive."
                ]
            ]
        ],
        "tools": []  // Function calling can be added here
    ]

    // MARK: - Initialization

    override private init() {
        super.init()
        setupAudioSession()
        setupSpeechRecognition()
        setupTextToSpeech()
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            print("✅ Audio session configured for conversational mode")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
        #endif
    }

    private func setupSpeechRecognition() {
        // Initialize speech recognizer with best available locale
        let preferredLocale = Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: preferredLocale)

        // Fallback to English if current locale isn't supported
        if speechRecognizer == nil || speechRecognizer?.isAvailable == false {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }

        speechRecognizer?.delegate = self
        speechRecognizer?.supportsOnDeviceRecognition = true // Force on-device when possible

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Speech recognition authorized")
                    // Check on-device support
                    if let recognizer = self?.speechRecognizer {
                        print("📱 On-device recognition supported: \(recognizer.supportsOnDeviceRecognition)")
                    }
                case .denied:
                    print("❌ Speech recognition denied")
                case .notDetermined:
                    print("⚠️ Speech recognition not determined")
                case .restricted:
                    print("⚠️ Speech recognition restricted")
                @unknown default:
                    print("⚠️ Unknown speech recognition status")
                }
            }
        }
    }

    private func setupTextToSpeech() {
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer?.delegate = self

        // Configure for mixed speech (allows both audio playback and speech synthesis)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
            )
        } catch {
            print("⚠️ Could not configure audio session for mixed speech: \(error)")
        }

        print("✅ Text-to-Speech synthesizer initialized with enhanced audio mixing")
    }

    // MARK: - Connection Management

    func connect() async throws {
        // Validate VertexConfig
        guard VertexConfig.shared.isConfigured else {
            print("❌ VertexConfig not properly configured")
            throw AudioSessionError.connectionFailed
        }

        print("🔗 Connecting LocalSTTTTS to Vertex AI...")
        print("📊 Project: \(VertexConfig.shared.projectId), Region: \(VertexConfig.shared.region)")

        // Get ephemeral token
        ephemeralToken = try await getEphemeralToken()

        // Build WebSocket URL
        let wsURL = buildWebSocketURL()

        // Configure URL session with privacy settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.httpAdditionalHeaders = [
            "User-Agent": "JarvisVertexAI-LocalSTTTTS/1.0 (Privacy-Focused)",
            "X-Privacy-Mode": "strict",
            "Cache-Control": "no-cache, no-store"
        ]

        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)

        // Create WebSocket connection
        let request = URLRequest(url: wsURL)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        receiveMessages()

        isActive = true

        // Create database session
        currentSessionId = SimpleDataManager.shared.createSession(
            mode: "VoiceChatLocal",
            metadata: [
                "sessionType": "conversational",
                "vadEnabled": true,
                "liveApi": true,
                "interruptionsSupported": true,
                "vertexAI": true
            ]
        )

        print("🗣️ Voice Chat Local session connected with VAD to Vertex AI")
    }

    private func buildWebSocketURL() -> URL {
        // Vertex AI Live API WebSocket endpoint (proper format)
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(VertexConfig.shared.region)-aiplatform.googleapis.com"
        components.path = "/ws/v1/projects/\(VertexConfig.shared.projectId)/locations/\(VertexConfig.shared.region)/publishers/google/models/gemini-2.0-flash-exp:streamGenerateContent"

        // Add authentication and privacy parameters
        components.queryItems = [
            URLQueryItem(name: "access_token", value: ephemeralToken),
            URLQueryItem(name: "alt", value: "websocket"),
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "quotaUser", value: UUID().uuidString),
            URLQueryItem(name: "fields", value: "candidates,modelVersion,usageMetadata")
        ]

        guard let url = components.url else {
            fatalError("Failed to build WebSocket URL for project: \(VertexConfig.shared.projectId), region: \(VertexConfig.shared.region)")
        }

        print("🌐 LocalSTTTTS WebSocket URL: \(url.absoluteString)")
        return url
    }

    private func sendConfiguration() async throws {
        // Vertex AI Live API setup message with proper format
        let setupMessage: [String: Any] = [
            "setup": [
                "model": "models/gemini-2.0-flash-exp",
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": "Charon"
                            ]
                        ]
                    ],
                    "candidate_count": 1,
                    "max_output_tokens": 2048,
                    "temperature": 0.7,
                    "top_p": 0.8,
                    "top_k": 40
                ],
                "system_instruction": [
                    "parts": [
                        [
                            "text": "You are a conversational AI assistant. Engage naturally and allow for interruptions. Keep responses concise and interactive."
                        ]
                    ]
                ],
                "safety_settings": [
                    [
                        "category": "HARM_CATEGORY_HARASSMENT",
                        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                    ],
                    [
                        "category": "HARM_CATEGORY_HATE_SPEECH",
                        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                    ],
                    [
                        "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                    ],
                    [
                        "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                        "threshold": "BLOCK_MEDIUM_AND_ABOVE"
                    ]
                ],
                "tools": []
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: setupMessage)
        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask?.send(message)

        print("✅ Vertex AI Live API configuration sent")
        if let setupString = String(data: data, encoding: .utf8) {
            print("📋 LocalSTTTTS Setup: \(setupString)")
        } else {
            print("📋 LocalSTTTTS Setup: [binary data]")
        }
    }

    // MARK: - Audio Streaming with VAD

    func startListening() {
        guard isActive else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap with Voice Activity Detection
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBufferWithVAD(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("🎤 Voice chat listening started with VAD")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBufferWithVAD(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        // Calculate audio level for Voice Activity Detection
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        lastAudioLevel = rms

        // Voice Activity Detection
        let wasUserSpeaking = isUserSpeaking
        isUserSpeaking = rms > vadThreshold

        // User started speaking - interrupt model if it's responding
        if !wasUserSpeaking && isUserSpeaking {
            Task {
                await sendInterrupt()
            }
        }

        // Only send audio when user is speaking
        if isUserSpeaking {
            // Convert to PCM data
            let channelDataArray = stride(from: 0, to: frameLength, by: 1).map {
                channelDataValue[$0]
            }

            let int16Data = channelDataArray.map { Int16($0 * 32767) }
            let data = int16Data.withUnsafeBufferPointer { Data(buffer: $0) }

            // Send audio data
            Task {
                await sendAudioData(data)
            }
        }

        // Notify UI about audio level
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .voiceChatAudioLevel,
                object: nil,
                userInfo: ["level": rms, "speaking": self.isUserSpeaking]
            )
        }
    }

    private func sendAudioData(_ data: Data) async {
        let audioMessage: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm",
                        "data": data.base64EncodedString()
                    ]
                ]
            ]
        ]

        if let messageData = try? JSONSerialization.data(withJSONObject: audioMessage) {
            let message = URLSessionWebSocketTask.Message.data(messageData)
            try? await webSocketTask?.send(message)
        }
    }

    private func sendInterrupt() async {
        let interruptMessage: [String: Any] = [
            "clientContent": [
                "turnComplete": true
            ]
        ]

        if let messageData = try? JSONSerialization.data(withJSONObject: interruptMessage) {
            let message = URLSessionWebSocketTask.Message.data(messageData)
            try? await webSocketTask?.send(message)
            print("⚡ User interruption sent")
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isUserSpeaking = false
        print("🛑 Voice chat listening stopped")
    }

    // MARK: - Message Reception

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessages() // Continue receiving
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")

                // Check if error might be authentication-related
                let errorDescription = error.localizedDescription.lowercased()
                if errorDescription.contains("401") || errorDescription.contains("unauthorized") ||
                   errorDescription.contains("403") || errorDescription.contains("forbidden") {
                    print("⚠️ Detected authentication error in WebSocket failure")
                    Task {
                        await self?.handleAuthenticationError()
                    }
                } else {
                    self?.handleDisconnection()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleDataMessage(data)
        case .string(let text):
            handleTextMessage(text)
        @unknown default:
            break
        }
    }

    private func handleDataMessage(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let serverContent = json["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Handle model responses with conversation context
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            for part in parts {
                // Handle text responses
                if let text = part["text"] as? String {
                    handleTextResponse(text)
                }

                // Handle audio responses
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   let data = inlineData["data"] as? String,
                   mimeType.contains("audio") {
                    handleAudioResponse(data)
                }
            }

            // Add to conversation history for context
            conversationHistory.append(modelTurn)
        }

        // Handle interruptions
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            print("🔄 Model response interrupted by user")
        }
    }

    private func handleTextMessage(_ text: String) {
        handleTextResponse(text)
    }

    private func handleTextResponse(_ text: String) {
        let redacted = PHIRedactor.shared.redactPHI(from: text)

        if let sessionId = currentSessionId {
            SimpleDataManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "assistant",
                text: redacted,
                metadata: ["liveApi": true, "mode": "voiceChat"]
            )
        }

        NotificationCenter.default.post(
            name: .voiceChatTranscript,
            object: nil,
            userInfo: ["text": redacted, "speaker": "assistant"]
        )
    }

    private var audioPlayer: AVAudioPlayer?

    private func handleAudioResponse(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }

        audioQueue.async { [weak self] in
            do {
                self?.audioPlayer = try AVAudioPlayer(data: audioData)
                self?.audioPlayer?.play()
                print("🔊 Playing voice chat response")
            } catch {
                print("❌ Audio playback error: \(error)")
            }
        }

        NotificationCenter.default.post(
            name: .voiceChatAudioResponse,
            object: nil,
            userInfo: ["audioData": audioData, "speaker": "assistant"]
        )
    }

    // MARK: - Session Management

    func terminateVoiceSession() {
        isActive = false
        stopListening()
        webSocketTask?.cancel(with: .goingAway, reason: nil)

        if let sessionId = currentSessionId {
            SimpleDataManager.shared.endSession(sessionId)
        }

        conversationHistory.removeAll()
        currentSessionId = nil
        ephemeralToken = ""

        print("🔒 Voice chat session terminated")
    }

    func pauseVoiceSession() {
        stopListening()
    }

    func resumeVoiceSession() {
        if isActive {
            startListening()
        }
    }

    // MARK: - Authentication

    private func getEphemeralToken() async throws -> String {
        // Use the comprehensive AccessTokenProvider
        do {
            let token = try await AccessTokenProvider.shared.getAccessToken()
            tokenExpiryTime = Date().addingTimeInterval(15 * 60)
            return token
        } catch {
            print("❌ Failed to get access token: \(error)")
            throw AudioSessionError.noAuthToken
        }
    }

    func setAccessToken(_ token: String) {
        ephemeralToken = token
    }

    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "mode": "Voice Chat Local (Mode 2)",
            "apiType": "Gemini Live API",
            "vadEnabled": true,
            "interruptionsSupported": true,
            "conversationContext": conversationHistory.count,
            "ephemeralSession": true,
            "localStorage": "Encrypted UserDefaults",
            "sttProcessing": "On-device iOS Speech Framework",
            "ttsProcessing": "On-device AVSpeechSynthesizer",
            "languageDetection": "On-device NLLanguageRecognizer",
            "voiceQuality": "Enhanced when available"
        ]
    }
}

// MARK: - URLSessionWebSocketDelegate

extension LocalSTTTTS: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                   webSocketTask: URLSessionWebSocketTask,
                   didOpenWithProtocol protocol: String?) {
        print("✅ Voice Chat WebSocket connected")

        Task {
            try await sendConfiguration()
            await MainActor.run {
                startListening()
            }
        }

        NotificationCenter.default.post(name: .voiceChatConnected, object: nil)
    }

    func urlSession(_ session: URLSession,
                   webSocketTask: URLSessionWebSocketTask,
                   didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            print("❌ WebSocket connection failed: \(error)")

            // Check for HTTP status code errors in the underlying error
            if let httpResponse = nsError.userInfo["NSHTTPURLResponseKey"] as? HTTPURLResponse {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    print("⚠️ HTTP authentication error (\(httpResponse.statusCode)) detected")
                    Task {
                        await handleAuthenticationError()
                    }
                    return
                }
            }

            // Check error description for auth-related keywords
            let errorDescription = error.localizedDescription.lowercased()
            if errorDescription.contains("401") || errorDescription.contains("unauthorized") ||
               errorDescription.contains("403") || errorDescription.contains("forbidden") {
                print("⚠️ Authentication error detected in connection failure")
                Task {
                    await handleAuthenticationError()
                }
                return
            }

            handleDisconnection()
        }
    }

    func urlSession(_ session: URLSession,
                   webSocketTask: URLSessionWebSocketTask,
                   didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                   reason: Data?) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown"
        print("🔌 Voice Chat WebSocket closed: \(closeCode) - \(reasonString)")

        // Check for authentication-related closures (401/403 usually map to policy violations)
        let isAuthError = closeCode == .policyViolation &&
                         (reasonString.contains("401") || reasonString.contains("403") || reasonString.contains("Unauthorized"))

        if isAuthError {
            print("⚠️ Authentication error detected in WebSocket closure")
            Task {
                await handleAuthenticationError()
            }
            return
        }

        // Handle different close codes
        switch closeCode {
        case .normalClosure:
            print("✅ WebSocket closed normally")
        case .goingAway:
            print("⏳ Server going away")
        case .protocolError:
            print("❌ WebSocket protocol error")
        case .unsupportedData:
            print("❌ Unsupported data type")
        case .noStatusReceived:
            print("❌ No status received")
        case .abnormalClosure:
            print("❌ Abnormal WebSocket closure")
        case .invalidFramePayloadData:
            print("❌ Invalid frame payload data")
        case .policyViolation:
            print("❌ Policy violation (may be auth-related)")
        case .messageTooBig:
            print("❌ Message too big")
        case .internalServerError:
            print("❌ Internal server error")
        case .invalid:
            print("❌ Invalid close code")
        case .mandatoryExtensionMissing:
            print("❌ Mandatory extension missing")
        case .tlsHandshakeFailure:
            print("❌ TLS handshake failure")
        @unknown default:
            print("❌ Unknown close code: \(closeCode)")
        }

        handleDisconnection()
    }

    private func handleDisconnection() {
        terminateVoiceSession()
        NotificationCenter.default.post(name: .voiceChatDisconnected, object: nil)
    }

    private func handleAuthenticationError() async {
        print("⚠️ Authentication error detected, refreshing token...")

        do {
            // Force refresh the token
            let newToken = try await AccessTokenProvider.shared.getAccessTokenWithRetry()
            ephemeralToken = newToken
            tokenExpiryTime = Date().addingTimeInterval(15 * 60)

            print("✅ Token refreshed successfully, reconnecting...")

            // Reconnect with new token
            if isActive {
                await reconnectWithNewToken()
            }
        } catch {
            print("❌ Failed to refresh token: \(error)")
            terminateVoiceSession()
            NotificationCenter.default.post(
                name: .voiceChatError,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    private func reconnectWithNewToken() async {
        // Terminate current session
        webSocketTask?.cancel()
        webSocketTask = nil

        // Small delay before reconnecting
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Reconnect
        do {
            try await connect()
            print("✅ Successfully reconnected with refreshed token")
        } catch {
            print("❌ Failed to reconnect: \(error)")
            handleDisconnection()
        }
    }

    // MARK: - Speech Recognition Methods

    func startLocalSpeechRecognition() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            return
        }

        // Cancel previous recognition task
        stopLocalSpeechRecognition()

        do {
            // Create recognition request with on-device preference
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                print("❌ Failed to create recognition request")
                return
            }

            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = true // Force on-device processing
            recognitionRequest.taskHint = .dictation // Optimize for conversation

            // Enhanced quality settings for better accuracy
            if #available(iOS 16.0, *) {
                recognitionRequest.addsPunctuation = true
            }

            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }

                if let result = result {
                    let transcript = result.bestTranscription.formattedString
                    let isFinal = result.isFinal

                    // Post STT transcript notification
                    NotificationCenter.default.post(
                        name: .voiceChatTranscript,
                        object: nil,
                        userInfo: [
                            "text": transcript,
                            "speaker": "user",
                            "wasRedacted": false
                        ]
                    )

                    if isFinal {
                        self.processTranscript(transcript)
                        NotificationCenter.default.post(name: .sttFinished, object: nil)
                    }
                }

                if let error = error {
                    print("❌ Speech recognition error: \(error)")
                    NotificationCenter.default.post(
                        name: .voiceChatError,
                        object: nil,
                        userInfo: ["error": error]
                    )
                    self.stopLocalSpeechRecognition()
                }
            }

            // Start recording
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            NotificationCenter.default.post(name: .sttStarted, object: nil)
            print("🎤 Local speech recognition started")

        } catch {
            print("❌ Failed to start speech recognition: \(error)")
            NotificationCenter.default.post(
                name: .voiceChatError,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    func stopLocalSpeechRecognition() {
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Finish recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        print("🛑 Local speech recognition stopped")
    }

    private func processTranscript(_ transcript: String) {
        // Send transcript to Gemini for processing
        Task {
            do {
                // This would integrate with your multimodal chat or text API
                // For now, we'll simulate a response
                await simulateGeminiResponse(for: transcript)
            } catch {
                print("❌ Failed to process transcript: \(error)")
            }
        }
    }

    private func simulateGeminiResponse(for transcript: String) async {
        // Call the real Vertex AI API through WebSocket
        await sendUserMessage(transcript)
    }

    private func sendUserMessage(_ text: String) async {
        guard let webSocketTask = webSocketTask else {
            print("❌ WebSocket not connected")
            return
        }

        let userMessage: [String: Any] = [
            "client_content": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "text": text
                            ]
                        ]
                    ]
                ],
                "turn_complete": true
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: userMessage) else {
            print("❌ Failed to serialize message")
            return
        }

        let message = URLSessionWebSocketTask.Message.data(data)
        do {
            try await webSocketTask.send(message)
            print("📤 Sent message to Vertex AI: \(text)")
        } catch {
            print("❌ Failed to send WebSocket message: \(error)")
        }
    }

    // MARK: - Text-to-Speech Methods

    func speakText(_ text: String, language: String = "en-US", rate: Float = 0.5, pitch: Float = 1.0) {
        guard let speechSynthesizer = speechSynthesizer else {
            print("❌ Speech synthesizer not available")
            return
        }

        // Stop current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        // Create utterance
        currentUtterance = AVSpeechUtterance(string: text)
        guard let utterance = currentUtterance else { return }

        // Select best available voice for language
        let bestVoice = selectBestVoice(for: language)
        utterance.voice = bestVoice

        // Enhanced natural speech parameters
        utterance.rate = normalizeRate(rate)
        utterance.pitchMultiplier = pitch
        utterance.volume = 1.0

        // Add natural pauses for better speech flow
        if #available(iOS 16.0, *) {
            utterance.prefersAssistiveTechnologySettings = false
        }

        // Pre-utterance delay for smoother transitions
        utterance.preUtteranceDelay = 0.1

        // Store transcript for session history
        if let sessionId = currentSessionId {
            SimpleDataManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "assistant_tts",
                text: text,
                metadata: [
                    "voice": bestVoice?.name ?? "system",
                    "language": language,
                    "rate": String(rate),
                    "pitch": String(pitch)
                ]
            )
        }

        // Speak
        speechSynthesizer.speak(utterance)
        NotificationCenter.default.post(name: .ttsStarted, object: nil)

        print("🔊 Speaking: \(text.prefix(50))... [Voice: \(bestVoice?.name ?? "system")]")
    }

    private func selectBestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()

        // First, try to find enhanced quality voices for the language
        let enhancedVoices = availableVoices.filter { voice in
            voice.language.hasPrefix(String(language.prefix(2))) &&
            voice.quality == .enhanced
        }

        if let bestEnhanced = enhancedVoices.first {
            return bestEnhanced
        }

        // Fallback to any voice for the language
        let languageVoices = availableVoices.filter { voice in
            voice.language.hasPrefix(String(language.prefix(2)))
        }

        if let firstLanguageVoice = languageVoices.first {
            return firstLanguageVoice
        }

        // Final fallback to system default
        return AVSpeechSynthesisVoice(language: language)
    }

    private func normalizeRate(_ rate: Float) -> Float {
        // Convert rate to more natural speech pattern
        // iOS speech rates: 0.0 (very slow) to 1.0 (very fast)
        // Our input: 0.0 to 1.0, but we want to map to a more natural range
        let minRate: Float = 0.4  // Minimum comfortable rate
        let maxRate: Float = 0.7  // Maximum comfortable rate
        return minRate + (rate * (maxRate - minRate))
    }

    func stopSpeaking() {
        speechSynthesizer?.stopSpeaking(at: .immediate)
        currentUtterance = nil
    }

    func pauseSpeaking() {
        speechSynthesizer?.pauseSpeaking(at: .word)
    }

    func continueSpeaking() {
        speechSynthesizer?.continueSpeaking()
    }

    // MARK: - Intelligent Speech Methods

    func speakIntelligently(_ text: String) {
        // Automatically detect best language and apply natural settings
        let detectedLanguage = detectLanguage(from: text) ?? "en-US"
        let naturalRate: Float = 0.6 // Slightly faster than default for conversation
        let naturalPitch: Float = 1.0

        speakText(text, language: detectedLanguage, rate: naturalRate, pitch: naturalPitch)
    }

    private func detectLanguage(from text: String) -> String? {
        // Simple language detection based on character patterns
        // This is basic - in production you might use NLLanguageRecognizer

        if #available(iOS 12.0, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)

            if let dominantLanguage = recognizer.dominantLanguage {
                // Map NLLanguage to AVSpeechSynthesizer locale format
                return mapNLLanguageToSpeechLocale(dominantLanguage)
            }
        }

        // Fallback to simple heuristics using character sets
        let spanishCharacters = CharacterSet(charactersIn: "áéíóúñü")
        let frenchCharacters = CharacterSet(charactersIn: "àâäéèêëîïôöùûüÿç")
        let germanCharacters = CharacterSet(charactersIn: "äöüß")

        if text.rangeOfCharacter(from: spanishCharacters) != nil {
            return "es-ES" // Spanish
        } else if text.rangeOfCharacter(from: frenchCharacters) != nil {
            return "fr-FR" // French
        } else if text.rangeOfCharacter(from: germanCharacters) != nil {
            return "de-DE" // German
        }

        return "en-US" // Default to English
    }

    @available(iOS 12.0, *)
    private func mapNLLanguageToSpeechLocale(_ language: NLLanguage) -> String {
        switch language {
        case .english:
            return "en-US"
        case .spanish:
            return "es-ES"
        case .french:
            return "fr-FR"
        case .german:
            return "de-DE"
        case .italian:
            return "it-IT"
        case .portuguese:
            return "pt-BR"
        case .russian:
            return "ru-RU"
        case .japanese:
            return "ja-JP"
        case .korean:
            return "ko-KR"
        case .simplifiedChinese:
            return "zh-CN"
        case .traditionalChinese:
            return "zh-TW"
        case .dutch:
            return "nl-NL"
        default:
            return "en-US"
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension LocalSTTTTS: SFSpeechRecognizerDelegate {

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("Speech recognizer availability changed: \(available)")

        if !available {
            stopLocalSpeechRecognition()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension LocalSTTTTS: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🔊 TTS started speaking")
        NotificationCenter.default.post(name: .ttsStarted, object: nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("🔇 TTS finished speaking")
        currentUtterance = nil
        NotificationCenter.default.post(name: .ttsFinished, object: nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("⏸️ TTS paused")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("▶️ TTS resumed")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("❌ TTS cancelled")
        currentUtterance = nil
        NotificationCenter.default.post(name: .ttsFinished, object: nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let voiceChatTranscript = Notification.Name("voiceChatTranscript")
    static let voiceChatAudioResponse = Notification.Name("voiceChatAudioResponse")
    static let voiceChatAudioLevel = Notification.Name("voiceChatAudioLevel")
    static let voiceChatConnected = Notification.Name("voiceChatConnected")
    static let voiceChatDisconnected = Notification.Name("voiceChatDisconnected")
    static let voiceChatError = Notification.Name("voiceChatError")
    static let sttStarted = Notification.Name("sttStarted")
    static let sttFinished = Notification.Name("sttFinished")
    static let ttsStarted = Notification.Name("ttsStarted")
    static let ttsFinished = Notification.Name("ttsFinished")
}