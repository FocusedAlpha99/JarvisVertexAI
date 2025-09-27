//
//  DataManagerProtocol.swift
//  JarvisVertexAI
//
//  Protocol for database managers to ensure compatibility
//  Allows switching between SimpleDataManager and ObjectBoxManager
//

import Foundation

// MARK: - Data Manager Protocol
protocol DataManagerProtocol {
    // Session Management
    func createSession(mode: String, metadata: [String: Any]) -> String
    func endSession(_ sessionId: String)
    func getActiveSessions() -> [SessionData]

    // Transcript Management
    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: String], wasRedacted: Bool)
    func getTranscripts(sessionId: String) -> [TranscriptData]

    // Memory Management
    func addMemory(sessionId: String, text: String, embedding: [Float], metadata: [String: String], importance: Float)
    func getMemories(sessionId: String) -> [MemoryData]

    // Audit Logging
    func logAudit(sessionId: String, action: String, details: String, metadata: [String: String])

    // Storage Information
    func getStorageInfo() async throws -> Any // Will return appropriate storage info type

    // Data Export and Deletion
    func exportData() async throws -> Data
    func deleteAllData() async throws
}

// MARK: - Universal Data Manager
final class UniversalDataManager {
    static let shared = UniversalDataManager()

    private let dataManager: DataManagerProtocol

    private init() {
        // Try to use ObjectBox first, fallback to SimpleDataManager
        #if canImport(ObjectBox)
        // Check if ObjectBox is properly configured
        if NSClassFromString("ObjectBoxManager") != nil {
            dataManager = ObjectBoxManager.shared
            print("📦 Using ObjectBoxManager for data storage")
        } else {
            dataManager = SimpleDataManager.shared
            print("📦 Using SimpleDataManager (ObjectBox not available)")
        }
        #else
        dataManager = SimpleDataManager.shared
        print("📦 Using SimpleDataManager (ObjectBox not imported)")
        #endif
    }

    // MARK: - Session Management
    func createSession(mode: String, metadata: [String: Any] = [:]) -> String {
        return dataManager.createSession(mode: mode, metadata: metadata)
    }

    func endSession(_ sessionId: String) {
        dataManager.endSession(sessionId)
    }

    func getActiveSessions() -> [SessionData] {
        return dataManager.getActiveSessions()
    }

    // MARK: - Transcript Management
    func addTranscript(sessionId: String, speaker: String, text: String, metadata: [String: String] = [:], wasRedacted: Bool = false) {
        dataManager.addTranscript(sessionId: sessionId, speaker: speaker, text: text, metadata: metadata, wasRedacted: wasRedacted)
    }

    func getTranscripts(sessionId: String) -> [TranscriptData] {
        return dataManager.getTranscripts(sessionId: sessionId)
    }

    // MARK: - Memory Management
    func addMemory(sessionId: String, text: String, embedding: [Float], metadata: [String: String] = [:], importance: Float = 0.5) {
        dataManager.addMemory(sessionId: sessionId, text: text, embedding: embedding, metadata: metadata, importance: importance)
    }

    func getMemories(sessionId: String) -> [MemoryData] {
        return dataManager.getMemories(sessionId: sessionId)
    }

    // MARK: - Audit Logging
    func logAudit(sessionId: String, action: String, details: String, metadata: [String: String] = [:]) {
        dataManager.logAudit(sessionId: sessionId, action: action, details: details, metadata: metadata)
    }

    // MARK: - Storage Information
    func getStorageInfo() async throws -> Any {
        return try await dataManager.getStorageInfo()
    }

    // MARK: - Data Export and Deletion
    func exportData() async throws -> Data {
        return try await dataManager.exportData()
    }

    func deleteAllData() async throws {
        try await dataManager.deleteAllData()
    }

    // MARK: - Manager Type Information
    var managerType: String {
        switch dataManager {
        case is ObjectBoxManager:
            return "ObjectBox"
        case is SimpleDataManager:
            return "SimpleDataManager"
        default:
            return "Unknown"
        }
    }

    var isObjectBoxEnabled: Bool {
        return dataManager is ObjectBoxManager
    }
}