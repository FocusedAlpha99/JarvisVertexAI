//
//  SimpleAudioSession.swift
//  JarvisVertexAI
//
//  Minimal Gemini Live API Implementation
//  Based on Google's best practices - Simple WebSocket + Audio streaming
//

import Foundation
import AVFoundation

final class SimpleAudioSession: NSObject, AVAudioPlayerDelegate {

    static let shared = SimpleAudioSession()

    // MARK: - Core Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let audioEngine = AVAudioEngine()
    private var isActive = false

    // MARK: - Audio Components
    private let audioQueue = DispatchQueue(label: "com.jarvis.audio")
    private var audioPlayer: AVAudioPlayer?

    override private init() {
        super.init()
        setupAudioSession()
    }

    // MARK: - Setup
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("❌ Audio session setup failed: \(error)")
        }
        #endif
    }

    // MARK: - Connection
    func connect() async throws {
        // Get API key
        guard let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !apiKey.isEmpty else {
            throw NSError(domain: "SimpleAudioSession", code: 1, userInfo: [NSLocalizedDescriptionKey: "GEMINI_API_KEY not found"])
        }

        // Build WebSocket URL
        let urlString = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw NSError(domain: "SimpleAudioSession", code: 2) }

        // Create WebSocket
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)

        // Start receiving messages
        receiveMessages()

        // Connect
        webSocketTask?.resume()
        print("🌐 WebSocket connecting...")

        // Send setup
        try await sendSetup()

        // Start audio streaming
        startAudioStreaming()

        isActive = true
        print("✅ Connected to Gemini Live API")
    }

    private func sendSetup() async throws {
        let setup: [String: Any] = [
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

        let data = try JSONSerialization.data(withJSONObject: setup)
        let message = URLSessionWebSocketTask.Message.data(data)
        try await webSocketTask?.send(message)
        print("📤 Setup sent")
    }

    // MARK: - Audio Streaming
    private func startAudioStreaming() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Convert to 16kHz mono for Gemini
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: recordingFormat, to: targetFormat)!

        inputNode.installTap(onBus: 0, bufferSize: 4800, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isActive else { return }

            // Convert audio format
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 4800)!
            var error: NSError?

            converter.convert(to: convertedBuffer, error: &error) { _, _ in
                return buffer
            }

            guard error == nil else { return }

            // Send audio data
            self.sendAudioChunk(convertedBuffer)
        }

        do {
            try audioEngine.start()
            print("🎤 Audio streaming started")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    private func sendAudioChunk(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.toPCMData() else { return }

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

        Task {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: message)
                let wsMessage = URLSessionWebSocketTask.Message.data(jsonData)
                try await self.webSocketTask?.send(wsMessage)
            } catch {
                print("❌ Failed to send audio: \(error)")
            }
        }
    }

    // MARK: - Message Handling
    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessages() // Continue receiving
            case .failure(let error):
                print("❌ WebSocket receive error: \(error)")
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    if json["setupComplete"] != nil {
                        print("✅ Setup complete")
                        return
                    }

                    if let serverContent = json["serverContent"] as? [String: Any],
                       let modelTurn = serverContent["modelTurn"] as? [String: Any],
                       let parts = modelTurn["parts"] as? [[String: Any]] {

                        for part in parts {
                            if let inlineData = part["inlineData"] as? [String: Any],
                               let mimeType = inlineData["mimeType"] as? String,
                               let audioData = inlineData["data"] as? String,
                               mimeType.contains("audio") {

                                playAudioResponse(audioData)
                            }
                        }
                    }
                }
            } catch {
                print("❌ Failed to parse message: \(error)")
            }
        case .string(let text):
            print("📨 String message: \(text)")
        @unknown default:
            break
        }
    }

    // MARK: - Audio Playback (Fixed)
    private func playAudioResponse(_ base64Audio: String) {
        guard let audioData = Data(base64Encoded: base64Audio) else { return }

        audioQueue.async { [weak self] in
            // Create WAV header for PCM data (this fixes the 1954115647 error)
            let wavData = self?.createWAVData(from: audioData, sampleRate: 24000, channels: 1) ?? audioData

            do {
                self?.audioPlayer = try AVAudioPlayer(data: wavData)
                self?.audioPlayer?.delegate = self
                self?.audioPlayer?.play()
                print("🔊 Playing audio response (\(audioData.count) bytes)")
            } catch {
                print("❌ Audio playback failed: \(error)")
            }
        }
    }

    // Create proper WAV file format from PCM data
    private func createWAVData(from pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        var data = Data()

        // WAV header
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

    // MARK: - Cleanup
    func disconnect() {
        isActive = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        print("🔒 Disconnected")
    }
}

// MARK: - Extensions

extension AVAudioPCMBuffer {
    func toPCMData() -> Data? {
        guard let channelData = int16ChannelData else { return nil }
        let frameLength = Int(self.frameLength)
        let data = Data(bytes: channelData[0], count: frameLength * 2) // 16-bit = 2 bytes per sample
        return data
    }
}