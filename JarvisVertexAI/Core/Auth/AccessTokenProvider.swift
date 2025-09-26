//
//  AccessTokenProvider.swift
//  JarvisVertexAI
//
//  Google Cloud OAuth2 & Service Account Authentication for Vertex AI
//  Privacy-focused implementation with secure token management
//

import Foundation
import Security
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Authentication Errors

enum AccessTokenError: Error {
    case invalidConfiguration
    case networkError(Error)
    case authenticationFailed
    case tokenExpired
    case keychainError
    case invalidResponse
    case serviceAccountError
    case missingCredentials
}

// MARK: - Token Response Models

private struct AccessTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct ServiceAccountKey: Codable {
    let type: String
    let projectId: String
    let privateKeyId: String
    let privateKey: String
    let clientEmail: String
    let clientId: String
    let authUri: String
    let tokenUri: String
    let authProviderX509CertUrl: String
    let clientX509CertUrl: String

    enum CodingKeys: String, CodingKey {
        case type
        case projectId = "project_id"
        case privateKeyId = "private_key_id"
        case privateKey = "private_key"
        case clientEmail = "client_email"
        case clientId = "client_id"
        case authUri = "auth_uri"
        case tokenUri = "token_uri"
        case authProviderX509CertUrl = "auth_provider_x509_cert_url"
        case clientX509CertUrl = "client_x509_cert_url"
    }
}

// MARK: - Stored Token Model

private struct StoredToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiryDate: Date
    let tokenType: String
    let scope: String?
}

// MARK: - Access Token Provider

final class AccessTokenProvider {

    // MARK: - Properties

    static let shared = AccessTokenProvider()

    private let keychainService = "com.focusedalpha.jarvisvertexai.auth"
    private let tokenKey = "vertex_ai_token"
    private let refreshTokenKey = "vertex_ai_refresh_token"

    // OAuth2 Configuration
    private let clientId: String
    private let clientSecret: String
    private let redirectUri = "com.focusedalpha.jarvisvertexai://oauth"

    // Vertex AI specific scopes (privacy-focused, minimal required)
    private let requiredScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/generative-language"
    ]

    // Service Account support
    private var serviceAccountKey: ServiceAccountKey?

    // URLs
    private let authBaseUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenUrl = "https://oauth2.googleapis.com/token"
    private let serviceAccountTokenUrl = "https://oauth2.googleapis.com/token"

    // Token management
    private var currentToken: StoredToken?
    private let tokenRefreshQueue = DispatchQueue(label: "com.jarvisvertexai.token-refresh", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        // Load configuration from environment
        self.clientId = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"] ?? ""
        self.clientSecret = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_SECRET"] ?? ""

        // Load service account key if available
        loadServiceAccountKey()

        // Load existing token from keychain
        loadStoredToken()

        print("✅ AccessTokenProvider initialized")
    }

    // MARK: - Public Interface

    /// Get a valid access token for Vertex AI
    func getAccessToken() async throws -> String {
        // Check environment variable first (highest priority)
        if let envToken = ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"], !envToken.isEmpty {
            print("✅ Using access token from environment variable")
            return envToken
        }

        // Check if we have a valid cached token
        if let token = currentToken, token.expiryDate > Date().addingTimeInterval(300) {
            return token.accessToken
        }

        // Try to refresh existing token
        if let token = currentToken, let refreshToken = token.refreshToken {
            do {
                return try await refreshAccessToken(refreshToken: refreshToken)
            } catch {
                print("⚠️ Token refresh failed, attempting new authentication: \(error)")
            }
        }

        // Attempt service account authentication first (production)
        if serviceAccountKey != nil {
            return try await authenticateWithServiceAccount()
        }

        // Check legacy keychain storage (backwards compatibility)
        if let keychainToken = KeychainHelper.getString("google_access_token"), !keychainToken.isEmpty {
            print("✅ Using legacy token from keychain")
            return keychainToken
        }

        // All methods failed
        throw AccessTokenError.missingCredentials
    }

    /// Force refresh token (for handling 401 errors)
    func refreshTokenForced() async throws -> String {
        // Clear potentially invalid cached token
        currentToken = nil

        // Try to get a fresh token
        return try await getAccessToken()
    }

    /// Get access token with automatic retry on authentication failures
    func getAccessTokenWithRetry() async throws -> String {
        return try await refreshTokenForced()
    }

    /// Clear all stored tokens and credentials
    func clearTokens() async {
        currentToken = nil
        await deleteFromKeychain(key: tokenKey)
        await deleteFromKeychain(key: refreshTokenKey)
        print("🔒 All tokens cleared from secure storage")
    }

    /// Validate current authentication status
    func isAuthenticated() -> Bool {
        // Check environment variable
        if let envToken = ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"], !envToken.isEmpty {
            return true
        }

        // Check stored token
        guard let token = currentToken else { return false }
        return token.expiryDate > Date().addingTimeInterval(60) // 1 minute buffer
    }

    // MARK: - Service Account Authentication

    private func loadServiceAccountKey() {
        // Try to load from environment variable (JSON string)
        if let keyJson = ProcessInfo.processInfo.environment["GOOGLE_SERVICE_ACCOUNT_KEY"] {
            do {
                let keyData = keyJson.data(using: .utf8) ?? Data()
                serviceAccountKey = try JSONDecoder().decode(ServiceAccountKey.self, from: keyData)
                print("✅ Service account key loaded from environment")
                return
            } catch {
                print("⚠️ Failed to parse service account key: \(error)")
            }
        }

        // Try to load from file path
        if let keyPath = ProcessInfo.processInfo.environment["GOOGLE_SERVICE_ACCOUNT_PATH"] {
            do {
                let keyData = try Data(contentsOf: URL(fileURLWithPath: keyPath))
                serviceAccountKey = try JSONDecoder().decode(ServiceAccountKey.self, from: keyData)
                print("✅ Service account key loaded from file: \(keyPath)")
                return
            } catch {
                print("⚠️ Failed to load service account key from file: \(error)")
            }
        }

        print("ℹ️ No service account key found, will use OAuth2 flow")
    }

    private func authenticateWithServiceAccount() async throws -> String {
        guard let serviceAccount = serviceAccountKey else {
            throw AccessTokenError.missingCredentials
        }

        // Create JWT assertion
        let jwt = try createJWTAssertion(serviceAccount: serviceAccount)

        // Exchange JWT for access token
        var request = URLRequest(url: URL(string: serviceAccountTokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": jwt
        ]

        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw AccessTokenError.authenticationFailed
            }

            let tokenResponse = try JSONDecoder().decode(AccessTokenResponse.self, from: data)

            // Store token securely
            let storedToken = StoredToken(
                accessToken: tokenResponse.accessToken,
                refreshToken: nil, // Service account tokens don't have refresh tokens
                expiryDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 300)), // 5 min buffer
                tokenType: tokenResponse.tokenType,
                scope: tokenResponse.scope
            )

            currentToken = storedToken
            await storeTokenInKeychain(token: storedToken)

            print("✅ Service account authentication successful")
            return tokenResponse.accessToken

        } catch {
            print("❌ Service account authentication failed: \(error)")
            throw AccessTokenError.networkError(error)
        }
    }

    private func createJWTAssertion(serviceAccount: ServiceAccountKey) throws -> String {
        let header = [
            "alg": "RS256",
            "typ": "JWT",
            "kid": serviceAccount.privateKeyId
        ]

        let now = Int(Date().timeIntervalSince1970)
        let expiration = now + 3600 // 1 hour

        let payload = [
            "iss": serviceAccount.clientEmail,
            "scope": requiredScopes.joined(separator: " "),
            "aud": serviceAccount.tokenUri,
            "exp": expiration,
            "iat": now
        ] as [String: Any]

        // Encode header and payload
        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerBase64 = headerData.base64URLEncodedString()
        let payloadBase64 = payloadData.base64URLEncodedString()

        let signingString = "\(headerBase64).\(payloadBase64)"

        // Sign with private key (simplified implementation)
        let signature = try signRS256(data: signingString.data(using: .utf8)!, privateKey: serviceAccount.privateKey)
        let signatureBase64 = signature.base64URLEncodedString()

        return "\(signingString).\(signatureBase64)"
    }

    private func signRS256(data: Data, privateKey: String) throws -> Data {
        // This is a simplified implementation
        // In production, you would use Security framework for proper RSA signing
        return SHA256.hash(data: data).withUnsafeBytes { Data($0) }
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AccessTokenError.invalidResponse
            }

            // Handle 401/403 errors specifically
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                print("⚠️ Refresh token expired or invalid (HTTP \(httpResponse.statusCode))")
                throw AccessTokenError.tokenExpired
            }

            guard httpResponse.statusCode == 200 else {
                print("❌ Token refresh failed with HTTP \(httpResponse.statusCode)")
                throw AccessTokenError.authenticationFailed
            }

            let tokenResponse = try JSONDecoder().decode(AccessTokenResponse.self, from: data)

            // Update stored token
            let storedToken = StoredToken(
                accessToken: tokenResponse.accessToken,
                refreshToken: tokenResponse.refreshToken ?? refreshToken, // Keep old refresh token if new one not provided
                expiryDate: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn - 300)),
                tokenType: tokenResponse.tokenType,
                scope: tokenResponse.scope
            )

            currentToken = storedToken
            await storeTokenInKeychain(token: storedToken)

            print("✅ Token refreshed successfully")
            return tokenResponse.accessToken

        } catch {
            if error is AccessTokenError {
                throw error
            }
            throw AccessTokenError.networkError(error)
        }
    }

    // MARK: - Keychain Storage

    private func storeTokenInKeychain(token: StoredToken) async {
        do {
            let tokenData = try JSONEncoder().encode(token)

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: tokenKey,
                kSecValueData as String: tokenData,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]

            // Delete existing item
            SecItemDelete(query as CFDictionary)

            // Add new item
            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess {
                print("✅ Token stored securely in Keychain")
            } else {
                print("⚠️ Failed to store token in Keychain: \(status)")
            }

        } catch {
            print("❌ Failed to encode token: \(error)")
        }
    }

    private func loadStoredToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let token = try? JSONDecoder().decode(StoredToken.self, from: data) {
            currentToken = token
            print("✅ Token loaded from Keychain")
        }
    }

    private func deleteFromKeychain(key: String) async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Backwards Compatibility (static methods)

    /// Static method for backwards compatibility with existing code
    static func currentToken() -> String? {
        // Check environment variable first (highest priority)
        if let envToken = ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"], !envToken.isEmpty {
            return envToken
        }

        // Check legacy keychain storage (backwards compatibility)
        if let keychainToken = KeychainHelper.getString("google_access_token"), !keychainToken.isEmpty {
            return keychainToken
        }

        return nil
    }

    // MARK: - Privacy & Configuration

    func getAuthConfiguration() -> [String: Any] {
        return [
            "authMethod": serviceAccountKey != nil ? "Service Account" : "OAuth2/Environment",
            "scopes": requiredScopes,
            "tokenStorage": "Secure Keychain",
            "analytics": "Disabled",
            "dataCollection": "None",
            "privacy": "Maximum",
            "hasValidToken": isAuthenticated()
        ]
    }
}

// MARK: - Backwards Compatibility

// Minimal Keychain helper (mirrors the one in GoogleOAuthManager)
private enum KeychainHelper {
    static func getString(_ key: String) -> String? {
        guard let data = getData(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }
}

// MARK: - Data Extensions

private extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

