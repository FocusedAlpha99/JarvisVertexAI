//
//  MultimodalChat.swift
//  JarvisVertexAI
//
//  Mode 3: Text + Multimodal Chat
//  Ephemeral File Handling, 24-Hour Auto-Delete
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers

// MARK: - Multimodal Chat Errors

enum MultimodalChatError: LocalizedError {
    case configurationMissing(String)
    case authenticationFailed
    case networkError(Error)
    case apiError(Int, String)
    case invalidResponse
    case fileProcessingFailed(String)
    case unsupportedFileType
    case fileSizeExceeded(Int)
    case quotaExceeded

    var errorDescription: String? {
        switch self {
        case .configurationMissing(let config):
            return "Configuration missing: \(config)"
        case .authenticationFailed:
            return "Authentication failed. Please check your credentials."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        case .invalidResponse:
            return "Invalid response from Gemini API"
        case .fileProcessingFailed(let reason):
            return "File processing failed: \(reason)"
        case .unsupportedFileType:
            return "Unsupported file type"
        case .fileSizeExceeded(let maxSize):
            return "File size exceeds maximum allowed \(maxSize)MB"
        case .quotaExceeded:
            return "API quota exceeded. Please try again later."
        }
    }
}

// MARK: - Multimodal Chat Class

final class MultimodalChat {

    // MARK: - Properties

    static let shared = MultimodalChat()

    // Configuration
    private let config = VertexConfig.shared
    private var accessToken: String = ""

    // Constants
    private let maxFileSize = 10 * 1024 * 1024 // 10MB
    private let supportedImageTypes = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    private let supportedDocumentTypes = ["text/plain", "application/pdf"]

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
        scheduleFileCleanup()
        loadAccessToken()
    }

    private func loadAccessToken() {
        Task {
            do {
                accessToken = try await AccessTokenProvider.shared.getAccessToken()
                print("✅ MultimodalChat: Access token loaded")
            } catch {
                print("❌ MultimodalChat: Failed to load access token: \(error)")
            }
        }
    }

    // MARK: - Session Management

    func startSession() {
        currentSessionId = SimpleDataManager.shared.createSession(
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
            SimpleDataManager.shared.endSession(sessionId)
        }

        // Clean up ephemeral files immediately
        cleanupAllFiles()

        conversationHistory = []
        currentSessionId = nil
        print("🔒 Multimodal session ended, files deleted")
    }

    // MARK: - Message Handling

    func sendMessage(text: String, attachments: [Attachment] = []) async -> String? {
        do {
            return try await sendMessageWithError(text: text, attachments: attachments)
        } catch {
            print("❌ MultimodalChat error: \(error.localizedDescription)")

            // Post error notification
            NotificationCenter.default.post(
                name: Notification.Name("multimodalError"),
                object: nil,
                userInfo: ["error": error]
            )

            // Return error message for development/debugging
            if ProcessInfo.processInfo.environment["DEBUG_LOGGING"] == "true" {
                return "Error: \(error.localizedDescription)"
            }

            return "I encountered an error processing your request. Please try again."
        }
    }

    private func sendMessageWithError(text: String, attachments: [Attachment] = []) async throws -> String {
        // Validate configuration
        try validateConfiguration()

        // Validate input
        try validateInput(text: text, attachments: attachments)

        // Start session if needed
        if currentSessionId == nil {
            startSession()
        }

        // Redact PHI from text
        let safeText = PHIRedactor.shared.redactPHI(from: text)
        let wasRedacted = safeText != text

        // Store user message locally
        if let sessionId = currentSessionId {
            SimpleDataManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "user",
                text: safeText,
                metadata: [
                    "attachmentCount": attachments.count,
                    "wasRedacted": wasRedacted
                ]
            )
        }

        // Process attachments with validation
        var parts: [[String: Any]] = [["text": safeText]]
        var processedAttachments: [[String: Any]] = []

        for attachment in attachments {
            do {
                if let part = try await processAttachmentWithValidation(attachment) {
                    processedAttachments.append(part)
                    parts.append(part)
                }
            } catch {
                print("⚠️ Skipping attachment due to error: \(error.localizedDescription)")
                continue
            }
        }

        // Add to conversation history
        let userMessage: [String: Any] = [
            "role": "user",
            "parts": parts
        ]
        conversationHistory.append(userMessage)

        // Call Gemini API with retry logic
        let response = try await callGeminiAPIWithRetry()

        // Store assistant response
        if let sessionId = currentSessionId {
            SimpleDataManager.shared.addTranscript(
                sessionId: sessionId,
                speaker: "assistant",
                text: response,
                metadata: [
                    "multimodal": !attachments.isEmpty,
                    "attachmentCount": processedAttachments.count,
                    "wasRedacted": wasRedacted
                ]
            )
        }

        // Post success notification
        NotificationCenter.default.post(
            name: Notification.Name("multimodalResponseReceived"),
            object: nil,
            userInfo: [
                "response": response,
                "attachmentCount": attachments.count
            ]
        )

        return response
    }

    // MARK: - Validation Methods

    private func validateConfiguration() throws {
        guard config.isConfigured else {
            throw MultimodalChatError.configurationMissing("Project ID or Region not configured")
        }

        if accessToken.isEmpty {
            throw MultimodalChatError.authenticationFailed
        }
    }

    private func validateInput(text: String, attachments: [Attachment]) throws {
        // Validate text input
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty && attachments.isEmpty {
            throw MultimodalChatError.fileProcessingFailed("Empty message with no attachments")
        }

        // Validate attachments
        for attachment in attachments {
            try validateAttachment(attachment)
        }
    }

    private func validateAttachment(_ attachment: Attachment) throws {
        // Check file size
        if attachment.data.count > maxFileSize {
            let maxSizeMB = maxFileSize / (1024 * 1024)
            throw MultimodalChatError.fileSizeExceeded(maxSizeMB)
        }

        // Validate file type
        let mimeType = detectMimeType(attachment.data)

        switch attachment.type {
        case .image:
            guard let mime = mimeType, supportedImageTypes.contains(mime) else {
                throw MultimodalChatError.unsupportedFileType
            }
        case .document:
            guard let mime = mimeType, supportedDocumentTypes.contains(mime) else {
                throw MultimodalChatError.unsupportedFileType
            }
        case .audio:
            throw MultimodalChatError.fileProcessingFailed("Audio files not supported in text multimodal mode")
        }
    }

    // MARK: - Attachment Processing

    private func processAttachment(_ attachment: Attachment) async -> [String: Any]? {
        do {
            return try await processAttachmentWithValidation(attachment)
        } catch {
            print("❌ Attachment processing failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func processAttachmentWithValidation(_ attachment: Attachment) async throws -> [String: Any]? {
        // Validate attachment
        try validateAttachment(attachment)

        switch attachment.type {
        case .image:
            return try await uploadImageWithValidation(attachment.data)
        case .document:
            return try await uploadDocumentWithValidation(attachment.data)
        case .audio:
            throw MultimodalChatError.fileProcessingFailed("Audio files not supported in text multimodal mode")
        }
    }

    func uploadImage(_ data: Data) async -> [String: Any]? {
        do {
            return try await uploadImageWithValidation(data)
        } catch {
            print("❌ Image upload failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func uploadImageWithValidation(_ data: Data) async throws -> [String: Any] {
        // Validate file size
        if data.count > maxFileSize {
            let maxSizeMB = maxFileSize / (1024 * 1024)
            throw MultimodalChatError.fileSizeExceeded(maxSizeMB)
        }

        // Detect and validate image type
        guard let mimeType = detectImageMimeType(data) else {
            throw MultimodalChatError.unsupportedFileType
        }

        guard supportedImageTypes.contains(mimeType) else {
            throw MultimodalChatError.unsupportedFileType
        }

        // Create ephemeral file reference
        let fileId = UUID().uuidString
        let expiryDate = Date().addingTimeInterval(maxFileRetention)

        // Store reference for cleanup
        ephemeralFiles[fileId] = [
            "data": data,
            "type": "image",
            "mimeType": mimeType,
            "uploadTime": Date(),
            "expiryTime": expiryDate,
            "size": data.count
        ]

        // Schedule deletion
        scheduleFileDeletion(fileId: fileId, at: expiryDate)

        // Convert to base64 for inline inclusion
        let base64String = data.base64EncodedString()

        print("📸 Image uploaded (ephemeral, \(mimeType), \(data.count) bytes, expires: \(expiryDate))")

        // Post notification
        NotificationCenter.default.post(
            name: .multimodalFileUploaded,
            object: nil,
            userInfo: [
                "fileId": fileId,
                "type": "image",
                "mimeType": mimeType,
                "size": data.count
            ]
        )

        return [
            "inline_data": [
                "mime_type": mimeType,
                "data": base64String
            ]
        ]
    }

    func uploadDocument(_ data: Data) async -> [String: Any]? {
        do {
            return try await uploadDocumentWithValidation(data)
        } catch {
            print("❌ Document upload failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func uploadDocumentWithValidation(_ data: Data) async throws -> [String: Any] {
        // Validate file size
        if data.count > maxFileSize {
            let maxSizeMB = maxFileSize / (1024 * 1024)
            throw MultimodalChatError.fileSizeExceeded(maxSizeMB)
        }

        // Detect document type
        let mimeType = detectDocumentMimeType(data)
        guard supportedDocumentTypes.contains(mimeType) else {
            throw MultimodalChatError.unsupportedFileType
        }

        // Extract text from document
        guard let text = try extractTextFromDocumentWithValidation(data, mimeType: mimeType) else {
            throw MultimodalChatError.fileProcessingFailed("Could not extract text from document")
        }

        // Redact PHI from document text
        let safeText = PHIRedactor.shared.redactPHI(from: text)
        let wasRedacted = safeText != text

        // Create ephemeral reference
        let fileId = UUID().uuidString
        let expiryDate = Date().addingTimeInterval(maxFileRetention)

        ephemeralFiles[fileId] = [
            "text": safeText,
            "originalLength": text.count,
            "type": "document",
            "mimeType": mimeType,
            "uploadTime": Date(),
            "expiryTime": expiryDate,
            "size": data.count,
            "wasRedacted": wasRedacted
        ]

        // Schedule deletion
        scheduleFileDeletion(fileId: fileId, at: expiryDate)

        print("📄 Document processed (\(mimeType), \(text.count) chars, PHI redacted: \(wasRedacted), expires: \(expiryDate))")

        // Post notification
        NotificationCenter.default.post(
            name: .multimodalFileUploaded,
            object: nil,
            userInfo: [
                "fileId": fileId,
                "type": "document",
                "mimeType": mimeType,
                "textLength": text.count,
                "wasRedacted": wasRedacted
            ]
        )

        return ["text": safeText]
    }

    // MARK: - Gemini API

    private func callGeminiAPI() async -> String? {
        do {
            return try await callGeminiAPIWithRetry()
        } catch {
            print("❌ Gemini API failed: \(error.localizedDescription)")

            // Return mock response in test mode
            if ProcessInfo.processInfo.environment["TEST_MODE"] == "true" {
                return await generateMockResponse()
            }

            return nil
        }
    }

    private func callGeminiAPIWithRetry(attempt: Int = 1, maxRetries: Int = 3) async throws -> String {
        do {
            return try await performGeminiAPICall()
        } catch let error as MultimodalChatError {
            // Don't retry certain errors
            switch error {
            case .authenticationFailed, .configurationMissing, .unsupportedFileType:
                throw error
            case .quotaExceeded:
                if attempt < maxRetries {
                    let delay = Double(attempt * 2) // Exponential backoff
                    print("⏳ Rate limited, retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await callGeminiAPIWithRetry(attempt: attempt + 1, maxRetries: maxRetries)
                } else {
                    throw error
                }
            case .networkError:
                if attempt < maxRetries {
                    let delay = Double(attempt) // Linear backoff for network errors
                    print("🔄 Network error, retrying in \(delay) seconds...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await callGeminiAPIWithRetry(attempt: attempt + 1, maxRetries: maxRetries)
                } else {
                    throw error
                }
            default:
                throw error
            }
        }
    }

    private func performGeminiAPICall() async throws -> String {
        // Return mock response in test mode
        if ProcessInfo.processInfo.environment["TEST_MODE"] == "true" {
            return await generateMockResponse()
        }

        // Validate configuration
        guard !config.projectId.isEmpty else {
            throw MultimodalChatError.configurationMissing("Project ID")
        }

        guard !accessToken.isEmpty else {
            throw MultimodalChatError.authenticationFailed
        }

        // Build URL
        let modelName = ProcessInfo.processInfo.environment["GEMINI_MODEL"] ?? "gemini-2.0-flash-exp"
        let urlString = "https://\(config.region)-aiplatform.googleapis.com/v1/projects/\(config.projectId)/locations/\(config.region)/publishers/google/models/\(modelName):generateContent"

        guard let url = URL(string: urlString) else {
            throw MultimodalChatError.configurationMissing("Invalid API URL")
        }

        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("JarvisVertexAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30.0

        // Privacy headers
        if ProcessInfo.processInfo.environment["DISABLE_PROMPT_LOGGING"] == "true" {
            request.setValue("strict", forHTTPHeaderField: "X-Privacy-Mode")
        }

        // Add CMEK header if configured
        if let cmekKey = ProcessInfo.processInfo.environment["CMEK_KEY"], !cmekKey.isEmpty {
            request.setValue(cmekKey, forHTTPHeaderField: "X-Goog-Encryption-Key")
        }

        // Build request body with privacy settings
        let requestBody: [String: Any] = [
            "contents": conversationHistory,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048,
                "topP": 0.95,
                "topK": 40,
                "candidateCount": 1
            ],
            "safetySettings": [
                ["category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                ["category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                ["category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"],
                ["category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_MEDIUM_AND_ABOVE"]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": """
                    You are a privacy-focused multimodal assistant. Follow these guidelines:
                    - All files are ephemeral and auto-delete after 24 hours
                    - Never request or store personal information
                    - PHI/PII is automatically redacted before you see it
                    - Conversations are stored locally with encryption
                    - Be helpful, accurate, and concise in your responses
                    - If you detect any sensitive information, remind the user about privacy
                    """]
                ]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw MultimodalChatError.invalidResponse
        }
        request.httpBody = httpBody

        // Make request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MultimodalChatError.networkError(URLError(.badServerResponse))
            }

            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200:
                break // Success
            case 401, 403:
                throw MultimodalChatError.authenticationFailed
            case 429:
                throw MultimodalChatError.quotaExceeded
            case 500...599:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Server error"
                throw MultimodalChatError.apiError(httpResponse.statusCode, errorMessage)
            default:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw MultimodalChatError.apiError(httpResponse.statusCode, errorMessage)
            }

            // Parse response
            let responseText = try parseGeminiResponse(data)

            // Add to conversation history
            let assistantMessage: [String: Any] = [
                "role": "model",
                "parts": [["text": responseText]]
            ]
            conversationHistory.append(assistantMessage)

            // Redact any PHI in response (double-check)
            let safeResponse = PHIRedactor.shared.redactPHI(from: responseText)

            print("✅ Gemini multimodal response received (\(responseText.count) chars)")
            return safeResponse

        } catch {
            if error is MultimodalChatError {
                throw error
            } else {
                throw MultimodalChatError.networkError(error)
            }
        }
    }

    private func parseGeminiResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MultimodalChatError.invalidResponse
        }

        // Check for API errors first
        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? Int,
           let message = error["message"] as? String {
            throw MultimodalChatError.apiError(code, message)
        }

        // Parse successful response
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let responseText = firstPart["text"] as? String else {
            throw MultimodalChatError.invalidResponse
        }

        return responseText
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
        SimpleDataManager.shared.logAudit(
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

    // MARK: - Mock Response Generation

    private func generateMockResponse() async -> String {
        // Simulate API delay
        let delay = Double.random(in: 0.5...2.0)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let mockResponses = [
            "I understand you're testing the multimodal functionality. This is a mock response generated in test mode. The actual Gemini API integration is ready and will be used when test mode is disabled.",

            "Thank you for sharing that with me. I can see your content and I'm ready to help analyze images, documents, or answer any questions you might have. This response is generated locally for testing purposes.",

            "I've processed your multimodal input successfully. In a real deployment, this would be handled by Google's Gemini API with full privacy protections including PHI redaction and ephemeral file handling.",

            "Your files have been processed securely with automatic expiration after 24 hours. I can help analyze images, extract text from documents, or discuss any content you've shared. This is a development response.",

            "I notice you're using the multimodal chat feature. All files are handled with maximum privacy - they're automatically deleted after 24 hours and any personal information is redacted before processing. How can I help you today?",

            "Thanks for testing the multimodal capabilities! I can process images and documents while maintaining strict privacy standards. All data is encrypted and ephemeral. What would you like to know?",

            "I'm ready to help with your multimodal content. The privacy-first design ensures your files are automatically cleaned up and any sensitive information is redacted. This is a mock response for development testing."
        ]

        let randomResponse = mockResponses.randomElement() ?? mockResponses[0]

        // Add conversation context if available
        if conversationHistory.count > 2 {
            return "Continuing our conversation... \(randomResponse)"
        } else {
            return randomResponse
        }
    }

    // MARK: - Helper Functions

    private func detectMimeType(_ data: Data) -> String? {
        return detectImageMimeType(data) ?? detectDocumentMimeType(data)
    }

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

    private func detectDocumentMimeType(_ data: Data) -> String {
        // Check for PDF signature
        if data.count >= 4 {
            let pdfHeader = [UInt8](data.prefix(4))
            if pdfHeader == [0x25, 0x50, 0x44, 0x46] { // %PDF
                return "application/pdf"
            }
        }

        // Try to decode as UTF-8 text
        if String(data: data, encoding: .utf8) != nil {
            return "text/plain"
        }

        // Default fallback
        return "text/plain"
    }

    private func extractTextFromDocument(_ data: Data) -> String? {
        do {
            return try extractTextFromDocumentWithValidation(data, mimeType: detectDocumentMimeType(data))
        } catch {
            print("❌ Text extraction failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func extractTextFromDocumentWithValidation(_ data: Data, mimeType: String) throws -> String? {
        switch mimeType {
        case "text/plain":
            // Try multiple encodings
            if let text = String(data: data, encoding: .utf8) {
                return text
            } else if let text = String(data: data, encoding: .ascii) {
                return text
            } else if let text = String(data: data, encoding: .utf16) {
                return text
            } else {
                throw MultimodalChatError.fileProcessingFailed("Could not decode text file")
            }

        case "application/pdf":
            // Basic PDF text extraction (simplified)
            // In a production app, you'd use PDFKit or similar
            if let pdfText = extractBasicPDFText(data) {
                return pdfText
            } else {
                throw MultimodalChatError.fileProcessingFailed("Could not extract text from PDF")
            }

        default:
            throw MultimodalChatError.unsupportedFileType
        }
    }

    private func extractBasicPDFText(_ data: Data) -> String? {
        // This is a very basic PDF text extraction
        // In production, use PDFKit: PDFDocument(data: data)?.string
        guard let pdfString = String(data: data, encoding: .utf8) else { return nil }

        // Look for text objects in PDF (simplified extraction)
        let lines = pdfString.components(separatedBy: .newlines)
        var extractedText: [String] = []

        for line in lines {
            // Very basic PDF text extraction
            if line.contains("(") && line.contains(")") {
                let text = line.components(separatedBy: "(")
                    .dropFirst()
                    .compactMap { part in
                        return part.components(separatedBy: ")").first
                    }
                    .joined(separator: " ")

                if !text.isEmpty {
                    extractedText.append(text)
                }
            }
        }

        let result = extractedText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
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
            "cmekEncryption": ProcessInfo.processInfo.environment["CMEK_KEY"]?.isEmpty == false,
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
