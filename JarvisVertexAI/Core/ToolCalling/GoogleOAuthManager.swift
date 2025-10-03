import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Google OAuth Manager with Minimal Scopes
class GoogleOAuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var userConsent: UserConsent?
    
    private let clientId: String
    private let redirectURI = "com.googleusercontent.apps.653043868454-oa9ina7p9kj0i782b8ivds1g5c5oatdu:/oauth2redirect"
    private var authSession: ASWebAuthenticationSession?
    private let keychain = KeychainManager()
    private let phiRedactor = PHIRedactor.shared
    
    // 2025-Compliant Personal Assistant scopes - Full Google Workspace access
    private let personalAssistantScopes = [
        // Gmail - Full access (2025 compliant - includes read, compose, send, delete)
        "https://mail.google.com/",

        // Google Calendar - Full read/write access to all calendars
        "https://www.googleapis.com/auth/calendar",

        // Google Tasks - Full access (create, read, update, delete tasks and lists)
        "https://www.googleapis.com/auth/tasks",

        // Google Drive - Full access to all Drive files
        "https://www.googleapis.com/auth/drive",

        // Additional profile access for user information
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/userinfo.email"
    ]
    
    struct UserConsent: Codable {
        let timestamp: Date
        let scopes: [String]
        let consentHash: String
        let expiresAt: Date

        var isValid: Bool {
            Date() < expiresAt
        }
    }
    
    init(clientId: String) {
        self.clientId = clientId
        super.init()
        loadStoredCredentials()
    }
    
    // MARK: - Authentication Flow
    func authenticate(presentingWindow: ASPresentationAnchor) async throws {
        // Generate PKCE challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        // Build auth URL with personal assistant scopes
        let authURL = buildAuthURL(
            codeChallenge: codeChallenge,
            scopes: personalAssistantScopes
        )
        
        // Present consent screen
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.googleusercontent.apps.653043868454-oa9ina7p9kj0i782b8ivds1g5c5oatdu"
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = callbackURL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: OAuthError.unknown)
                }
            }
            
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = true // No cookies stored
            authSession?.start()
        }
        
        // Exchange code for token
        let code = extractCode(from: callbackURL)
        let token = try await exchangeCodeForToken(
            code: code,
            codeVerifier: codeVerifier
        )
        
        // Store securely with consent record
        storeCredentials(token: token, scopes: personalAssistantScopes)

        // Log consent event
        logConsentEvent(scopes: personalAssistantScopes)
        
        await MainActor.run {
            self.accessToken = token.accessToken
            self.isAuthenticated = true
            self.userConsent = UserConsent(
                timestamp: Date(),
                scopes: personalAssistantScopes,
                consentHash: generateConsentHash(scopes: personalAssistantScopes),
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
            )
        }
    }
    
    // MARK: - Token Management
    private func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
    
    func refreshTokenIfNeeded() async throws {
        guard let refreshToken = keychain.getString("google_refresh_token") else {
            throw OAuthError.noRefreshToken
        }
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        
        let body = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        await MainActor.run {
            self.accessToken = token.accessToken
        }
        
        // Update stored token
        keychain.set(token.accessToken, forKey: "google_access_token")
    }
    
    // MARK: - Enhanced Google Tasks Integration for Personal Assistant

    func getAllTasks() async throws -> [TaskWithList] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // First, get all task lists
        let taskLists = try await getTaskLists()
        var allTasks: [TaskWithList] = []

        // Get tasks from each list
        for taskList in taskLists {
            do {
                let tasks = try await getTasks(from: taskList.id)
                let tasksWithList = tasks.map { task in
                    TaskWithList(
                        task: task,
                        listName: taskList.title,
                        listId: taskList.id
                    )
                }
                allTasks.append(contentsOf: tasksWithList)
            } catch {
                print("⚠️ Failed to get tasks from list \(taskList.title): \(error)")
            }
        }

        // Sort by due date and status
        return allTasks.sorted { task1, task2 in
            // Incomplete tasks first
            if task1.task.status != task2.task.status {
                return task1.task.status == "needsAction"
            }

            // Then by due date
            switch (task1.task.due, task2.task.due) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            case (let date1?, let date2?): return date1 < date2
            }
        }
    }

    func getTaskLists() async throws -> [GoogleTaskList] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        var request = URLRequest(url: URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TaskListsResponse.self, from: data)

        return response.items
    }

    func getTasks(from listId: String) async throws -> [GoogleTaskDetailed] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks")!
        components.queryItems = [
            URLQueryItem(name: "showCompleted", value: "true"),
            URLQueryItem(name: "showDeleted", value: "false"),
            URLQueryItem(name: "maxResults", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TasksDetailedResponse.self, from: data)

        return response.items ?? []
    }

    func getUpcomingTasks(days: Int = 7) async throws -> [TaskWithList] {
        let allTasks = try await getAllTasks()
        let calendar = Calendar.current
        let now = Date()
        let futureDate = calendar.date(byAdding: .day, value: days, to: now) ?? now

        return allTasks.filter { taskWithList in
            let task = taskWithList.task

            // Include tasks that are incomplete
            guard task.status == "needsAction" else { return false }

            // Include tasks with due dates in the next week
            if let dueDateString = task.due,
               let dueDate = parseTaskDate(dueDateString) {
                return dueDate <= futureDate
            }

            // Include tasks without due dates (always relevant)
            return true
        }.prefix(20).map { $0 } // Limit to 20 most relevant tasks
    }

    private func parseTaskDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
    
    func getCalendarEvents(startDate: Date, endDate: Date) async throws -> [CalendarEvent] {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        
        let formatter = ISO8601DateFormatter()
        let timeMin = formatter.string(from: startDate)
        let timeMax = formatter.string(from: endDate)
        
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CalendarResponse.self, from: data)
        
        // Return events without PHI redaction for personal assistant use
        return response.items
    }

    func createCalendarEvent(title: String, startTime: Date, endTime: Date, description: String? = nil, location: String? = nil, attendees: [String]? = nil) async throws -> String {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        let formatter = ISO8601DateFormatter()
        var eventData: [String: Any] = [
            "summary": title,
            "start": ["dateTime": formatter.string(from: startTime)],
            "end": ["dateTime": formatter.string(from: endTime)]
        ]

        if let description = description {
            eventData["description"] = description
        }
        if let location = location {
            eventData["location"] = location
        }
        if let attendees = attendees, !attendees.isEmpty {
            eventData["attendees"] = attendees.map { ["email": $0] }
        }

        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: eventData)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return response?["id"] as? String ?? "unknown"
    }

    func updateCalendarEvent(eventId: String, title: String? = nil, startTime: Date? = nil, endTime: Date? = nil, description: String? = nil, location: String? = nil) async throws {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        let formatter = ISO8601DateFormatter()
        var eventData: [String: Any] = [:]

        if let title = title {
            eventData["summary"] = title
        }
        if let startTime = startTime {
            eventData["start"] = ["dateTime": formatter.string(from: startTime)]
        }
        if let endTime = endTime {
            eventData["end"] = ["dateTime": formatter.string(from: endTime)]
        }
        if let description = description {
            eventData["description"] = description
        }
        if let location = location {
            eventData["location"] = location
        }

        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: eventData)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.unknown
        }
    }

    func deleteCalendarEvent(eventId: String) async throws {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(eventId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OAuthError.unknown
        }
    }

    // MARK: - Enhanced Gmail Methods for Personal Assistant

    func getTodaysImportantEmails() async throws -> [GmailMessage] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Query for today's emails in inbox with importance markers
        let today = Calendar.current.startOfDay(for: Date())
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        let todayString = dateFormatter.string(from: today)

        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "in:inbox after:\(todayString) (is:important OR is:starred OR from:boss OR from:urgent)"),
            URLQueryItem(name: "maxResults", value: "20")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GmailListResponse.self, from: data)

        var messages: [GmailMessage] = []
        for messageRef in response.messages {
            if let fullMessage = try? await getGmailMessage(messageId: messageRef.id) {
                messages.append(fullMessage)
            }
        }

        return messages
    }

    func getGmailMessage(messageId: String) async throws -> GmailMessage {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        let messageURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)")!
        var request = URLRequest(url: messageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(GmailMessage.self, from: data)
    }

    func searchGmail(query: String, maxResults: Int = 10) async throws -> [GmailMessage] {
        // Refresh token if needed before making request
        if accessToken == nil {
            try await refreshTokenIfNeeded()
        }

        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GmailListResponse.self, from: data)

        var messages: [GmailMessage] = []
        for messageRef in response.messages {
            if let fullMessage = try? await getGmailMessage(messageId: messageRef.id) {
                messages.append(fullMessage)
            }
        }

        return messages
    }

    func sendEmail(to: String, subject: String, body: String, cc: String? = nil, bcc: String? = nil) async throws -> String {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Create email message in RFC 2822 format
        var emailContent = "To: \(to)\r\n"
        if let cc = cc { emailContent += "Cc: \(cc)\r\n" }
        if let bcc = bcc { emailContent += "Bcc: \(bcc)\r\n" }
        emailContent += "Subject: \(subject)\r\n"
        emailContent += "Content-Type: text/plain; charset=utf-8\r\n"
        emailContent += "\r\n"
        emailContent += body

        // Encode message in base64url
        let messageData = emailContent.data(using: .utf8)!
        let base64Message = messageData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let requestBody = ["raw": base64Message]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        return response?["id"] as? String ?? "unknown"
    }

    func replyToEmail(messageId: String, body: String) async throws -> String {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Get original message to extract reply information
        let originalMessage = try await getGmailMessage(messageId: messageId)

        // Extract subject and sender information
        let headers = originalMessage.payload.headers
        let originalSubject = headers.first(where: { $0.name.lowercased() == "subject" })?.value ?? ""
        let replySubject = originalSubject.hasPrefix("Re:") ? originalSubject : "Re: \(originalSubject)"
        let replyTo = headers.first(where: { $0.name.lowercased() == "from" })?.value ?? ""

        return try await sendEmail(to: replyTo, subject: replySubject, body: body)
    }

    func markAsRead(messageId: String) async throws {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        let requestBody = ["removeLabelIds": ["UNREAD"]]
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)

        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)/modify")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        _ = try await URLSession.shared.data(for: request)
    }
    
    // MARK: - Enhanced Google Drive Integration for Personal Assistant

    func uploadToDrive(fileName: String, data: Data, mimeType: String, description: String? = nil) async throws -> DriveFileResult {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Enhanced metadata with better organization
        var metadata: [String: Any] = [
            "name": fileName, // No PHI redaction in Drive for personal assistant
            "mimeType": mimeType,
            "description": description ?? "Uploaded via JarvisVertexAI Personal Assistant",
            "properties": [
                "source": "JarvisVertexAI",
                "uploadDate": ISO8601DateFormatter().string(from: Date()),
                "ephemeral": "true",
                "autoDelete": "24h"
            ]
        ]

        // Add folder organization for better file management
        if let folderId = try? await getOrCreateAssistantFolder() {
            metadata["parents"] = [folderId]
        }

        // Multipart upload with progress tracking
        let boundary = UUID().uuidString
        var body = Data()

        // Metadata part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(try JSONSerialization.data(withJSONObject: metadata))
        body.append("\r\n".data(using: .utf8)!)

        // File content part
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,size,mimeType,createdTime,webViewLink")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (responseData, _) = try await URLSession.shared.data(for: request)
        let file = try JSONDecoder().decode(DriveFileDetailed.self, from: responseData)

        // Schedule deletion after 24 hours
        scheduleFileDeletion(fileId: file.id, token: token)

        return DriveFileResult(
            id: file.id,
            name: file.name,
            size: file.sizeInt,
            mimeType: file.mimeType,
            createdTime: file.createdTime,
            webViewLink: file.webViewLink
        )
    }

    func listDriveFiles(query: String? = nil, maxResults: Int = 20) async throws -> [DriveFileResult] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        var queryItems = [
            URLQueryItem(name: "pageSize", value: String(maxResults)),
            URLQueryItem(name: "fields", value: "files(id,name,size,mimeType,createdTime,webViewLink,description)")
        ]

        // Build search query
        var searchQuery = "trashed=false"
        if let query = query {
            searchQuery += " and (name contains '\(query)' or fullText contains '\(query)')"
        }

        // Only show files created by this app for privacy
        searchQuery += " and properties has {key='source' and value='JarvisVertexAI'}"

        queryItems.append(URLQueryItem(name: "q", value: searchQuery))
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DriveListResponse.self, from: data)

        return response.files.map { file in
            DriveFileResult(
                id: file.id,
                name: file.name,
                size: file.sizeInt,
                mimeType: file.mimeType,
                createdTime: file.createdTime,
                webViewLink: file.webViewLink
            )
        }
    }

    func downloadFromDrive(fileId: String) async throws -> (data: Data, fileName: String, mimeType: String) {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Get file metadata first
        let metadataURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=name,mimeType")!
        var metadataRequest = URLRequest(url: metadataURL)
        metadataRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (metadataData, _) = try await URLSession.shared.data(for: metadataRequest)
        let fileInfo = try JSONDecoder().decode(DriveFileInfo.self, from: metadataData)

        // Download file content
        let downloadURL = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (fileData, _) = try await URLSession.shared.data(for: downloadRequest)

        return (data: fileData, fileName: fileInfo.name, mimeType: fileInfo.mimeType)
    }

    func deleteDriveFile(fileId: String) async throws {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        _ = try await URLSession.shared.data(for: request)
    }

    private func getOrCreateAssistantFolder() async throws -> String {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }

        // Search for existing JarvisVertexAI folder
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "name='JarvisVertexAI' and mimeType='application/vnd.google-apps.folder' and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id)")
        ]

        var searchRequest = URLRequest(url: components.url!)
        searchRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (searchData, _) = try await URLSession.shared.data(for: searchRequest)
        let searchResponse = try JSONDecoder().decode(DriveListResponse.self, from: searchData)

        if let existingFolder = searchResponse.files.first {
            return existingFolder.id
        }

        // Create new folder
        let folderMetadata: [String: Any] = [
            "name": "JarvisVertexAI",
            "mimeType": "application/vnd.google-apps.folder",
            "description": "Files created by JarvisVertexAI Personal Assistant"
        ]

        var createRequest = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: folderMetadata)

        let (createData, _) = try await URLSession.shared.data(for: createRequest)
        let folder = try JSONDecoder().decode(DriveFileBasic.self, from: createData)

        return folder.id
    }
    
    // MARK: - Privacy & Security Helpers
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = verifier.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateConsentHash(scopes: [String]) -> String {
        let consentString = scopes.sorted().joined(separator: ",") + Date().description
        let hash = SHA256.hash(data: consentString.data(using: .utf8)!)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func buildAuthURL(codeChallenge: String, scopes: [String]) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent") // Always show consent
        ]
        return components.url!
    }
    
    private func extractCode(from url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value ?? ""
    }
    
    private func storeCredentials(token: TokenResponse, scopes: [String]) {
        // Store in keychain with encryption
        keychain.set(token.accessToken, forKey: "google_access_token")
        if let refreshToken = token.refreshToken {
            keychain.set(refreshToken, forKey: "google_refresh_token")
        }
        
        // Store consent record
        let consentData = try? JSONEncoder().encode(UserConsent(
            timestamp: Date(),
            scopes: scopes,
            consentHash: generateConsentHash(scopes: scopes),
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn))
        ))
        
        if let data = consentData {
            keychain.setData(data, forKey: "google_consent_record")
        }
    }
    
    private func loadStoredCredentials() {
        // Check if we have stored credentials
        if let consentData = keychain.getData("google_consent_record"),
           let consent = try? JSONDecoder().decode(UserConsent.self, from: consentData) {

            self.userConsent = consent

            // Load access token if available and consent is valid
            if consent.isValid, let token = keychain.getString("google_access_token") {
                self.accessToken = token
                self.isAuthenticated = true
            }
            // If consent exists but access token is missing, check for refresh token
            else if keychain.getString("google_refresh_token") != nil {
                // We have a refresh token, mark as authenticated
                // The actual token refresh will happen on first API call
                self.isAuthenticated = true
                print("📝 Access token expired but refresh token available")
            }
        }
    }
    
    private func logConsentEvent(scopes: [String]) {
        // Log to local audit log
        let event = AuditEvent(
            timestamp: Date(),
            eventType: "oauth_consent",
            scopes: scopes,
            consentHash: generateConsentHash(scopes: scopes)
        )
        
        // Note: logAuditEvent will be implemented when ObjectBox is re-enabled
        // try? SimpleDataManager.shared.logAuditEvent(event)
    }
    
    private func scheduleFileDeletion(fileId: String, token: String) {
        // Schedule deletion after 24 hours
        DispatchQueue.global().asyncAfter(deadline: .now() + 86400) {
            Task {
                var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
    
    // MARK: - Revoke Access
    func revokeAccess() async throws {
        guard let token = accessToken else { return }
        
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "token=\(token)".data(using: .utf8)
        
        _ = try await URLSession.shared.data(for: request)
        
        // Clear all stored credentials
        keychain.delete("google_access_token")
        keychain.delete("google_refresh_token")
        keychain.delete("google_consent_record")
        
        await MainActor.run {
            self.accessToken = nil
            self.isAuthenticated = false
            self.userConsent = nil
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension GoogleOAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - Response Models
struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

// MARK: - Enhanced Tasks Response Models

struct GoogleTaskDetailed: Codable, Identifiable {
    let id: String
    let title: String
    let notes: String?
    let due: String?
    let status: String
    let updated: String?
    let completed: String?
    let parent: String?
    let position: String?

    var isCompleted: Bool {
        return status == "completed"
    }

    var isDue: Bool {
        guard let dueDateString = due,
              let dueDate = ISO8601DateFormatter().date(from: dueDateString) else {
            return false
        }
        return dueDate <= Date()
    }
}

struct GoogleTaskList: Codable, Identifiable {
    let id: String
    let title: String
    let updated: String?
}

struct TaskWithList {
    let task: GoogleTaskDetailed
    let listName: String
    let listId: String
}

struct TasksDetailedResponse: Codable {
    let items: [GoogleTaskDetailed]?
}

struct TaskListsResponse: Codable {
    let items: [GoogleTaskList]
}

struct CalendarEvent: Codable, Identifiable {
    let id: String
    var summary: String
    var description: String?
    var location: String?
    let start: EventDateTime
    let end: EventDateTime
    var attendees: [Attendee]?
    
    struct EventDateTime: Codable {
        let dateTime: String?
        let date: String?
    }
    
    struct Attendee: Codable {
        let email: String
    }
}

struct CalendarResponse: Codable {
    let items: [CalendarEvent]
}

struct GmailMessage: Codable {
    let id: String
    let threadId: String
    let labelIds: [String]
    let snippet: String
    let payload: MessagePayload
    let sizeEstimate: Int?
    let historyId: String?

    struct MessagePayload: Codable {
        let headers: [MessageHeader]
        let body: MessageBody?
        let parts: [MessagePart]?

        struct MessageHeader: Codable {
            let name: String
            let value: String
        }

        struct MessageBody: Codable {
            let data: String?
            let size: Int
        }

        struct MessagePart: Codable {
            let headers: [MessageHeader]?
            let body: MessageBody?
            let parts: [MessagePart]?
        }
    }
}

struct GmailListResponse: Codable {
    let messages: [MessageReference]
    let nextPageToken: String?
    let resultSizeEstimate: Int?

    struct MessageReference: Codable {
        let id: String
        let threadId: String
    }
}

// MARK: - Enhanced Drive Response Models

struct DriveFileResult {
    let id: String
    let name: String
    let size: Int64?
    let mimeType: String
    let createdTime: String?
    let webViewLink: String?
}

struct DriveFileDetailed: Codable {
    let id: String
    let name: String
    let size: String?
    let mimeType: String
    let createdTime: String?
    let webViewLink: String?

    var sizeInt: Int64? {
        guard let size = size else { return nil }
        return Int64(size)
    }
}

struct DriveFileBasic: Codable {
    let id: String
    let name: String
    let mimeType: String?
}

struct DriveFileInfo: Codable {
    let name: String
    let mimeType: String
}

struct DriveListResponse: Codable {
    let files: [DriveFileDetailed]
    let nextPageToken: String?
}

struct AuditEvent: Codable {
    let timestamp: Date
    let eventType: String
    let scopes: [String]
    let consentHash: String
}

enum OAuthError: Error {
    case notAuthenticated
    case noRefreshToken
    case unknown
}

// MARK: - Keychain Manager
class KeychainManager {
    func set(_ string: String, forKey key: String) {
        let data = string.data(using: .utf8)!
        setData(data, forKey: key)
    }
    
    func getString(_ key: String) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    func setData(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
    
    func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}