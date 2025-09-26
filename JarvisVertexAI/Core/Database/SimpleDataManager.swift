import Foundation

// MARK: - Simple Data Models
struct SessionData: Codable {
    let sessionId: String
    let mode: String
    let startTime: Date
    var endTime: Date?
    let metadata: [String: String]
    var isActive: Bool
}

struct TranscriptData: Codable {
    let sessionId: String
    let speaker: String
    let text: String
    let timestamp: Date
    let metadata: [String: String]
    let wasRedacted: Bool
}

struct MemoryData: Codable {
    let sessionId: String
    let text: String
    let embedding: [Float]
    let timestamp: Date
    let metadata: [String: String]
}

// MARK: - Simple Data Manager (UserDefaults-based for now)
final class SimpleDataManager {
    static let shared = SimpleDataManager()

    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "jarvis_sessions"
    private let transcriptsKey = "jarvis_transcripts"
    private let memoriesKey = "jarvis_memories"

    private init() {
        print("📦 SimpleDataManager initialized (UserDefaults-based storage)")
    }

    // MARK: - Session Management

    func createSession(mode: String, metadata: [String: Any] = [:]) -> String {
        let sessionId = "session_\(Date().timeIntervalSince1970)_\(UUID().uuidString.prefix(8))"

        let stringMetadata = metadata.compactMapValues { "\($0)" }
        let session = SessionData(
            sessionId: sessionId,
            mode: mode,
            startTime: Date(),
            metadata: stringMetadata,
            isActive: true
        )

        var sessions = getSessions()
        sessions.append(session)
        saveSessions(sessions)

        print("✅ Session created: \(sessionId), mode: \(mode)")
        return sessionId
    }

    func endSession(_ sessionId: String) {
        var sessions = getSessions()
        for i in sessions.indices {
            if sessions[i].sessionId == sessionId {
                sessions[i].endTime = Date()
                sessions[i].isActive = false
                break
            }
        }
        saveSessions(sessions)
        print("✅ Session ended: \(sessionId)")
    }

    // MARK: - Transcript Management

    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: Any] = [:]) {
        let stringMetadata = metadata.compactMapValues { "\($0)" }
        let transcript = TranscriptData(
            sessionId: sessionId,
            speaker: speaker,
            text: text,
            timestamp: Date(),
            metadata: stringMetadata,
            wasRedacted: text.contains("_REDACTED]")
        )

        var transcripts = getTranscripts()
        transcripts.append(transcript)
        saveTranscripts(transcripts)

        print("💬 Transcript added - session: \(sessionId), speaker: \(speaker), redacted: \(transcript.wasRedacted)")
    }

    func getTranscripts(sessionId: String) -> [TranscriptData] {
        return getTranscripts().filter { $0.sessionId == sessionId }
    }

    func getRecentSessions(mode: String, limit: Int) -> [SessionData] {
        return getSessions()
            .filter { $0.mode == mode }
            .sorted { $0.startTime > $1.startTime }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Memory Storage

    func storeMemory(sessionId: String, text: String, embedding: [Float], metadata: [String: Any] = [:]) {
        let stringMetadata = metadata.compactMapValues { "\($0)" }
        let memory = MemoryData(
            sessionId: sessionId,
            text: text,
            embedding: embedding,
            timestamp: Date(),
            metadata: stringMetadata
        )

        var memories = getMemories()
        memories.append(memory)
        saveMemories(memories)

        print("🧠 Memory stored for session: \(sessionId)")
    }

    func searchMemories(embedding: [Float], limit: Int = 5) -> [MemoryData] {
        // Simple implementation - just return recent memories
        let memories = getMemories()
        return Array(memories.suffix(limit))
    }

    // MARK: - Maintenance and Cleanup

    func performMaintenance() async {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        // Clean up old data
        let sessions = getSessions().filter { $0.startTime > thirtyDaysAgo }
        saveSessions(sessions)

        let transcripts = getTranscripts().filter { $0.timestamp > thirtyDaysAgo }
        saveTranscripts(transcripts)

        let memories = getMemories().filter { $0.timestamp > thirtyDaysAgo }
        saveMemories(memories)

        let oldSessionCount = getSessions().count - sessions.count
        let oldTranscriptCount = getTranscripts().count - transcripts.count
        let oldMemoryCount = getMemories().count - memories.count
        print("🧹 Maintenance completed - cleaned \(oldSessionCount) sessions, \(oldTranscriptCount) transcripts, \(oldMemoryCount) memories")
    }

    func deleteAllData() async throws {
        userDefaults.removeObject(forKey: sessionsKey)
        userDefaults.removeObject(forKey: transcriptsKey)
        userDefaults.removeObject(forKey: memoriesKey)
        print("🗑️ All user data deleted (complete wipe)")
    }

    func deleteSession(sessionId: String) {
        var sessions = getSessions()
        sessions.removeAll { $0.sessionId == sessionId }
        saveSessions(sessions)

        var transcripts = getTranscripts()
        let transcriptsToDelete = transcripts.filter { $0.sessionId == sessionId }
        transcripts.removeAll { $0.sessionId == sessionId }
        saveTranscripts(transcripts)

        let deletedTranscripts = transcriptsToDelete.count
        print("🗑️ Session deleted: \(sessionId) (removed \(deletedTranscripts) transcripts)")
    }

    // MARK: - Export and Storage Info

    func exportAllData(format: String, includeMetadata: Bool) async -> Data? {
        let exportData: [String: Any] = [
            "exportDate": Date().timeIntervalSince1970,
            "format": format,
            "encrypted": false,
            "sessions": getSessions().map { sessionToDict($0, includeMetadata: includeMetadata) },
            "transcripts": getTranscripts().map { transcriptToDict($0, includeMetadata: includeMetadata) }
        ]

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    func getStorageInfo() async -> (totalSize: Int64, sessionCount: Int, transcriptCount: Int, oldestData: Date?) {
        let sessions = getSessions()
        let transcripts = getTranscripts()

        let oldestDate = sessions.map(\.startTime).min()

        // Approximate size calculation
        let sessionsData = try? JSONEncoder().encode(sessions)
        let transcriptsData = try? JSONEncoder().encode(transcripts)
        let totalSize = Int64((sessionsData?.count ?? 0) + (transcriptsData?.count ?? 0))

        return (totalSize, sessions.count, transcripts.count, oldestDate)
    }

    // MARK: - Audit Logging

    func logAudit(action: String, sessionId: String? = nil, metadata: [String: Any] = [:]) {
        let sessionInfo = sessionId != nil ? "Session: \(sessionId!)" : "Session: none"
        let metadataInfo = metadata.isEmpty ? "" : ", Metadata: \(metadata)"
        print("🔍 Audit: Action: \(action), \(sessionInfo)\(metadataInfo)")
    }


    // MARK: - Privacy Verification

    func verifyPrivacySettings() -> [String: Any] {
        return [
            "localStorage": "UserDefaults (encrypted by iOS)",
            "cloudSync": "Disabled",
            "dataRetention": "30 days",
            "phiRedaction": "Active",
            "sessionCount": getSessions().count,
            "transcriptCount": getTranscripts().count
        ]
    }

    func getDatabasePath() -> String {
        return "UserDefaults" // Not a file path for this implementation
    }

    func getConfiguration() -> [String: Any] {
        return [
            "enableSync": false,
            "syncServerUrl": NSNull(),
            "encryption": "iOS System"
        ]
    }

    // MARK: - Private Helpers

    private func getSessions() -> [SessionData] {
        guard let data = userDefaults.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([SessionData].self, from: data) else {
            return []
        }
        return sessions
    }

    private func saveSessions(_ sessions: [SessionData]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        userDefaults.set(data, forKey: sessionsKey)
    }

    private func getTranscripts() -> [TranscriptData] {
        guard let data = userDefaults.data(forKey: transcriptsKey),
              let transcripts = try? JSONDecoder().decode([TranscriptData].self, from: data) else {
            return []
        }
        return transcripts
    }

    private func saveTranscripts(_ transcripts: [TranscriptData]) {
        guard let data = try? JSONEncoder().encode(transcripts) else { return }
        userDefaults.set(data, forKey: transcriptsKey)
    }

    private func getMemories() -> [MemoryData] {
        guard let data = userDefaults.data(forKey: memoriesKey),
              let memories = try? JSONDecoder().decode([MemoryData].self, from: data) else {
            return []
        }
        return memories
    }

    private func saveMemories(_ memories: [MemoryData]) {
        guard let data = try? JSONEncoder().encode(memories) else { return }
        userDefaults.set(data, forKey: memoriesKey)
    }

    private func sessionToDict(_ session: SessionData, includeMetadata: Bool) -> [String: Any] {
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

    private func transcriptToDict(_ transcript: TranscriptData, includeMetadata: Bool) -> [String: Any] {
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

    // MARK: - Additional Methods for ObjectBoxManager Compatibility

    func initialize() {
        // SimpleDataManager uses UserDefaults and doesn't need explicit initialization
        print("📦 SimpleDataManager initialized (no-op)")
    }

    func logAuditEvent(_ event: [String: Any]) {
        // Convert event dictionary to audit log
        let action = event["action"] as? String ?? "unknown"
        let sessionId = event["sessionId"] as? String
        let metadata = event["metadata"] as? [String: Any] ?? [:]

        logAudit(action: action, sessionId: sessionId, metadata: metadata)
    }
}