import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - Google OAuth Manager with Minimal Scopes
class GoogleOAuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var userConsent: UserConsent?
    
    private let clientId: String
    private let redirectURI = "com.jarvis.vertexai:/oauth"
    private var authSession: ASWebAuthenticationSession?
    private let keychain = KeychainManager()
    private let phiRedactor = PHIRedactor()
    
    // Minimal scopes for privacy
    private let minimalScopes = [
        "https://www.googleapis.com/auth/tasks.readonly",      // Read-only Tasks
        "https://www.googleapis.com/auth/calendar.events.readonly", // Read-only Calendar
        "https://www.googleapis.com/auth/gmail.readonly",      // Read-only Gmail
        "https://www.googleapis.com/auth/drive.file"          // Only files created by app
    ]
    
    struct UserConsent {
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
        
        // Build auth URL with minimal scopes
        let authURL = buildAuthURL(
            codeChallenge: codeChallenge,
            scopes: minimalScopes
        )
        
        // Present consent screen
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "com.jarvis.vertexai"
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
        storeCredentials(token: token, scopes: minimalScopes)
        
        // Log consent event
        logConsentEvent(scopes: minimalScopes)
        
        await MainActor.run {
            self.accessToken = token.accessToken
            self.isAuthenticated = true
            self.userConsent = UserConsent(
                timestamp: Date(),
                scopes: minimalScopes,
                consentHash: generateConsentHash(scopes: minimalScopes),
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
    
    // MARK: - Tool Calling Methods with PHI Protection
    func getTasks() async throws -> [GoogleTask] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        
        var request = URLRequest(url: URL(string: "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(TasksResponse.self, from: data)
        
        // Redact PHI from task titles
        return response.items.map { task in
            var redactedTask = task
            redactedTask.title = phiRedactor.redactPHI(from: task.title)
            redactedTask.notes = task.notes.map { phiRedactor.redactPHI(from: $0) }
            return redactedTask
        }
    }
    
    func getCalendarEvents(startDate: Date, endDate: Date) async throws -> [CalendarEvent] {
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
        
        // Redact PHI from event details
        return response.items.map { event in
            var redactedEvent = event
            redactedEvent.summary = phiRedactor.redactPHI(from: event.summary)
            redactedEvent.description = event.description.map { phiRedactor.redactPHI(from: $0) }
            redactedEvent.location = event.location.map { phiRedactor.redactPHI(from: $0) }
            // Keep attendees redacted
            redactedEvent.attendees = nil
            return redactedEvent
        }
    }
    
    func searchGmail(query: String, maxResults: Int = 10) async throws -> [EmailSummary] {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        
        // Redact PHI from search query
        let redactedQuery = phiRedactor.redactPHI(from: query)
        
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "q", value: redactedQuery),
            URLQueryItem(name: "maxResults", value: String(maxResults))
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GmailListResponse.self, from: data)
        
        // Fetch message headers only (no body for privacy)
        var summaries: [EmailSummary] = []
        for message in response.messages {
            let messageURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(message.id)?format=metadata")!
            var messageRequest = URLRequest(url: messageURL)
            messageRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (messageData, _) = try await URLSession.shared.data(for: messageRequest)
            if let summary = try? JSONDecoder().decode(EmailSummary.self, from: messageData) {
                // Redact sender/recipient info
                var redactedSummary = summary
                redactedSummary.from = "[REDACTED]"
                redactedSummary.to = "[REDACTED]"
                redactedSummary.subject = phiRedactor.redactPHI(from: summary.subject)
                summaries.append(redactedSummary)
            }
        }
        
        return summaries
    }
    
    func uploadToDrive(fileName: String, data: Data, mimeType: String) async throws -> String {
        guard let token = accessToken else { throw OAuthError.notAuthenticated }
        
        // Create metadata
        let metadata = [
            "name": phiRedactor.redactPHI(from: fileName),
            "mimeType": mimeType,
            "properties": [
                "ephemeral": "true",
                "autoDelete": "24h"
            ]
        ]
        
        // Multipart upload
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
        
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        
        let (responseData, _) = try await URLSession.shared.data(for: request)
        let file = try JSONDecoder().decode(DriveFile.self, from: responseData)
        
        // Schedule deletion after 24 hours
        scheduleFileDeletion(fileId: file.id, token: token)
        
        return file.id
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
        if let token = keychain.getString("google_access_token"),
           let consentData = keychain.getData("google_consent_record"),
           let consent = try? JSONDecoder().decode(UserConsent.self, from: consentData),
           consent.isValid {
            
            self.accessToken = token
            self.userConsent = consent
            self.isAuthenticated = true
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
        
        try? ObjectBoxManager.shared.logAuditEvent(event)
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

struct GoogleTask: Codable, Identifiable {
    let id: String
    var title: String
    var notes: String?
    let due: String?
    let status: String
}

struct TasksResponse: Codable {
    let items: [GoogleTask]
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

struct EmailSummary: Codable {
    let id: String
    var from: String
    var to: String
    var subject: String
    let snippet: String
    let date: String
}

struct GmailListResponse: Codable {
    let messages: [GmailMessage]
    
    struct GmailMessage: Codable {
        let id: String
    }
}

struct DriveFile: Codable {
    let id: String
    let name: String
    let mimeType: String
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