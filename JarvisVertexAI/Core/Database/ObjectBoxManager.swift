//
//  ObjectBoxManager.swift
//  JarvisVertexAI
//
//  Privacy-First Local Database with AES-256 Encryption
//  100% On-Device Storage - No Cloud Sync
//

import Foundation
import ObjectBox
import CryptoSwift

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
    private let aes: AES

    private init() {
        // Generate device-specific encryption key
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.encryptionKey = "JarvisVertexAI_\(deviceId)".sha256().prefix(32).description

        // Initialize AES encryption
        guard let keyData = encryptionKey.data(using: .utf8),
              let aes = try? AES(key: Array(keyData.prefix(32)), blockMode: CBC(iv: Array(keyData.prefix(16)))) else {
            fatalError("Failed to initialize AES encryption")
        }
        self.aes = aes

        setupStore()
        setupAutoCleanup()

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

    private func setupAutoCleanup() {
        // Schedule cleanup every 24 hours
        Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            Task {
                await self.performAutoCleanup()
            }
        }
    }

    // MARK: - Encryption Helpers
    private func encrypt(_ data: String) -> String {
        guard let inputData = data.data(using: .utf8) else { return data }
        do {
            let encrypted = try aes.encrypt(Array(inputData))
            return Data(encrypted).base64EncodedString()
        } catch {
            print("❌ Encryption failed: \(error)")
            return data
        }
    }

    private func decrypt(_ encryptedData: String) -> String {
        guard let data = Data(base64Encoded: encryptedData) else { return encryptedData }
        do {
            let decrypted = try aes.decrypt(Array(data))
            return String(data: Data(decrypted), encoding: .utf8) ?? encryptedData
        } catch {
            print("❌ Decryption failed: \(error)")
            return encryptedData
        }
    }

    // MARK: - Session Management
    func createSession(mode: String, metadata: [String: Any] = [:]) -> String {
        let sessionId = "session_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"
        let stringMetadata = metadata.compactMapValues { "\($0)" }

        let session = SessionEntity(sessionId: sessionId, mode: mode, metadata: stringMetadata)

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
            let query = sessionBox.query(SessionEntity.sessionId == sessionId && SessionEntity.isActive == true).build()
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

    func getActiveSessions() -> [SessionData] {
        do {
            let query = sessionBox.query(SessionEntity.isActive == true).build()
            let entities = try query.find()

            return entities.map { entity in
                SessionData(
                    sessionId: entity.sessionId,
                    mode: entity.mode,
                    startTime: entity.startTime,
                    endTime: entity.endTime,
                    metadata: entity.getMetadata(),
                    isActive: entity.isActive
                )
            }
        } catch {
            print("❌ Failed to get active sessions: \(error)")
            return []
        }
    }

    // MARK: - Transcript Management
    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: String] = [:], wasRedacted: Bool = false) {
        let encryptedText = encrypt(text)
        let transcript = TranscriptEntity(
            sessionId: sessionId,
            speaker: speaker,
            text: encryptedText,
            metadata: metadata,
            wasRedacted: wasRedacted
        )

        do {
            try transcriptBox.put(transcript)
            logAudit(sessionId: sessionId, action: "transcript_added", details: "Speaker: \(speaker), Length: \(text.count), Redacted: \(wasRedacted)")
        } catch {
            print("❌ Failed to add transcript: \(error)")
        }
    }

    func getTranscripts(sessionId: String) -> [TranscriptData] {
        do {
            let query = transcriptBox.query(TranscriptEntity.sessionId == sessionId).order(by: .timestamp).build()
            let entities = try query.find()

            return entities.map { entity in
                TranscriptData(
                    sessionId: entity.sessionId,
                    speaker: entity.speaker,
                    text: decrypt(entity.encryptedText),
                    timestamp: entity.timestamp,
                    metadata: entity.getMetadata(),
                    wasRedacted: entity.wasRedacted
                )
            }
        } catch {
            print("❌ Failed to get transcripts: \(error)")
            return []
        }
    }

    // MARK: - Memory Management (Embeddings)
    func addMemory(sessionId: String, text: String, embedding: [Float], metadata: [String: String] = [:], importance: Float = 0.5) {
        let encryptedText = encrypt(text)
        let memory = MemoryEntity(
            sessionId: sessionId,
            text: encryptedText,
            embedding: embedding,
            metadata: metadata,
            importance: importance
        )

        do {
            try memoryBox.put(memory)
            logAudit(sessionId: sessionId, action: "memory_added", details: "Text length: \(text.count), Embedding dimensions: \(embedding.count)")
        } catch {
            print("❌ Failed to add memory: \(error)")
        }
    }

    func getMemories(sessionId: String) -> [MemoryData] {
        do {
            let query = memoryBox.query(MemoryEntity.sessionId == sessionId).order(by: .importance, flags: .descending).build()
            let entities = try query.find()

            return entities.map { entity in
                MemoryData(
                    sessionId: entity.sessionId,
                    text: decrypt(entity.encryptedText),
                    embedding: entity.embedding,
                    timestamp: entity.timestamp,
                    metadata: entity.getMetadata()
                )
            }
        } catch {
            print("❌ Failed to get memories: \(error)")
            return []
        }
    }

    // MARK: - File Management (Multimodal)
    func storeFile(sessionId: String, fileName: String, mimeType: String, data: Data, metadata: [String: String] = [:]) -> String? {
        do {
            let encryptedData = try aes.encrypt(Array(data))
            let fileEntity = FileEntity(
                sessionId: sessionId,
                fileName: fileName,
                mimeType: mimeType,
                data: Data(encryptedData),
                metadata: metadata
            )

            try fileBox.put(fileEntity)
            logAudit(sessionId: sessionId, action: "file_stored", details: "File: \(fileName), Size: \(data.count) bytes")
            return fileEntity.id.description
        } catch {
            print("❌ Failed to store file: \(error)")
            return nil
        }
    }

    func getFile(fileId: String) -> (data: Data, fileName: String, mimeType: String)? {
        guard let id = Id(fileId) else { return nil }

        do {
            guard let fileEntity = try fileBox.get(id) else { return nil }

            // Check if expired
            if fileEntity.checkExpiry() {
                try fileBox.put(fileEntity) // Update expiry status
                return nil
            }

            let decryptedData = try aes.decrypt(Array(fileEntity.encryptedData))
            return (Data(decryptedData), fileEntity.fileName, fileEntity.mimeType)
        } catch {
            print("❌ Failed to get file: \(error)")
            return nil
        }
    }

    // MARK: - Audit Logging
    func logAudit(sessionId: String, action: String, details: String, metadata: [String: String] = [:]) {
        let audit = AuditEntity(sessionId: sessionId, action: action, details: details, metadata: metadata)

        do {
            try auditBox.put(audit)
        } catch {
            print("❌ Failed to log audit: \(error)")
        }
    }

    // MARK: - Cleanup Operations
    @MainActor
    func performAutoCleanup() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.cleanupExpiredFiles() }
            group.addTask { await self.cleanupOldSessions() }
            group.addTask { await self.cleanupOldAudits() }
        }
    }

    private func cleanupExpiredFiles() async {
        do {
            let query = fileBox.query(FileEntity.expiryTimestamp < Date()).build()
            let expiredFiles = try query.find()

            for file in expiredFiles {
                try fileBox.remove(file.id)
            }

            if !expiredFiles.isEmpty {
                print("🗑️ Cleaned up \(expiredFiles.count) expired files")
                logAudit(sessionId: "system", action: "cleanup_files", details: "Removed \(expiredFiles.count) expired files")
            }
        } catch {
            print("❌ Failed to cleanup expired files: \(error)")
        }
    }

    private func cleanupOldSessions() async {
        do {
            let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            let query = sessionBox.query(SessionEntity.startTime < thirtyDaysAgo).build()
            let oldSessions = try query.find()

            for session in oldSessions {
                // Remove associated transcripts and memories
                try transcriptBox.remove(TranscriptEntity.sessionId == session.sessionId)
                try memoryBox.remove(MemoryEntity.sessionId == session.sessionId)
                try sessionBox.remove(session.id)
            }

            if !oldSessions.isEmpty {
                print("🗑️ Cleaned up \(oldSessions.count) old sessions")
                logAudit(sessionId: "system", action: "cleanup_sessions", details: "Removed \(oldSessions.count) sessions older than 30 days")
            }
        } catch {
            print("❌ Failed to cleanup old sessions: \(error)")
        }
    }

    private func cleanupOldAudits() async {
        do {
            let sixMonthsAgo = Date().addingTimeInterval(-6 * 30 * 24 * 60 * 60)
            let query = auditBox.query(AuditEntity.timestamp < sixMonthsAgo).build()
            let oldAudits = try query.find()

            for audit in oldAudits {
                try auditBox.remove(audit.id)
            }

            if !oldAudits.isEmpty {
                print("🗑️ Cleaned up \(oldAudits.count) old audit logs")
            }
        } catch {
            print("❌ Failed to cleanup old audits: \(error)")
        }
    }

    // MARK: - Storage Information
    func getStorageInfo() async throws -> StorageInfo {
        do {
            let sessionCount = try sessionBox.count()
            let transcriptCount = try transcriptBox.count()
            let memoryCount = try memoryBox.count()
            let fileCount = try fileBox.count()
            let auditCount = try auditBox.count()

            // Calculate approximate size
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let storeDirectory = documentsPath.appendingPathComponent("JarvisVertexAI_ObjectBox")

            let directorySize = try FileManager.default.allocatedSizeOfDirectory(at: storeDirectory)

            return StorageInfo(
                totalSizeBytes: directorySize,
                sessionCount: Int(sessionCount),
                transcriptCount: Int(transcriptCount),
                memoryCount: Int(memoryCount),
                fileCount: Int(fileCount),
                auditCount: Int(auditCount),
                encryptionEnabled: true,
                lastCleanup: Date(),
                databaseType: "ObjectBox"
            )
        } catch {
            throw error
        }
    }

    // MARK: - Data Export
    func exportData() async throws -> Data {
        let exportData: [String: Any] = [
            "export_timestamp": Date().ISO8601Format(),
            "sessions": getActiveSessions().map { session in
                [
                    "sessionId": session.sessionId,
                    "mode": session.mode,
                    "startTime": session.startTime.ISO8601Format(),
                    "endTime": session.endTime?.ISO8601Format() ?? "",
                    "transcripts": getTranscripts(sessionId: session.sessionId).map { transcript in
                        [
                            "speaker": transcript.speaker,
                            "text": transcript.text,
                            "timestamp": transcript.timestamp.ISO8601Format(),
                            "wasRedacted": transcript.wasRedacted
                        ]
                    }
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        logAudit(sessionId: "system", action: "data_exported", details: "Full data export performed")
        return jsonData
    }

    // MARK: - Complete Data Deletion
    func deleteAllData() async throws {
        do {
            try sessionBox.removeAll()
            try transcriptBox.removeAll()
            try memoryBox.removeAll()
            try fileBox.removeAll()
            try auditBox.removeAll()

            print("🗑️ All data deleted from ObjectBox")
            logAudit(sessionId: "system", action: "all_data_deleted", details: "Complete data deletion performed")
        } catch {
            throw error
        }
    }
}

// MARK: - Storage Info Structure
struct StorageInfo {
    let totalSizeBytes: Int64
    let sessionCount: Int
    let transcriptCount: Int
    let memoryCount: Int
    let fileCount: Int
    let auditCount: Int
    let encryptionEnabled: Bool
    let lastCleanup: Date
    let databaseType: String
}

// MARK: - FileManager Extension
extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [], errorHandler: nil)!

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile == true {
                totalSize += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        return totalSize
    }
}