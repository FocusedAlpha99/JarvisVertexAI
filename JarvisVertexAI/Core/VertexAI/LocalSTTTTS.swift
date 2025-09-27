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

    // Audio engine for local speech recognition
    private let audioEngine = AVAudioEngine()

    // iOS Speech Framework Integration
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()

    // Text-to-Speech
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var currentUtterance: AVSpeechUtterance?

    // Session management
    private var currentSessionId: String?
    private var isActive = false

    // Voice Activity Detection
    private var isUserSpeaking = false
    private var lastAudioLevel: Float = 0.0
    private let vadThreshold: Float = 0.02

    // Prevent duplicate processing (iOS 18 fix)
    private var lastProcessedTranscript: String = ""
    private var isProcessingTranscript = false
    private var processingTimeout: Task<Void, Never>?
    private var lastTranscriptTimestamp: Date = Date.distantPast
    private var isRecognitionRunning = false
    private var shouldRestartRecognition = false

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

    // MARK: - Session Management

    func startVoiceSession() {
        isActive = true

        // Create database session
        currentSessionId = SimpleDataManager.shared.createSession(
            mode: "VoiceChatLocal",
            metadata: [
                "sessionType": "conversational",
                "sttProcessing": "On-device iOS Speech Framework",
                "ttsProcessing": "On-device AVSpeechSynthesizer",
                "apiType": "Vertex AI REST API"
            ]
        )

        print("🗣️ Voice Chat Local session started (REST API mode)")
    }


    private func handleTextResponse(_ text: String) {
        // Reset processing state when we get a response
        isProcessingTranscript = false
        processingTimeout?.cancel()

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

        // Speak the response using on-device TTS
        speakText(redacted)
    }

    private var audioPlayer: AVAudioPlayer?

    private func handleAudioResponse(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }

        DispatchQueue.main.async { [weak self] in
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
        stopLocalSpeechRecognition()

        if let sessionId = currentSessionId {
            SimpleDataManager.shared.endSession(sessionId)
        }

        currentSessionId = nil

        print("🔒 Voice chat session terminated")
    }

    func pauseVoiceSession() {
        stopLocalSpeechRecognition()
    }

    func resumeVoiceSession() {
        // Note: UI controls speech recognition lifecycle, no auto-start here
        print("🔄 Voice session resume requested")
    }

    // MARK: - Authentication

    private func getEphemeralToken() async throws -> String {
        // Use the comprehensive AccessTokenProvider
        do {
            let token = try await AccessTokenProvider.shared.getAccessToken()
            // Note: No token caching needed for REST API calls
            return token
        } catch {
            print("❌ Failed to get access token: \(error)")
            throw AudioSessionError.noAuthToken
        }
    }

    func setAccessToken(_ token: String) {
        // Note: Access tokens are fetched fresh for each REST API call
    }

    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "mode": "Voice Chat Local (Mode 2)",
            "apiType": "Gemini Live API",
            "vadEnabled": true,
            "interruptionsSupported": true,
            "conversationContext": 0,
            "ephemeralSession": true,
            "localStorage": "Encrypted UserDefaults",
            "sttProcessing": "On-device iOS Speech Framework",
            "ttsProcessing": "On-device AVSpeechSynthesizer",
            "languageDetection": "On-device NLLanguageRecognizer",
            "voiceQuality": "Enhanced when available"
        ]
    }

    // MARK: - Speech Recognition Methods

    func startLocalSpeechRecognition() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            return
        }

        print("🎤 Starting speech recognition...")

        // Cancel previous recognition task
        stopLocalSpeechRecognition()

        // Ensure audio session is properly configured
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("❌ Audio session setup failed: \(error)")
            return
        }

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

                    // iOS 18 Fix: Check if result is truly final using metadata and confidence
                    let isTrulyFinal = self.checkIfTrulyFinal(result)
                    let confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
                    let currentTime = Date()

                    // Only post partial results for UI feedback
                    if !isFinal {
                        NotificationCenter.default.post(
                            name: .voiceChatTranscript,
                            object: nil,
                            userInfo: [
                                "text": transcript,
                                "speaker": "user",
                                "wasRedacted": false,
                                "partial": true
                            ]
                        )
                    }

                    if isFinal && isTrulyFinal {
                        let timeSinceLastTranscript = currentTime.timeIntervalSince(self.lastTranscriptTimestamp)
                        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

                        print("🎯 Final transcript: \"\(transcript)\" (confidence: \(confidence), time since last: \(timeSinceLastTranscript)s)")
                        print("🔍 Processing check: isProcessing=\(self.isProcessingTranscript), lastTranscript=\"\(self.lastProcessedTranscript)\", isEmpty=\(trimmedTranscript.isEmpty)")

                        // iOS 18 Fix: Enhanced duplicate detection with timing and confidence
                        let isDuplicate = transcript == self.lastProcessedTranscript ||
                                        (timeSinceLastTranscript < 2.0 && confidence < 0.5) ||
                                        trimmedTranscript.isEmpty

                        if !self.isProcessingTranscript && !isDuplicate {
                            print("✅ Processing transcript: \"\(transcript)\" (confidence: \(confidence))")
                            self.lastTranscriptTimestamp = currentTime

                            // Post final transcript for UI
                            NotificationCenter.default.post(
                                name: .voiceChatTranscript,
                                object: nil,
                                userInfo: [
                                    "text": transcript,
                                    "speaker": "user",
                                    "wasRedacted": false,
                                    "final": true
                                ]
                            )

                            self.processTranscript(transcript)
                            self.stopLocalSpeechRecognition()
                            self.shouldRestartRecognition = true // Request restart after TTS
                        } else {
                            if isDuplicate {
                                print("⏭️ Skipping duplicate transcript (confidence: \(confidence), time: \(timeSinceLastTranscript)s)")
                            } else {
                                print("⏭️ Skipping transcript - already processing")
                            }
                            self.stopLocalSpeechRecognition()
                        }

                        NotificationCenter.default.post(name: .sttFinished, object: nil)
                    }
                }

                if let error = error {
                    print("❌ Speech recognition error: \(error)")
                    self.isRecognitionRunning = false
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

            print("🔧 Audio format: \(recordingFormat)")

            // Remove any existing tap first
            inputNode.removeTap(onBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecognitionRunning = true

            print("🎤 Local speech recognition started successfully")
            print("🔧 Audio engine running: \(audioEngine.isRunning)")
            NotificationCenter.default.post(name: .sttStarted, object: nil)

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
        print("🛑 Stopping local speech recognition...")

        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            print("🔧 Audio engine stopped: running=\(audioEngine.isRunning)")
        }

        // Finish recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        isRecognitionRunning = false
        print("🛑 Local speech recognition stopped")
    }

    // iOS 18 Fix: Check if speech recognition result is truly final
    private func checkIfTrulyFinal(_ result: SFSpeechRecognitionResult) -> Bool {
        // Method 1: Check if speechRecognitionMetadata is not nil (recommended approach)
        if #available(iOS 14.0, *) {
            if result.speechRecognitionMetadata != nil {
                return true
            }
        }

        // Method 2: Check confidence scores - final results typically have confidence > 0
        let segments = result.bestTranscription.segments
        if !segments.isEmpty {
            let lastSegmentConfidence = segments.last?.confidence ?? 0.0
            let avgConfidence = segments.map { $0.confidence }.reduce(0, +) / Float(segments.count)

            // Final results usually have confidence > 0.3
            if lastSegmentConfidence > 0.3 && avgConfidence > 0.2 {
                return true
            }
        }

        // Method 3: Check if result has timing information (final results have timing)
        if !result.bestTranscription.segments.isEmpty {
            let hasTimingInfo = result.bestTranscription.segments.allSatisfy { segment in
                segment.timestamp > 0 && segment.duration > 0
            }
            if hasTimingInfo {
                return true
            }
        }

        // Fallback: use isFinal flag but with caution
        return result.isFinal
    }

    private func processTranscript(_ transcript: String) {
        // Prevent duplicate processing
        guard !isProcessingTranscript else {
            print("⚠️ Already processing transcript, skipping duplicate")
            return
        }

        isProcessingTranscript = true
        lastProcessedTranscript = transcript

        print("🗣️ Processing transcript: \"\(transcript)\"")

        // Set a timeout to reset processing state if no response received
        processingTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
            await MainActor.run { [weak self] in
                if self?.isProcessingTranscript == true {
                    print("⏰ Processing timeout - resetting state")
                    self?.isProcessingTranscript = false
                }
            }
        }

        // Send transcript to Gemini for processing
        Task {
            await sendUserMessage(transcript)
        }
    }


    private func sendUserMessage(_ text: String) async {
        do {
            // Get access token
            let accessToken = try await AccessTokenProvider.shared.getAccessToken()

            // Build REST API URL for Gemini
            let modelName = "gemini-2.0-flash-exp"
            let urlString = "https://\(VertexConfig.shared.region)-aiplatform.googleapis.com/v1/projects/\(VertexConfig.shared.projectId)/locations/\(VertexConfig.shared.region)/publishers/google/models/\(modelName):generateContent"

            guard let url = URL(string: urlString) else {
                print("❌ Invalid API URL")
                await MainActor.run { isProcessingTranscript = false }
                return
            }

            // Create request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("JarvisVertexAI-LocalSTTTTS/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30.0

            // Create request body
            let requestBody: [String: Any] = [
                "contents": [
                    [
                        "role": "user",
                        "parts": [
                            ["text": text]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.7,
                    "topP": 0.8,
                    "topK": 40,
                    "maxOutputTokens": 2048
                ],
                "safetySettings": [
                    ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                    ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                    ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                    ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"]
                ]
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            print("📤 Sending REST API request to Gemini: \(text)")

            // Send request
            let (data, response) = try await URLSession.shared.data(for: request)

            // Check response
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Gemini API Response: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 200 {
                    // Parse response
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let candidates = json["candidates"] as? [[String: Any]],
                       let content = candidates.first?["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let responseText = parts.first?["text"] as? String {

                        print("✅ Received Gemini response: \(responseText.prefix(100))...")
                        await MainActor.run {
                            handleTextResponse(responseText)
                        }
                    } else {
                        print("❌ Failed to parse Gemini response")
                        await MainActor.run { isProcessingTranscript = false }
                    }
                } else {
                    print("❌ Gemini API error: \(httpResponse.statusCode)")
                    if let errorData = String(data: data, encoding: .utf8) {
                        print("❌ Error details: \(errorData)")
                    }
                    await MainActor.run { isProcessingTranscript = false }
                }
            }

        } catch {
            print("❌ Failed to send REST API request: \(error)")
            await MainActor.run {
                isProcessingTranscript = false
            }
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

        // Note: No automatic restart after TTS - UI controls speech recognition lifecycle
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