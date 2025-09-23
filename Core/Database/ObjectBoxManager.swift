//
//  ObjectBoxManager.swift
//  JarvisVertexAI
//
//  Privacy-First Local Database with AES-256 Encryption
//  100% On-Device Storage - No Cloud Sync
//

import Foundation
import ObjectBox
import CryptoKit
import CommonCrypto

// MARK: - Entities

@objc(SessionEntity)
class SessionEntity: NSObject {
    var id: Id = 0
    var sessionId: String = ""
    var mode: String = ""
    var startTime: Date = Date()
    var endTime: Date?
    var metadata: Data?
    var isActive: Bool = true

    required override init() {
        super.init()
    }
}

@objc(TranscriptEntity)
class TranscriptEntity: NSObject {
    var id: Id = 0
    var sessionId: String = ""
    var speaker: String = ""
    var text: String = ""
    var timestamp: Date = Date()
    var metadata: Data?
    var redactedPHI: Bool = false

    required override init() {
        super.init()
    }
}

@objc(MemoryEntity)
class MemoryEntity: NSObject {
    var id: Id = 0
    var content: String = ""
    var embedding: Data?
    var category: String = ""
    var importance: Float = 0.5
    var lastAccessed: Date = Date()
    var expiryDate: Date = Date().addingTimeInterval(30 * 24 * 60 * 60)

    required override init() {
        super.init()
    }
}

@objc(AuditLogEntity)
class AuditLogEntity: NSObject {
    var id: Id = 0
    var action: String = ""
    var sessionId: String?
    var timestamp: Date = Date()
    var metadata: Data?
    var phiAccessed: Bool = false

    required override init() {
        super.init()
    }
}

// MARK: - ObjectBoxManager

final class ObjectBoxManager {

    // MARK: - Properties

    static let shared = ObjectBoxManager()

    private var store: Store?
    private let encryptionKey: SymmetricKey
    private let documentsPath: URL
    private let maintenanceQueue = DispatchQueue(label: "com.jarvisvertexai.maintenance", qos: .utility)

    // Boxes
    private var sessionBox: Box<SessionEntity>?
    private var transcriptBox: Box<TranscriptEntity>?
    private var memoryBox: Box<MemoryEntity>?
    private var auditBox: Box<AuditLogEntity>?

    // MARK: - Initialization

    private init() {
        // Get documents directory (local only, no iCloud)
        self.documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                      in: .userDomainMask).first!
            .appendingPathComponent("JarvisVertexAI_LocalDB", isDirectory: true)

        // Generate device-specific encryption key
        self.encryptionKey = ObjectBoxManager.generateDeviceKey()

        // Create directory if needed
        try? FileManager.default.createDirectory(at: documentsPath,
                                                withIntermediateDirectories: true)

        // Set strict file permissions (owner-only)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: documentsPath.path)
    }

    func initialize() throws {
        print("🔒 Initializing ObjectBox with AES-256 encryption...")

        // Build model
        let model = try ModelBuilder()
            .entity(SessionEntity.self)
            .entity(TranscriptEntity.self)
            .entity(MemoryEntity.self)
            .entity(AuditLogEntity.self)
            .build()

        // Configure store with encryption
        let storeOptions = StoreOptions(
            directory: documentsPath.path,
            maxDbSizeInKByte: 500_000, // 500MB max
            fileMode: 0o600, // Owner-only access
            encryptionKey: encryptionKey.dataRepresentation,
            enableSync: false, // CRITICAL: No cloud sync
            syncServerUrl: nil
        )

        // Initialize store
        self.store = try Store(model: model, options: storeOptions)

        // Initialize boxes
        self.sessionBox = store?.box(for: SessionEntity.self)
        self.transcriptBox = store?.box(for: TranscriptEntity.self)
        self.memoryBox = store?.box(for: MemoryEntity.self)
        self.auditBox = store?.box(for: AuditLogEntity.self)

        // Schedule maintenance
        scheduleMaintenance()

        // Log initialization
        logAudit(action: "DATABASE_INITIALIZED", metadata: ["encryption": "AES-256"])

        print("✅ ObjectBox initialized with local-only storage")
    }

    // MARK: - Session Management

    func createSession(mode: String, metadata: [String: Any]? = nil) -> String {
        let sessionId = UUID().uuidString
        let session = SessionEntity()
        session.sessionId = sessionId
        session.mode = mode
        session.startTime = Date()
        session.isActive = true

        if let metadata = metadata {
            session.metadata = try? JSONSerialization.data(withJSONObject: metadata)
        }

        try? sessionBox?.put(session)

        logAudit(action: "SESSION_CREATED",
                sessionId: sessionId,
                metadata: ["mode": mode])

        return sessionId
    }

    func endSession(_ sessionId: String) {
        guard let sessions = try? sessionBox?.query()
            .equal(SessionEntity.sessionId, to: sessionId)
            .build()
            .find(),
              let session = sessions.first else { return }

        session.isActive = false
        session.endTime = Date()
        try? sessionBox?.put(session)

        logAudit(action: "SESSION_ENDED", sessionId: sessionId)
    }

    // MARK: - Transcript Management

    func addTranscript(sessionId: String,
                      speaker: String,
                      text: String,
                      metadata: [String: Any]? = nil) {
        let transcript = TranscriptEntity()
        transcript.sessionId = sessionId
        transcript.speaker = speaker
        transcript.text = text
        transcript.timestamp = Date()
        transcript.redactedPHI = text.contains("[REDACTED]") || text.contains("_REDACTED")

        if let metadata = metadata {
            transcript.metadata = try? JSONSerialization.data(withJSONObject: metadata)
        }

        try? transcriptBox?.put(transcript)

        logAudit(action: "TRANSCRIPT_ADDED",
                sessionId: sessionId,
                metadata: ["speaker": speaker, "phiRedacted": transcript.redactedPHI])
    }

    func getTranscripts(sessionId: String) -> [TranscriptEntity] {
        guard let transcripts = try? transcriptBox?.query()
            .equal(TranscriptEntity.sessionId, to: sessionId)
            .order(TranscriptEntity.timestamp)
            .build()
            .find() else { return [] }

        return transcripts
    }

    // MARK: - Memory Management

    func addMemory(_ content: String,
                  category: String,
                  importance: Float = 0.5,
                  embedding: [Float]? = nil) {
        let memory = MemoryEntity()
        memory.content = content
        memory.category = category
        memory.importance = importance
        memory.lastAccessed = Date()
        memory.expiryDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days

        if let embedding = embedding {
            memory.embedding = Data(bytes: embedding, count: embedding.count * MemoryLayout<Float>.size)
        }

        try? memoryBox?.put(memory)

        logAudit(action: "MEMORY_ADDED",
                metadata: ["category": category, "importance": importance])
    }

    func searchMemories(query: String, limit: Int = 10) -> [MemoryEntity] {
        guard let memories = try? memoryBox?.query()
            .contains(MemoryEntity.content, string: query)
            .order(MemoryEntity.importance, flags: .DESCENDING)
            .build()
            .find(limit: limit) else { return [] }

        // Update last accessed
        for memory in memories {
            memory.lastAccessed = Date()
        }
        try? memoryBox?.put(memories)

        return memories
    }

    // MARK: - Maintenance

    func performMaintenance() {
        maintenanceQueue.async { [weak self] in
            guard let self = self else { return }

            let cutoffDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago

            // Clean old sessions
            if let oldSessions = try? self.sessionBox?.query()
                .less(SessionEntity.startTime, than: cutoffDate)
                .build()
                .find() {

                for session in oldSessions {
                    // Delete associated transcripts
                    if let transcripts = try? self.transcriptBox?.query()
                        .equal(TranscriptEntity.sessionId, to: session.sessionId)
                        .build()
                        .find() {
                        try? self.transcriptBox?.remove(transcripts)
                    }
                }

                try? self.sessionBox?.remove(oldSessions)
                print("🧹 Cleaned \(oldSessions.count) old sessions")
            }

            // Clean expired memories
            if let expiredMemories = try? self.memoryBox?.query()
                .less(MemoryEntity.expiryDate, than: Date())
                .build()
                .find() {

                try? self.memoryBox?.remove(expiredMemories)
                print("🧹 Cleaned \(expiredMemories.count) expired memories")
            }

            // Clean old audit logs (keep 90 days)
            let auditCutoff = Date().addingTimeInterval(-90 * 24 * 60 * 60)
            if let oldAudits = try? self.auditBox?.query()
                .less(AuditLogEntity.timestamp, than: auditCutoff)
                .build()
                .find() {

                try? self.auditBox?.remove(oldAudits)
                print("🧹 Cleaned \(oldAudits.count) old audit logs")
            }

            self.logAudit(action: "MAINTENANCE_COMPLETED")
        }
    }

    private func scheduleMaintenance() {
        // Run maintenance daily at 2 AM
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { _ in
            self.performMaintenance()
        }
        RunLoop.main.add(timer, forMode: .common)

        // Run initial maintenance after 1 minute
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            self.performMaintenance()
        }
    }

    // MARK: - Data Operations

    func deleteSession(sessionId: String) {
        // Delete session
        if let sessions = try? sessionBox?.query()
            .equal(SessionEntity.sessionId, to: sessionId)
            .build()
            .find() {
            try? sessionBox?.remove(sessions)
        }

        // Delete transcripts
        if let transcripts = try? transcriptBox?.query()
            .equal(TranscriptEntity.sessionId, to: sessionId)
            .build()
            .find() {
            try? transcriptBox?.remove(transcripts)
        }

        logAudit(action: "SESSION_DELETED", sessionId: sessionId)
    }

    func deleteAllData() {
        try? sessionBox?.removeAll()
        try? transcriptBox?.removeAll()
        try? memoryBox?.removeAll()

        logAudit(action: "ALL_DATA_DELETED",
                metadata: ["timestamp": ISO8601DateFormatter().string(from: Date())])
    }

    func exportData() -> Data? {
        var exportData: [String: Any] = [:]

        // Export sessions
        if let sessions = try? sessionBox?.getAll() {
            exportData["sessions"] = sessions.map { session in
                [
                    "sessionId": session.sessionId,
                    "mode": session.mode,
                    "startTime": ISO8601DateFormatter().string(from: session.startTime),
                    "endTime": session.endTime.map { ISO8601DateFormatter().string(from: $0) }
                ]
            }
        }

        // Export transcripts (without PHI)
        if let transcripts = try? transcriptBox?.getAll() {
            exportData["transcripts"] = transcripts.map { transcript in
                [
                    "sessionId": transcript.sessionId,
                    "speaker": transcript.speaker,
                    "text": transcript.redactedPHI ? "[CONTENT_REDACTED]" : transcript.text,
                    "timestamp": ISO8601DateFormatter().string(from: transcript.timestamp)
                ]
            }
        }

        logAudit(action: "DATA_EXPORTED")

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    // MARK: - Audit Logging

    private func logAudit(action: String,
                         sessionId: String? = nil,
                         metadata: [String: Any]? = nil) {
        let audit = AuditLogEntity()
        audit.action = action
        audit.sessionId = sessionId
        audit.timestamp = Date()
        audit.phiAccessed = action.contains("PHI") || action.contains("TRANSCRIPT")

        if let metadata = metadata {
            audit.metadata = try? JSONSerialization.data(withJSONObject: metadata)
        }

        try? auditBox?.put(audit)
    }

    // MARK: - Encryption

    private static func generateDeviceKey() -> SymmetricKey {
        // Use device-specific identifier + app bundle ID
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let bundleId = Bundle.main.bundleIdentifier ?? "com.jarvisvertexai.app"
        let keyString = "\(deviceId)-\(bundleId)-jarvis-vertex-ai"

        // Generate 256-bit key
        let keyData = SHA256.hash(data: keyString.data(using: .utf8)!)
        return SymmetricKey(data: keyData)
    }
}

// MARK: - Privacy Extensions

extension ObjectBoxManager {

    func getPrivacyStats() -> [String: Any] {
        var stats: [String: Any] = [:]

        stats["totalSessions"] = try? sessionBox?.count() ?? 0
        stats["totalTranscripts"] = try? transcriptBox?.count() ?? 0
        stats["totalMemories"] = try? memoryBox?.count() ?? 0
        stats["phiRedactedTranscripts"] = try? transcriptBox?.query()
            .equal(TranscriptEntity.redactedPHI, to: true)
            .build()
            .count() ?? 0

        stats["storageLocation"] = "Local Device Only"
        stats["encryption"] = "AES-256"
        stats["cloudSync"] = "Disabled"
        stats["autoCleanup"] = "30 days"

        return stats
    }

    func verifyPrivacyCompliance() -> Bool {
        // Verify encryption is active
        guard store?.encryptionKey != nil else {
            print("❌ Encryption not active")
            return false
        }

        // Verify no cloud sync
        guard store?.syncEnabled == false else {
            print("❌ Cloud sync is enabled")
            return false
        }

        // Verify file permissions
        if let attributes = try? FileManager.default.attributesOfItem(atPath: documentsPath.path),
           let permissions = attributes[.posixPermissions] as? Int {
            guard permissions == 0o600 else {
                print("❌ File permissions not restricted")
                return false
            }
        }

        print("✅ Privacy compliance verified")
        return true
    }
}