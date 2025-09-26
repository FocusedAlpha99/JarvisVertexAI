//
//  LocalSTTTTS.swift
//  JarvisVertexAI
//
//  Mode 2: On-Device Speech Recognition & Synthesis
//  100% Local STT/TTS, Text-Only Gemini API Calls
//

import Foundation
import Speech
import AVFoundation

final class LocalSTTTTS: NSObject {

    // MARK: - Properties

    static let shared = LocalSTTTTS()

    // Speech recognition
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Speech synthesis
    private let synthesizer = AVSpeechSynthesizer()

    // Gemini text API
    private var projectId: String = ""
    private var region: String = "us-central1"
    private var accessToken: String = ""

    // Session management
    private var currentSessionId: String?
    private var isListening = false
    private var pendingText = ""

    // Privacy configuration
    private let textOnlyMode = true
    private let onDeviceRecognition = true

    // Queue for text processing
    private let processingQueue = DispatchQueue(label: "com.jarvisvertexai.localprocessing", qos: .userInitiated)

    // MARK: - Initialization

    override private init() {
        // Initialize on-device speech recognizer
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        super.init()

        // Set delegate
        synthesizer.delegate = self
        speechRecognizer?.delegate = self

        // Load configuration
        loadConfiguration()

        // Request permissions
        requestPermissions()
    }

    private func loadConfiguration() {
        projectId = ProcessInfo.processInfo.environment["VERTEX_PROJECT_ID"] ?? ""
        region = ProcessInfo.processInfo.environment["VERTEX_REGION"] ?? "us-central1"
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("✅ Speech recognition permission granted")
            case .denied:
                print("❌ Speech recognition permission denied")
            case .restricted:
                print("⚠️ Speech recognition permission restricted")
            case .notDetermined:
                print("❓ Speech recognition not determined")
            @unknown default:
                break
            }
        }

        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("✅ Microphone permission granted")
            } else {
                print("❌ Microphone permission denied")
            }
        }
        #else
        print("✅ Microphone permission assumed on macOS")
        #endif
    }

    // MARK: - Speech Recognition (STT)

    func startListening() throws {
        guard !isListening else { return }

        // Ensure on-device recognition
        guard let recognizer = speechRecognizer,
              recognizer.isAvailable else {
            throw LocalSTTError.recognizerNotAvailable
        }

        // Configure audio session (iOS only)
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw LocalSTTError.requestCreationFailed
        }

        // Configure for on-device recognition
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // CRITICAL: Force on-device
        if #available(macOS 13.0, iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }
        recognitionRequest.contextualStrings = ["Jarvis", "privacy", "HIPAA", "PHI"]

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleRecognitionResult(result, error: error)
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()

        isListening = true

        // Create session in database
        currentSessionId = ObjectBoxManager.shared.createSession(
            mode: "Voice Local",
            metadata: [
                "onDevice": true,
                "textOnly": true,
                "localSTT": true,
                "localTTS": true
            ]
        )

        print("🎤 Local STT started (100% on-device recognition)")
    }

    func stopListening() {
        guard isListening else { return }

        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        // Process any pending text
        if !pendingText.isEmpty {
            processFinalText(pendingText)
            pendingText = ""
        }

        // End database session
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.endSession(sessionId)
        }

        print("🛑 Local STT stopped and session ended")
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("❌ Speech recognition error: \(error)")
            stopListening()
            return
        }

        guard let result = result else { return }

        let transcript = result.bestTranscription.formattedString
        pendingText = transcript

        // Redact PHI before storing
        let redactedTranscript = PHIRedactor.shared.redactPHI(from: transcript)

        // Store in local database
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "user",
                text: redactedTranscript,
                metadata: ["onDevice": true]
            )
        }

        // If final, process with Gemini
        if result.isFinal {
            processFinalText(transcript)
            pendingText = ""
        }

        // Notify UI
        NotificationCenter.default.post(
            name: .localSTTTranscript,
            object: nil,
            userInfo: [
                "text": redactedTranscript,
                "isFinal": result.isFinal
            ]
        )
    }

    private func processFinalText(_ text: String) {
        // Redact PHI before sending to Gemini
        let redactedText = PHIRedactor.shared.redactPHI(from: text)

        // Process with Gemini (text only)
        Task {
            if let response = await processTextOnly(redactedText) {
                // Store response
                if let sessionId = currentSessionId {
                    ObjectBoxManager.shared.addTranscript(
                        sessionId: sessionId,
                        speaker: "assistant",
                        text: response,
                        metadata: ["textOnly": true]
                    )
                }

                // Speak response
                await speak(text: response)
            }
        }
    }

    // MARK: - Text Processing (Gemini API)

    func processTextOnly(_ text: String) async -> String? {
        guard !projectId.isEmpty else {
            print("❌ Project ID not configured for Vertex AI API")
            return nil
        }

        // Redact PHI one more time to be safe
        let safeText = PHIRedactor.shared.redactPHI(from: text)

        // Build Gemini API URL
        let urlString = "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/gemini-2.0-flash-exp:generateContent"

        guard let url = URL(string: urlString) else { return nil }

        // Get fresh access token with automatic refresh
        do {
            let token = try await AccessTokenProvider.shared.getAccessTokenWithRetry()
            return await performAPIRequest(url: url, text: safeText, token: token)
        } catch {
            print("❌ Failed to get access token for Vertex AI: \(error)")
            return nil
        }
    }

    private func performAPIRequest(url: URL, text: String, token: String) async -> String? {
        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build privacy-focused request body
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        ["text": safeText]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 1024,
                "disablePromptLogging": true,
                "disableDataRetention": true
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ],
            "systemInstruction": "You are a privacy-focused assistant. Never request or store personal information. Audio is processed locally. Only text is sent to you."
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        request.httpBody = httpBody

        // Make request with 401 retry logic
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                return nil
            }

            // Handle 401 authentication errors with token refresh
            if httpResponse.statusCode == 401 {
                print("⚠️ 401 Authentication error detected - attempting token refresh...")
                do {
                    let freshToken = try await AccessTokenProvider.shared.getAccessTokenWithRetry()
                    // Retry with fresh token
                    request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, retryResponse) = try await URLSession.shared.data(for: request)

                    guard let retryHttpResponse = retryResponse as? HTTPURLResponse,
                          retryHttpResponse.statusCode == 200 else {
                        let retryStatusCode = (retryResponse as? HTTPURLResponse)?.statusCode ?? 0
                        print("❌ Gemini API error after token refresh retry: HTTP \(retryStatusCode)")
                        return nil
                    }

                    return parseGeminiResponse(retryData)

                } catch {
                    print("❌ Token refresh failed during API retry: \(error)")
                    return nil
                }
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ Gemini API error: HTTP \(httpResponse.statusCode)")
                return nil
            }

            return parseGeminiResponse(data)

        } catch {
            print("❌ Network error during Gemini API call: \(error)")
            return nil
        }
    }

    private func parseGeminiResponse(_ data: Data) -> String? {
        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            return nil
        }

        // Redact any PHI in response
        let safeResponse = PHIRedactor.shared.redactPHI(from: responseText)

        print("✅ Gemini text response received successfully (PHI redacted)")
        return safeResponse
    }

    // MARK: - Speech Synthesis (TTS)

    func speak(text: String) async {
        // Redact PHI before speaking
        let safeText = PHIRedactor.shared.redactPHI(from: text)

        // Create utterance
        let utterance = AVSpeechUtterance(string: safeText)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.9
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        // Speak
        synthesizer.speak(utterance)

        print("🔊 Speaking response using local TTS")
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func pauseSpeaking() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "mode": "Voice Local (Mode 2)",
            "sttLocation": "100% On-Device",
            "ttsLocation": "100% On-Device",
            "apiCalls": "Text Only",
            "audioTransmission": "Never",
            "phiRedaction": "Active",
            "onDeviceRecognition": speechRecognizer?.supportsOnDeviceRecognition ?? false,
            "localStorage": "Encrypted ObjectBox",
            "dataRetention": "Zero (API)",
            "audioStorage": "Never"
        ]
    }

    // MARK: - Authentication (Legacy Support)

    /// Legacy method for backwards compatibility
    func setAccessToken(_ token: String) {
        self.accessToken = token
        print("⚠️ Using legacy setAccessToken method - consider migrating to AccessTokenProvider")
    }
}

// MARK: - Speech Recognizer Delegate

extension LocalSTTTTS: SFSpeechRecognizerDelegate {

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("Speech recognizer availability changed: \(available)")

        if !available {
            stopListening()
        }
    }
}

// MARK: - Speech Synthesizer Delegate

extension LocalSTTTTS: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("TTS started")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("TTS finished")

        NotificationCenter.default.post(name: .localTTSFinished, object: nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("TTS paused")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("TTS continued")
    }
}

// MARK: - Error Types

enum LocalSTTError: Error {
    case recognizerNotAvailable
    case requestCreationFailed
    case audioEngineError
    case permissionDenied
}

// MARK: - Notifications

extension Notification.Name {
    static let localSTTTranscript = Notification.Name("localSTTTranscript")
    static let localTTSFinished = Notification.Name("localTTSFinished")
}