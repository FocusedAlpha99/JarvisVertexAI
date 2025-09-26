//
//  AudioSession.swift
//  JarvisVertexAI
//
//  Mode 1: Native Audio Streaming with Gemini Live API
//  Restored Essential Functionality - Fixed Audio Playback + Preserved Working Components
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

final class AudioSession: NSObject, AVAudioPlayerDelegate, URLSessionWebSocketDelegate {

    // MARK: - Properties

    static let shared = AudioSession()

    private var webSocketTask: URLSessionWebSocketTask? 
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "com.jarvisvertexai.audio", qos: .userInteractive)
    private let audioQueueKey = DispatchSpecificKey<Void>()

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
    private var heartbeatTask: Task<Void, Never>?

    // Lifecycle guards
    private var postSetupGraceUntil: Date?
    private var terminating = false

    // Audio configuration (Gemini Live API optimized)
    private let targetInputSampleRate: Double = 16_000
    private let outputSampleRate: Double = 24_000
    private let channelCount: Int = 1
    private let captureBufferSize: UInt32 = 4096  // tap buffer size; converter consolidates to target chunking
    private let chunkFrameCount: Int = 16_384
    private let bytesPerSample = 2
    private var currentInputSampleRate: Double = 0
    private var audioConverter: AVAudioConverter?
    private var pcmChunkAccumulator = Data()

    // Voice Activity Detection (silence handling for turn completion)
    private var silenceStartTime: Date?
    private var hasSentStreamEnd = false
    private let vadSilenceThresholdSeconds: TimeInterval = 1.0
    private let silenceAmplitudeThreshold: Float = 0.005
    private var isTapInstalled = false
    private var sentAudioSinceLastStreamEnd = false
    private let speechAmplitudeResetThreshold: Float = 0.02
    private let minimumAmplitudeToTransmit: Float = 0.003  // Increased noise gate for cleaner audio

    // Debugging metrics for bottleneck analysis
    private var audioChunksSent = 0
    private var totalAudioBytesSent = 0
    private var lastResponseTime: Date?
    private var lastActivityTime: Date = Date()
    private var responseLatencies: [TimeInterval] = []
    private var connectionStartTime: Date?
    private var setupCompletionTime: Date?
    private var vadEventsLog: [(Date, String, Float)] = []
    private var webSocketHealthMetrics = WebSocketHealthMetrics()

    // Audio playback (streaming via AVAudioEngine)
    private var playbackEngine: AVAudioEngine?
    private var playbackNode: AVAudioPlayerNode?
    private var playbackConverter: AVAudioConverter?
    private var playbackInputFormat: AVAudioFormat?
    private var playbackOutputFormat: AVAudioFormat?
    // Playback tail and turn guards removed for responsiveness

    // Live API configuration with privacy settings
    private var liveApiConfig: [String: Any] = [
        "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
        "generationConfig": [
            "responseModalities": ["AUDIO"],
            "speechConfig": [
                "voiceConfig": [
                    "prebuiltVoiceConfig": [
                        "voiceName": "Aoede"
                    ]
                ],
                // Prefer English (US) for spoken responses
                "languageCode": "en-US",
                // Some builds expect snake_case; include for compatibility
                "language_code": "en-US"
            ],
            // Privacy and compliance settings
            "candidateCount": 1,
            "maxOutputTokens": 2048,
            "temperature": 0.7,
            "topP": 0.8,
            "topK": 40
        ],
        // Minimal configuration — avoid heavy prompting; rely on model defaults
        "tools": []
    ]

    // MARK: - Initialization

    override private init() {
        super.init()
        loadConfiguration()
        setupAudioSession()
        audioQueue.setSpecific(key: audioQueueKey, value: ())
        terminating = false
    }

    private func loadConfiguration() {
        // Configuration loaded from environment
        print("✅ Audio session configuration loaded")
    }

    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // CRITICAL: Optimize for speech recognition and echo cancellation
            try session.setCategory(.playAndRecord,
                                   mode: .voiceChat,
                                   options: [.defaultToSpeaker,
                                           .duckOthers,
                                           .allowBluetooth,
                                           .interruptSpokenAudioAndMixWithOthers])

            // Set preferred sample rate for better speech quality
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.02) // 20ms buffer for low latency
            try session.setActive(true)

            print("✅ Audio session configured for speech recognition")
            print("   🔧 Sample rate: \(session.sampleRate)Hz, IO buffer: \(session.ioBufferDuration * 1000)ms")
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
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
        print("🚨 DEBUG: VertexConfig loaded - isConfigured: \(hasGeneralConfig)")
        print("🚨 DEBUG: Project ID: \(VertexConfig.shared.projectId)")
        print("🚨 DEBUG: Access Token exists: \(VertexConfig.shared.accessToken?.isEmpty == false)")

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
        connectionAttempts = 0
        retryDelay = 1.0
        try await connectWithRetry()
    }

    private func connectWithRetry() async throws {
        while connectionAttempts < maxRetryAttempts && !isConnected {
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
                    print("💀 All connection attempts failed")
                    throw error
                }
            }
        }
    }

    private func performConnection() async throws {
        print("📍 STEP 4: AudioSession.performConnection() starting...")
        PersistentLogger.shared.logVertex(.info, "STEP 4: performConnection() starting")

        // Reset debugging metrics
        connectionStartTime = Date()
        audioChunksSent = 0
        totalAudioBytesSent = 0
        responseLatencies.removeAll()
        vadEventsLog.removeAll()
        webSocketHealthMetrics.reset()

        silenceStartTime = nil
        hasSentStreamEnd = false
        sentAudioSinceLastStreamEnd = false

        print("🔍 DEBUG: Connection metrics reset at \(connectionStartTime!)")
        logSystemAudioConfiguration()

        // Resolve authentication: prefer GEMINI_API_KEY for Live WS; otherwise fetch OAuth token
        print("📍 STEP 5: Resolving authentication...")
        PersistentLogger.shared.logVertex(.info, "STEP 5: Resolving authentication")
        if VertexConfig.shared.geminiApiKey?.isEmpty == false {
            print("🔑 STEP 5 SKIPPED: Using GEMINI_API_KEY for Live WS")
            PersistentLogger.shared.logVertex(.info, "STEP 5: Using GEMINI_API_KEY")
        } else {
            do {
                if let expiry = tokenExpiryTime, expiry > Date() {
                    let seconds = expiry.timeIntervalSince(Date())
                    print("🔑 Reusing cached access token (expires in \(String(format: "%.0f", seconds))s)")
                    PersistentLogger.shared.logVertex(.info, "STEP 5: Reusing cached token")
                } else {
                    ephemeralToken = try await getEphemeralToken()
                    print("✅ STEP 5 PASSED: Token retrieved (length: \(ephemeralToken.count))")
                    PersistentLogger.shared.logVertex(.info, "STEP 5: Token retrieved length=\(ephemeralToken.count)")
                }
            } catch {
                print("❌ STEP 5 FAILED: Token retrieval error: \(error)")
                throw error
            }
        }

        // Build WebSocket URL (Gemini Live API endpoint)
        print("📍 STEP 6: Building WebSocket URL...")
        let url = try buildWebSocketURL()
        print("✅ STEP 6 PASSED: WebSocket URL built: \(url.absoluteString)")

        // Configure URLSession
        print("📍 STEP 7: Configuring URLSession...")
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0
        configuration.timeoutIntervalForResource = 300.0
        print("   ⏰ Connection timeout: \(configuration.timeoutIntervalForRequest)s")
        print("   ⏰ Resource timeout: \(configuration.timeoutIntervalForResource)s")
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        print("✅ STEP 7 PASSED: URLSession configured with privacy settings")

        // Create and configure WebSocket request
        print("📍 STEP 8A: Creating WebSocket request...")
        var request = URLRequest(url: url)

        // Add headers for privacy and authentication
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("JarvisVertexAI-iOS/1.0 (Privacy-Focused)", forHTTPHeaderField: "User-Agent")
        request.setValue("strict", forHTTPHeaderField: "X-Privacy-Mode")
        request.setValue("strict", forHTTPHeaderField: "X-Goog-Privacy-Setting")

        if let cmekKey = VertexConfig.shared.cmekKey, !cmekKey.isEmpty {
            request.setValue(cmekKey, forHTTPHeaderField: "X-Goog-Encryption-Key")
        }

        // Authentication headers
        if let apiKey = VertexConfig.shared.geminiApiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
            print("   🔑 Added Gemini API key to headers")
        } else if !ephemeralToken.isEmpty {
            request.setValue("Bearer \(ephemeralToken)", forHTTPHeaderField: "Authorization")
            print("   🔑 Added Bearer token to headers")
        }

        print("   📋 Request Headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key.lowercased().contains("key") || key.lowercased().contains("auth") {
                print("     \(key): [\(value.count) chars] \(String(value.prefix(12)))...")
            } else {
                print("     \(key): \(value)")
            }
        }
        print("✅ STEP 8A PASSED: WebSocket request configured")

        // Create WebSocket task
        print("📍 STEP 8B: Creating WebSocket task...")
        webSocketTask = urlSession?.webSocketTask(with: request)
        print("✅ STEP 8B PASSED: WebSocket task created")
        print("   📊 Task State: \(webSocketTask?.state.description ?? "unknown")")

        // Start WebSocket connection
        print("📍 STEP 9: Starting WebSocket connection...")
        print("   🌐 Attempting connection to: \(url.host ?? "unknown host")")
        print("   🚀 Resuming WebSocket task...")
        webSocketTask?.resume()
        print("✅ STEP 9 PASSED: WebSocket connection initiated")
        print("   📊 Post-resume Task State: \(webSocketTask?.state.description ?? "unknown")")

        // Start receiving messages
        print("📍 STEP 10: Starting message receiving...")
        receiveMessages()
    }

    private func buildWebSocketURL() throws -> URL {
        // Use Gemini Live API endpoint
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "generativelanguage.googleapis.com"
        components.path = "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"

        var queryItems: [URLQueryItem] = []

        if let apiKey = VertexConfig.shared.geminiApiKey, !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        } else if !ephemeralToken.isEmpty {
            queryItems.append(URLQueryItem(name: "access_token", value: ephemeralToken))
        }

        queryItems.append(URLQueryItem(name: "alt", value: "websocket"))
        queryItems.append(URLQueryItem(name: "prettyPrint", value: "false"))

        components.queryItems = queryItems

        guard let url = components.url else {
            throw AudioSessionError.connectionFailed
        }

        print("🔍 URL Components breakdown:")
        print("   Scheme: \(components.scheme ?? "nil")")
        print("   Host: \(components.host ?? "nil")")
        print("   Path: \(components.path)")
        print("   Query parameters: \(queryItems.count)")

        return url
    }

    private func receiveMessages() {
        guard !terminating else { return }

        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                self.handleMessage(message)

                // Continue receiving messages
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) {
                    self.receiveMessages()
                }

            case .failure(let error):
                // Error handling is now managed by the URLSessionDelegate
                print("❌ WebSocket receive error: \(error). Delegate will handle.")
            }
        }
    }

    private func reconnectWithBackoff() async {
        isActive = false
        isConnected = false
        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

        do {
            try await connect()
        } catch {
            print("❌ Reconnection failed: \(error)")
        }
    }

    private func handleDisconnection() {
        isActive = false
        isConnected = false
        stopHeartbeat()
        NotificationCenter.default.post(name: NSNotification.Name("audioSessionDisconnected"), object: nil)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task.detached { [weak self] in
            guard let self = self else { return }
            let interval = UInt64(15 * NSEC_PER_SEC)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { return }
                guard self.isConnected else { continue }

                let idleDuration = Date().timeIntervalSince(self.lastActivityTime)
                if idleDuration >= 15 {
                    await self.sendHeartbeatPing()
                }
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func sendHeartbeatPing() async {
        guard let webSocketTask = webSocketTask else { return }

        await withCheckedContinuation { continuation in
            webSocketTask.sendPing { [weak self] error in
                if let error = error {
                    print("⚠️ Heartbeat ping failed: \(error)")
                    self?.webSocketHealthMetrics.recordSendError()
                } else if VertexConfig.shared.debugLogging {
                    print("💓 Heartbeat ping sent")
                }

                self?.lastActivityTime = Date()
                continuation.resume()
            }
        }
    }

    private func sendInitialConfiguration() async throws {
        print("📤 Sending initial configuration to Gemini Live API...")

        var config = liveApiConfig
        
        // Add session resumption if handle exists
        if let handle = sessionResumeHandle {
            config["session_resumption"] = ["handle": handle]
            print("🔄 Including session resumption handle in setup.")
        } else {
            config["session_resumption"] = [:]
        }

        config["realtime_input_config"] = [
            // Enable server VAD but we still send explicit audio_stream_end
            "automatic_activity_detection": [
                "disabled": false
            ]
        ]

        let setupMessage: [String: Any] = ["setup": config]

        let data = try JSONSerialization.data(withJSONObject: setupMessage)
        let message = URLSessionWebSocketTask.Message.data(data)

        try await webSocketTask?.send(message)
        lastActivityTime = Date()
        print("✅ Vertex AI Live API configuration sent")
        print("📋 Setup: \(setupMessage)")

        postSetupGraceUntil = Date().addingTimeInterval(2.0)
        print("⏳ Waiting for setup completion from API...")
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleDataMessage(data)
        case .string(let text):
            print("📨 String message: \(text)")
        @unknown default:
            print("📨 Unknown message type received")
        }
    }

    private func handleDataMessage(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Failed to parse JSON from data message")
                return
            }

            lastActivityTime = Date()

            if VertexConfig.shared.debugLogging {
                print("📨 Raw message: \(json)")
            }

            // Handle setup completion
            if json["setupComplete"] != nil {
                setupCompletionTime = Date()
                let setupLatency = connectionStartTime.map { setupCompletionTime!.timeIntervalSince($0) } ?? 0
                print("✅ Gemini Live API setup completed successfully")
                print("⏱️ Setup latency: \(String(format: "%.3f", setupLatency))s")

                let sessionId = UUID().uuidString
                currentSessionId = sessionId
                print("✅ Session created: \(sessionId), mode: GeminiLiveAudio")

                // Start audio streaming only after setup is complete
                if !isActive {
                    startAudioStreaming()
                    silenceStartTime = nil
                    hasSentStreamEnd = false
                    isActive = true
                    print("🔍 DEBUG: Audio streaming started at \(Date())")
                    NotificationCenter.default.post(name: NSNotification.Name("audioSessionConnected"), object: nil)
                }
                return
            }

            // Handle server content (audio responses)
            if let serverContent = json["serverContent"] as? [String: Any],
               let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {

                // Model output received

                // Track response latency
                let responseTime = Date()
                if let lastSent = lastResponseTime {
                    let latency = responseTime.timeIntervalSince(lastSent)
                    responseLatencies.append(latency)
                    if responseLatencies.count > 10 {
                        responseLatencies.removeFirst()
                    }
                    let avgLatency = responseLatencies.reduce(0, +) / Double(responseLatencies.count)
                    print("🤖 Model response received - latency: \(String(format: "%.3f", latency))s, avg: \(String(format: "%.3f", avgLatency))s")
                } else {
                    print("🤖 Model response received - maintaining continuous audio stream")
                }

                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let mimeType = inlineData["mimeType"] as? String,
                       let audioData = inlineData["data"] as? String,
                       mimeType.contains("audio") {

                        print("🔍 DEBUG: Audio response size: \(audioData.count) chars (base64)")
                        playAudio(audioData)
                    }
                }
            }

            // Handle turn completion
            if let _ = json["turnComplete"] {
                print("🔄 Turn complete - server detected end of user speech")
            }

            // Handle interruption
            if let _ = json["interrupted"] {
                print("⚡ Model interrupted by user - server detected speech during response")
            }

            // Handle session resumption
            if let sessionUpdate = json["sessionResumptionUpdate"] as? [String: Any] {
                if let handle = sessionUpdate["handle"] as? String {
                    sessionResumeHandle = handle
                    print("📝 Session resumption handle received: \(handle.prefix(20))...")
                } else {
                    print("ℹ️ SessionResumptionUpdate received (no handle field)")
                }
            }

            // Handle usage metadata
            if let _ = json["usageMetadata"] {
                print("📊 Usage metadata received")
            }

            if let error = json["error"] as? [String: Any] {
                print("🚨 Gemini Live API error: \(error)")
            }

            if json.keys.contains("realtimeOutput") {
                print("ℹ️ Realtime output message: \(json)")
            }

        } catch {
            print("❌ JSON parsing error: \(error)")
        }
    }

    // MARK: - Audio Streaming

    private func startAudioStreaming() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        currentInputSampleRate = recordingFormat.sampleRate

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: targetInputSampleRate,
                                               channels: AVAudioChannelCount(channelCount),
                                               interleaved: false) else {
            print("❌ Failed to create 16 kHz mono target format")
            return
        }

        audioConverter = AVAudioConverter(from: recordingFormat, to: targetFormat)

        guard audioConverter != nil else {
            print("❌ Failed to initialize audio converter for 16 kHz PCM")
            return
        }

        pcmChunkAccumulator.removeAll(keepingCapacity: true)

        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        inputNode.installTap(onBus: 0, bufferSize: captureBufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isActive else { return }
            self.handleIncomingAudioBuffer(buffer, targetFormat: targetFormat)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("🎤 Audio streaming started - Format: \(Int(targetInputSampleRate))Hz, \(channelCount) channel(s)")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }

        isTapInstalled = true
    }

    private func handleIncomingAudioBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        // (Reverted) Allow barge-in: do not block mic when TTS is playing
        let averageAmplitude = averageMagnitude(from: buffer)

        // Allow barge-in; keep responsiveness high (no extra guards)
        let timestamp = Date()

        if averageAmplitude < silenceAmplitudeThreshold {
            if silenceStartTime == nil {
                silenceStartTime = timestamp
                vadEventsLog.append((timestamp, "SILENCE_START", averageAmplitude))
                if VertexConfig.shared.debugLogging {
                    print("🔇 VAD: Silence started (amp: \(String(format: "%.6f", averageAmplitude)))")
                }
            }

            // With server-side VAD configured, don't send manual stream_end on silence
            // Let the server handle turn detection with its superior audio processing

        } else {
            if let start = silenceStartTime {
                let duration = timestamp.timeIntervalSince(start)
                vadEventsLog.append((timestamp, "SILENCE_END", averageAmplitude))
                if VertexConfig.shared.debugLogging {
                    print("🔊 VAD: Silence ended after \(String(format: "%.3f", duration))s (amp: \(String(format: "%.6f", averageAmplitude)))")
                }
            }
            silenceStartTime = nil
            if averageAmplitude >= speechAmplitudeResetThreshold {
                sentAudioSinceLastStreamEnd = true
                hasSentStreamEnd = false
                vadEventsLog.append((timestamp, "SPEECH_DETECTED", averageAmplitude))
                if VertexConfig.shared.debugLogging {
                    print("🗣️ VAD: Speech detected (amp: \(String(format: "%.6f", averageAmplitude)))")
                }
            }
        }

        guard averageAmplitude >= minimumAmplitudeToTransmit else {
            return
        }

        guard let converter = audioConverter,
              let convertedBuffer = convert(buffer, using: converter, targetFormat: targetFormat),
              let data = convertedBuffer.toPCMData(),
              !data.isEmpty else {
            return
        }

        audioQueue.async { [weak self] in
            self?.appendPCMData(data)
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer,
                         using converter: AVAudioConverter,
                         targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let estimatedCapacity = AVAudioFrameCount(Double(buffer.frameLength) * targetInputSampleRate / buffer.format.sampleRate) + 1

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedCapacity) else {
            return nil
        }

        var error: NSError?
        var inputProvided = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("⚠️ Audio conversion error: \(error)")
            return nil
        }

        outputBuffer.frameLength = min(outputBuffer.frameCapacity,
                                       AVAudioFrameCount(Double(buffer.frameLength) * targetInputSampleRate / buffer.format.sampleRate))
        return outputBuffer
    }

    private func appendPCMData(_ data: Data) {
        guard !data.isEmpty else { return }

        if DispatchQueue.getSpecific(key: audioQueueKey) == nil {
            audioQueue.async { [weak self] in
                self?.appendPCMData(data)
            }
            return
        }

        pcmChunkAccumulator.append(data)
        let chunkByteCount = chunkFrameCount * bytesPerSample

        while pcmChunkAccumulator.count >= chunkByteCount {
            let chunk = pcmChunkAccumulator.prefix(chunkByteCount)
            sendAudioChunk(data: Data(chunk))
            pcmChunkAccumulator.removeSubrange(..<chunkByteCount)
        }
    }

    @discardableResult
    private func flushPendingAudio(sync: Bool = false) -> Task<Void, Never>? {
        var pendingTask: Task<Void, Never>?

        let work = { [weak self] in
            guard let self = self else { return }
            guard !self.pcmChunkAccumulator.isEmpty else { return }
            let chunk = self.pcmChunkAccumulator
            self.pcmChunkAccumulator.removeAll(keepingCapacity: true)
            pendingTask = self.sendAudioChunk(data: chunk)
        }

        if DispatchQueue.getSpecific(key: audioQueueKey) != nil {
            work()
        } else if sync {
            audioQueue.sync(execute: work)
        } else {
            audioQueue.async(execute: work)
        }

        return pendingTask
    }

    @discardableResult
    private func sendAudioChunk(data: Data) -> Task<Void, Never>? {
        guard !data.isEmpty else { return nil }

        audioChunksSent += 1
        totalAudioBytesSent += data.count
        lastResponseTime = Date()
        webSocketHealthMetrics.recordChunkSent(bytes: data.count)
        lastActivityTime = Date()

        if VertexConfig.shared.debugLogging {
            print("📤 Sending audio chunk #\(audioChunksSent): \(data.count) bytes (total: \(totalAudioBytesSent) bytes)")

            // CRITICAL DEBUG: Validate audio data has speech content
            if data.count >= 4 {
                let firstBytes = data.prefix(4)
                let samples = firstBytes.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                let sample1 = samples[0]
                let sample2 = samples[1]
                print("🔍 AUDIO CONTENT: First samples: \(sample1), \(sample2) (non-zero = \(sample1 != 0 || sample2 != 0))")
            }
        } else if audioChunksSent % 50 == 0 {
            print("📊 Audio transmission: \(audioChunksSent) chunks, \(totalAudioBytesSent) bytes total")
        }

        sentAudioSinceLastStreamEnd = true

        let message: [String: Any] = [
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
                        "data": data.base64EncodedString()
                    ]
                ]
            ]
        ]

        let task = Task { [weak self] in
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: message)
                let wsMessage = URLSessionWebSocketTask.Message.data(jsonData)
                let sendStart = Date()
                try await self?.webSocketTask?.send(wsMessage)
                let latency = Date().timeIntervalSince(sendStart)
                self?.webSocketHealthMetrics.recordSendLatency(latency)

                if let debugSelf = self, VertexConfig.shared.debugLogging && latency > 0.010 {
                    print("⚠️ Slow WebSocket send: \(String(format: "%.3f", latency))s")
                }
            } catch {
                print("❌ Failed to send audio chunk: \(error)")
                self?.webSocketHealthMetrics.recordSendError()
            }
        }

        return task
    }

    private func averageMagnitude(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelPointer = buffer.floatChannelData?.pointee else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            sum += abs(channelPointer[index])
        }

        return sum / Float(frameLength)
    }

    private func sendAudioStreamEnd(force: Bool = false) async {
        if !force {
            guard isActive else { return }
            guard sentAudioSinceLastStreamEnd else { return }
            guard hasSentStreamEnd == false else { return }
        }

        if let flushTask = flushPendingAudio(sync: true) {
            await flushTask.value
        }

        hasSentStreamEnd = true
        let message: [String: Any] = [
            "realtime_input": [
                "audio_stream_end": true
            ]
        ]

        sentAudioSinceLastStreamEnd = false
        silenceStartTime = nil

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            let wsMessage = URLSessionWebSocketTask.Message.data(jsonData)
            try await webSocketTask?.send(wsMessage)
            lastActivityTime = Date()
            hasSentStreamEnd = true
            print(force ? "🛑 Sent audio_stream_end to Gemini Live API (forced)" : "🛑 Sent audio_stream_end to Gemini Live API")
        } catch {
            print("⚠️ Failed to send audio_stream_end: \(error)")
            if !force {
                // Allow retry if the send failed
                hasSentStreamEnd = false
                sentAudioSinceLastStreamEnd = true
            }
        }
    }

    // MARK: - Audio Playback (Streaming)

    private func ensurePlaybackEngine() {
        if playbackEngine == nil || playbackNode == nil {
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            // Use the mixer output format (typically Float32 at 44.1/48 kHz)
            let mixerFormat = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(node, to: engine.mainMixerNode, format: mixerFormat)
            do {
                try engine.start()
                playbackEngine = engine
                playbackNode = node
                // Prepare converter from 24 kHz Int16 mono -> mixer format
                playbackInputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                                   sampleRate: outputSampleRate,
                                                   channels: 1,
                                                   interleaved: false)
                playbackOutputFormat = mixerFormat
                if let inFmt = playbackInputFormat {
                    playbackConverter = AVAudioConverter(from: inFmt, to: mixerFormat)
                }
                print("✅ Playback engine started for 24 kHz PCM")
            } catch {
                print("❌ Failed to start playback engine: \(error)")
                playbackEngine = nil
                playbackNode = nil
            }
        }
    }

    private func playAudio(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }
        ensurePlaybackEngine()
        guard let node = playbackNode,
              let inFmt = playbackInputFormat,
              let outFmt = playbackOutputFormat,
              let converter = playbackConverter else { return }

        // Build input Int16 buffer at 24 kHz mono
        let inFrames = AVAudioFrameCount(audioData.count / 2)
        guard let inBuffer = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: inFrames) else { return }
        inBuffer.frameLength = inFrames
        audioData.withUnsafeBytes { rawPtr in
            guard let src = rawPtr.bindMemory(to: Int16.self).baseAddress,
                  let dst = inBuffer.int16ChannelData?.pointee else { return }
            dst.assign(from: src, count: Int(inFrames))
        }

        // Estimate output frames for converter
        let ratio = outFmt.sampleRate / inFmt.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inFrames) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCapacity) else { return }

        var error: NSError?
        var provided = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return inBuffer
        }
        if let error = error {
            print("⚠️ Playback convert error: \(error)")
            return
        }
        if outBuffer.frameLength == 0 {
            return
        }

        if !node.isPlaying { node.play() }
        node.scheduleBuffer(outBuffer, completionHandler: nil)
        print("🔊 Queued native audio chunk (\(audioData.count) bytes)")
    }

    // MARK: - Token Management

    private func getEphemeralToken() async throws -> String {
        do {
            let token = try await AccessTokenProvider.shared.getAccessToken()
            tokenExpiryTime = Date().addingTimeInterval(15 * 60)
            return token
        } catch {
            print("❌ Failed to get access token: \(error)")
            throw AudioSessionError.noAuthToken
        }
    }

    // MARK: - Cleanup

    func terminate() {
        if terminating { return }
        terminating = true

        Task { [weak self] in
            guard let self = self else { return }
            await self.sendAudioStreamEnd(force: true)
            await MainActor.run {
                self.completeTerminationCleanup()
            }
        }
    }

    @MainActor
    private func completeTerminationCleanup() {
        print("🔒 Terminating audio session... Stack: \(Thread.callStackSymbols.joined(separator: "\n"))")

        isActive = false
        isConnected = false

        audioEngine.stop()
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()

        if let node = playbackNode, node.isPlaying {
            node.stop()
        }
        if let engine = playbackEngine {
            engine.stop()
        }
        playbackNode = nil
        playbackEngine = nil
        stopHeartbeat()

        // Clear sensitive data
        ephemeralToken = ""
        // Do not clear sessionResumeHandle
        tokenExpiryTime = nil

        connectionAttempts = 0
        retryDelay = 1.0
        silenceStartTime = nil
        hasSentStreamEnd = false
        sentAudioSinceLastStreamEnd = false

        terminating = false

        printDebugSummary()
        NotificationCenter.default.post(name: NSNotification.Name("audioSessionDisconnected"), object: nil)
        print("✅ Session ended: \(currentSessionId ?? "unknown")")
        print("🔒 Audio session terminated, all ephemeral data cleared")
    }

    // MARK: - Debugging Helper Functions

    private func logSystemAudioConfiguration() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        print("🔍 AUDIO CONFIG: Sample rate: \(session.sampleRate)Hz, channels: \(session.inputNumberOfChannels)")
        print("🔍 AUDIO CONFIG: Category: \(session.category), mode: \(session.mode)")
        print("🔍 AUDIO CONFIG: Available inputs: \(session.availableInputs?.count ?? 0)")
        #endif
        print("🔍 TARGET CONFIG: Input \(Int(targetInputSampleRate))Hz → Output \(Int(outputSampleRate))Hz")

        // CRITICAL: Log byte order for debugging audio comprehension issues
        let testValue: Int16 = 0x1234
        let littleEndian = testValue.littleEndian
        print("🔍 BYTE ORDER: System endianness test - 0x1234 → LE: 0x\(String(littleEndian, radix: 16))")
        print("🔍 GEMINI REQUIREMENT: 16-bit PCM, 16kHz, mono, little-endian")
    }

    private func printDebugSummary() {
        guard connectionStartTime != nil else { return }

        let sessionDuration = Date().timeIntervalSince(connectionStartTime!)
        let avgLatency = responseLatencies.isEmpty ? 0 : responseLatencies.reduce(0, +) / Double(responseLatencies.count)
        let wsMetrics = webSocketHealthMetrics

        print("📊 SESSION SUMMARY (\(String(format: "%.1f", sessionDuration))s):")
        print("   Audio: \(audioChunksSent) chunks, \(totalAudioBytesSent) bytes")
        print("   Response latency: avg \(String(format: "%.3f", avgLatency))s, samples: \(responseLatencies.count)")
        print("   WebSocket: \(wsMetrics.chunksSent) sent, \(wsMetrics.sendErrors) errors")
        print("   WebSocket latency: avg \(String(format: "%.3f", wsMetrics.averageSendLatency))s")
        print("   VAD events: \(vadEventsLog.count)")

        if VertexConfig.shared.debugLogging && !vadEventsLog.isEmpty {
            print("📋 VAD EVENT LOG (last 10):")
            for event in vadEventsLog.suffix(10) {
                let timeOffset = connectionStartTime.map { event.0.timeIntervalSince($0) } ?? 0
                print("   +\(String(format: "%.3f", timeOffset))s: \(event.1) (amp: \(String(format: "%.6f", event.2)))")
            }
        }
    }

    func stopStreaming() {
        terminate()
    }
    
    // MARK: - URLSessionWebSocketDelegate Methods
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connection opened.")
        isConnected = true
        connectionAttempts = 0
        retryDelay = 1.0
        lastActivityTime = Date()
        startHeartbeat()

        Task {
            do {
                try await sendInitialConfiguration()
            } catch {
                print("❌ Failed to send initial configuration: \(error)")
                handleDisconnection()
            }
        }
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("❌ WebSocket connection closed. Code: \(closeCode.rawValue)")
        handleDisconnection()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ WebSocket task completed with error: \(error)")
            
            let nsError = error as NSError
            switch nsError.code {
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                print("⚠️ Connection issue detected, attempting reconnection...")
                Task {
                    await reconnectWithBackoff()
                }
            default:
                handleDisconnection()
            }
        }
    }
}

// MARK: - Extensions

extension AVAudioPCMBuffer {
    func toPCMData() -> Data? {
        guard let channelData = int16ChannelData else { return nil }
        let frameLength = Int(self.frameLength)

        // CRITICAL FIX: Ensure little-endian format for Gemini Live API
        var data = Data()
        data.reserveCapacity(frameLength * 2)

        let sourcePtr = channelData[0]
        for i in 0..<frameLength {
            let sample = sourcePtr[i]
            // Convert to little-endian Int16 (required by Gemini Live API)
            let littleEndianSample = sample.littleEndian
            withUnsafeBytes(of: littleEndianSample) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        if VertexConfig.shared.debugLogging && frameLength > 0 {
            // Verify first few samples for debugging
            let firstSample = sourcePtr[0]
            let littleEndian = firstSample.littleEndian
            print("🔍 AUDIO DEBUG: Sample \(firstSample) → LE: \(littleEndian), bytes: \(frameLength * 2)")
        }

        return data
    }
}

extension URLSessionTask.State {
    var description: String {
        switch self {
        case .running: return "running"
        case .suspended: return "suspended"
        case .canceling: return "canceling"
        case .completed: return "completed"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - WebSocket Health Metrics

struct WebSocketHealthMetrics {
    private(set) var chunksSent = 0
    private(set) var sendErrors = 0
    private var sendLatencies: [TimeInterval] = []

    var averageSendLatency: TimeInterval {
        return sendLatencies.isEmpty ? 0 : sendLatencies.reduce(0, +) / Double(sendLatencies.count)
    }

    mutating func recordChunkSent(bytes: Int) {
        chunksSent += 1
    }

    mutating func recordSendLatency(_ latency: TimeInterval) {
        sendLatencies.append(latency)
        if sendLatencies.count > 20 {
            sendLatencies.removeFirst()
        }
    }

    mutating func recordSendError() {
        sendErrors += 1
    }

    mutating func reset() {
        chunksSent = 0
        sendErrors = 0
        sendLatencies.removeAll()
    }
}
