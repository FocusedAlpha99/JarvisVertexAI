
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

    // Audio configuration
    private let outputSampleRate: Double = 16000
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
        isActive = true
        startKeepAliveTimer()
        resetReconnectionAttempts()
        Task {
            await sendConfiguration()
            startAudioStreaming()
        }
    }

    private var reconnectionTimer: Timer?
    private var reconnectionAttempts = 0

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        connectionStatePublisher.send(.disconnected)
        isActive = false
        stopKeepAliveTimer()

        if closeCode != .goingAway {
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
                "generation_config": [
                    "response_modalities": ["AUDIO"],
                    "speech_config": [
                        "voice_config": [
                            "prebuilt_voice_config": [
                                "voice_name": "Aoede"
                            ]
                        ]
                    ]
                ],
                "system_instruction": [
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
        // Handle incoming messages
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
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: outputSampleRate, channels: outputChannels, interleaved: true)!

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

        let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(outputSampleRate))!
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
            "realtime_input": [
                "media_chunks": [
                    [
                        "mime_type": "audio/pcm;rate=16000",
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
