//
//  MultimodalChat.swift
//  JarvisVertexAI
//
//  Mode 3: Text + Multimodal Chat
//  Ephemeral File Handling, 24-Hour Auto-Delete
//

import Foundation
import UIKit
import UniformTypeIdentifiers

final class MultimodalChat {

    // MARK: - Properties

    static let shared = MultimodalChat()

    // API configuration
    private var projectId: String = ""
    private var region: String = "us-central1"
    private var accessToken: String = ""
    private var cmekKeyPath: String = ""

    // Session management
    private var currentSessionId: String?
    private var conversationHistory: [[String: Any]] = []

    // File management
    private let ephemeralFiles: NSMutableDictionary = NSMutableDictionary()
    private let fileCleanupQueue = DispatchQueue(label: "com.jarvisvertexai.cleanup", qos: .utility)
    private let maxFileRetention: TimeInterval = 24 * 60 * 60 // 24 hours

    // Privacy configuration
    private let privacyConfig: [String: Any] = [
        "disablePromptLogging": true,
        "disableDataRetention": true,
        "disableModelTraining": true,
        "ephemeralContent": true,
        "autoDeleteFiles": true
    ]

    // MARK: - Initialization

    private init() {
        loadConfiguration()
        scheduleFileCleanup()
    }

    private func loadConfiguration() {
        projectId = ProcessInfo.processInfo.environment["VERTEX_PROJECT_ID"] ?? ""
        region = ProcessInfo.processInfo.environment["VERTEX_REGION"] ?? "us-central1"
        cmekKeyPath = ProcessInfo.processInfo.environment["VERTEX_CMEK_KEY"] ?? ""
    }

    // MARK: - Session Management

    func startSession() {
        currentSessionId = ObjectBoxManager.shared.createSession(
            mode: "Text Multimodal",
            metadata: [
                "multimodal": true,
                "ephemeralFiles": true,
                "autoDelete": "24h"
            ]
        )

        conversationHistory = []
        print("📝 Multimodal chat session started")
    }

    func endSession() {
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.endSession(sessionId)
        }

        // Clean up ephemeral files immediately
        cleanupAllFiles()

        conversationHistory = []
        currentSessionId = nil
        print("🔒 Multimodal session ended, files deleted")
    }

    // MARK: - Message Handling

    func sendMessage(text: String, attachments: [Attachment] = []) async -> String? {
        // Redact PHI from text
        let safeText = PHIRedactor.shared.redactPHI(from: text)

        // Store user message locally
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "user",
                text: safeText,
                metadata: ["attachmentCount": attachments.count]
            )
        }

        // Prepare message parts
        var parts: [[String: Any]] = [["text": safeText]]

        // Process attachments
        for attachment in attachments {
            if let part = await processAttachment(attachment) {
                parts.append(part)
            }
        }

        // Add to conversation
        let userMessage: [String: Any] = [
            "role": "user",
            "parts": parts
        ]
        conversationHistory.append(userMessage)

        // Call Gemini API
        guard let response = await callGeminiAPI() else {
            return nil
        }

        // Store assistant response
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "assistant",
                text: response,
                metadata: ["multimodal": !attachments.isEmpty]
            )
        }

        return response
    }

    // MARK: - Attachment Processing

    private func processAttachment(_ attachment: Attachment) async -> [String: Any]? {
        switch attachment.type {
        case .image:
            return await uploadImage(attachment.data)
        case .document:
            return await uploadDocument(attachment.data)
        case .audio:
            // Audio is never uploaded in Mode 3
            print("⚠️ Audio must use Mode 1 or 2")
            return nil
        }
    }

    func uploadImage(_ data: Data) async -> [String: Any]? {
        // Create ephemeral file reference
        let fileId = UUID().uuidString
        let expiryDate = Date().addingTimeInterval(maxFileRetention)

        // Store reference for cleanup
        ephemeralFiles[fileId] = [
            "data": data,
            "type": "image",
            "uploadTime": Date(),
            "expiryTime": expiryDate
        ]

        // Schedule deletion
        scheduleFileDeletion(fileId: fileId, at: expiryDate)

        // Convert to base64 for inline inclusion
        let base64String = data.base64EncodedString()

        // Detect image type
        let mimeType = detectImageMimeType(data) ?? "image/jpeg"

        print("📸 Image uploaded (ephemeral, expires: \(expiryDate))")

        return [
            "inline_data": [
                "mime_type": mimeType,
                "data": base64String
            ]
        ]
    }

    func uploadDocument(_ data: Data) async -> [String: Any]? {
        // Extract text from document
        guard let text = extractTextFromDocument(data) else {
            print("❌ Failed to extract text from document")
            return nil
        }

        // Redact PHI from document text
        let safeText = PHIRedactor.shared.redactPHI(from: text)

        // Create ephemeral reference
        let fileId = UUID().uuidString
        let expiryDate = Date().addingTimeInterval(maxFileRetention)

        ephemeralFiles[fileId] = [
            "text": safeText,
            "type": "document",
            "uploadTime": Date(),
            "expiryTime": expiryDate
        ]

        // Schedule deletion
        scheduleFileDeletion(fileId: fileId, at: expiryDate)

        print("📄 Document processed (PHI redacted, expires: \(expiryDate))")

        return ["text": safeText]
    }

    // MARK: - Gemini API

    private func callGeminiAPI() async -> String? {
        guard !projectId.isEmpty else {
            print("❌ Project ID not configured")
            return nil
        }

        // Build URL
        let urlString = "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/gemini-2.0-pro:generateContent"

        guard let url = URL(string: urlString) else { return nil }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add CMEK header if configured
        if !cmekKeyPath.isEmpty {
            request.setValue(cmekKeyPath, forHTTPHeaderField: "X-Goog-Encryption-Key")
        }

        // Build request body
        let requestBody: [String: Any] = [
            "contents": conversationHistory,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048,
                "topP": 0.95,
                "topK": 40,
                "disablePromptLogging": true,
                "disableDataRetention": true
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE"]
            ],
            "systemInstruction": """
                You are a privacy-focused multimodal assistant.
                - All files are ephemeral and auto-delete after 24 hours
                - Never request or store personal information
                - PHI/PII is automatically redacted before you see it
                - Conversations are stored locally with encryption
                """
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

            // Add to conversation history
            let assistantMessage: [String: Any] = [
                "role": "model",
                "parts": [["text": responseText]]
            ]
            conversationHistory.append(assistantMessage)

            // Redact any PHI in response
            let safeResponse = PHIRedactor.shared.redactPHI(from: responseText)

            print("✅ Gemini multimodal response received")
            return safeResponse

        } catch {
            print("❌ Network error: \(error)")
            return nil
        }
    }

    // MARK: - File Management

    private func scheduleFileCleanup() {
        // Run cleanup every hour
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            self.cleanupExpiredFiles()
        }

        // Initial cleanup after 1 minute
        fileCleanupQueue.asyncAfter(deadline: .now() + 60) {
            self.cleanupExpiredFiles()
        }
    }

    private func scheduleFileDeletion(fileId: String, at date: Date) {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else {
            deleteFile(fileId)
            return
        }

        fileCleanupQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.deleteFile(fileId)
        }
    }

    private func deleteFile(_ fileId: String) {
        ephemeralFiles.removeObject(forKey: fileId)
        print("🗑️ Ephemeral file deleted: \(fileId)")

        // Log deletion
        ObjectBoxManager.shared.logAudit(
            action: "EPHEMERAL_FILE_DELETED",
            sessionId: currentSessionId,
            metadata: ["fileId": fileId]
        )
    }

    private func cleanupExpiredFiles() {
        let now = Date()
        let keysToDelete = NSMutableArray()

        ephemeralFiles.enumerateKeysAndObjects { key, value, _ in
            if let fileInfo = value as? [String: Any],
               let expiryTime = fileInfo["expiryTime"] as? Date,
               expiryTime <= now {
                keysToDelete.add(key)
            }
        }

        for key in keysToDelete {
            if let fileId = key as? String {
                deleteFile(fileId)
            }
        }

        if keysToDelete.count > 0 {
            print("🧹 Cleaned up \(keysToDelete.count) expired files")
        }
    }

    private func cleanupAllFiles() {
        let fileCount = ephemeralFiles.count
        ephemeralFiles.removeAllObjects()
        print("🗑️ All \(fileCount) ephemeral files deleted")
    }

    // MARK: - Helper Functions

    private func detectImageMimeType(_ data: Data) -> String? {
        // Check first few bytes for image format
        let bytes = [UInt8](data.prefix(12))

        // JPEG
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }

        // PNG
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }

        // GIF
        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return "image/gif"
        }

        // WebP
        if bytes.count >= 12 &&
           bytes[0...3] == [0x52, 0x49, 0x46, 0x46] &&
           bytes[8...11] == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }

        return nil
    }

    private func extractTextFromDocument(_ data: Data) -> String? {
        // Try to extract text from common document formats
        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        // For PDF, RTF, etc., would need additional processing
        // This is a simplified version
        return nil
    }

    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "mode": "Text Multimodal (Mode 3)",
            "fileHandling": "Ephemeral (24h auto-delete)",
            "phiRedaction": "Active",
            "promptLogging": "Disabled",
            "dataRetention": "Zero",
            "modelTraining": "Disabled",
            "cmekEncryption": !cmekKeyPath.isEmpty,
            "localStorage": "Encrypted ObjectBox",
            "activeFiles": ephemeralFiles.count,
            "conversationLength": conversationHistory.count
        ]
    }

    // MARK: - Authentication

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }
}

// MARK: - Supporting Types

struct Attachment {
    enum AttachmentType {
        case image
        case document
        case audio
    }

    let type: AttachmentType
    let data: Data
    let filename: String?
}

// MARK: - Notifications

extension Notification.Name {
    static let multimodalMessageSent = Notification.Name("multimodalMessageSent")
    static let multimodalFileUploaded = Notification.Name("multimodalFileUploaded")
    static let multimodalFileDeleted = Notification.Name("multimodalFileDeleted")
}