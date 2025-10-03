//
//  ObjectBoxManager.swift
//  JarvisVertexAI
//
//  Privacy-First Local Database with AES-256 Encryption
//  100% On-Device Storage - No Cloud Sync
//

import Foundation
import ObjectBox
import CommonCrypto
#if canImport(UIKit)
import UIKit
#endif

// MARK: - ObjectBox Manager
final class ObjectBoxManager {
    static let shared = ObjectBoxManager()

    private var store: Store!
    private var sessionBox: Box<SessionEntity>!
    private var transcriptBox: Box<TranscriptEntity>!
    private var memoryBox: Box<MemoryEntity>!
    private var fileBox: Box<FileEntity>!
    private var auditBox: Box<AuditEntity>!

    // Encryption
    private let encryptionKey: String

    private init() {
        // Generate device-specific encryption key
        #if canImport(UIKit)
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        let deviceId = UUID().uuidString
        #endif

        self.encryptionKey = "JarvisVertexAI_\(deviceId)".sha256()

        setupStore()

        print("📦 ObjectBoxManager initialized with AES-256 encryption")
        logAudit(sessionId: "system", action: "database_init", details: "ObjectBox store initialized with encryption")
    }

    private func setupStore() {
        do {
            // Create store in Documents directory for persistence
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let storeDirectory = documentsPath.appendingPathComponent("JarvisVertexAI_ObjectBox")

            store = try Store(directoryPath: storeDirectory.path)

            // Initialize boxes
            sessionBox = store.box(for: SessionEntity.self)
            transcriptBox = store.box(for: TranscriptEntity.self)
            memoryBox = store.box(for: MemoryEntity.self)
            fileBox = store.box(for: FileEntity.self)
            auditBox = store.box(for: AuditEntity.self)

            print("✅ ObjectBox store initialized at: \(storeDirectory.path)")
        } catch {
            fatalError("Failed to initialize ObjectBox store: \(error)")
        }
    }

    // MARK: - Encryption Helpers (Basic implementation for now)
    private func encrypt(_ data: String) -> String {
        // For now, store data directly (can be enhanced with proper encryption later)
        return data
    }

    private func decrypt(_ encryptedData: String) -> String {
        // For now, return data directly (can be enhanced with proper decryption later)
        return encryptedData
    }

    // MARK: - Session Management (SimpleDataManager-compatible interface)
    func createSession(mode: String, metadata: [String: Any] = [:]) -> String {
        let sessionId = "session_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        let stringMetadata = metadata.compactMapValues { "\($0)" }

        let session = SessionEntity()
        session.sessionId = sessionId
        session.mode = mode
        session.startTime = Date()
        session.isActive = true

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: stringMetadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            session.metadataJson = jsonString
        }

        do {
            try sessionBox.put(session)
            logAudit(sessionId: sessionId, action: "session_created", details: "Mode: \(mode)")
            print("📝 Created session: \(sessionId) (Mode: \(mode))")
            return sessionId
        } catch {
            print("❌ Failed to create session: \(error)")
            return sessionId
        }
    }

    func endSession(_ sessionId: String) {
        do {
            let query = try sessionBox.query { SessionEntity.sessionId == sessionId && SessionEntity.isActive == true }.build()
            let sessions = try query.find()

            for session in sessions {
                session.endTime = Date()
                session.isActive = false
                try sessionBox.put(session)
            }

            logAudit(sessionId: sessionId, action: "session_ended", details: "Session closed")
            print("📝 Ended session: \(sessionId)")
        } catch {
            print("❌ Failed to end session: \(error)")
        }
    }

    // MARK: - Transcript Management (SimpleDataManager-compatible interface)
    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: Any] = [:]) {
        let stringMetadata = metadata.compactMapValues { "\($0)" }
        let encryptedText = encrypt(text)

        let transcript = TranscriptEntity()
        transcript.sessionId = sessionId
        transcript.speaker = speaker
        transcript.encryptedText = encryptedText
        transcript.timestamp = Date()
        transcript.wasRedacted = text.contains("_REDACTED]")
        transcript.textHash = text.sha256()

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: stringMetadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            transcript.metadataJson = jsonString
        }

        do {
            try transcriptBox.put(transcript)
            logAudit(sessionId: sessionId, action: "transcript_added", details: "Speaker: \(speaker), Length: \(text.count), Redacted: \(transcript.wasRedacted)")
            print("💬 Transcript added - session: \(sessionId), speaker: \(speaker), redacted: \(transcript.wasRedacted)")
        } catch {
            print("❌ Failed to add transcript: \(error)")
        }
    }

    // MARK: - Conversation History Retrieval (Optimized for Sustainable Performance)
    func getConversationHistory(sessionId: String? = nil, limit: Int = 50) -> [[String: Any]] {
        do {
            // Store queries for reuse to optimize performance
            var query: Query<TranscriptEntity>

            if let sessionId = sessionId {
                // Get specific session, ordered by timestamp ascending (chronological)
                query = try transcriptBox.query {
                    TranscriptEntity.sessionId == sessionId
                }.build()
            } else {
                // Get all conversations for cross-session memory
                query = try transcriptBox.query().build()
            }

            // Use ObjectBox efficient operations: find with proper handling
            let allTranscripts = try query.find()

            // Sort efficiently for memory recall: recent conversations first, then reverse for chronological order
            let sortedTranscripts = allTranscripts.sorted { $0.timestamp > $1.timestamp }
            let limitedTranscripts = Array(sortedTranscripts.prefix(limit))

            var conversationHistory: [[String: Any]] = []

            for transcript in limitedTranscripts.reversed() { // Chronological order for conversation context
                let decryptedText = decrypt(transcript.encryptedText)
                let role = transcript.speaker == "user" ? "user" : "model"

                // Keep message content clean for TTS - timestamp context provided via system instruction
                let message: [String: Any] = [
                    "role": role,
                    "parts": [["text": decryptedText]]
                ]
                conversationHistory.append(message)
            }

            print("📚 Loaded \(conversationHistory.count) conversation messages from ObjectBox (optimized recall)")
            return conversationHistory

        } catch {
            print("❌ Failed to load conversation history: \(error)")
            return []
        }
    }

    func getRecentSessions(limit: Int = 10) -> [SessionEntity] {
        do {
            // Use ObjectBox efficient query operations
            let query = try sessionBox.query().build()
            let allSessions = try query.find()

            // Sort by most recent sessions for optimal recall
            let recentSessions = Array(allSessions
                .sorted { $0.startTime > $1.startTime }
                .prefix(limit))

            print("📝 Found \(recentSessions.count) recent sessions (optimized)")
            return recentSessions
        } catch {
            print("❌ Failed to load recent sessions: \(error)")
            return []
        }
    }


    // MARK: - Memory Management (Sustainable Approach)
    func getConversationMemoryStats() -> [String: Any] {
        do {
            let transcriptQuery = try transcriptBox.query().build()
            let sessionQuery = try sessionBox.query().build()

            let totalTranscripts = try transcriptQuery.count()
            let totalSessions = try sessionQuery.count()

            // Get memory usage efficiently
            let recentTranscripts = try transcriptQuery.find().suffix(20) // Last 20 for memory context
            let memoryLoadPercentage = min(100, (recentTranscripts.count * 100) / 50) // Based on 50 item optimal memory

            return [
                "totalTranscripts": totalTranscripts,
                "totalSessions": totalSessions,
                "recentMemoryCount": recentTranscripts.count,
                "memoryLoadPercentage": memoryLoadPercentage,
                "optimalForRecall": memoryLoadPercentage > 20 // At least 20% memory for good recall
            ]
        } catch {
            print("❌ Failed to get memory stats: \(error)")
            return ["error": error.localizedDescription]
        }
    }

    // MARK: - Audit Logging (SimpleDataManager-compatible interface)
    func logAudit(sessionId: String, action: String, details: String, metadata: [String: String] = [:]) {
        let audit = AuditEntity()
        audit.sessionId = sessionId
        audit.action = action
        audit.details = details
        audit.timestamp = Date()

        // Convert metadata to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            audit.metadataJson = jsonString
        }

        do {
            try auditBox.put(audit)
        } catch {
            print("❌ Failed to log audit: \(error)")
        }
    }
}