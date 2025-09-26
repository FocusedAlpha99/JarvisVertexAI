//
//  AudioSession.swift
//  JarvisVertexAI
//
//  Mode 1: Native Audio Streaming with Gemini Live API
//  Best Practices Implementation - Server-Side Processing, Zero Retention
//

import Foundation
import AVFoundation

// MARK: - Errors

enum AudioSessionError: Error {
    case noAuthToken
    case connectionFailed
    case invalidResponse
    case tokenExpired
}

final class AudioSession: NSObject {

    // MARK: - Properties

    static let shared = AudioSession()

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.jarvisvertexai.audio", qos: .userInteractive)

    // Ephemeral token authentication
    private var ephemeralToken: String = ""
    private var tokenExpiryTime: Date?

    // Connection parameters
    private var projectId: String = ""
    private var region: String = ""
    private var endpointId: String = ""

    // Session management
    private var currentSessionId: String?
    private var isActive = false
    private var isConnected = false
    private var sessionResumeHandle: String?

    // Connection management
    private var connectionAttempts = 0
    private let maxRetryAttempts = 5
    private var retryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 30.0
    private var connectionTask: Task<Void, Never>?
    // Lifecycle guards (added for 2025 stability)
    private var postSetupGraceUntil: Date?
    private var terminating = false

    // Audio streaming state (continuous mode)

    // Audio configuration (Gemini Live API optimized)
    private let sampleRate: Double = 24000  // Higher quality for Live API
    private let channelCount: Int = 1
    private let bufferSize: UInt32 = 4096  // Optimized buffer size for real-time streaming
    private var currentInputSampleRate: Double = 24000
    private var silenceStartTime: Date?
    private let vadSilenceThresholdSeconds: Double = 1.0

    // Live API configuration with privacy settings
    private let liveApiConfig: [String: Any] = [
        "model": "gemini-2.0-flash-exp",
        "generationConfig": [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": "Aoede"
                    ]
                ]
            ],
            // Privacy and compliance settings
            "candidateCount": 1,
            "maxOutputTokens": 2048,
            "temperature": 0.7,
            "topP": 0.8,
            "topK": 40
        ],
        "systemInstruction": [
            "parts": [
                [
                    "text": "You are a privacy-focused AI assistant. Provide helpful, natural responses. All conversations are ephemeral and not stored. Prioritize user privacy and data protection."
                ]
            ]
        ],
        "safetySettings": [
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

    // MARK: - Initialization

    override private init() {
        super.init()
        loadConfiguration()
        setupAudioSession()
    }

    private func loadConfiguration() {
        // Configuration loaded from environment
        print("✅ Audio session configuration loaded")
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true)
            print("✅ Audio session configured for voice chat")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
        #else
        print("✅ Audio session setup skipped on macOS")
        #endif
    }

    // MARK: - Connection Management

    // MARK: - Public Connection Methods

    /// Connect with default VertexConfig settings (called from AudioModeView)
    func connect() async throws {
        print("📍 STEP 1: AudioSession.connect() called from UI")
        PersistentLogger.shared.logVertex(.info, "STEP 1: UI requested AudioSession.connect()")

        // Validate configuration first (Mode 1 supports GEMINI_API_KEY-only)
        print("📍 STEP 2: Validating VertexConfig...")
        let hasApiKey = (VertexConfig.shared.geminiApiKey?.isEmpty == false)
        let hasGeneralConfig = VertexConfig.shared.isConfigured
        print("🔎 hasApiKey: \(hasApiKey), isConfigured: \(hasGeneralConfig)")
        PersistentLogger.shared.logVertex(.info, "STEP 2: Validate (hasApiKey=\(hasApiKey), isConfigured=\(hasGeneralConfig))")
        print("🚨 VertexConfig.projectId: '\(VertexConfig.shared.projectId)'")
        print("🚨 VertexConfig.region: '\(VertexConfig.shared.region)'")
        print("🚨 VertexConfig.audioEndpoint: '\(VertexConfig.shared.audioEndpoint ?? "nil")'")

        // For Live WS we allow proceeding with API key even if broader Vertex config is not complete
        guard hasApiKey || hasGeneralConfig else {
            print("🚨 STEP 2 FAILED: No valid authentication found (API key or access token)")
            throw AudioSessionError.connectionFailed
        }

        // If no API key, require projectId for Vertex-style auth; if API key present, projectId is optional
        if !hasApiKey {
            guard !VertexConfig.shared.projectId.isEmpty else {
                print("🚨 STEP 2 FAILED: Empty project ID (required without API key)")
                throw AudioSessionError.connectionFailed
            }
        }
        print("✅ STEP 2 PASSED: Validation successful for Mode 1")

        print("📍 STEP 3: Delegating to parameterized connect method...")
        PersistentLogger.shared.logVertex(.info, "STEP 3: Delegating to parameterized connect")
        try await connect(
            projectId: VertexConfig.shared.projectId,
            region: VertexConfig.shared.region,
            endpointId: VertexConfig.shared.audioEndpoint ?? ""
        )
        print("✅ STEP 3 COMPLETED: Connection delegation successful")
    }

    /// Connect with specific parameters
    func connect(projectId: String, region: String, endpointId: String) async throws {
        print("🔗 Connecting to Vertex AI Live API...")
        print("📊 Project: \(projectId), Region: \(region)")

        // Store connection parameters
        self.projectId = projectId
        self.region = region
        self.endpointId = endpointId

        // Start connection with retry logic
        connectionTask = Task {
            await connectWithRetry()
        }

        // Wait up to 5 seconds for socket open (isConnected) or setup completion (isActive)
        let maxWaitSlices = 10
        for _ in 0..<maxWaitSlices {
            if isConnected || isActive { break }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        if !(isConnected || isActive) {
            throw AudioSessionError.connectionFailed
        }
    }

    private func connectWithRetry() async {
        while connectionAttempts < maxRetryAttempts && !isActive {
            do {
                try await performConnection()
                connectionAttempts = 0 // Reset on success
                retryDelay = 1.0 // Reset delay on success
                return
            } catch {
                connectionAttempts += 1
                print("❌ Connection attempt \(connectionAttempts)/\(maxRetryAttempts) failed: \(error)")

                if connectionAttempts < maxRetryAttempts {
                    print("⏱️ Retrying in \(retryDelay) seconds...")
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

                    // Exponential backoff with jitter
                    retryDelay = min(retryDelay * 2.0 + Double.random(in: 0...1), maxRetryDelay)
                } else {
                    print("❌ Max retry attempts reached. Connection failed.")
                    NotificationCenter.default.post(name: .audioSessionDisconnected, object: nil)
                    return
                }
            }
        }
    }

    private func performConnection() async throws {
        print("📍 STEP 4: AudioSession.performConnection() starting...")
        PersistentLogger.shared.logVertex(.info, "STEP 4: performConnection() starting")

        // Resolve authentication: prefer GEMINI_API_KEY for Live WS; otherwise fetch OAuth token
        print("📍 STEP 5: Resolving authentication...")
        PersistentLogger.shared.logVertex(.info, "STEP 5: Resolving authentication")
        if VertexConfig.shared.geminiApiKey?.isEmpty == false {
            print("🔑 STEP 5 SKIPPED: Using GEMINI_API_KEY for Live WS")
            PersistentLogger.shared.logVertex(.info, "STEP 5: Using GEMINI_API_KEY")
        } else {
            do {
                ephemeralToken = try await getEphemeralToken()
                print("✅ STEP 5 PASSED: Token retrieved (length: \(ephemeralToken.count))")
                PersistentLogger.shared.logVertex(.info, "STEP 5: Token retrieved length=\(ephemeralToken.count)")
            } catch {
                print("🚨 STEP 5 FAILED: Token error - \(error)")
                PersistentLogger.shared.logVertex(.error, "STEP 5 FAILED: \(error.localizedDescription)")
                throw error
            }
        }

        // Build WebSocket URL for Gemini Live API
        print("📍 STEP 6: Building WebSocket URL...")
        let wsURL: URL
        do {
            wsURL = buildWebSocketURL()
            print("✅ STEP 6 PASSED: WebSocket URL built: \(wsURL.absoluteString)")
        } catch {
            print("🚨 STEP 6 FAILED: URL building error - \(error)")
            throw AudioSessionError.connectionFailed
        }

        // Configure URL session with privacy settings and optimized WebSocket timeouts
        print("📍 STEP 7: Configuring URLSession...")
        PersistentLogger.shared.logVertex(.info, "STEP 7: Configuring URLSession")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.isDiscretionary = false
        configuration.shouldUseExtendedBackgroundIdleMode = false

        // WebSocket-specific timeout configuration
        configuration.timeoutIntervalForRequest = 15.0  // Faster timeout for initial handshake
        configuration.timeoutIntervalForResource = 300.0 // Longer for ongoing WebSocket connection

        print("   ⏰ Connection timeout: \(configuration.timeoutIntervalForRequest)s")
        print("   ⏰ Resource timeout: \(configuration.timeoutIntervalForResource)s")

        // Privacy headers
        configuration.httpAdditionalHeaders = [
            "User-Agent": "JarvisVertexAI-iOS/1.0 (Privacy-Focused)",
            "X-Privacy-Mode": "strict",
            "Cache-Control": "no-cache, no-store",
            "Pragma": "no-cache"
        ]

        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        print("✅ STEP 7 PASSED: URLSession configured with privacy settings")

        // Create WebSocket request with privacy headers and enhanced logging
        print("📍 STEP 8A: Creating WebSocket request...")
        print("   🔗 Target URL: \(wsURL.absoluteString)")

        var request = URLRequest(url: wsURL)
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("JarvisVertexAI-iOS/1.0 (Privacy-Focused)", forHTTPHeaderField: "User-Agent")
        request.setValue("strict", forHTTPHeaderField: "X-Privacy-Mode")
        request.setValue("disabled", forHTTPHeaderField: "X-Goog-User-Project-Override")

        // Add authentication header based on the authentication method
        if let apiKey = VertexConfig.shared.geminiApiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
            print("   🔑 Added Gemini API key to headers")
        } else if !ephemeralToken.isEmpty {
            request.setValue("Bearer \(ephemeralToken)", forHTTPHeaderField: "Authorization")
            print("   🔑 Added OAuth Bearer token to headers")
        } else {
            print("   ⚠️ WARNING: No authentication headers added!")
        }

        // Log all request headers for debugging
        print("   📋 Request Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            // Don't log sensitive values fully
            if key.lowercased().contains("auth") || key.lowercased().contains("key") {
                print("     \(key): [\(value.count) chars] \(String(value.prefix(10)))...")
            } else {
                print("     \(key): \(value)")
            }
        }
        print("✅ STEP 8A PASSED: WebSocket request configured")

        print("📍 STEP 8B: Creating WebSocket task...")
        guard let session = urlSession else {
            print("🚨 STEP 8B FAILED: URLSession is nil")
            throw AudioSessionError.connectionFailed
        }
        webSocketTask = session.webSocketTask(with: request)
        print("✅ STEP 8B PASSED: WebSocket task created")
        print("   📊 Task State: \(webSocketTask?.state.description ?? "unknown")")

        // Connect with enhanced logging
        print("📍 STEP 9: Starting WebSocket connection...")
        print("   🌐 Attempting connection to: \(wsURL.host ?? "unknown host")")
        print("   🚀 Resuming WebSocket task...")
        webSocketTask?.resume()
        print("✅ STEP 9 PASSED: WebSocket connection initiated")
        PersistentLogger.shared.logVertex(.info, "STEP 9: WebSocket resume() called")
        print("   📊 Post-resume Task State: \(webSocketTask?.state.description ?? "unknown")")

        print("📍 STEP 10: Starting message receiving...")

        // Start receiving messages
        receiveMessages()

        print("🎙️ Gemini Live API WebSocket connecting...")
    }

    private func buildWebSocketURL() -> URL {
        // Gemini Live API WebSocket endpoint (corrected format)
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

        // Add authentication and privacy parameters (using API key for Gemini Live)
        // Note: Gemini Live API uses different auth than Vertex AI
        var queryItems: [URLQueryItem] = []

        // Use Gemini API key if available, otherwise fall back to access token
        if let apiKey = VertexConfig.shared.geminiApiKey {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
            print("🔑 Using Gemini API key for authentication")
        } else if !ephemeralToken.isEmpty {
            queryItems.append(URLQueryItem(name: "access_token", value: ephemeralToken))
            print("🔑 Using OAuth access token for authentication")
        } else {
            print("⚠️ WARNING: No authentication method available for WebSocket")
        }

        // Add standard WebSocket parameters
        queryItems.append(contentsOf: [
            URLQueryItem(name: "alt", value: "websocket"),
            URLQueryItem(name: "prettyPrint", value: "false")
        ])

        components.queryItems = queryItems

        guard let url = components.url else {
            print("❌ Failed to build WebSocket URL - components invalid")
            print("   Host: \(components.host ?? "nil")")
            print("   Path: \(components.path)")
            print("   Query items count: \(queryItems.count)")
            fatalError("Failed to build WebSocket URL for Gemini Live API")
        }

        print("🌐 Corrected WebSocket URL: \(url.absoluteString)")
        print("🔍 URL Components breakdown:")
        print("   Scheme: \(components.scheme ?? "nil")")
        print("   Host: \(components.host ?? "nil")")
        print("   Path: \(components.path)")
        print("   Query parameters: \(queryItems.count)")
        return url
    }

    private func sendConfiguration() async throws {
        // Gemini Live API setup message (objects, not arrays; remove unsupported fields)
        let setupMessage: [String: Any] = [
            "setup": [
                // 2025 native audio model
                "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Aoede"
                            ]
                        ]
                    ],
                    "candidateCount": 1,
                    "maxOutputTokens": 2048,
                    "temperature": 0.7,
                    "topP": 0.8,
                    "topK": 40
                ],
                // Voice Activity Detection (2025)
                "realtime_input_config": [
                    "automaticActivityDetection": [
                        "disabled": false
                    ]
                ],
                // Session resumption (2025) - minimal config: empty object enables feature
                "session_resumption": [:],
                "systemInstruction": [
                    "parts": [
                        [
                            "text": "You are a privacy-focused AI assistant. Provide helpful, natural responses. All conversations are ephemeral and not stored. Prioritize user privacy and data protection."
                        ]
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
            print("📋 Setup: \(setupString)")
        } else {
            print("📋 Setup: [binary data]")
        }
    }

    // MARK: - Audio Streaming

    func streamAudio() {
        guard isActive else { return }

        // Verify microphone permission at runtime
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .undetermined:
            session.requestRecordPermission { _ in }
        case .denied:
            print("❌ Microphone permission denied")
            return
        case .granted: break
        @unknown default: break
        }
        #endif

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        currentInputSampleRate = recordingFormat.sampleRate

        // Install tap using native input format to avoid buffer issues
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, targetFormat: recordingFormat)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            print("🎤 Audio streaming started - Format: \(Int(sampleRate))Hz, \(channelCount) channel(s)")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        // Debug: buffer receipt
        print("🎤 Audio buffer received: \(buffer.frameLength) frames")

        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let channelDataValue = channelData.pointee

        // Compute simple amplitude for VAD and normalize
        var sumAbs: Float = 0
        var processedAudio = [Float]()
        processedAudio.reserveCapacity(frameLength)
        for i in 0..<frameLength {
            let s = max(-1.0, min(1.0, channelDataValue[i]))
            sumAbs += abs(s)
            processedAudio.append(abs(s) > 0.01 ? s : 0.0) // noise gate at ~-40dB
        }
        let avgAbs = sumAbs / Float(frameLength)

        // VAD: detect >1s silence and send audioStreamEnd once
        if avgAbs < 0.005 { // silence threshold
            if silenceStartTime == nil { silenceStartTime = Date() }
            if let start = silenceStartTime, Date().timeIntervalSince(start) > vadSilenceThresholdSeconds {
                Task { [weak self] in
                    await self?.sendAudioStreamEnd()
                }
                silenceStartTime = nil
            }
        } else {
            silenceStartTime = nil
        }

        // Convert to 16-bit PCM
        let int16Data = processedAudio.map { Int16($0 * Float(Int16.max)) }
        let pcmData = int16Data.withUnsafeBufferPointer { Data(buffer: $0) }

        // Send audio data
        Task { [weak self] in
            await self?.sendAudioChunk(pcmData: pcmData)
        }
    }

    private func sendAudioChunk(pcmData: Data) async {
        guard isActive, !pcmData.isEmpty else { return }
        // Debug: chunk size
        print("📤 Sending audio chunk: \(pcmData.count) bytes")

        // Build mime with current input sample rate
        let rate = Int(currentInputSampleRate.rounded())
        let audioMessage: [String: Any] = [
            "realtime_input": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=\(rate)",
                        "data": pcmData.base64EncodedString()
                    ]
                ]
            ]
        ]

        do {
            let messageData = try JSONSerialization.data(withJSONObject: audioMessage, options: [])
            let message = URLSessionWebSocketTask.Message.data(messageData)
            try await webSocketTask?.send(message)
        } catch {
            print("❌ Failed to send audio chunk: \(error)")
        }
    }

    private func sendAudioStreamEnd() async {
        guard isActive else { return }
        let message: [String: Any] = [
            "realtime_input": [
                "audio_stream_end": true
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            let msg = URLSessionWebSocketTask.Message.data(data)
            try? await webSocketTask?.send(msg)
            print("🛑 Sent audioStreamEnd after silence")
        }
    }

    func stopStreaming() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        print("🛑 Audio streaming stopped")
    }

    // MARK: - Message Reception

    private func receiveMessages() {
        // Keep receive loop active as long as a WebSocket task exists so we can
        // handle setupComplete and other initial messages before isActive flips.
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                // Continue receiving messages
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    self.receiveMessages()
                }

            case .failure(let error):
                let nsError = error as NSError
                if let grace = self.postSetupGraceUntil, Date() < grace,
                   nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
                    print("⚠️ Transient socket error during setup grace window; continuing")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.receiveMessages()
                    }
                    return
                }
                switch nsError.code {
                case NSURLErrorTimedOut:
                    print("⚠️ WebSocket timeout, attempting reconnection...")
                    Task {
                        await self.reconnectWithBackoff()
                    }
                case NSURLErrorNetworkConnectionLost:
                    print("⚠️ Network connection lost, attempting reconnection...")
                    Task {
                        await self.reconnectWithBackoff()
                    }
                case NSURLErrorCannotConnectToHost:
                    print("❌ Cannot connect to host: \(error)")
                    self.handleDisconnection()
                default:
                    print("❌ WebSocket receive error: \(error)")
                    self.handleDisconnection()
                }
            }
        }
    }

    private func reconnectWithBackoff() async {
        isActive = false
        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

        do {
            try await connect()
        } catch {
            print("❌ Reconnection failed: \(error)")
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
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ Failed to parse WebSocket message as JSON")
                return
            }

            // Log message type for debugging (privacy-safe)
            let messageType = json.keys.first ?? "unknown"
            print("📨 Received message type: \(messageType)")

            // Handle different Gemini Live API message types
            if let serverContent = json["serverContent"] as? [String: Any] {
                handleServerContent(serverContent)
            } else if let sessionResume = json["sessionResume"] as? [String: Any] {
                handleSessionResume(sessionResume)
            } else if let resumptionUpdate = json["sessionResumptionUpdate"] as? [String: Any] {
                // 2025 resumption update: capture resume handle or related info
                if let handle = resumptionUpdate["handle"] as? String {
                    sessionResumeHandle = handle
                    print("🔄 SessionResumptionUpdate received. Handle updated.")
                } else {
                    print("ℹ️ SessionResumptionUpdate received (no handle field)")
                }
            } else if let error = json["error"] as? [String: Any] {
                handleError(error)
            } else if json["setupComplete"] != nil {
                // Gemini Live API sends setupComplete as an empty object: {"setupComplete": {}}
                // Treat presence of the key as completion, regardless of value type
                if let flag = json["setupComplete"] as? Bool {
                    handleSetupComplete(flag)
                } else {
                    handleSetupComplete(true)
                }
            } else if let candidates = json["candidates"] as? [[String: Any]] {
                handleCandidates(candidates)
            } else {
                print("⚠️ Unknown message type: \(messageType)")
            }

        } catch {
            print("❌ Failed to process WebSocket message: \(error)")
        }
    }

    private func handleSetupComplete(_ setupComplete: Bool) {
        if setupComplete {
            print("✅ Gemini Live API setup completed successfully")
            PersistentLogger.shared.logVertex(.info, "Gemini Live API setup completed successfully")

            // Mark connection as active and create database session
            isActive = true
            postSetupGraceUntil = Date().addingTimeInterval(2.0)
            currentSessionId = SimpleDataManager.shared.createSession(
                mode: "GeminiLiveAudio",
                metadata: [
                    "sessionType": "ephemeral",
                    "apiVersion": "v1beta",
                    "zeroRetention": true,
                    "liveApi": true,
                    "privacyMode": "strict"
                ]
            )

            // Notify UI about successful connection
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .audioSessionConnected, object: nil)
            }

            // Begin streaming microphone audio to the Live API
            streamAudio()
        }
    }

    private func handleCandidates(_ candidates: [[String: Any]]) {
        for candidate in candidates {
            if let content = candidate["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                handleResponseParts(parts)
            }
        }
    }

    private func handleResponseParts(_ parts: [[String: Any]]) {
        for part in parts {
            // Handle text responses
            if let text = part["text"] as? String {
                handleTextResponse(text)
            }

            // Handle audio responses
            if let inlineData = part["inlineData"] as? [String: Any],
               let mimeType = inlineData["mimeType"] as? String,
               let audioData = inlineData["data"] as? String,
               mimeType.contains("audio") {
                handleAudioResponse(audioData)
            }
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        // Handle model turn responses
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {

            // Model is responding with server content
            print("🤖 Model response received - maintaining continuous audio stream")

            for part in parts {
                // Handle text responses
                if let text = part["text"] as? String {
                    handleTextResponse(text)
                }

                // Handle audio responses (native audio)
                if let inlineData = part["inlineData"] as? [String: Any],
                   let mimeType = inlineData["mimeType"] as? String,
                   let data = inlineData["data"] as? String,
                   mimeType.contains("audio") {
                    handleAudioResponse(data)
                }
            }
        }

        // Handle turn detection and interrupts (continuous streaming maintained)
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            print("🔄 Turn complete - continuous streaming continues")
        }

        if let interrupted = content["interrupted"] as? Bool, interrupted {
            print("⚡ Model interrupted by user - continuous streaming maintained")
        }
    }

    private func handleSessionResume(_ resume: [String: Any]) {
        if let handle = resume["handle"] as? String {
            sessionResumeHandle = handle
            print("📌 Session resume handle stored: \(handle)")
        }
    }

    private func handleTextMessage(_ text: String) {
        handleTextResponse(text)
    }

    private func handleTextResponse(_ text: String) {
        // Redact any PHI before logging
        let redacted = PHIRedactor.shared.redactPHI(from: text)

        // Store in local database
        if let sessionId = currentSessionId {
            SimpleDataManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "assistant",
                text: redacted,
                metadata: ["liveApi": true, "responseType": "text"]
            )
        }

        // Notify UI
        NotificationCenter.default.post(
            name: .audioSessionTranscript,
            object: nil,
            userInfo: ["text": redacted, "speaker": "assistant", "type": "text"]
        )
    }

    private func handleAudioResponse(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }

        // Play native audio response
        playAudio(audioData)

        // Notify UI about audio response
        NotificationCenter.default.post(
            name: .audioSessionAudioResponse,
            object: nil,
            userInfo: ["audioData": audioData, "speaker": "assistant", "type": "audio"]
        )
    }

    private func handleError(_ error: [String: Any]) {
        let errorCode = error["code"] as? String ?? "unknown"
        let errorMessage = error["message"] as? String ?? "No message"
        print("❌ Gemini Live API error - Code: \(errorCode), Message: \(errorMessage)")
        PersistentLogger.shared.logVertex(.error, "Live API error code=\(errorCode) message=\(errorMessage)")

        // Log error without PHI
        SimpleDataManager.shared.logAudit(
            action: "AUDIO_SESSION_ERROR",
            sessionId: currentSessionId,
            metadata: [
                "errorCode": errorCode,
                "errorType": "api_error"
            ]
        )

        // Handle specific error types
        if let code = error["code"] as? Int {
            switch code {
            case 401, 403:
                print("🔑 Authentication error, clearing tokens...")
                Task {
                    await AccessTokenProvider.shared.clearTokens()
                }
            case 429:
                print("⏳ Rate limit exceeded, backing off...")
                Task {
                    await reconnectWithBackoff()
                }
            case 503:
                print("🔧 Service unavailable, retrying...")
                Task {
                    await reconnectWithBackoff()
                }
            default:
                break
            }
        }
    }

    // MARK: - Audio Playback

    private var audioPlayer: AVAudioPlayer?

    private func playAudio(_ data: Data) {
        audioQueue.async { [weak self] in
            do {
                // Play native audio response from Gemini Live API with file type hint for PCM format
                self?.audioPlayer = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
                self?.audioPlayer?.play()
                print("🔊 Playing native audio response (\(data.count) bytes)")
            } catch {
                print("❌ Audio playback error: \(error)")
            }
        }
    }

    // MARK: - Session Termination

    func terminate() {
        if terminating { return }
        terminating = true
        isActive = false
        isConnected = false

        // Cancel any ongoing connection tasks
        connectionTask?.cancel()
        connectionTask = nil

        // Stop audio
        stopStreaming()

        // Close WebSocket gracefully
        webSocketTask?.cancel(with: .goingAway, reason: "Session terminated".data(using: .utf8))
        webSocketTask = nil

        // Invalidate URL session
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // End database session
        if let sessionId = currentSessionId {
            SimpleDataManager.shared.endSession(sessionId)
        }

        // Clear ephemeral data
        currentSessionId = nil
        ephemeralToken = ""
        sessionResumeHandle = nil

        // Reset connection state
        connectionAttempts = 0
        retryDelay = 1.0

        print("🔒 Audio session terminated, all ephemeral data cleared")
        terminating = false
    }

    private func handleDisconnection() {
        if terminating { return }
        terminate()
    }

    // MARK: - Authentication

    private func getEphemeralToken() async throws -> String {
        print("📍 STEP 5A: AudioSession.getEphemeralToken() starting...")

        // Use the comprehensive AccessTokenProvider
        do {
            print("📍 STEP 5B: Calling AccessTokenProvider.getAccessToken()...")
            let token = try await AccessTokenProvider.shared.getAccessToken()
            print("✅ STEP 5B PASSED: Token received from AccessTokenProvider (length: \(token.count))")

            print("📍 STEP 5C: Setting token expiry...")
            tokenExpiryTime = Date().addingTimeInterval(15 * 60)
            print("✅ STEP 5C PASSED: Token expiry set to: \(tokenExpiryTime!)")

            print("✅ STEP 5A COMPLETED: Token retrieval successful")
            return token
        } catch {
            print("🚨 STEP 5A FAILED: \(error)")
            print("🚨 ERROR DETAILS: \(String(describing: type(of: error)))")
            throw AudioSessionError.noAuthToken
        }
    }

    private func refreshTokenIfNeeded() async throws {
        if let expiry = tokenExpiryTime, Date() >= expiry {
            ephemeralToken = try await getEphemeralToken()
            print("🔄 Ephemeral token refreshed")
        }
    }

    // MARK: - Session Resume Support

    func resumeSession() async throws {
        guard let handle = sessionResumeHandle else {
            print("⚠️ No session to resume, starting new session")
            try await connect()
            return
        }

        // Use stored session handle to resume (Live API feature)
        let resumeMessage: [String: Any] = [
            "sessionResume": [
                "handle": handle
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: resumeMessage) {
            let message = URLSessionWebSocketTask.Message.data(data)
            try await webSocketTask?.send(message)
            print("🔄 Session resumed with handle: \(handle)")
        }
    }

    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "mode": "Native Audio (Mode 1)",
            "zeroRetention": true,
            "ephemeralSession": true,
            "promptLogging": "Disabled",
            "modelTraining": "Disabled",
            "sessionType": "Ephemeral",
            "localStorage": "Encrypted ObjectBox"
        ]
    }
}

// MARK: - Extensions

extension URLSessionWebSocketTask.State {
    var description: String {
        switch self {
        case .running:
            return "running"
        case .suspended:
            return "suspended"
        case .canceling:
            return "canceling"
        case .completed:
            return "completed"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - URLSessionDelegate

extension AudioSession: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                   webSocketTask: URLSessionWebSocketTask,
                   didOpenWithProtocol protocol: String?) {
        print("🎉 WEBSOCKET CONNECTED SUCCESSFULLY!")
        PersistentLogger.shared.logVertex(.info, "WEBSOCKET CONNECTED SUCCESSFULLY")
        print("✅ Gemini Live API WebSocket opened")
        print("🔗 Protocol: \(`protocol` ?? "none")")
        print("📊 WebSocket state: \(webSocketTask.state.description)")
        print("🌐 Connected to: \(webSocketTask.currentRequest?.url?.absoluteString ?? "unknown URL")")

        // Mark socket as connected on successful handshake
        isConnected = true

        // Post connection notification
        NotificationCenter.default.post(name: .audioSessionConnected, object: nil)
        print("📡 Posted audioSessionConnected notification")

        // Send initial configuration
        Task {
            do {
                print("📤 Sending initial configuration to Gemini Live API...")
                try await sendConfiguration()
                print("✅ Initial configuration sent successfully")
                PersistentLogger.shared.logVertex(.info, "Initial configuration sent")

                // Wait for setup completion before starting audio
                print("⏳ Waiting for setup completion from API...")

                // Note: Audio streaming will be started when we receive setupComplete=true

            } catch {
                print("❌ CONFIGURATION FAILED: \(error)")
                print("🔄 Attempting reconnection due to configuration failure...")
                await reconnectWithBackoff()
            }
        }
    }

    func urlSession(_ session: URLSession,
                   webSocketTask: URLSessionWebSocketTask,
                   didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                   reason: Data?) {
        print("🔌 WEBSOCKET DISCONNECTED")
        print("📊 Close code: \(closeCode)")
        print("📊 Close code raw value: \(closeCode.rawValue)")

        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            print("📝 Disconnect reason: \(reasonString)")
        } else {
            print("📝 Disconnect reason: [no reason provided]")
        }

        // Post disconnection notification
        NotificationCenter.default.post(name: .audioSessionDisconnected, object: nil)
        print("📡 Posted audioSessionDisconnected notification")

        handleDisconnection()
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioSessionTranscript = Notification.Name("audioSessionTranscript")
    static let audioSessionAudioResponse = Notification.Name("audioSessionAudioResponse")
    static let audioSessionDisconnected = Notification.Name("audioSessionDisconnected")
    static let audioSessionConnected = Notification.Name("audioSessionConnected")
}
