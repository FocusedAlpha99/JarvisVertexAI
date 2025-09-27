//
//  VertexConfig.swift
//  JarvisVertexAI
//
//  Centralized configuration management for Vertex AI and environment variables
//  Loads from .env.local and validates required configuration
//

import Foundation
import Security

// MARK: - Configuration Errors

enum ConfigurationError: Error, LocalizedError {
    case missingRequiredVariable(String)
    case invalidConfiguration(String)
    case fileNotFound(String)
    case authenticationRequired
    case projectNotConfigured

    var errorDescription: String? {
        switch self {
        case .missingRequiredVariable(let variable):
            return "Missing required environment variable: \(variable)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .fileNotFound(let file):
            return "Configuration file not found: \(file)"
        case .authenticationRequired:
            return "No valid authentication method configured. Please set up service account, OAuth2, or access token."
        case .projectNotConfigured:
            return "Google Cloud Project ID not configured. Please set GOOGLE_CLOUD_PROJECT_ID or VERTEX_PROJECT_ID."
        }
    }
}

// MARK: - Vertex Configuration Manager

final class VertexConfig {

    // MARK: - Singleton

    static let shared = VertexConfig()

    // MARK: - Configuration Properties

    // Google Cloud Project Configuration
    private(set) var projectId: String = ""
    private(set) var region: String = "us-central1"
    private(set) var cmekKey: String?

    // Authentication Configuration
    private(set) var serviceAccountPath: String?
    private(set) var serviceAccountKey: String?
    private(set) var oauthClientId: String?
    private(set) var oauthClientSecret: String?
    private(set) var accessToken: String?

    // API Configuration
    private(set) var geminiModel: String = "gemini-2.0-flash-exp"
    private(set) var geminiApiKey: String?
    private(set) var apiEndpoint: String?
    private(set) var audioEndpoint: String?

    // Privacy & Security Configuration
    private(set) var enablePhiRedaction: Bool = true
    private(set) var enableAuditLogging: Bool = true
    private(set) var dataRetentionDays: Int = 30
    private(set) var disablePromptLogging: Bool = true
    private(set) var disableDataRetention: Bool = true
    private(set) var localOnlyMode: Bool = true

    // App Configuration
    private(set) var appBundleId: String = "com.focusedalpha.jarvisvertexai"
    private(set) var appVersion: String = "1.0.0"
    private(set) var debugLogging: Bool = false
    private(set) var testMode: Bool = false

    // Advanced Configuration
    private(set) var apiTimeout: TimeInterval = 30.0
    private(set) var maxFileUploadSizeMB: Int = 10
    private(set) var enableExperimentalFeatures: Bool = false

    // Configuration Status
    private(set) var isConfigured: Bool = false
    private(set) var configurationErrors: [ConfigurationError] = []
    private(set) var loadedFromFile: String?

    // MARK: - Initialization

    private init() {
        print("🚨 DEBUG: VertexConfig initializing...")
        loadConfiguration()
        print("🚨 DEBUG: VertexConfig loaded - isConfigured: \(isConfigured)")
        print("🚨 DEBUG: Project ID: \(projectId)")
        let hasToken = !(ProcessInfo.processInfo.environment["VERTEX_ACCESS_TOKEN"]?.isEmpty ?? true)
        print("🚨 DEBUG: Access Token exists: \(hasToken)")
    }

    // MARK: - Configuration Loading

    func loadConfiguration() {
        configurationErrors.removeAll()

        // Try loading from .env.local file first
        if let envPath = findEnvFile() {
            loadFromEnvFile(envPath)
            loadedFromFile = envPath
        }

        // Override with environment variables
        loadFromEnvironment()

        // Validate configuration
        validateConfiguration()

        // Log configuration status
        logConfigurationStatus()
    }

    private func findEnvFile() -> String? {
        let possiblePaths = [
            "./.env.local",
            "./.env",
            "./JarvisVertexAI/.env.local",
            // Absolute path to project directory
            "/Users/tim/JarvisVertexAI/.env.local",
            // Also support non-hidden resource copies for Simulator packaging
            Bundle.main.path(forResource: "env", ofType: "local"),
            Bundle.main.bundlePath + "/env.local",
            // Hidden file variants (may be skipped by packager)
            Bundle.main.path(forResource: ".env", ofType: "local"),
            Bundle.main.bundlePath + "/.env.local"
        ]

        print("🔍 DEBUG: Searching for .env.local file...")
        for path in possiblePaths {
            guard let path = path else { continue }
            let expandedPath = NSString(string: path).expandingTildeInPath
            print("🔍 Checking: \(expandedPath)")
            if FileManager.default.fileExists(atPath: expandedPath) {
                print("✅ Found .env.local at: \(expandedPath)")
                return expandedPath
            }
        }

        print("❌ No .env.local file found in any of the checked paths")
        return nil
    }

    private func loadFromEnvFile(_ filePath: String) {
        do {
            let content = try String(contentsOfFile: filePath)
            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                // Skip comments and empty lines
                if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                    continue
                }

                // Parse key=value pairs
                let components = trimmedLine.components(separatedBy: "=")
                guard components.count >= 2 else { continue }

                let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = components[1...].joined(separator: "=")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                // Set environment variable
                setenv(key, value, 0) // Don't overwrite existing env vars
            }

            print("✅ Loaded configuration from: \(filePath)")
        } catch {
            configurationErrors.append(.fileNotFound(filePath))
            print("⚠️ Failed to load env file: \(error)")
        }
    }

    private func loadFromEnvironment() {
        let env = ProcessInfo.processInfo.environment

        // Google Cloud Project Configuration
        projectId = env["GOOGLE_CLOUD_PROJECT_ID"] ??
                   env["VERTEX_PROJECT_ID"] ??
                   env["GCP_PROJECT_ID"] ?? ""

        region = env["GOOGLE_CLOUD_REGION"] ??
                env["VERTEX_REGION"] ??
                env["GCP_REGION"] ?? "us-central1"

        cmekKey = env["VERTEX_CMEK_KEY"]

        // Authentication Configuration
        serviceAccountPath = env["GOOGLE_SERVICE_ACCOUNT_PATH"]
        serviceAccountKey = env["GOOGLE_SERVICE_ACCOUNT_KEY"]
        oauthClientId = env["GOOGLE_OAUTH_CLIENT_ID"]
        oauthClientSecret = env["GOOGLE_OAUTH_CLIENT_SECRET"]
        accessToken = env["VERTEX_ACCESS_TOKEN"]

        // API Configuration
        geminiModel = env["GEMINI_MODEL"] ?? "gemini-2.0-flash-exp"
        geminiApiKey = env["GEMINI_API_KEY"]
        apiEndpoint = env["GEMINI_API_ENDPOINT"]
        audioEndpoint = env["VERTEX_AUDIO_ENDPOINT"]

        // Privacy & Security Configuration
        enablePhiRedaction = getBool(env["ENABLE_PHI_REDACTION"], defaultValue: true)
        enableAuditLogging = getBool(env["ENABLE_AUDIT_LOGGING"], defaultValue: true)
        dataRetentionDays = getInt(env["DATA_RETENTION_DAYS"], defaultValue: 30)
        disablePromptLogging = getBool(env["DISABLE_PROMPT_LOGGING"], defaultValue: true)
        disableDataRetention = getBool(env["DISABLE_DATA_RETENTION"], defaultValue: true)
        localOnlyMode = getBool(env["LOCAL_ONLY_MODE"], defaultValue: true)

        // App Configuration
        appBundleId = env["APP_BUNDLE_ID"] ?? "com.focusedalpha.jarvisvertexai"
        appVersion = env["APP_VERSION"] ?? "1.0.0"
        debugLogging = getBool(env["DEBUG_LOGGING"], defaultValue: false)
        testMode = getBool(env["TEST_MODE"], defaultValue: false)

        // Advanced Configuration
        apiTimeout = getDouble(env["API_TIMEOUT_SECONDS"], defaultValue: 30.0)
        maxFileUploadSizeMB = getInt(env["MAX_FILE_UPLOAD_SIZE_MB"], defaultValue: 10)
        enableExperimentalFeatures = getBool(env["ENABLE_EXPERIMENTAL_FEATURES"], defaultValue: false)
    }

    // MARK: - Configuration Validation

    private func validateConfiguration() {
        var isValid = true

        // Validate Google Cloud Project
        if projectId.isEmpty {
            configurationErrors.append(.projectNotConfigured)
            isValid = false
        }

        // Validate Authentication
        let hasServiceAccount = serviceAccountPath != nil || serviceAccountKey != nil
        let hasOAuth = oauthClientId != nil && oauthClientSecret != nil
        let hasAccessToken = accessToken != nil

        if !hasServiceAccount && !hasOAuth && !hasAccessToken {
            configurationErrors.append(.authenticationRequired)
            isValid = false
        }

        // Validate required API configuration for different auth methods
        if hasServiceAccount && serviceAccountPath != nil {
            // Validate service account file exists
            let path = NSString(string: serviceAccountPath!).expandingTildeInPath
            if !FileManager.default.fileExists(atPath: path) {
                configurationErrors.append(.fileNotFound(serviceAccountPath!))
                isValid = false
            }
        }

        // Validate region format
        if !isValidRegion(region) {
            configurationErrors.append(.invalidConfiguration("Invalid region format: \(region)"))
            isValid = false
        }

        // Validate numeric configurations
        if dataRetentionDays < 0 {
            configurationErrors.append(.invalidConfiguration("Data retention days cannot be negative"))
            isValid = false
        }

        if maxFileUploadSizeMB <= 0 {
            configurationErrors.append(.invalidConfiguration("Max file upload size must be positive"))
            isValid = false
        }

        isConfigured = isValid
    }

    private func isValidRegion(_ region: String) -> Bool {
        let regionPattern = "^[a-z]+-[a-z0-9]+(\\d+)?$"
        let regex = try? NSRegularExpression(pattern: regionPattern)
        let range = NSRange(location: 0, length: region.utf16.count)
        return regex?.firstMatch(in: region, options: [], range: range) != nil
    }

    // MARK: - Public Interface

    /// Reload configuration from environment and files
    func reloadConfiguration() {
        loadConfiguration()
    }

    /// Get current authentication method
    func getAuthenticationMethod() -> String {
        if serviceAccountPath != nil || serviceAccountKey != nil {
            return "Service Account"
        } else if oauthClientId != nil && oauthClientSecret != nil {
            return "OAuth2"
        } else if accessToken != nil {
            return "Access Token"
        } else {
            return "None"
        }
    }

    /// Get API endpoint URL
    func getApiEndpoint() -> String {
        if let customEndpoint = apiEndpoint {
            return customEndpoint
        }
        return "https://\(region)-aiplatform.googleapis.com"
    }

    /// Get Gemini Live API WebSocket URL base
    func getWebSocketBaseURL() -> String {
        return "wss://generativelanguage.googleapis.com"
    }

    /// Validate and return current access token
    func getCurrentAccessToken() -> String? {
        return accessToken
    }

    /// Get configuration summary for debugging
    func getConfigurationSummary() -> [String: Any] {
        return [
            "isConfigured": isConfigured,
            "projectId": projectId.isEmpty ? "NOT_SET" : projectId,
            "region": region,
            "authMethod": getAuthenticationMethod(),
            "geminiModel": geminiModel,
            "enablePhiRedaction": enablePhiRedaction,
            "localOnlyMode": localOnlyMode,
            "debugLogging": debugLogging,
            "testMode": testMode,
            "configurationErrors": configurationErrors.count,
            "loadedFromFile": loadedFromFile ?? "Environment only"
        ]
    }

    // MARK: - Helper Functions

    private func getBool(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value = value else { return defaultValue }
        return ["true", "1", "yes", "on"].contains(value.lowercased())
    }

    private func getInt(_ value: String?, defaultValue: Int) -> Int {
        guard let value = value, let intValue = Int(value) else { return defaultValue }
        return intValue
    }

    private func getDouble(_ value: String?, defaultValue: Double) -> Double {
        guard let value = value, let doubleValue = Double(value) else { return defaultValue }
        return doubleValue
    }

    private func logConfigurationStatus() {
        if isConfigured {
            print("✅ VertexConfig: Configuration loaded successfully")
            print("🔧 Project: \(projectId), Region: \(region)")
            print("🔐 Auth: \(getAuthenticationMethod())")
            if debugLogging {
                print("📊 Config Summary: \(getConfigurationSummary())")
            }
        } else {
            print("❌ VertexConfig: Configuration validation failed")
            for error in configurationErrors {
                print("   • \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Configuration Validation Extensions

extension VertexConfig {

    /// Check if configuration is valid for a specific feature
    func validateFor(_ feature: ConfigurationFeature) throws {
        guard isConfigured else {
            throw configurationErrors.first ?? ConfigurationError.invalidConfiguration("Configuration not loaded")
        }

        switch feature {
        case .audioSession:
            guard !projectId.isEmpty else {
                throw ConfigurationError.projectNotConfigured
            }
            guard accessToken != nil || serviceAccountPath != nil || serviceAccountKey != nil else {
                throw ConfigurationError.authenticationRequired
            }

        case .textMultimodal:
            guard !projectId.isEmpty else {
                throw ConfigurationError.projectNotConfigured
            }

        case .voiceChat:
            guard !projectId.isEmpty else {
                throw ConfigurationError.projectNotConfigured
            }

        case .fileUpload:
            guard maxFileUploadSizeMB > 0 else {
                throw ConfigurationError.invalidConfiguration("File upload size must be positive")
            }
        }
    }

    enum ConfigurationFeature {
        case audioSession
        case textMultimodal
        case voiceChat
        case fileUpload
    }
}
