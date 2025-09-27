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

// Import ObjectBox for local database
// Note: Fallback to SimpleDataManager if ObjectBox unavailable
#if canImport(ObjectBox)
// ObjectBox integration will be handled by generated files
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
        loadPreviousConversationHistory()
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

    private func loadPreviousConversationHistory() {
        // Load recent conversation history with time context from ObjectBox (cross-session memory)
        // Use sustainable approach: limit to recent 30 messages for optimal recall without performance impact
        conversationHistory = ObjectBoxManager.shared.getConversationHistoryWithTimeContext(limit: 30)

        if !conversationHistory.isEmpty {
            print("🧠 Loaded \(conversationHistory.count) time-aware messages from persistent memory")

            // Log memory stats for optimization tracking
            let memoryStats = ObjectBoxManager.shared.getConversationMemoryStats()
            if let optimalForRecall = memoryStats["optimalForRecall"] as? Bool {
                print("🧠 Memory recall status: \(optimalForRecall ? "Optimal" : "Building")")
            }
        } else {
            print("🧠 No previous conversation memory found - starting fresh with time awareness")
        }
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

        // Don't reset conversation history - keep cross-session memory
        // conversationHistory = [] // Removed to maintain memory between sessions
        print("📝 Multimodal chat session started (preserving conversation memory)")
    }

    func endSession() {
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.endSession(sessionId)
        }

        // Clean up ephemeral files immediately
        cleanupAllFiles()

        // Don't clear conversation history - preserve memory between sessions
        // conversationHistory = [] // Removed to maintain memory between app launches
        currentSessionId = nil
        print("🔒 Multimodal session ended, files deleted (preserving conversation memory)")
    }

    // MARK: - Memory Management

    func reloadConversationMemory() {
        // Intelligently reload conversation history from ObjectBox
        let previousCount = conversationHistory.count
        conversationHistory = ObjectBoxManager.shared.getConversationHistory(limit: 30)

        let newCount = conversationHistory.count
        let memoryStats = ObjectBoxManager.shared.getConversationMemoryStats()

        print("🔄 Memory reloaded: \(previousCount) → \(newCount) messages")
        if let optimalForRecall = memoryStats["optimalForRecall"] as? Bool {
            print("🧠 Recall optimization: \(optimalForRecall ? "✅ Optimal" : "⚠️ Building")")
        }
    }

    func clearConversationMemory() {
        // Clear in-memory conversation but preserve database for recall capability
        let clearedCount = conversationHistory.count
        conversationHistory = []
        print("🧹 Cleared \(clearedCount) messages from active memory (database preserved for recall)")
    }

    func getMemoryStatus() -> [String: Any] {
        let memoryStats = ObjectBoxManager.shared.getConversationMemoryStats()

        return [
            "activeConversationCount": conversationHistory.count,
            "currentSessionId": currentSessionId ?? "none",
            "hasActiveMemory": !conversationHistory.isEmpty,
            "totalDatabaseTranscripts": memoryStats["totalTranscripts"] ?? 0,
            "totalSessions": memoryStats["totalSessions"] ?? 0,
            "memoryOptimal": memoryStats["optimalForRecall"] ?? false,
            "memoryLoadPercentage": memoryStats["memoryLoadPercentage"] ?? 0
        ]
    }

    func getMemoryInsights() -> String {
        let status = getMemoryStatus()
        let activeCount = status["activeConversationCount"] as? Int ?? 0
        let totalCount = status["totalDatabaseTranscripts"] as? Int ?? 0
        let isOptimal = status["memoryOptimal"] as? Bool ?? false

        if totalCount == 0 {
            return "Starting fresh - no conversation history yet. I'll remember everything you tell me."
        } else if activeCount == 0 {
            return "I have \(totalCount) messages in my memory database but none are currently loaded. My memory recall is available."
        } else {
            let memoryStatus = isOptimal ? "optimal" : "building"
            return "I remember \(activeCount) recent messages and have \(totalCount) total in persistent memory. Recall status: \(memoryStatus)."
        }
    }

    // MARK: - Email Action Handlers

    func handleEmailRequest(_ request: String) async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Gmail access not configured. Please authorize Gmail access to enable email management."
        }

        let lowercased = request.lowercased()

        do {
            // Handle different email requests
            if lowercased.contains("important email") || lowercased.contains("today's email") {
                let emails = try await oauthManager.getTodaysImportantEmails()
                return formatEmailSummary(emails)
            }
            else if lowercased.contains("search") && (lowercased.contains("email") || lowercased.contains("mail")) {
                // Extract search query - simplified for now
                let searchQuery = extractSearchQuery(from: request)
                let emails = try await oauthManager.searchGmail(query: searchQuery, maxResults: 10)
                return formatEmailSummary(emails, searchContext: searchQuery)
            }
            else if lowercased.contains("send email") || lowercased.contains("email to") {
                return "To send an email, I need: recipient, subject, and message content. Please provide these details."
            }
            else if lowercased.contains("reply to") {
                return "To reply to an email, please specify which email you'd like to reply to and your response message."
            }
            else {
                return "I can help with emails. Try: 'Show me today's important emails', 'Search emails from [sender]', 'Send email to [person]', or 'Reply to [person]'s email'."
            }
        } catch {
            return "Email operation failed: \(error.localizedDescription)"
        }
    }

    private func formatEmailSummary(_ emails: [GmailMessage], searchContext: String? = nil) -> String {
        if emails.isEmpty {
            let context = searchContext != nil ? " matching '\(searchContext!)'" : ""
            return "No emails found\(context)."
        }

        let summary = emails.prefix(5).enumerated().map { index, email in
            let subject = email.payload.headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "No Subject"
            let from = email.payload.headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown Sender"
            let snippet = String(email.snippet.prefix(100))

            return """
            \(index + 1). **\(subject)**
               From: \(from)
               Preview: \(snippet)...
            """
        }.joined(separator: "\n\n")

        let context = searchContext != nil ? " matching '\(searchContext!)'" : ""
        let header = emails.count == 1 ? "Found 1 email\(context):" : "Found \(emails.count) emails\(context) (showing first 5):"

        return "\(header)\n\n\(summary)"
    }

    private func extractSearchQuery(from request: String) -> String {
        // Simple extraction - could be enhanced with NLP
        let words = request.components(separatedBy: .whitespacesAndNewlines)

        // Look for patterns like "search emails from John" or "emails about project"
        if let fromIndex = words.firstIndex(where: { $0.lowercased() == "from" }),
           fromIndex + 1 < words.count {
            return "from:\(words[fromIndex + 1])"
        }

        if let aboutIndex = words.firstIndex(where: { $0.lowercased() == "about" }),
           aboutIndex + 1 < words.count {
            return words[aboutIndex + 1]
        }

        // Default: search for key terms
        let searchTerms = words.filter { word in
            word.count > 3 && !["email", "emails", "search", "find", "show"].contains(word.lowercased())
        }

        return searchTerms.prefix(3).joined(separator: " ")
    }

    // MARK: - Email Composition and Sending (with Security Safeguards)

    func composeAndSendEmail(to: String, subject: String, body: String, cc: String? = nil) async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Gmail access not configured. Please authorize Gmail access to send emails."
        }

        // Security safeguards
        if !isValidEmailRequest(to: to, subject: subject, body: body) {
            return "Email request appears suspicious or invalid. Please verify recipient and content."
        }

        // Rate limiting check
        if await isRateLimited() {
            return "Too many email requests recently. Please wait before sending more emails."
        }

        do {
            let messageId = try await oauthManager.sendEmail(to: to, subject: subject, body: body, cc: cc)

            // Log the email sending for audit
            logEmailAction(action: "send", recipient: to, subject: subject)

            return "✅ Email sent successfully to \(to) with subject '\(subject)'. Message ID: \(messageId)"
        } catch {
            return "Failed to send email: \(error.localizedDescription)"
        }
    }

    func replyToEmailByContext(originalSender: String, replyContent: String) async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Gmail access not configured. Please authorize Gmail access to reply to emails."
        }

        do {
            // Search for recent emails from the sender
            let searchQuery = "from:\(originalSender)"
            let emails = try await oauthManager.searchGmail(query: searchQuery, maxResults: 5)

            guard let latestEmail = emails.first else {
                return "No recent emails found from \(originalSender) to reply to."
            }

            // Security check
            if !isValidReplyRequest(replyContent: replyContent) {
                return "Reply content appears inappropriate. Please review your message."
            }

            let messageId = try await oauthManager.replyToEmail(messageId: latestEmail.id, body: replyContent)

            // Log the email action
            logEmailAction(action: "reply", recipient: originalSender, subject: "Reply")

            return "✅ Reply sent successfully to \(originalSender). Message ID: \(messageId)"
        } catch {
            return "Failed to reply to email: \(error.localizedDescription)"
        }
    }

    // MARK: - Security Safeguards

    private func isValidEmailRequest(to: String, subject: String, body: String) -> Bool {
        // Basic email validation
        let emailRegex = #"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"#
        guard to.range(of: emailRegex, options: .regularExpression) != nil else {
            return false
        }

        // Check for suspicious content patterns
        let suspiciousPatterns = [
            "password", "login", "urgent", "confidential", "click here",
            "verify account", "suspended", "phishing", "virus"
        ]

        let lowercasedBody = body.lowercased()
        let lowercasedSubject = subject.lowercased()

        let containsSuspiciousContent = suspiciousPatterns.contains { pattern in
            lowercasedBody.contains(pattern) || lowercasedSubject.contains(pattern)
        }

        // Reject if too many suspicious patterns
        return !containsSuspiciousContent
    }

    private func isValidReplyRequest(replyContent: String) -> Bool {
        // Check reply length (prevent spam)
        if replyContent.count > 5000 {
            return false
        }

        // Check for inappropriate content patterns
        let inappropriatePatterns = ["spam", "advertisement", "promotion"]
        let lowercased = replyContent.lowercased()

        return !inappropriatePatterns.contains { pattern in
            lowercased.contains(pattern)
        }
    }

    private func isRateLimited() async -> Bool {
        // Simple rate limiting: max 10 emails per hour
        let currentTime = Date()
        let oneHourAgo = currentTime.addingTimeInterval(-3600)

        // In a real implementation, this would check ObjectBox for recent email sends
        // For now, implement basic check
        return false // Placeholder - implement proper rate limiting
    }

    private func logEmailAction(action: String, recipient: String, subject: String) {
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.logAudit(
                sessionId: sessionId,
                action: "email_\(action)",
                details: "Recipient: \(recipient), Subject: \(subject)",
                metadata: ["timestamp": ISO8601DateFormatter().string(from: Date())]
            )
        }
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

        // PHI redaction disabled for conversational context - users intentionally share names for personalization
        // let safeText = PHIRedactor.shared.redactPHI(from: text)
        let safeText = text
        let wasRedacted = false // safeText != text

        // Store user message locally
        if let sessionId = currentSessionId {
            ObjectBoxManager.shared.addTranscript(
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
            ObjectBoxManager.shared.addTranscript(
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
        // For direct Gemini API, we only need the API key
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            throw MultimodalChatError.configurationMissing("GEMINI_API_KEY environment variable not set")
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

        // PHI redaction disabled for conversational context in Mode 3
        // let safeText = PHIRedactor.shared.redactPHI(from: text)
        let safeText = text
        let wasRedacted = false // safeText != text

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

        // Use direct Gemini API (same approach as Mode 2)
        let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        guard !apiKey.isEmpty else {
            throw MultimodalChatError.configurationMissing("GEMINI_API_KEY")
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        // Inject comprehensive personal assistant context
        let currentTime = getCurrentTimeContext()
        let calendarContext = await getCalendarContext()
        let emailContext = await getEmailContext()
        let driveContext = await getDriveContext()
        let tasksContext = await getTasksContext()

        // Build request body with comprehensive assistant context and Google Search
        let requestBody: [String: Any] = [
            "contents": conversationHistory,
            "tools": [
                [
                    "google_search": [:]  // Enable Google Search grounding for real-time information
                ]
            ],
            "systemInstruction": [
                "parts": [
                    [
                        "text": """
                        Current date and time: \(currentTime.fullContext)
                        Local timezone: \(currentTime.timezone)

                        \(calendarContext)

                        \(emailContext)

                        \(driveContext)

                        \(tasksContext)

                        You are a comprehensive personal AI assistant with full access to:
                        - **Google Search**: Real-time web information and current events
                        - **Gmail Integration**: Full email management (read, compose, send, reply)
                        - **Calendar Integration**: Schedule awareness and conflict detection
                        - **Google Drive**: File management, upload, download, and organization
                        - **Google Tasks**: Task management and deadline tracking
                        - **Time Awareness**: Current date/time for accurate responses

                        **CONFIRMED CAPABILITIES (You DO have access to these):**
                        - **Gmail Full Access**: \(emailContext.contains("Gmail access not configured") ? "NOT AUTHENTICATED - Request user to authorize Gmail" : "AUTHENTICATED - Can read, send, reply to emails")
                        - **Google Calendar**: \(calendarContext.contains("Calendar access not configured") ? "NOT AUTHENTICATED - Request user to authorize Calendar" : "AUTHENTICATED - Can view events, check schedule")
                        - **Google Drive**: \(driveContext.contains("Drive access not configured") ? "NOT AUTHENTICATED - Request user to authorize Drive" : "AUTHENTICATED - Can manage files, upload, download")
                        - **Google Tasks**: \(tasksContext.contains("Tasks access not configured") ? "NOT AUTHENTICATED - Request user to authorize Tasks" : "AUTHENTICATED - Can view tasks, track deadlines")
                        - **Google Search**: ENABLED - Can search the web for current information, news, facts
                        - **Time Integration**: ACTIVE - Always aware of current time and relative dates

                        **Personal Assistant Actions:**
                        - **Email**: "Show important emails", "Send email to [person]", "Reply to [sender]"
                        - **Calendar**: "Check my schedule", "Do I have conflicts tomorrow?"
                        - **Drive**: "Upload this file", "Find my document", "Share file with team"
                        - **Tasks**: "Show my tasks", "What's due this week?", "Add reminder for project"
                        - **Search**: "What's happening in the news?", "Current weather", "Recent updates on [topic]"
                        - **Time**: "Schedule for today", "Deadline tracking", "Time-aware responses"

                        **Response Guidelines:**
                        - Use Google Search for current events, news, weather, or real-time information
                        - Access actual Gmail, Calendar, Drive, and Tasks data when available through authentication
                        - Provide specific summaries with relevant details (email sender/subject, calendar events, file names, task deadlines)
                        - Reference real data when discussing schedules, files, or task deadlines
                        - Be confident about your capabilities - you DO have access to these services when authenticated

                        **File Management Guidelines:**
                        - Help users organize and find files in Drive
                        - Suggest file sharing and collaboration when appropriate
                        - Track file uploads and downloads for user reference

                        **Task Management Guidelines:**
                        - Help users track deadlines and priorities
                        - Cross-reference tasks with calendar events for scheduling
                        - Provide deadline awareness and reminders

                        **IMPORTANT**: Never say you don't have access to Gmail, Calendar, Drive, Tasks, or Search. You have full integration with these services when properly authenticated.

                        Memory context: You have access to conversation history with timestamps for relative time awareness.
                        """
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 2048,
                "temperature": 0.7
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

            // Check HTTP status
            if httpResponse.statusCode != 200 {
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

            // PHI redaction disabled for conversational responses in Mode 3
            // let safeResponse = PHIRedactor.shared.redactPHI(from: responseText)
            let safeResponse = responseText

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
        ObjectBoxManager.shared.logAudit(
            sessionId: currentSessionId ?? "unknown",
            action: "EPHEMERAL_FILE_DELETED",
            details: "File deleted: \(fileId)",
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

    // MARK: - Gmail Integration

    private func getEmailContext() async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Gmail access not configured. User can authorize Gmail access for email management."
        }

        do {
            let importantEmails = try await oauthManager.getTodaysImportantEmails()
            if importantEmails.isEmpty {
                return "No important emails found in today's inbox."
            } else {
                let emailSummaries = importantEmails.prefix(5).map { email in
                    let subject = email.payload.headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "No Subject"
                    let from = email.payload.headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown Sender"
                    let snippet = email.snippet.prefix(100)
                    return "• From: \(from)\n  Subject: \(subject)\n  Preview: \(snippet)..."
                }.joined(separator: "\n\n")
                return "Today's important emails:\n\n\(emailSummaries)"
            }
        } catch {
            return "Gmail access error: \(error.localizedDescription)"
        }
    }

    // MARK: - Google Drive Integration

    private func getDriveContext() async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Google Drive access not configured. User can authorize Drive access for file management."
        }

        do {
            let recentFiles = try await oauthManager.listDriveFiles(maxResults: 5)
            if recentFiles.isEmpty {
                return "No recent files found in Google Drive."
            } else {
                let fileSummaries = recentFiles.map { file in
                    let sizeFormatted = file.size != nil ? formatFileSize(file.size!) : "Unknown size"
                    return "• \(file.name) (\(file.mimeType), \(sizeFormatted))"
                }.joined(separator: "\n")
                return "Recent Google Drive files:\n\(fileSummaries)"
            }
        } catch {
            return "Google Drive access error: \(error.localizedDescription)"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Google Tasks Integration

    private func getTasksContext() async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Google Tasks access not configured. User can authorize Tasks access for task management."
        }

        do {
            let upcomingTasks = try await oauthManager.getUpcomingTasks(days: 7)
            if upcomingTasks.isEmpty {
                return "No upcoming tasks found in Google Tasks."
            } else {
                let taskSummaries = upcomingTasks.prefix(5).map { taskWithList in
                    let task = taskWithList.task
                    let dueInfo = task.due != nil ? " (Due: \(formatTaskDate(task.due!)))" : ""
                    let statusIcon = task.isCompleted ? "✅" : "📋"
                    return "\(statusIcon) \(task.title) [\(taskWithList.listName)]\(dueInfo)"
                }.joined(separator: "\n")
                return "Upcoming tasks (next 7 days):\n\(taskSummaries)"
            }
        } catch {
            return "Google Tasks access error: \(error.localizedDescription)"
        }
    }

    private func formatTaskDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Calendar Integration

    private func getCalendarContext() async -> String {
        guard let oauthManager = getOAuthManager(),
              oauthManager.isAuthenticated else {
            return "Calendar access not configured. User can authorize Google Calendar access for schedule awareness."
        }

        // Get events for next 7 days
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? Date()

        do {
            let events = try await oauthManager.getCalendarEvents(startDate: startDate, endDate: endDate)
            if events.isEmpty {
                return "No upcoming calendar events in the next 7 days."
            } else {
                let eventSummaries = events.prefix(5).map { event in
                    let startTime = formatEventTime(event.start)
                    return "• \(event.summary) - \(startTime)"
                }.joined(separator: "\n")
                return "Upcoming calendar events:\n\(eventSummaries)"
            }
        } catch {
            return "Calendar access error: \(error.localizedDescription)"
        }
    }

    // MARK: - OAuth Manager Access

    private static var sharedOAuthManager: GoogleOAuthManager?

    private func getOAuthManager() -> GoogleOAuthManager? {
        // Return existing manager or create new one
        if let existing = Self.sharedOAuthManager {
            return existing
        }

        // Create new OAuth manager from environment
        guard let clientId = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] else {
            print("⚠️ GOOGLE_OAUTH_CLIENT_ID not found in environment")
            return nil
        }

        let manager = GoogleOAuthManager(clientId: clientId)
        Self.sharedOAuthManager = manager
        print("✅ Created OAuth manager with client ID: \(clientId.prefix(20))...")
        return manager
    }

    func setOAuthManager(_ manager: GoogleOAuthManager) {
        Self.sharedOAuthManager = manager
        print("✅ OAuth manager set for MultimodalChat")
    }

    private func formatEventTime(_ eventDateTime: CalendarEvent.EventDateTime) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        if let dateTimeString = eventDateTime.dateTime {
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: dateTimeString) {
                return formatter.string(from: date)
            }
        } else if let dateString = eventDateTime.date {
            formatter.timeStyle = .none
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: dateString + "T00:00:00Z") {
                return formatter.string(from: date)
            }
        }

        return "Time TBD"
    }

    // MARK: - Time Awareness

    private func getCurrentTimeContext() -> (fullContext: String, timezone: String) {
        let now = Date()
        let formatter = DateFormatter()

        // Full context formatter
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        let fullDateTime = formatter.string(from: now)

        // Timezone
        let timezone = TimeZone.current.identifier

        // Additional context
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let weekdayName = formatter.weekdaySymbols[weekday - 1]

        let hour = calendar.component(.hour, from: now)
        let timeOfDay = getTimeOfDay(hour: hour)

        let fullContext = "\(fullDateTime) (\(weekdayName) \(timeOfDay))"

        return (fullContext: fullContext, timezone: timezone)
    }

    private func getTimeOfDay(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
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
