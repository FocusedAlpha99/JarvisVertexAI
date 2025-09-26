//
//  NotificationNames.swift
//  JarvisVertexAI
//
//  Centralized notification names for all app components
//  Provides consistent notification handling across UI views and services
//

import Foundation

// MARK: - Notification Names Extension

extension Notification.Name {

    // MARK: - Audio Session (Mode 1: Native Audio)

    /// Posted when AudioSession connects to Gemini Live API
    static let audioSessionConnected = Notification.Name("audioSessionConnected")

    /// Posted when AudioSession disconnects from Gemini Live API
    static let audioSessionDisconnected = Notification.Name("audioSessionDisconnected")

    /// Posted when AudioSession receives a transcript
    static let audioSessionTranscript = Notification.Name("audioSessionTranscript")

    /// Posted when AudioSession receives audio response
    static let audioSessionAudioResponse = Notification.Name("audioSessionAudioResponse")

    /// Posted when AudioSession detects audio level changes
    static let audioSessionAudioLevel = Notification.Name("audioSessionAudioLevel")

    /// Posted when AudioSession encounters an error
    static let audioSessionError = Notification.Name("audioSessionError")

    // MARK: - Voice Chat Local (Mode 2: STT/TTS)

    /// Posted when LocalSTTTTS connects to Gemini Live API
    static let voiceChatConnected = Notification.Name("voiceChatConnected")

    /// Posted when LocalSTTTTS disconnects from Gemini Live API
    static let voiceChatDisconnected = Notification.Name("voiceChatDisconnected")

    /// Posted when LocalSTTTTS receives a transcript
    static let voiceChatTranscript = Notification.Name("voiceChatTranscript")

    /// Posted when LocalSTTTTS receives audio response
    static let voiceChatAudioResponse = Notification.Name("voiceChatAudioResponse")

    /// Posted when LocalSTTTTS detects audio level changes with VAD
    static let voiceChatAudioLevel = Notification.Name("voiceChatAudioLevel")

    /// Posted when LocalSTTTTS encounters an error
    static let voiceChatError = Notification.Name("voiceChatError")

    /// Posted when STT starts processing
    static let sttStarted = Notification.Name("sttStarted")

    /// Posted when STT finishes processing
    static let sttFinished = Notification.Name("sttFinished")

    /// Posted when TTS starts playback
    static let ttsStarted = Notification.Name("ttsStarted")

    /// Posted when TTS finishes playback
    static let ttsFinished = Notification.Name("ttsFinished")

    // MARK: - Text Multimodal (Mode 3: Text + Files)

    /// Posted when a multimodal message is sent
    static let multimodalMessageSent = Notification.Name("multimodalMessageSent")

    /// Posted when a multimodal response is received
    static let multimodalResponseReceived = Notification.Name("multimodalResponseReceived")

    /// Posted when a file is uploaded
    static let multimodalFileUploaded = Notification.Name("multimodalFileUploaded")

    /// Posted when a file is deleted/removed
    static let multimodalFileDeleted = Notification.Name("multimodalFileDeleted")

    /// Posted when multimodal processing starts
    static let multimodalProcessingStarted = Notification.Name("multimodalProcessingStarted")

    /// Posted when multimodal processing finishes
    static let multimodalProcessingFinished = Notification.Name("multimodalProcessingFinished")

    /// Posted when multimodal processing encounters an error
    static let multimodalError = Notification.Name("multimodalError")

    // MARK: - Permission & System

    /// Posted when microphone permission status changes
    static let microphonePermissionChanged = Notification.Name("microphonePermissionChanged")

    /// Posted when speech recognition permission status changes
    static let speechRecognitionPermissionChanged = Notification.Name("speechRecognitionPermissionChanged")

    /// Posted when app configuration is validated
    static let configurationValidated = Notification.Name("configurationValidated")

    /// Posted when app configuration validation fails
    static let configurationValidationFailed = Notification.Name("configurationValidationFailed")

    /// Posted when app enters error state
    static let appErrorStateEntered = Notification.Name("appErrorStateEntered")

    /// Posted when app recovers from error state
    static let appErrorStateRecovered = Notification.Name("appErrorStateRecovered")

    // MARK: - Privacy & Compliance

    /// Posted when PHI is detected and redacted
    static let phiRedacted = Notification.Name("phiRedacted")

    /// Posted when audit event is logged
    static let auditEventLogged = Notification.Name("auditEventLogged")

    /// Posted when ephemeral data is cleaned up
    static let ephemeralDataCleaned = Notification.Name("ephemeralDataCleaned")

    // MARK: - Database & Storage

    /// Posted when a new session is created
    static let sessionCreated = Notification.Name("sessionCreated")

    /// Posted when a session is ended
    static let sessionEnded = Notification.Name("sessionEnded")

    /// Posted when conversation history is updated
    static let conversationHistoryUpdated = Notification.Name("conversationHistoryUpdated")

    /// Posted when local storage is cleared
    static let localStorageCleared = Notification.Name("localStorageCleared")
}

// MARK: - Notification UserInfo Keys

/// Keys for notification userInfo dictionaries
enum NotificationUserInfoKeys {

    // MARK: - Common Keys

    static let sessionId = "sessionId"
    static let timestamp = "timestamp"
    static let error = "error"
    static let errorMessage = "errorMessage"

    // MARK: - Audio Keys

    static let audioLevel = "audioLevel"
    static let audioData = "audioData"
    static let speaking = "speaking"
    static let duration = "duration"

    // MARK: - Transcript Keys

    static let text = "text"
    static let speaker = "speaker"
    static let wasRedacted = "wasRedacted"
    static let confidence = "confidence"
    static let language = "language"

    // MARK: - File Keys

    static let fileData = "fileData"
    static let fileName = "fileName"
    static let fileType = "fileType"
    static let fileSize = "fileSize"

    // MARK: - Permission Keys

    static let permissionStatus = "permissionStatus"
    static let permissionType = "permissionType"

    // MARK: - Configuration Keys

    static let configurationStatus = "configurationStatus"
    static let validationErrors = "validationErrors"
    static let authMethod = "authMethod"

    // MARK: - Privacy Keys

    static let redactionReason = "redactionReason"
    static let originalText = "originalText"
    static let redactedText = "redactedText"
}

// MARK: - Notification Helper Extensions

extension NotificationCenter {

    /// Post notification with common userInfo structure
    func post(name: Notification.Name,
              sessionId: String? = nil,
              error: Error? = nil,
              userInfo: [String: Any] = [:]) {
        var info = userInfo
        info[NotificationUserInfoKeys.timestamp] = Date()

        if let sessionId = sessionId {
            info[NotificationUserInfoKeys.sessionId] = sessionId
        }

        if let error = error {
            info[NotificationUserInfoKeys.error] = error
            info[NotificationUserInfoKeys.errorMessage] = error.localizedDescription
        }

        self.post(name: name, object: nil, userInfo: info)
    }

    /// Post audio level notification
    func postAudioLevel(_ level: Float,
                       speaking: Bool,
                       for mode: AudioMode) {
        let notificationName: Notification.Name
        switch mode {
        case .audioSession:
            notificationName = .audioSessionAudioLevel
        case .voiceChat:
            notificationName = .voiceChatAudioLevel
        }

        post(name: notificationName, userInfo: [
            NotificationUserInfoKeys.audioLevel: level,
            NotificationUserInfoKeys.speaking: speaking
        ])
    }

    /// Post transcript notification
    func postTranscript(_ text: String,
                       speaker: String,
                       wasRedacted: Bool = false,
                       for mode: AudioMode,
                       sessionId: String? = nil) {
        let notificationName: Notification.Name
        switch mode {
        case .audioSession:
            notificationName = .audioSessionTranscript
        case .voiceChat:
            notificationName = .voiceChatTranscript
        }

        post(name: notificationName, sessionId: sessionId, userInfo: [
            NotificationUserInfoKeys.text: text,
            NotificationUserInfoKeys.speaker: speaker,
            NotificationUserInfoKeys.wasRedacted: wasRedacted
        ])
    }

    /// Post error notification
    func postError(_ error: Error,
                   for mode: AudioMode,
                   sessionId: String? = nil) {
        let notificationName: Notification.Name
        switch mode {
        case .audioSession:
            notificationName = .audioSessionError
        case .voiceChat:
            notificationName = .voiceChatError
        }

        post(name: notificationName, sessionId: sessionId, error: error)
    }

    /// Post permission change notification
    func postPermissionChange(type: PermissionType,
                             status: PermissionStatus) {
        let notificationName: Notification.Name
        switch type {
        case .microphone:
            notificationName = .microphonePermissionChanged
        case .speechRecognition:
            notificationName = .speechRecognitionPermissionChanged
        }

        post(name: notificationName, userInfo: [
            NotificationUserInfoKeys.permissionType: type.rawValue,
            NotificationUserInfoKeys.permissionStatus: status.rawValue
        ])
    }
}

// MARK: - Supporting Enums

enum AudioMode {
    case audioSession
    case voiceChat
}

enum PermissionType: String {
    case microphone = "microphone"
    case speechRecognition = "speechRecognition"
}

enum PermissionStatus: String {
    case authorized = "authorized"
    case denied = "denied"
    case notDetermined = "notDetermined"
    case restricted = "restricted"
}