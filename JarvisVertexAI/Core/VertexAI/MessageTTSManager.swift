//
//  MessageTTSManager.swift
//  JarvisVertexAI
//
//  Mode 3: Text-to-Speech Manager for Message Reading
//  Privacy-First: 100% On-Device TTS using iOS AVSpeechSynthesizer
//

import AVFoundation
import SwiftUI
import Combine

// MARK: - Message TTS Manager
@MainActor
@Observable
class MessageTTSManager: NSObject, ObservableObject {
    static let shared = MessageTTSManager()

    // MARK: - Private Properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var wordRanges: [NSRange] = []
    private var totalCharacters: Int = 0

    // MARK: - Observable State
    private(set) var isCurrentlySpeaking = false
    private(set) var currentSpeakingMessageId: UUID?
    private(set) var speechProgress: Double = 0.0
    private(set) var currentWordRange: NSRange?

    // MARK: - Configuration
    var preferredVoice: AVSpeechSynthesisVoice?
    var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower for clarity
    var speechVolume: Float = 0.8
    var autoPlayEnabled: Bool = true // Auto-play assistant responses
    private var personalVoiceAuthorized: Bool = false

    // MARK: - Initialization
    override init() {
        super.init()
        setupSpeechSynthesizer()
        configureAudioSession()
        loadUserPreferences()
        handleApplicationStateChanges()
        requestPersonalVoiceAuthorization()
        print("🔊 MessageTTSManager initialized - Privacy-first on-device TTS ready")
    }

    private func requestPersonalVoiceAuthorization() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch status {
                case .authorized:
                    self.personalVoiceAuthorized = true
                    print("✅ Personal Voice authorized")
                    self.updatePreferredVoiceToPersonal()
                case .denied:
                    print("⚠️ Personal Voice denied")
                case .notDetermined:
                    print("⚠️ Personal Voice not determined")
                case .unsupported:
                    print("⚠️ Personal Voice unsupported on this device")
                @unknown default:
                    print("⚠️ Personal Voice unknown status")
                }
            }
        }
    }

    private func updatePreferredVoiceToPersonal() {
        let personalVoices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.voiceTraits.contains(.isPersonalVoice)
        }

        if let personalVoice = personalVoices.first {
            preferredVoice = personalVoice
            UserDefaults.standard.set(personalVoice.identifier, forKey: "preferred_tts_voice")
            print("✅ Using Personal Voice: \(personalVoice.name)")
        } else {
            print("⚠️ No Personal Voice found on device")
        }
    }

    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
    }

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // Configure for playback with spoken audio optimization
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay]
            )

            // Activate the session
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Register for interruption notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )

            // Register for route change notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioSessionRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )

            print("✅ Audio session configured for TTS playback")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }

    private func loadUserPreferences() {
        // Load saved voice preference
        if let voiceIdentifier = UserDefaults.standard.string(forKey: "preferred_tts_voice") {
            preferredVoice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        }

        // Load rate preference
        speechRate = UserDefaults.standard.object(forKey: "tts_speech_rate") as? Float ??
                    (AVSpeechUtteranceDefaultSpeechRate * 0.9)

        // Ensure rate is within acceptable bounds
        speechRate = max(AVSpeechUtteranceMinimumSpeechRate,
                        min(AVSpeechUtteranceMaximumSpeechRate, speechRate))
    }

    // MARK: - Public Interface
    func speakMessage(_ message: ConversationMessage) {
        guard !message.isUser else {
            print("⚠️ Skipping user message - TTS only for assistant messages")
            return
        }

        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        // Reset state
        resetSpeechState()

        // Prepare new utterance
        let utterance = createUtterance(from: message.content)
        currentUtterance = utterance
        currentSpeakingMessageId = message.id

        // Calculate word boundaries for progress tracking
        calculateWordRanges(for: message.content)

        // Update state
        withAnimation(.easeInOut(duration: 0.3)) {
            isCurrentlySpeaking = true
            speechProgress = 0.0
        }

        // Start speaking
        speechSynthesizer.speak(utterance)
        print("🗣️ Speaking message: \(message.id)")
    }

    func pauseSpeech() {
        speechSynthesizer.pauseSpeaking(at: .word)
        print("⏸️ Speech paused")
    }

    func resumeSpeech() {
        speechSynthesizer.continueSpeaking()
        print("▶️ Speech resumed")
    }

    func stopSpeech() {
        speechSynthesizer.stopSpeaking(at: .word)
        print("⏹️ Speech stopped")
    }

    func isMessageCurrentlyPlaying(_ messageId: UUID) -> Bool {
        return currentSpeakingMessageId == messageId && isCurrentlySpeaking
    }

    // MARK: - Private Methods
    private func createUtterance(from text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)

        // Set voice preference
        if let preferredVoice = preferredVoice {
            utterance.voice = preferredVoice
        } else {
            utterance.voice = selectOptimalVoice()
        }

        utterance.rate = speechRate
        utterance.volume = speechVolume
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.1

        return utterance
    }

    private func selectOptimalVoice() -> AVSpeechSynthesisVoice? {
        let currentLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()

        // Prefer enhanced quality voices (on-device only)
        let enhancedVoice = availableVoices.first { voice in
            voice.language.hasPrefix(currentLanguage) && voice.quality == .enhanced
        }

        if let enhancedVoice = enhancedVoice {
            return enhancedVoice
        }

        // Fallback to default quality
        return availableVoices.first { voice in
            voice.language.hasPrefix(currentLanguage)
        } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func calculateWordRanges(for text: String) {
        wordRanges.removeAll()
        totalCharacters = text.count

        let words = text.components(separatedBy: .whitespacesAndNewlines)
        var currentIndex = 0

        for word in words {
            let range = NSRange(location: currentIndex, length: word.count)
            wordRanges.append(range)
            currentIndex += word.count + 1 // +1 for space
        }
    }

    private func resetSpeechState() {
        currentUtterance = nil
        currentWordRange = nil
        speechProgress = 0.0
        wordRanges.removeAll()
        totalCharacters = 0
    }

    // MARK: - Audio Session Interruption Handling
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began - pause speech
            if speechSynthesizer.isSpeaking {
                speechSynthesizer.pauseSpeaking(at: .immediate)
                print("⚠️ TTS interrupted")
            }

        case .ended:
            // Interruption ended - check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && !speechSynthesizer.isSpeaking {
                    speechSynthesizer.continueSpeaking()
                    print("▶️ TTS resumed after interruption")
                }
            }
        @unknown default:
            break
        }
    }

    @objc private func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Audio device was disconnected - stop speech
            speechSynthesizer.stopSpeaking(at: .immediate)
            print("⚠️ Audio device disconnected - TTS stopped")

        case .newDeviceAvailable:
            // New audio device connected - continue with current settings
            print("🔊 New audio device connected")
            break

        default:
            break
        }
    }

    // MARK: - Application Lifecycle Handling
    private func handleApplicationStateChanges() {
        // Handle app backgrounding
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }

        // Handle app foregrounding
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }

        // Handle app termination
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cleanup()
        }
    }

    private func handleAppDidEnterBackground() {
        // Pause speech when app enters background
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.pauseSpeaking(at: .word)
        }

        // Deactivate audio session to allow other apps
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session on backgrounding: \(error)")
        }
    }

    private func handleAppWillEnterForeground() {
        // Reactivate audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Resume speech if it was paused
            if speechSynthesizer.isPaused {
                speechSynthesizer.continueSpeaking()
            }
        } catch {
            print("⚠️ Failed to reactivate audio session on foregrounding: \(error)")
        }
    }

    // MARK: - Cleanup
    func cleanup() {
        speechSynthesizer.stopSpeaking(at: .immediate)

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ Failed to deactivate audio session during cleanup: \(error)")
        }

        NotificationCenter.default.removeObserver(self)
        print("🧹 MessageTTSManager cleaned up")
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension MessageTTSManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isCurrentlySpeaking = true
            print("▶️ Speech started")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.5)) {
                isCurrentlySpeaking = false
                currentSpeakingMessageId = nil
                speechProgress = 1.0
            }

            // Reset progress after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.speechProgress = 0.0
            }

            print("✅ Speech finished")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.3)) {
                isCurrentlySpeaking = false
                currentSpeakingMessageId = nil
                speechProgress = 0.0
            }
            print("⏹️ Speech cancelled")
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in
            currentWordRange = characterRange

            // Calculate progress based on character position
            if totalCharacters > 0 {
                let progress = Double(characterRange.location + characterRange.length) / Double(totalCharacters)
                withAnimation(.linear(duration: 0.1)) {
                    speechProgress = min(progress, 1.0)
                }
            }
        }
    }
}
