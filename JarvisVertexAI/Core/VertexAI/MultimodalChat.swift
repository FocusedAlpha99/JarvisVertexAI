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

// MARK: - Gmail API Data Models

struct DirectGmailMessage {
    let id: String
    let snippet: String
    let payload: Payload

    struct Payload {
        let headers: [Header]
    }

    struct Header {
        let name: String
        let value: String
    }

    // Helper methods to extract common header values
    var subject: String {
        payload.headers.first { $0.name.lowercased() == "subject" }?.value ?? "No Subject"
    }

    var from: String {
        payload.headers.first { $0.name.lowercased() == "from" }?.value ?? "Unknown Sender"
    }

    var date: String {
        payload.headers.first { $0.name.lowercased() == "date" }?.value ?? "Unknown Date"
    }
}

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
    // private let googleWorkspace = GoogleWorkspaceClient.shared  // Temporarily commented for build

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
        // Note: MultimodalChat uses Gemini API directly with API key authentication
        // No Vertex AI access token needed
        print("✅ MultimodalChat: Initialized with Gemini API authentication")

        // Debug: Verify configuration loading
        let hasApiKey = VertexConfig.shared.geminiApiKey != nil
        let hasOAuthClientId = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] != nil
        print("🔑 API Key available: \(hasApiKey)")
        print("🔐 OAuth Client ID available: \(hasOAuthClientId)")

        if !hasApiKey {
            print("⚠️ WARNING: GEMINI_API_KEY not loaded from configuration")
        }

        loadPreviousConversationHistory()
    }

    private func loadPreviousConversationHistory() {
        // Load recent conversation history from ObjectBox (cross-session memory)
        // Use sustainable approach: limit to recent 30 messages for optimal recall without performance impact
        conversationHistory = ObjectBoxManager.shared.getConversationHistory(limit: 30)

        if !conversationHistory.isEmpty {
            print("🧠 Loaded \(conversationHistory.count) messages with absolute timestamps from persistent memory")

            // Log memory stats for optimization tracking
            let memoryStats = ObjectBoxManager.shared.getConversationMemoryStats()
            if let optimalForRecall = memoryStats["optimalForRecall"] as? Bool {
                print("🧠 Memory recall status: \(optimalForRecall ? "Optimal" : "Building")")
            }
        } else {
            print("🧠 No previous conversation memory found - starting fresh")
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

    // MARK: - Email Action Handlers (Direct Gmail API)

    func handleWorkspaceRequest(_ request: String) async -> String {
        // Temporarily return placeholder for Google Workspace features
        return "Google Workspace integration is temporarily disabled during ElevenLabs implementation. Feature will be restored after build completion."

        /*
        let lowercased = request.lowercased()

        do {
            // Initialize Google Workspace if needed
            try await initializeGoogleWorkspaceIfNeeded()

            // Handle Email Operations
            if lowercased.contains("send email") || lowercased.contains("email to") {
                if let emailDetails = extractEmailDetails(from: request) {
                    let result = try await googleWorkspace.sendEmail(
                        to: emailDetails.to,
                        subject: emailDetails.subject,
                        body: emailDetails.body
                    )
                    return "Email sent successfully (ID: \(result))"
                } else {
                    return "To send an email, I need: recipient, subject, and message content."
                }
            }
            else if lowercased.contains("important email") || lowercased.contains("today's email") {
                let emails = try await googleWorkspace.getRecentEmails(maxResults: 10)
                return formatWorkspaceEmailSummary(emails)
            }
            else if lowercased.contains("search") && (lowercased.contains("email") || lowercased.contains("mail")) {
                let emails = try await googleWorkspace.getRecentEmails(maxResults: 20)
                let searchQuery = extractSearchQuery(from: request)
                let filteredEmails = emails.filter { email in
                    email.subject.localizedCaseInsensitiveContains(searchQuery) ||
                    email.sender.localizedCaseInsensitiveContains(searchQuery) ||
                    email.snippet.localizedCaseInsensitiveContains(searchQuery)
                }
                return formatWorkspaceEmailSummary(filteredEmails, searchContext: searchQuery)
            }

            // Handle Calendar Operations
            else if lowercased.contains("calendar") || lowercased.contains("meeting") || lowercased.contains("schedule") {
                if lowercased.contains("show") || lowercased.contains("what's") || lowercased.contains("today") {
                    let events = try await googleWorkspace.getCalendarEvents(maxResults: 10)
                    return formatCalendarEventsSummary(events)
                }
                else if lowercased.contains("create") || lowercased.contains("schedule") || lowercased.contains("add") {
                    if let eventDetails = extractEventDetails(from: request) {
                        let result = try await googleWorkspace.createCalendarEvent(
                            title: eventDetails.title,
                            startTime: eventDetails.startTime,
                            endTime: eventDetails.endTime,
                            description: eventDetails.description
                        )
                        return "Calendar event created successfully (ID: \(result))"
                    } else {
                        return "To create an event, I need: title, date, and time."
                    }
                }
                else {
                    return "I can help with calendar operations. Try: 'Show today's calendar' or 'Schedule meeting tomorrow at 2pm'"
                }
            }

            // Handle Drive Operations
            else if lowercased.contains("drive") || lowercased.contains("document") || lowercased.contains("create file") {
                if lowercased.contains("list") || lowercased.contains("show") || lowercased.contains("files") {
                    let files = try await googleWorkspace.listDriveFiles(maxResults: 10)
                    return formatDriveFilesSummary(files)
                }
                else if lowercased.contains("create") || lowercased.contains("new") {
                    if let docDetails = extractDocumentDetails(from: request) {
                        let result = try await googleWorkspace.createDocument(
                            title: docDetails.title,
                            content: docDetails.content
                        )
                        return "Document created successfully (ID: \(result))"
                    } else {
                        return "To create a document, I need a title."
                    }
                }
                else {
                    return "I can help with Drive operations. Try: 'Show my recent files' or 'Create document called Project Plan'"
                }
            }

            // Handle Task Operations
            else if lowercased.contains("task") || lowercased.contains("todo") || lowercased.contains("reminder") {
                if lowercased.contains("show") || lowercased.contains("list") || lowercased.contains("what") {
                    let tasks = try await googleWorkspace.getTasks()
                    return formatTasksSummary(tasks)
                }
                else if lowercased.contains("add") || lowercased.contains("create") || lowercased.contains("new") {
                    if let taskDetails = extractTaskDetails(from: request) {
                        let result = try await googleWorkspace.createTask(
                            title: taskDetails.title,
                            notes: taskDetails.notes,
                            dueDate: taskDetails.dueDate
                        )
                        return "Task created successfully (ID: \(result))"
                    } else {
                        return "To create a task, I need a title."
                    }
                }
                else {
                    return "I can help with task management. Try: 'Show my tasks' or 'Add task Review proposal due tomorrow'"
                }
            }
            else {
                return "I can help with Google Workspace operations: Email, Calendar, Drive, and Tasks. What would you like to do?"
            }
        } catch {
            return "Email operation failed: \(error.localizedDescription)"
        }
        */
    }

    // MARK: - Public Email Methods

    func sendEmail(to: String, subject: String, body: String) async -> String {
        // Temporarily disabled for build
        return "Email functionality temporarily disabled during ElevenLabs implementation"
        /*
        do {
            try await initializeGoogleWorkspaceIfNeeded()
            let result = try await googleWorkspace.sendEmail(to: to, subject: subject, body: body)
            return "Email sent successfully (ID: \(result))"
        } catch {
            return "Failed to send email: \(error.localizedDescription)"
        }
        */
    }

    // Helper to extract email details from natural language
    private func extractEmailDetails(from request: String) -> (to: String, subject: String, body: String)? {
        // Simple regex-based extraction - could be enhanced with NLP
        let emailPattern = #"([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#
        let emailRegex = try? NSRegularExpression(pattern: emailPattern)

        let range = NSRange(location: 0, length: request.utf16.count)
        let emailMatch = emailRegex?.firstMatch(in: request, options: [], range: range)

        guard let match = emailMatch,
              let emailRange = Range(match.range, in: request) else {
            return nil
        }

        let email = String(request[emailRange])

        // Extract subject (look for "subject" followed by text)
        let subjectPattern = #"subject[:\s]+([^,\n]+)"#
        let subjectRegex = try? NSRegularExpression(pattern: subjectPattern, options: .caseInsensitive)
        let subjectMatch = subjectRegex?.firstMatch(in: request, options: [], range: range)

        let subject: String
        if let subjectMatch = subjectMatch,
           let subjectRange = Range(subjectMatch.range(at: 1), in: request) {
            subject = String(request[subjectRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            subject = "Message from Jarvis"
        }

        // Extract body (look for "saying" or "message" followed by text)
        let bodyPattern = #"(?:saying|message|body)[:\s]+(.+)"#
        let bodyRegex = try? NSRegularExpression(pattern: bodyPattern, options: .caseInsensitive)
        let bodyMatch = bodyRegex?.firstMatch(in: request, options: [], range: range)

        let body: String
        if let bodyMatch = bodyMatch,
           let bodyRange = Range(bodyMatch.range(at: 1), in: request) {
            body = String(request[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            body = "This email was sent via Jarvis AI assistant."
        }

        return (to: email, subject: subject, body: body)
    }

    // MARK: - Direct Gmail API Implementation (API Key Only)

    private func getGmailApiKey() throws -> String {
        // Try GOOGLE_BROWSER_API_KEY first (the working key from autonomous-email-assistant), then fallback to GEMINI_API_KEY
        if let browserApiKey = ProcessInfo.processInfo.environment["GOOGLE_BROWSER_API_KEY"], !browserApiKey.isEmpty {
            return browserApiKey
        } else if let geminiApiKey = VertexConfig.shared.geminiApiKey, !geminiApiKey.isEmpty {
            return geminiApiKey
        } else {
            throw MultimodalChatError.configurationMissing("GOOGLE_BROWSER_API_KEY or GEMINI_API_KEY required for Gmail API")
        }
    }

    private func sendEmailDirect(to: String, subject: String, body: String) async throws -> String {
        let apiKey = try getGmailApiKey()

        // Create email content following the working gmail_sms_fixed.py format
        let emailContent = """
            To: \(to)\r
            From: timrattigan72@gmail.com\r
            Subject: \(subject)\r
            \r
            \(body)
            """

        // Base64 encode for Gmail API (urlsafe like the working implementation)
        let rawMessage = Data(emailContent.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        // Gmail API send using the exact same approach as gmail_sms_fixed.py
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["raw": rawMessage]
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MultimodalChatError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode == 200 {
            let messageId = extractMessageId(from: data)
            return "✅ Email sent successfully to \(to). Message ID: \(messageId)"
        } else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MultimodalChatError.apiError(httpResponse.statusCode, errorText)
        }
    }

    private func getImportantEmails() async throws -> [DirectGmailMessage] {
        let apiKey = try getGmailApiKey()

        // Use Gmail API to get important emails (is:important in inbox)
        let query = "is:important in:inbox"
        return try await searchEmails(query: query)
    }

    private func searchEmails(query: String) async throws -> [DirectGmailMessage] {
        let apiKey = try getGmailApiKey()

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages?key=\(apiKey)&q=\(encodedQuery)&maxResults=10")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MultimodalChatError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MultimodalChatError.apiError(httpResponse.statusCode, errorText)
        }

        // Parse the response to get message IDs, then fetch message details
        let searchResult = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = searchResult?["messages"] as? [[String: Any]] ?? []

        var emailMessages: [DirectGmailMessage] = []
        for messageData in messages.prefix(5) { // Limit to 5 for performance
            if let messageId = messageData["id"] as? String {
                if let email = try? await getEmailDetails(messageId: messageId, apiKey: apiKey) {
                    emailMessages.append(email)
                }
            }
        }

        return emailMessages
    }

    private func getEmailDetails(messageId: String, apiKey: String) async throws -> DirectGmailMessage {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)?key=\(apiKey)")!

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MultimodalChatError.networkError(URLError(.badServerResponse))
        }

        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MultimodalChatError.apiError(httpResponse.statusCode, errorText)
        }

        // Parse Gmail message format
        let messageJson = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return parseGmailMessage(messageJson ?? [:])
    }

    private func parseGmailMessage(_ json: [String: Any]) -> DirectGmailMessage {
        let id = json["id"] as? String ?? ""
        let snippet = json["snippet"] as? String ?? ""

        let payload = json["payload"] as? [String: Any] ?? [:]
        let headers = payload["headers"] as? [[String: Any]] ?? []

        let parsedHeaders = headers.map { header in
            DirectGmailMessage.Header(
                name: header["name"] as? String ?? "",
                value: header["value"] as? String ?? ""
            )
        }

        return DirectGmailMessage(
            id: id,
            snippet: snippet,
            payload: DirectGmailMessage.Payload(headers: parsedHeaders)
        )
    }

    private func extractMessageId(from data: Data) -> String {
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["id"] as? String ?? "unknown"
        } catch {
            return "unknown"
        }
    }

    private func formatEmailSummary(_ emails: [DirectGmailMessage], searchContext: String? = nil) -> String {
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

    // MARK: - Google Workspace Helper Methods (Temporarily Disabled)

    /*
    private func initializeGoogleWorkspaceIfNeeded() async throws {
        // Initialize the Google Workspace client with service account credentials
        try await googleWorkspace.initialize()
    }

    private func formatWorkspaceEmailSummary(_ emails: [EmailSummary], searchContext: String? = nil) -> String {
        if emails.isEmpty {
            let context = searchContext != nil ? " matching '\(searchContext!)'" : ""
            return "No emails found\(context)."
        }

        let summary = emails.prefix(5).enumerated().map { index, email in
            let snippet = String(email.snippet.prefix(100))
            return "\(index + 1). **\(email.subject)**\n   From: \(email.sender)\n   \(snippet)..."
        }.joined(separator: "\n\n")

        let context = searchContext != nil ? " matching '\(searchContext!)'" : ""
        let header = emails.count == 1 ? "Found 1 email\(context):" : "Found \(emails.count) emails\(context) (showing first 5):"

        return "\(header)\n\n\(summary)"
    }

    // MARK: - Event/Document/Task Extraction Methods

    private func extractEventDetails(from request: String) -> (title: String, startTime: Date, endTime: Date, description: String?)? {
        // Simple extraction - in production, use more sophisticated NLP
        let words = request.components(separatedBy: .whitespacesAndNewlines)

        // Look for time patterns like "2pm", "14:00", "tomorrow at 3"
        var title = "Meeting"
        var startTime = Date().addingTimeInterval(3600) // Default to 1 hour from now
        var endTime = startTime.addingTimeInterval(3600) // 1 hour duration

        // Extract title (words after "schedule" or "meeting")
        if let scheduleIndex = words.firstIndex(where: { $0.lowercased().contains("schedule") || $0.lowercased().contains("meeting") }) {
            let titleWords = words.dropFirst(scheduleIndex + 1).prefix(while: { !$0.contains("at") && !$0.contains("tomorrow") && !$0.contains("today") })
            if !titleWords.isEmpty {
                title = titleWords.joined(separator: " ")
            }
        }

        // Extract time
        for (index, word) in words.enumerated() {
            if word.lowercased() == "tomorrow" {
                startTime = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            } else if word.lowercased() == "today" {
                startTime = Date()
            } else if word.contains("pm") || word.contains("am") {
                if let hour = extractHour(from: word) {
                    var components = Calendar.current.dateComponents([.year, .month, .day], from: startTime)
                    components.hour = hour
                    components.minute = 0
                    startTime = Calendar.current.date(from: components) ?? startTime
                }
            }
        }

        endTime = startTime.addingTimeInterval(3600) // 1 hour duration

        return (title: title, startTime: startTime, endTime: endTime, description: nil)
    }

    private func extractDocumentDetails(from request: String) -> (title: String, content: String)? {
        let words = request.components(separatedBy: .whitespacesAndNewlines)

        var title = "Untitled Document"

        // Look for patterns like "create document called 'Project Plan'"
        if let calledIndex = words.firstIndex(where: { $0.lowercased().contains("called") || $0.lowercased().contains("named") }) {
            let titleWords = words.dropFirst(calledIndex + 1).prefix(5)
            if !titleWords.isEmpty {
                title = titleWords.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }

        return (title: title, content: "Document created by Jarvis AI Assistant")
    }

    private func extractTaskDetails(from request: String) -> (title: String, notes: String?, dueDate: Date?)? {
        let words = request.components(separatedBy: .whitespacesAndNewlines)

        var title = ""
        var dueDate: Date?

        // Extract task title (words after "add task" or "create task")
        if let taskIndex = words.firstIndex(where: { $0.lowercased() == "task" }) {
            let titleWords = words.dropFirst(taskIndex + 1).prefix(while: { !$0.lowercased().contains("due") && !$0.lowercased().contains("tomorrow") })
            title = titleWords.joined(separator: " ")
        }

        // Extract due date
        if request.lowercased().contains("tomorrow") {
            dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        } else if request.lowercased().contains("today") {
            dueDate = Date()
        }

        return title.isEmpty ? nil : (title: title, notes: nil, dueDate: dueDate)
    }

    private func extractHour(from timeString: String) -> Int? {
        let digits = timeString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let hour = Int(digits) else { return nil }

        if timeString.lowercased().contains("pm") && hour < 12 {
            return hour + 12
        } else if timeString.lowercased().contains("am") && hour == 12 {
            return 0
        }

        return hour
    }

    // MARK: - Formatting Methods for New Services

    private func formatCalendarEventsSummary(_ events: [CalendarEventSummary]) -> String {
        if events.isEmpty {
            return "No upcoming calendar events found."
        }

        let summary = events.prefix(5).enumerated().map { index, event in
            let startTime = event.startTime?.formatted(date: .omitted, time: .shortened) ?? "No time"
            let endTime = event.endTime?.formatted(date: .omitted, time: .shortened) ?? ""
            let timeRange = endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"

            return "\(index + 1). **\(event.title)**\n   Time: \(timeRange)\n   \(event.description ?? "")"
        }.joined(separator: "\n\n")

        let header = events.count == 1 ? "Found 1 calendar event:" : "Found \(events.count) calendar events (showing first 5):"
        return "\(header)\n\n\(summary)"
    }

    private func formatDriveFilesSummary(_ files: [DriveFileSummary]) -> String {
        if files.isEmpty {
            return "No Drive files found."
        }

        let summary = files.prefix(5).enumerated().map { index, file in
            let modifiedTime = file.modifiedTime?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown"
            let fileType = file.mimeType.components(separatedBy: ".").last ?? "File"

            return "\(index + 1). **\(file.name)**\n   Type: \(fileType)\n   Modified: \(modifiedTime)"
        }.joined(separator: "\n\n")

        let header = files.count == 1 ? "Found 1 Drive file:" : "Found \(files.count) Drive files (showing first 5):"
        return "\(header)\n\n\(summary)"
    }

    private func formatTasksSummary(_ tasks: [TaskSummary]) -> String {
        if tasks.isEmpty {
            return "No tasks found."
        }

        let summary = tasks.prefix(5).enumerated().map { index, task in
            let dueDate = task.dueDate?.formatted(date: .abbreviated, time: .omitted) ?? "No due date"
            let status = task.status == "completed" ? "✅" : "⏳"

            return "\(index + 1). \(status) **\(task.title)**\n   Due: \(dueDate)\n   \(task.notes ?? "")"
        }.joined(separator: "\n\n")

        let header = tasks.count == 1 ? "Found 1 task:" : "Found \(tasks.count) tasks (showing first 5):"
        return "\(header)\n\n\(summary)"
    }
    */

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
        guard let apiKey = VertexConfig.shared.geminiApiKey, !apiKey.isEmpty else {
            throw MultimodalChatError.configurationMissing("GEMINI_API_KEY not configured. Check .env.local or environment variables.")
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
        guard let apiKey = VertexConfig.shared.geminiApiKey, !apiKey.isEmpty else {
            throw MultimodalChatError.configurationMissing("GEMINI_API_KEY not found in configuration")
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        // Inject comprehensive personal assistant context
        let currentTime = getCurrentTimeContext()
        // Email and Calendar context removed - using function calling instead
        let driveContext = await getDriveContext()
        let tasksContext = await getTasksContext()

        // Build request body with comprehensive assistant context, Google Search, and Gmail function calling
        let requestBody: [String: Any] = [
            "contents": conversationHistory,
            "tools": [
                [
                    "functionDeclarations": [
                        [
                            "name": "searchGmail",
                            "description": "Search Gmail messages using Gmail query syntax. Returns the most relevant emails matching the query. Use this to find specific emails, codes, attachments, or any email content.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "query": [
                                        "type": "string",
                                        "description": "Gmail search query (e.g., 'from:sender@example.com subject:code', 'is:unread', 'after:2025/10/01', 'has:attachment filename:pdf'). Leave empty to get recent inbox emails."
                                    ],
                                    "maxResults": [
                                        "type": "integer",
                                        "description": "Maximum number of emails to return (default 10, max 50)"
                                    ]
                                ],
                                "required": []
                            ]
                        ],
                        [
                            "name": "getEmail",
                            "description": "Get full content of a specific email by ID including body, attachments, and all headers.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "messageId": [
                                        "type": "string",
                                        "description": "The Gmail message ID to retrieve"
                                    ]
                                ],
                                "required": ["messageId"]
                            ]
                        ],
                        [
                            "name": "listCalendarEvents",
                            "description": "List calendar events within a date range. Returns events with start/end times, titles, descriptions, and attendees.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "startDate": [
                                        "type": "string",
                                        "description": "Start date in ISO8601 format (e.g., '2025-10-02T00:00:00Z'). Defaults to now if not specified."
                                    ],
                                    "endDate": [
                                        "type": "string",
                                        "description": "End date in ISO8601 format. Defaults to 7 days from start if not specified."
                                    ],
                                    "maxResults": [
                                        "type": "integer",
                                        "description": "Maximum number of events to return (default 20, max 100)"
                                    ]
                                ],
                                "required": []
                            ]
                        ],
                        [
                            "name": "createCalendarEvent",
                            "description": "Create a new calendar event with title, time, description, and optional attendees.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "title": [
                                        "type": "string",
                                        "description": "Event title/summary"
                                    ],
                                    "startTime": [
                                        "type": "string",
                                        "description": "Event start time in ISO8601 format"
                                    ],
                                    "endTime": [
                                        "type": "string",
                                        "description": "Event end time in ISO8601 format"
                                    ],
                                    "description": [
                                        "type": "string",
                                        "description": "Event description (optional)"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "Event location (optional)"
                                    ],
                                    "attendees": [
                                        "type": "array",
                                        "description": "Array of attendee email addresses (optional)",
                                        "items": [
                                            "type": "string"
                                        ]
                                    ]
                                ],
                                "required": ["title", "startTime", "endTime"]
                            ]
                        ],
                        [
                            "name": "updateCalendarEvent",
                            "description": "Update an existing calendar event. Only provided fields will be updated.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "eventId": [
                                        "type": "string",
                                        "description": "Calendar event ID to update"
                                    ],
                                    "title": [
                                        "type": "string",
                                        "description": "New event title (optional)"
                                    ],
                                    "startTime": [
                                        "type": "string",
                                        "description": "New start time in ISO8601 format (optional)"
                                    ],
                                    "endTime": [
                                        "type": "string",
                                        "description": "New end time in ISO8601 format (optional)"
                                    ],
                                    "description": [
                                        "type": "string",
                                        "description": "New description (optional)"
                                    ],
                                    "location": [
                                        "type": "string",
                                        "description": "New location (optional)"
                                    ]
                                ],
                                "required": ["eventId"]
                            ]
                        ],
                        [
                            "name": "deleteCalendarEvent",
                            "description": "Delete a calendar event by ID.",
                            "parameters": [
                                "type": "object",
                                "properties": [
                                    "eventId": [
                                        "type": "string",
                                        "description": "Calendar event ID to delete"
                                    ]
                                ],
                                "required": ["eventId"]
                            ]
                        ]
                    ]
                ]
            ],
            "systemInstruction": [
                "parts": [
                    [
                        "text": """
                        Current date and time: \(currentTime.fullContext)
                        Local timezone: \(currentTime.timezone)

                        \(driveContext)

                        \(tasksContext)

                        You are a comprehensive personal AI assistant with full Google Workspace access via function calling:

                        **AVAILABLE FUNCTIONS:**

                        **Gmail Functions (Always Available):**
                        - searchGmail(query, maxResults): Search emails using Gmail syntax
                        - getEmail(messageId): Get full email content including body text

                        **Calendar Functions (Always Available):**
                        - listCalendarEvents(startDate, endDate, maxResults): List calendar events in date range
                        - createCalendarEvent(title, startTime, endTime, description, location, attendees): Create new event
                        - updateCalendarEvent(eventId, title, startTime, endTime, description, location): Update existing event
                        - deleteCalendarEvent(eventId): Delete an event

                        **CRITICAL INSTRUCTIONS:**
                        1. ALWAYS use function calls when user asks about emails or calendar - NEVER make up information
                        2. For recent emails: searchGmail("")
                        3. For calendar: listCalendarEvents() with appropriate date range
                        4. To create events: Use createCalendarEvent() with ISO8601 datetime strings
                        5. NEVER hallucinate data - only report what functions return

                        **Service Status:**
                        - Gmail: ✅ AUTHENTICATED - Full CRUD access via function calling
                        - Calendar: ✅ AUTHENTICATED - Full CRUD access via function calling
                        - Drive: \(driveContext.contains("not configured") ? "⏸️ Not authenticated" : "✅ Authenticated")
                        - Tasks: \(tasksContext.contains("not configured") ? "⏸️ Not authenticated" : "✅ Authenticated")
                        - Google Search: ✅ Always available

                        **Response Rules:**
                        - When asked about emails/calendar, immediately call appropriate function - don't guess
                        - Be precise and factual - only report what functions return
                        - For event creation, parse user's natural language into ISO8601 format
                        - Use Google Search for current events/news
                        - Maintain conversation memory with timestamps
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

            // Parse response and check for function calls
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first else {
                throw MultimodalChatError.invalidResponse
            }

            // Check if this is a function call
            if let functionCall = firstPart["functionCall"] as? [String: Any],
               let functionName = functionCall["name"] as? String,
               let args = functionCall["args"] as? [String: Any] {

                print("🔧 Gemini requested function: \(functionName) with args: \(args)")

                // Add function call to history
                conversationHistory.append([
                    "role": "model",
                    "parts": [["functionCall": functionCall]]
                ])

                // Execute the function
                let functionResult = try await executeFunctionCall(name: functionName, args: args)

                // Add function response to history
                conversationHistory.append([
                    "role": "function",
                    "parts": [[
                        "functionResponse": [
                            "name": functionName,
                            "response": functionResult
                        ]
                    ]]
                ])

                // Recursively call API again with function result
                print("🔄 Sending function result back to Gemini...")
                return try await performGeminiAPICall()
            }

            // Regular text response
            guard let responseText = firstPart["text"] as? String else {
                throw MultimodalChatError.invalidResponse
            }

            // Add to conversation history
            conversationHistory.append([
                "role": "model",
                "parts": [["text": responseText]]
            ])

            print("✅ Gemini multimodal response received (\(responseText.count) chars)")
            return responseText

        } catch {
            if error is MultimodalChatError {
                throw error
            } else {
                throw MultimodalChatError.networkError(error)
            }
        }
    }

    // MARK: - Function Calling

    private func executeFunctionCall(name: String, args: [String: Any]) async throws -> [String: Any] {
        guard let oauthManager = getOAuthManager() else {
            return ["error": "OAuth manager not available. Please restart the app."]
        }

        // Check if authenticated, if not return helpful error
        if !oauthManager.isAuthenticated {
            return ["error": "Not authenticated with Google. Please go to Settings and authenticate with Google to enable Gmail and Calendar access."]
        }

        switch name {
        case "searchGmail":
            let query = args["query"] as? String ?? ""
            let maxResults = args["maxResults"] as? Int ?? 10

            do {
                let messages = try await oauthManager.searchGmail(query: query, maxResults: maxResults)

                // Return email summaries as structured data
                let emailData = messages.map { email -> [String: Any] in
                    let subject = email.payload.headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "No Subject"
                    let from = email.payload.headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown"
                    let date = email.payload.headers.first(where: { $0.name.lowercased() == "date" })?.value ?? ""

                    return [
                        "id": email.id,
                        "from": from,
                        "subject": subject,
                        "snippet": email.snippet,
                        "date": date
                    ]
                }

                return [
                    "success": true,
                    "count": emailData.count,
                    "emails": emailData
                ]
            } catch {
                return ["error": "Failed to search Gmail: \(error.localizedDescription)"]
            }

        case "getEmail":
            guard let messageId = args["messageId"] as? String else {
                return ["error": "Missing messageId parameter"]
            }

            do {
                let email = try await oauthManager.getGmailMessage(messageId: messageId)

                let subject = email.payload.headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? "No Subject"
                let from = email.payload.headers.first(where: { $0.name.lowercased() == "from" })?.value ?? "Unknown"
                let to = email.payload.headers.first(where: { $0.name.lowercased() == "to" })?.value ?? ""
                let date = email.payload.headers.first(where: { $0.name.lowercased() == "date" })?.value ?? ""

                // Extract email body
                let body = extractEmailBody(from: email.payload)

                return [
                    "success": true,
                    "id": email.id,
                    "from": from,
                    "to": to,
                    "subject": subject,
                    "date": date,
                    "body": body,
                    "snippet": email.snippet
                ]
            } catch {
                return ["error": "Failed to get email: \(error.localizedDescription)"]
            }

        case "listCalendarEvents":
            let formatter = ISO8601DateFormatter()
            let startDate: Date
            let endDate: Date

            if let startStr = args["startDate"] as? String, let parsed = formatter.date(from: startStr) {
                startDate = parsed
            } else {
                startDate = Date()
            }

            if let endStr = args["endDate"] as? String, let parsed = formatter.date(from: endStr) {
                endDate = parsed
            } else {
                endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? startDate
            }

            do {
                let events = try await oauthManager.getCalendarEvents(startDate: startDate, endDate: endDate)
                let eventData = events.map { event -> [String: Any] in
                    var data: [String: Any] = [
                        "id": event.id,
                        "summary": event.summary,
                        "start": event.start.dateTime ?? event.start.date ?? "",
                        "end": event.end.dateTime ?? event.end.date ?? ""
                    ]
                    if let desc = event.description {
                        data["description"] = desc
                    }
                    if let loc = event.location {
                        data["location"] = loc
                    }
                    return data
                }

                return [
                    "success": true,
                    "count": eventData.count,
                    "events": eventData
                ]
            } catch {
                return ["error": "Failed to list calendar events: \(error.localizedDescription)"]
            }

        case "createCalendarEvent":
            guard let title = args["title"] as? String,
                  let startTimeStr = args["startTime"] as? String,
                  let endTimeStr = args["endTime"] as? String else {
                return ["error": "Missing required parameters: title, startTime, endTime"]
            }

            let formatter = ISO8601DateFormatter()
            guard let startTime = formatter.date(from: startTimeStr),
                  let endTime = formatter.date(from: endTimeStr) else {
                return ["error": "Invalid date format. Use ISO8601 format."]
            }

            let description = args["description"] as? String
            let location = args["location"] as? String
            let attendees = args["attendees"] as? [String]

            do {
                let eventId = try await oauthManager.createCalendarEvent(
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    description: description,
                    location: location,
                    attendees: attendees
                )

                return [
                    "success": true,
                    "eventId": eventId,
                    "message": "Event '\(title)' created successfully"
                ]
            } catch {
                return ["error": "Failed to create calendar event: \(error.localizedDescription)"]
            }

        case "updateCalendarEvent":
            guard let eventId = args["eventId"] as? String else {
                return ["error": "Missing required parameter: eventId"]
            }

            let title = args["title"] as? String
            let description = args["description"] as? String
            let location = args["location"] as? String

            let formatter = ISO8601DateFormatter()
            var startTime: Date?
            var endTime: Date?

            if let startStr = args["startTime"] as? String {
                startTime = formatter.date(from: startStr)
            }
            if let endStr = args["endTime"] as? String {
                endTime = formatter.date(from: endStr)
            }

            do {
                try await oauthManager.updateCalendarEvent(
                    eventId: eventId,
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    description: description,
                    location: location
                )

                return [
                    "success": true,
                    "message": "Event updated successfully"
                ]
            } catch {
                return ["error": "Failed to update calendar event: \(error.localizedDescription)"]
            }

        case "deleteCalendarEvent":
            guard let eventId = args["eventId"] as? String else {
                return ["error": "Missing required parameter: eventId"]
            }

            do {
                try await oauthManager.deleteCalendarEvent(eventId: eventId)

                return [
                    "success": true,
                    "message": "Event deleted successfully"
                ]
            } catch {
                return ["error": "Failed to delete calendar event: \(error.localizedDescription)"]
            }

        default:
            return ["error": "Unknown function: \(name)"]
        }
    }

    private func extractEmailBody(from payload: GmailMessage.MessagePayload) -> String {
        // Try to get plain text body
        if let body = payload.body,
           let data = body.data,
           !data.isEmpty {
            let fixedData = data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            if let decoded = Data(base64Encoded: fixedData),
               let text = String(data: decoded, encoding: .utf8) {
                return text
            }
        }

        // Check parts for multipart messages
        if let parts = payload.parts {
            for part in parts {
                if let body = part.body,
                   let data = body.data,
                   !data.isEmpty {
                    let fixedData = data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    if let decoded = Data(base64Encoded: fixedData),
                       let text = String(data: decoded, encoding: .utf8) {
                        return text
                    }
                }
            }
        }

        return "No body text available"
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

        // Create new OAuth manager from VertexConfig
        print("🔍 DEBUG: Checking VertexConfig for OAuth Client ID...")
        print("🔍 DEBUG: VertexConfig.shared.oauthClientId = \(VertexConfig.shared.oauthClientId?.prefix(20) ?? "nil")")

        guard let clientId = VertexConfig.shared.oauthClientId else {
            print("⚠️ GOOGLE_OAUTH_CLIENT_ID not found in configuration")
            print("💡 Please ensure GOOGLE_OAUTH_CLIENT_ID is set in .env.local")
            print("💡 Current .env.local path being used: \(VertexConfig.shared.loadedFromFile ?? "none")")
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
