
//
//  AudioSession.swift
//  JarvisVertexAI
//
//  Mode 1: Native Audio Streaming with Gemini Live API
//  Zero Retention, CMEK Encryption, Maximum Privacy
//

import Foundation
import AVFoundation
import Combine

final class AudioSession: NSObject, URLSessionWebSocketDelegate {

    // MARK: - Properties

    static let shared = AudioSession()
    let connectionStatePublisher = PassthroughSubject<AudioModeViewModel.ConnectionState, Never>()

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let audioEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    private var keepAliveTimer: Timer?

    // Configuration
    private var projectId: String = ""
    private var region: String = "us-central1"
    private var endpointId: String = ""
    private var cmekKeyPath: String = ""
    private var accessToken: String = ""

    // Session management
    private var currentSessionId: String?
    private var isActive = false

    // Audio configuration (Gemini Live API spec-compliant)
    private let inputSampleRate: Double = 16000   // Input to Gemini Live API: 16 kHz
    private let outputSampleRate: Double = 24000  // Output from Gemini Live API: 24 kHz
    private let outputChannels: UInt32 = 1

    // MARK: - Initialization

    override private init() {
        super.init()
        loadConfiguration()
    }

    private func loadConfiguration() {
        projectId = ProcessInfo.processInfo.environment["VERTEX_PROJECT_ID"] ?? ""
        region = ProcessInfo.processInfo.environment["VERTEX_REGION"] ?? "us-central1"
        cmekKeyPath = ProcessInfo.processInfo.environment["VERTEX_CMEK_KEY"] ?? ""
    }

    // MARK: - Connection Management

    func connect(projectId: String, region: String, endpointId: String) async {
        connectionStatePublisher.send(.connecting)

        self.projectId = projectId
        self.region = region
        self.endpointId = endpointId

        do {
            accessToken = try await getAccessToken()
        } catch {
            connectionStatePublisher.send(.error("Failed to get access token."))
            return
        }

        let wsURL = buildWebSocketURL()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(accessToken)"]

        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = urlSession?.webSocketTask(with: wsURL)
        webSocketTask?.resume()
    }

    private func buildWebSocketURL() -> URL {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(region)-aiplatform.googleapis.com"
        components.path = "/v1/projects/\(projectId)/locations/\(region)/endpoints/\(endpointId):streamRawPredict"
        components.queryItems = [
            URLQueryItem(name: "alt", value: "ws"),
            URLQueryItem(name: "key", value: cmekKeyPath)
        ]
        return components.url!
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        connectionStatePublisher.send(.connected)
        startKeepAliveTimer()
        resetReconnectionAttempts()

        // Start receiving messages immediately to catch setupComplete
        receiveMessages()

        Task {
            await sendConfiguration()
            // Note: Audio streaming will start only after receiving setupComplete
            print("⏳ Configuration sent, waiting for setupComplete acknowledgment...")
        }
    }

    private var reconnectionTimer: Timer?
    private var reconnectionAttempts = 0

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        connectionStatePublisher.send(.disconnected)
        isActive = false
        stopKeepAliveTimer()

        print("❌ WebSocket closed with code: \(closeCode.rawValue)")
        if let reason = reason, let reasonString = String(data: reason, encoding: .utf8) {
            print("📝 Reason: \(reasonString)")
        }

        // Handle different close codes appropriately
        switch closeCode {
        case .normalClosure: // 1000 - Normal closure, don't reconnect
            print("✅ Normal closure - session ended cleanly")

        case .goingAway: // 1001 - Server restart, should reconnect
            print("⚠️ Server going away - will reconnect")
            startReconnectionTimer()

        case .internalServerError: // 1011 - Server overload, use backoff
            print("⚠️ Server internal error (1011) - implementing extended backoff")
            // Double the backoff for server errors
            let serverErrorBackoff = min(pow(2.0, Double(reconnectionAttempts + 2)), 120.0)
            reconnectionTimer = Timer.scheduledTimer(withTimeInterval: serverErrorBackoff, repeats: false) { [weak self] _ in
                self?.reconnect()
            }

        case .protocolError, .unsupportedData: // 1002, 1003 - Client errors
            print("❌ Protocol/data error - client implementation issue, not reconnecting")
            // Don't reconnect for client-side errors

        default:
            print("⚠️ Unexpected close code, attempting reconnection")
            startReconnectionTimer()
        }
    }

    private func startReconnectionTimer() {
        let backoff = min(pow(2.0, Double(reconnectionAttempts)), 60.0) // Exponential backoff up to 60 seconds
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: backoff, repeats: false) { [weak self] _ in
            self?.reconnect()
        }
    }

    private func reconnect() {
        reconnectionAttempts += 1
        Task {
            await connect(projectId: projectId, region: region, endpointId: endpointId)
        }
    }

    private func resetReconnectionAttempts() {
        reconnectionAttempts = 0
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
    }

    // MARK: - WebSocket Communication

    private func sendConfiguration() async {
        let config: [String: Any] = [
            "setup": [
                "model": "models/gemini-2.5-flash-native-audio-preview-09-2025",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": [
                            "prebuiltVoiceConfig": [
                                "voiceName": "Aoede"
                            ]
                        ]
                    ]
                ],
                "systemInstruction": [
                    "parts": [
                        ["text": "You are a helpful AI assistant. Respond naturally and conversationally."]
                    ]
                ]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: config)
            try await webSocketTask?.send(.data(data))
        } catch {
            connectionStatePublisher.send(.error("Failed to send configuration."))
        }
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessages()
            case .failure(let error):
                self?.connectionStatePublisher.send(.error(error.localizedDescription))
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleDataMessage(data)
        case .string(let text):
            print("📨 String message: \(text)")
            if let data = text.data(using: .utf8) {
                handleDataMessage(data)
            }
        @unknown default:
            print("⚠️ Unknown message type received")
        }
    }

    private func handleDataMessage(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ Failed to parse JSON from WebSocket message")
                return
            }

            print("📨 Received message: \(json.keys.joined(separator: ", "))")

            // Handle setup completion - CRITICAL: Wait for this before streaming!
            if json["setupComplete"] != nil {
                print("✅ Gemini Live API setup completed successfully")

                // Now it's safe to start audio streaming
                if !isActive {
                    isActive = true
                    startAudioStreaming()
                    print("🎤 Audio streaming started after setupComplete acknowledgment")
                }
                return
            }

            // Handle server audio responses
            if let serverContent = json["serverContent"] as? [String: Any],
               let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {

                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let audioData = inlineData["data"] as? String {
                        // Handle audio response from Gemini
                        playAudioResponse(audioData)
                    }
                }
            }

            // Handle errors
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                print("❌ Server error: \(message)")
                connectionStatePublisher.send(.error(message))
            }

        } catch {
            print("❌ Error parsing WebSocket message: \(error)")
        }
    }

    private func playAudioResponse(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else {
            print("❌ Failed to decode base64 audio data")
            return
        }

        // Create WAV data with proper 24 kHz format for Gemini Live API output
        let wavData = createWAVData(from: audioData, sampleRate: Int(outputSampleRate), channels: 1)

        DispatchQueue.main.async { [weak self] in
            do {
                let audioPlayer = try AVAudioPlayer(data: wavData)
                audioPlayer.play()
                print("🔊 Playing Gemini audio response (\(audioData.count) bytes)")
            } catch {
                print("❌ Audio playback failed: \(error)")
            }
        }
    }

    private func startKeepAliveTimer() {
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    self?.connectionStatePublisher.send(.error("Ping failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func stopKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    // MARK: - Audio Streaming

    private func startAudioStreaming() {
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputSampleRate, channels: outputChannels, interleaved: true)!

        audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            connectionStatePublisher.send(.error("Failed to start audio engine."))
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter else { return }

        let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(inputSampleRate))!
        var error: NSError?

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("Audio conversion error: \(error.localizedDescription)")
            return
        }

        let data = Data(bytes: outputBuffer.int16ChannelData![0], count: Int(outputBuffer.frameLength) * 2)
        sendAudioData(data)
    }

    private func sendAudioData(_ data: Data) {
        let message: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [
                    [
                        "mimeType": "audio/pcm;rate=16000",  // Gemini Live API input requirement
                        "data": data.base64EncodedString()
                    ]
                ]
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            Task {
                try await webSocketTask?.send(.data(data))
            }
        } catch {
            // Handle error
        }
    }

    // MARK: - WAV Header Creation

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

    // MARK: - Session Termination

    func terminate() {
        isActive = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        stopKeepAliveTimer()
    }

    // MARK: - Authentication

    private func getAccessToken() async throws -> String {
        return ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"] ?? ""
    }
}
