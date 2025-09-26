// This file is disabled to avoid ObjectBox compilation issues
// Use SimpleDataManager instead

/*
import Foundation
import ObjectBox
import CryptoSwift

// MARK: - Simple ObjectBox Manager
final class SimpleObjectBoxManager {
    static let shared = SimpleObjectBoxManager()

    private var store: Store?
    private let dbPath: String

    private init() {
        // Set up database path
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                   in: .userDomainMask).first!
        self.dbPath = documentsPath.appendingPathComponent("jarvis_local_db").path

        // Initialize store
        do {
            self.store = try Store(directory: dbPath)
            print("📦 ObjectBox initialized at: \(dbPath)")
        } catch {
            print("❌ ObjectBox initialization failed: \(error)")
        }
    }

    // MARK: - Simple Session Management

    func createSession(mode: String, metadata: [String: Any] = [:]) -> String {
        let sessionId = "session_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"

        let session = SessionEntity(sessionId: sessionId, mode: mode, metadata: metadata)

        do {
            let sessionBox: Box<SessionEntity> = store!.box(for: SessionEntity.self)
            try sessionBox.put(session)

            // Log audit
            logAudit(action: "SESSION_CREATED", sessionId: sessionId, metadata: ["mode": mode])

            print("✅ Session created: \(sessionId)")
            return sessionId
        } catch {
            print("❌ Failed to create session: \(error)")
            return sessionId // Return ID even if storage fails
        }
    }

    func endSession(_ sessionId: String) {
        do {
            let sessionBox: Box<SessionEntity> = store!.box(for: SessionEntity.self)
            let query = sessionBox.query { SessionEntity.sessionId == sessionId }
            let sessions = try query.find()

            for session in sessions {
                session.endTime = Date()
                session.isActive = false
                try sessionBox.put(session)
            }

            logAudit(action: "SESSION_ENDED", sessionId: sessionId)
            print("✅ Session ended: \(sessionId)")
        } catch {
            print("❌ Failed to end session: \(error)")
        }
    }

    // MARK: - Transcript Management

    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: Any] = [:]) {
        let transcript = TranscriptEntity(
            sessionId: sessionId,
            speaker: speaker,
            text: text,
            metadata: metadata,
            wasRedacted: text.contains("_REDACTED]")
        )

        do {
            let transcriptBox: Box<TranscriptEntity> = store!.box(for: TranscriptEntity.self)
            try transcriptBox.put(transcript)

            print("💬 Transcript added for session: \(sessionId)")
        } catch {
            print("❌ Failed to add transcript: \(error)")
        }
    }

    func getTranscripts(sessionId: String) -> [TranscriptEntity] {
        do {
            let transcriptBox: Box<TranscriptEntity> = store!.box(for: TranscriptEntity.self)
            let query = transcriptBox.query { TranscriptEntity.sessionId == sessionId }
            return try query.find().sorted { $0.timestamp < $1.timestamp }
        } catch {
            print("❌ Failed to get transcripts: \(error)")
            return []
        }
    }

    // MARK: - Memory Storage

    func storeMemory(sessionId: String, text: String, embedding: [Float], metadata: [String: Any] = [:]) {
        let memory = MemoryEntity(
            sessionId: sessionId,
            text: text,
            embedding: embedding,
            metadata: metadata
        )

        do {
            let memoryBox: Box<MemoryEntity> = store!.box(for: MemoryEntity.self)
            try memoryBox.put(memory)

            print("🧠 Memory stored for session: \(sessionId)")
        } catch {
            print("❌ Failed to store memory: \(error)")
        }
    }

    // MARK: - Audit Logging

    func logAudit(action: String, sessionId: String? = nil, metadata: [String: Any] = [:]) {
        let auditLog = AuditLogEntity(
            action: action,
            sessionId: sessionId,
            metadata: metadata
        )

        do {
            let auditBox: Box<AuditLogEntity> = store!.box(for: AuditLogEntity.self)
            try auditBox.put(auditLog)
        } catch {
            print("❌ Failed to log audit: \(error)")
        }
    }

    // MARK: - Cleanup and Maintenance

    func performMaintenance() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.cleanupOldData()
                continuation.resume()
            }
        }
    }

    private func cleanupOldData() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        do {
            // Clean up old sessions
            let sessionBox: Box<SessionEntity> = store!.box(for: SessionEntity.self)
            let oldSessions = try sessionBox.query { SessionEntity.startTime < thirtyDaysAgo }.find()

            for session in oldSessions {
                try sessionBox.remove(session)
                logAudit(action: "SESSION_DELETED", sessionId: session.sessionId, metadata: ["reason": "auto_cleanup"])
            }

            print("🧹 Cleaned up \(oldSessions.count) old sessions")
        } catch {
            print("❌ Cleanup failed: \(error)")
        }
    }

    // MARK: - Data Export and Privacy

    func exportAllData(format: String, includeMetadata: Bool) async -> Data? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let sessionBox: Box<SessionEntity> = self.store!.box(for: SessionEntity.self)
                    let transcriptBox: Box<TranscriptEntity> = self.store!.box(for: TranscriptEntity.self)

                    let sessions = try sessionBox.all()
                    let transcripts = try transcriptBox.all()

                    let exportData: [String: Any] = [
                        "exportDate": Date().timeIntervalSince1970,
                        "format": format,
                        "encrypted": true,
                        "sessions": sessions.map { self.sessionToDict($0, includeMetadata: includeMetadata) },
                        "transcripts": transcripts.map { self.transcriptToDict($0, includeMetadata: includeMetadata) }
                    ]

                    let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
                    continuation.resume(returning: jsonData)
                } catch {
                    print("❌ Export failed: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func deleteAllData() async throws {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try self?.store?.removeAll()
                    self?.logAudit(action: "ALL_DATA_DELETED", metadata: ["reason": "user_request"])
                    print("🗑️ All data deleted")
                } catch {
                    print("❌ Failed to delete all data: \(error)")
                }
                continuation.resume()
            }
        }
    }

    // MARK: - Helper Functions

    private func sessionToDict(_ session: SessionEntity, includeMetadata: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": session.sessionId,
            "mode": session.mode,
            "startTime": session.startTime.timeIntervalSince1970,
            "isActive": session.isActive
        ]

        if let endTime = session.endTime {
            dict["endTime"] = endTime.timeIntervalSince1970
        }

        if includeMetadata {
            dict["metadata"] = session.metadata
        }

        return dict
    }

    private func transcriptToDict(_ transcript: TranscriptEntity, includeMetadata: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "sessionId": transcript.sessionId,
            "speaker": transcript.speaker,
            "text": transcript.text,
            "timestamp": transcript.timestamp.timeIntervalSince1970,
            "wasRedacted": transcript.wasRedacted
        ]

        if includeMetadata {
            dict["metadata"] = transcript.metadata
        }

        return dict
    }

    // MARK: - Storage Info

    func getStorageInfo() async -> (totalSize: Int64, sessionCount: Int, transcriptCount: Int, oldestData: Date?) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: (0, 0, 0, nil))
                    return
                }

                do {
                    let sessionBox: Box<SessionEntity> = self.store!.box(for: SessionEntity.self)
                    let transcriptBox: Box<TranscriptEntity> = self.store!.box(for: TranscriptEntity.self)

                    let sessionCount = try sessionBox.count()
                    let transcriptCount = try transcriptBox.count()

                    // Calculate approximate size
                    let dbURL = URL(fileURLWithPath: self.dbPath)
                    let totalSize = (try? FileManager.default.attributesOfItem(atPath: dbURL.path)[.size] as? Int64) ?? 0

                    // Find oldest data
                    let allSessions = try sessionBox.all()
                    let oldestDate = allSessions.map(\.startTime).min()

                    continuation.resume(returning: (totalSize, Int(sessionCount), Int(transcriptCount), oldestDate))
                } catch {
                    print("❌ Failed to get storage info: \(error)")
                    continuation.resume(returning: (0, 0, 0, nil))
                }
            }
        }
    }
}*/
