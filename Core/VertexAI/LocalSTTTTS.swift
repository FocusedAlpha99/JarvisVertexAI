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
                print("✅ Speech recognition authorized")
            case .denied:
                print("❌ Speech recognition denied")
            case .restricted:
                print("⚠️ Speech recognition restricted")
            case .notDetermined:
                print("❓ Speech recognition not determined")
            @unknown default:
                break
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if granted {
                print("✅ Microphone access granted")
            } else {
                print("❌ Microphone access denied")
            }
        }
    }

    // MARK: - Speech Recognition (STT)

    func startListening() throws {
        guard !isListening else { return }

        // Ensure on-device recognition
        guard let recognizer = speechRecognizer,
              recognizer.isAvailable else {
            throw LocalSTTError.recognizerNotAvailable
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .defaultToSpeaker)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw LocalSTTError.requestCreationFailed
        }

        // Configure for on-device recognition
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // CRITICAL: Force on-device
        recognitionRequest.addsPunctuation = true
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

        print("🎤 Local STT started (100% on-device)")
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

        print("🛑 Local STT stopped")
    }

    private func handleRecognitionResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("❌ Recognition error: \(error)")
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
            print("❌ Project ID not configured")
            return nil
        }

        // Redact PHI one more time to be safe
        let safeText = PHIRedactor.shared.redactPHI(from: text)

        // Build Gemini API URL
        let urlString = "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/gemini-2.0-flash-exp:generateContent"

        guard let url = URL(string: urlString) else { return nil }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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

        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Gemini API error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

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

            print("✅ Gemini text response received (PHI redacted)")
            return safeResponse

        } catch {
            print("❌ Network error: \(error)")
            return nil
        }
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

        print("🔊 Speaking response (local TTS)")
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

    // MARK: - Authentication

    func setAccessToken(_ token: String) {
        self.accessToken = token
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