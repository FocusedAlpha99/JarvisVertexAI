//
//  ObjectBoxEntities.swift
//  JarvisVertexAI
//
//  Privacy-First Local Database Entities with AES-256 Encryption
//  100% On-Device Storage - No Cloud Sync
//

import Foundation
import ObjectBox

// MARK: - Session Entity
// objectbox: entity
final class SessionEntity {
    var id: Id = 0
    var sessionId: String = ""
    var mode: String = ""
    var startTime: Date = Date()
    var endTime: Date?
    var isActive: Bool = true
    var metadataJson: String = "{}" // Encrypted metadata as JSON
    var encryptionKey: String = "" // Device-specific encryption key reference

    init() {} // Required by ObjectBox

    init(sessionId: String, mode: String, metadata: [String: String] = [:]) {
        self.sessionId = sessionId
        self.mode = mode
        self.startTime = Date()
        self.isActive = true

        // Convert metadata to encrypted JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.metadataJson = jsonString
        }

        // Generate device-specific encryption key reference
        self.encryptionKey = "device_key_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
    }

    // Helper to get metadata as dictionary
    func getMetadata() -> [String: String] {
        guard let data = metadataJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Transcript Entity
// objectbox: entity
final class TranscriptEntity {
    var id: Id = 0
    var sessionId: String = ""
    var speaker: String = ""
    var encryptedText: String = "" // PHI-redacted and encrypted text
    var timestamp: Date = Date()
    var wasRedacted: Bool = false
    var metadataJson: String = "{}"
    var textHash: String = "" // SHA-256 hash for integrity verification

    init() {} // Required by ObjectBox

    init(sessionId: String, speaker: String, text: String, metadata: [String: String] = [:], wasRedacted: Bool = false) {
        self.sessionId = sessionId
        self.speaker = speaker
        self.encryptedText = text // Will be encrypted by manager
        self.timestamp = Date()
        self.wasRedacted = wasRedacted

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.metadataJson = jsonString
        }

        // Generate hash for integrity
        self.textHash = text.sha256()
    }

    // Helper to get metadata as dictionary
    func getMetadata() -> [String: String] {
        guard let data = metadataJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Memory Entity (for embeddings and semantic search)
// objectbox: entity
final class MemoryEntity {
    var id: Id = 0
    var sessionId: String = ""
    var encryptedText: String = ""
    var embedding: [Float] = [] // Vector embedding for semantic search
    var timestamp: Date = Date()
    var metadataJson: String = "{}"
    var importance: Float = 0.5 // 0.0 to 1.0 importance score

    init() {} // Required by ObjectBox

    init(sessionId: String, text: String, embedding: [Float], metadata: [String: String] = [:], importance: Float = 0.5) {
        self.sessionId = sessionId
        self.encryptedText = text // Will be encrypted by manager
        self.embedding = embedding
        self.timestamp = Date()
        self.importance = max(0.0, min(1.0, importance)) // Clamp to 0-1

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.metadataJson = jsonString
        }
    }

    // Helper to get metadata as dictionary
    func getMetadata() -> [String: String] {
        guard let data = metadataJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - File Entity (for multimodal attachments)
// objectbox: entity
final class FileEntity {
    var id: Id = 0
    var sessionId: String = ""
    var fileName: String = ""
    var mimeType: String = ""
    var encryptedData: Data = Data() // Encrypted file data
    var fileSize: Int64 = 0
    var uploadTimestamp: Date = Date()
    var expiryTimestamp: Date = Date() // 24-hour expiry for ephemeral files
    var isExpired: Bool = false
    var metadataJson: String = "{}"

    init() {} // Required by ObjectBox

    init(sessionId: String, fileName: String, mimeType: String, data: Data, metadata: [String: String] = [:]) {
        self.sessionId = sessionId
        self.fileName = fileName
        self.mimeType = mimeType
        self.encryptedData = data // Will be encrypted by manager
        self.fileSize = Int64(data.count)
        self.uploadTimestamp = Date()
        self.expiryTimestamp = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
        self.isExpired = false

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.metadataJson = jsonString
        }
    }

    // Helper to check if file is expired
    func checkExpiry() -> Bool {
        let expired = Date() > expiryTimestamp
        if expired && !isExpired {
            isExpired = true
        }
        return expired
    }

    // Helper to get metadata as dictionary
    func getMetadata() -> [String: String] {
        guard let data = metadataJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - Audit Entity (for compliance logging)
// objectbox: entity
final class AuditEntity {
    var id: Id = 0
    var sessionId: String = ""
    var action: String = ""
    var details: String = ""
    var timestamp: Date = Date()
    var userId: String = "anonymous" // Privacy-first - no real user identification
    var metadataJson: String = "{}"

    init() {} // Required by ObjectBox

    init(sessionId: String, action: String, details: String, metadata: [String: String] = [:]) {
        self.sessionId = sessionId
        self.action = action
        self.details = details
        self.timestamp = Date()

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.metadataJson = jsonString
        }
    }

    // Helper to get metadata as dictionary
    func getMetadata() -> [String: String] {
        guard let data = metadataJson.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dict
    }
}

// MARK: - String Extension for SHA-256
extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return "" }

        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = digest.withUnsafeMutableBytes { bytes in
            data.withUnsafeBytes { dataBytes in
                CC_SHA256(dataBytes.baseAddress, CC_LONG(data.count), bytes.bindMemory(to: UInt8.self).baseAddress)
            }
        }

        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}

import CommonCrypto